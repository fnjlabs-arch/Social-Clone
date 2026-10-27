/*
 * This file is part of Social Clone
 * (see https://github.com/fnjlabs-arch/Social-Clone).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'license_code.dart';

/// A license activated on this device.
class LicenseState {
  final LicenseTier tier;
  final String code;
  final DateTime activatedAt;

  /// The stable per-device id this license was bound to, if known.
  /// Null only for license files written before device binding existed
  /// (old files are read as unverified); every new activation — server
  /// or offline fallback — records the current device id, so a later
  /// online re-paste can redeem with the same id.
  final String? deviceId;

  /// True only when the Social Clone dashboard confirmed the binding
  /// server-side (POST /api/v1/licenses/redeem returned `activated` or
  /// `already_active_on_this_device`). False means the license was
  /// activated through the offline fallback and the 1-device rule has
  /// NOT been enforced for it yet — re-pasting the code while the
  /// dashboard is reachable retries the redeem.
  final bool serverVerified;

  const LicenseState({
    required this.tier,
    required this.code,
    required this.activatedAt,
    this.deviceId,
    this.serverVerified = false,
  });

  Map<String, dynamic> toJson() => {
    'tier': tier.name,
    'code': code,
    'activatedAt': activatedAt.toIso8601String(),
    'deviceId': deviceId,
    'serverVerified': serverVerified,
  };

  factory LicenseState.fromJson(Map<String, dynamic> json) {
    final tier = LicenseTier.values.firstWhere(
      (t) => t.name == json['tier'],
      orElse: () => LicenseTier.five,
    );
    return LicenseState(
      tier: tier,
      code: json['code'] as String,
      activatedAt: DateTime.parse(json['activatedAt'] as String),
      // Old license files predate these fields; treat them as unverified.
      deviceId: json['deviceId'] as String?,
      serverVerified: json['serverVerified'] as bool? ?? false,
    );
  }
}

/// Thrown when a license code fails offline validation.
class InvalidLicenseCodeException implements Exception {
  const InvalidLicenseCodeException();
}

/// Thrown when the dashboard says the code is already bound to a
/// different device (HTTP 409, error `already_in_use`). [message] is the
/// dashboard's own message, shown to the user verbatim.
class LicenseAlreadyInUseException implements Exception {
  final String message;

  const LicenseAlreadyInUseException(this.message);
}

/// Thrown when the dashboard does not know the code at all (HTTP 404,
/// error `invalid_code`): the code is well-formed and checksummed, but
/// was never issued by the dashboard.
class LicenseNotIssuedException implements Exception {
  const LicenseNotIssuedException();
}

/// Thrown when the dashboard says the code was deactivated by an admin
/// (HTTP 403, error `code_deactivated`). [message] is the dashboard's
/// own message, shown to the user verbatim.
class LicenseDeactivatedException implements Exception {
  final String message;

  const LicenseDeactivatedException(this.message);
}

/// Thrown when the dashboard says the code has expired (HTTP 403,
/// error `code_expired`).
class LicenseExpiredException implements Exception {
  const LicenseExpiredException();
}

/// Thrown when activation is blocked by the wrong-code lockout (see
/// [_LockoutState]). [unlockAt] is when activation works again.
class LicenseLockedException implements Exception {
  final DateTime unlockAt;

  const LicenseLockedException(this.unlockAt);
}

/// Wrong-code lockout state, persisted in secure storage so it survives
/// app restarts (never in-memory only).
///
/// THE RULE, exactly: after 3 wrong code entries the app locks for
/// 8 hours. If, after that lock expires, the user again piles up
/// 3 wrong entries, the lock is 24 hours — and every further lock
/// without an intervening successful activation is also 24 hours.
/// The attempt counter resets to 0 when a lock expires, and the
/// escalation level (8h vs 24h) persists until a successful activation
/// clears the whole state.
///
/// WHAT COUNTS AS A WRONG ENTRY: a malformed/offline-invalid code, or
/// a dashboard 404 `invalid_code` (well-formed but never issued).
/// Definitive rejections that prove the code EXISTS but is unusable —
/// deactivated (403) and expired (403) — do NOT count: they are not
/// guesses. Network/timeout errors and 409 already-in-use NEVER count
/// either (a bound code is not a wrong guess, and a dead network is
/// not the user's fault). Tapping Activate with an empty field does
/// not reach this code at all, so it never counts.
class _LockoutState {
  /// Wrong entries in the current window (0..2; hitting 3 locks).
  int wrongAttempts;

  /// When the current lock ends, or null when not locked.
  DateTime? lockUntil;

  /// Locks already served in this cycle (0 = next lock is 8h,
  /// 1+ = next lock is 24h). Cleared only by a successful activation.
  int lockCount;

  _LockoutState({
    this.wrongAttempts = 0,
    this.lockUntil,
    this.lockCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'wrongAttempts': wrongAttempts,
    'lockUntil': lockUntil?.toUtc().toIso8601String(),
    'lockCount': lockCount,
  };

  factory _LockoutState.fromJson(Map<String, dynamic> json) {
    DateTime? lockUntil;
    final raw = json['lockUntil'] as String?;
    if (raw != null) {
      try {
        lockUntil = DateTime.parse(raw);
      } catch (_) {
        lockUntil = null;
      }
    }
    return _LockoutState(
      wrongAttempts: json['wrongAttempts'] as int? ?? 0,
      lockUntil: lockUntil,
      lockCount: json['lockCount'] as int? ?? 0,
    );
  }
}

/// Holds the device license. Stored app-global (not per-profile) so it
/// survives profile switches, and checked before any profile may be added.
///
/// Activation order:
/// 1. Offline validation (format + checksum) — always first, so a
///    malformed code is rejected without any network call.
/// 2. Dashboard redeem (POST /api/v1/licenses/redeem) — when the
///    dashboard base URL is configured (see [dashboardBaseUrl]). This
///    is what enforces the 1-device rule: a code bound to another
///    device is rejected with HTTP 409, and re-pasting on the same
///    device is idempotent (no second activation).
/// 3. Offline fallback — when the dashboard is not configured, or the
///    network/server is unavailable. The license is still persisted
///    locally, so the app keeps working offline.
///
/// HONEST TRADEOFF (do not remove this comment without fixing the
/// behaviour): the offline fallback CANNOT enforce the 1-device rule
/// by itself. A code activated offline on two devices will look valid
/// on both until one of them redeems online and the dashboard binds
/// it. Full enforcement therefore only applies once the dashboard is
/// live, reachable, and [dashboardBaseUrl] points at it. The stored
/// [LicenseState.serverVerified] flag records which path was taken.
class LicenseRepository extends AsyncNotifier<LicenseState?> {
  static const _fileName = 'social_clone_license.json';
  static const _deviceIdKey = 'social_clone_device_id';
  static const _lockoutKey = 'social_clone_lockout_state';

  /// Loads the persisted lockout state (a fresh state when none exists
  /// or the stored JSON is damaged — a damaged lockout file must not
  /// brick activation).
  Future<_LockoutState> _loadLockout() async {
    try {
      final raw = await _secureStorage.read(key: _lockoutKey);
      if (raw == null || raw.isEmpty) return _LockoutState();
      return _LockoutState.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return _LockoutState();
    }
  }

  Future<void> _saveLockout(_LockoutState lockout) async {
    await _secureStorage.write(
      key: _lockoutKey,
      value: jsonEncode(lockout.toJson()),
    );
  }

  /// Clears the whole lockout state (attempts, lock, escalation).
  /// Called only on a successful activation.
  Future<void> _clearLockout() async {
    await _secureStorage.delete(key: _lockoutKey);
  }

  /// Returns the unlock time when the app is currently locked, or null
  /// when it is not. An expired lock clears itself (attempts reset to
  /// 0, escalation kept) and returns null.
  Future<DateTime?> _checkLock() async {
    final lockout = await _loadLockout();
    final until = lockout.lockUntil;
    if (until == null) return null;
    if (DateTime.now().isBefore(until)) return until;
    lockout.lockUntil = null;
    lockout.wrongAttempts = 0;
    await _saveLockout(lockout);
    return null;
  }

  /// Records one wrong entry. Returns the new lock's unlock time when
  /// this entry hit the 3-attempt limit (and the app is now locked),
  /// or null when the attempt was only counted.
  Future<DateTime?> _recordWrongAttempt() async {
    final lockout = await _loadLockout();
    // Defensive: never stack a second lock on top of a live one.
    if (lockout.lockUntil != null &&
        DateTime.now().isBefore(lockout.lockUntil!)) {
      return lockout.lockUntil;
    }
    lockout.wrongAttempts += 1;
    if (lockout.wrongAttempts < 3) {
      await _saveLockout(lockout);
      return null;
    }
    final duration = lockout.lockCount == 0
        ? const Duration(hours: 8)
        : const Duration(hours: 24);
    lockout.lockUntil = DateTime.now().add(duration);
    lockout.wrongAttempts = 0;
    lockout.lockCount += 1;
    await _saveLockout(lockout);
    return lockout.lockUntil;
  }

  /// Dashboard base URL — the live Worker deployed 2026-10-27.
  /// With this set, activation redeems against the dashboard (1-device
  /// binding, 30-day expiry from first activation), falling back to
  /// offline activation only when the network/server is unavailable.
  static const dashboardBaseUrl = 'https://social-clone-dashboard.qs62765.workers.dev';

  static bool get _dashboardConfigured =>
      dashboardBaseUrl.startsWith('https://') &&
      !dashboardBaseUrl.contains('__SET_DEPLOYED_WORKER_URL_HERE__');

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<File> _licenseFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Stable per-device id, generated once and kept in secure storage.
  ///
  /// It survives app restarts and upgrades, but NOT an uninstall or an
  /// app-data clear: secure storage is wiped then, a fresh id is
  /// generated, and the dashboard will see the device as a new one
  /// (HTTP 409 for a code already bound to the old id). There is no
  /// dashboard unbind endpoint, so that case needs teacher/admin help
  /// outside the app. This is a documented limit, not a silent one.
  /// No hardware identifier is used: the id is random, app-scoped,
  /// and never leaves the device except as `device_id` in the redeem
  /// call itself.
  Future<String> _deviceId() async {
    final existing = await _secureStorage.read(key: _deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final fresh = const Uuid().v4();
    await _secureStorage.write(key: _deviceIdKey, value: fresh);
    return fresh;
  }

  /// One redeem attempt against the dashboard, matching the dashboard
  /// contract in `dashboard/src/index.js` field for field:
  /// request `{ "code": ..., "device_id": ... }`;
  /// success `{ "ok": true, "status": "activated" |
  /// "already_active_on_this_device", "tier": "SC5" | "SC10",
  /// "max_profiles": 5 | 10 }`;
  /// 409 `{ "ok": false, "error": "already_in_use", "message": ... }`;
  /// 404 `{ "ok": false, "error": "invalid_code", ... }`.
  ///
  /// Returns the server-confirmed tier, or null when the caller should
  /// fall back to offline activation (network/server unavailable, or
  /// an unexpected response shape). Throws only for definitive server
  /// rejections (409 already-in-use, 404 not-issued, 403 deactivated,
  /// 403 expired), which must never be masked by the offline fallback
  /// — falling back on those would let a bound, disabled, or expired
  /// code activate here anyway.
  Future<LicenseTier?> _redeem(String code, LicenseTier tier) async {
    final deviceId = await _deviceId();
    late final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$dashboardBaseUrl/api/v1/licenses/redeem'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'code': code, 'device_id': deviceId}),
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      return null;
    } on SocketException {
      return null;
    } on HttpException {
      return null;
    } on http.ClientException {
      return null;
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    if (response.statusCode == 409 && body['error'] == 'already_in_use') {
      throw LicenseAlreadyInUseException(
        body['message'] as String? ??
            'This code is already in use on another device.',
      );
    }
    if (response.statusCode == 404 && body['error'] == 'invalid_code') {
      throw const LicenseNotIssuedException();
    }
    if (response.statusCode == 403 && body['error'] == 'code_deactivated') {
      throw LicenseDeactivatedException(
        body['message'] as String? ??
            'This code has been deactivated. Please check with your teacher.',
      );
    }
    if (response.statusCode == 403 && body['error'] == 'code_expired') {
      throw const LicenseExpiredException();
    }
    if (response.statusCode != 200 || body['ok'] != true) {
      return null;
    }

    // The server's tier must agree with the offline tier (and its
    // profile count); a mismatch is treated as an unusable response,
    // never persisted.
    final serverTier = body['tier'] as String?;
    final serverMaxProfiles = body['max_profiles'];
    final expectedTier =
        tier == LicenseTier.five ? 'SC5' : 'SC10';
    if (serverTier != expectedTier ||
        serverMaxProfiles != tier.maxProfiles) {
      return null;
    }
    final status = body['status'] as String?;
    if (status != 'activated' &&
        status != 'already_active_on_this_device') {
      return null;
    }
    return tier;
  }

  /// Signs out of the current license without touching profiles.
  ///
  /// Deletes the stored license file and clears the in-memory state, so
  /// the license gate returns to the plan/activation funnel and the user
  /// can activate a different code (for example, switching between a
  /// 5-profile and a 10-profile code they both own). Profiles on disk
  /// are NOT deleted, and the stable device id is kept, so re-entering
  /// the old code later on this same device re-activates idempotently
  /// against the dashboard. New profile creation always follows the
  /// currently active tier's cap; profiles created under a higher tier
  /// are not deleted by switching to a lower one.
  Future<void> signOut() async {
    try {
      final file = await _licenseFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // A file we cannot delete must not leave the app licensed:
      // clearing the state still sends the user back to activation,
      // and the next activation overwrites the file.
    }
    state = const AsyncData(null);
  }

  @override
  Future<LicenseState?> build() async {
    try {
      final file = await _licenseFile();
      if (!await file.exists()) {
        return null;
      }
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return LicenseState.fromJson(json);
    } catch (_) {
      // A damaged license file must not brick the app: treat as unlicensed.
      return null;
    }
  }

  /// Validates [rawCode] and persists the resulting license.
  /// Returns the activated tier, or throws [InvalidLicenseCodeException],
  /// [LicenseAlreadyInUseException], [LicenseNotIssuedException],
  /// [LicenseDeactivatedException], [LicenseExpiredException], or
  /// [LicenseLockedException] when the wrong-code lockout is live
  /// (the locked message carries the unlock time).
  ///
  /// Re-pasting the already-stored, server-verified code on the same
  /// device is a local no-op (the dashboard itself is also idempotent
  /// for this case, but no network call is needed to prove it). Any
  /// other activation retries the redeem first when configured, so an
  /// offline-activated code binds itself on its first online activation.
  Future<LicenseTier> activate(String rawCode) async {
    // A live lock blocks every activation attempt, including re-pasting
    // an already-stored code — the lock is on activation, not on one
    // particular code. It does NOT lock the whole app permanently: it
    // ends at [unlockAt], and there is no remote-unlock path.
    final lockedUntil = await _checkLock();
    if (lockedUntil != null) {
      throw LicenseLockedException(lockedUntil);
    }

    final code = rawCode.trim();
    final tier = validateLicenseCode(code);
    if (tier == null) {
      // Malformed/offline-invalid: a wrong entry.
      final lock = await _recordWrongAttempt();
      if (lock != null) throw LicenseLockedException(lock);
      throw const InvalidLicenseCodeException();
    }

    final deviceId = await _deviceId();
    final existing = state.value;
    if (existing != null &&
        existing.code == code &&
        existing.serverVerified &&
        existing.deviceId == deviceId) {
      await _clearLockout();
      return existing.tier;
    }

    var serverVerified = false;
    if (_dashboardConfigured) {
      try {
        final confirmed = await _redeem(code, tier);
        if (confirmed != null) {
          serverVerified = true;
        }
        // _redeem returns null on network/server trouble, which falls
        // through to the offline fallback below — see the class-level
        // tradeoff note. Network errors never count toward lockout.
      } on LicenseNotIssuedException {
        // Well-formed but never issued: a wrong entry, like a malformed
        // code. The other definitive rejections (409 already-in-use,
        // 403 deactivated, 403 expired) prove the code exists and are
        // deliberately NOT counted — see [_LockoutState].
        final lock = await _recordWrongAttempt();
        if (lock != null) throw LicenseLockedException(lock);
        rethrow;
      }
      // LicenseAlreadyInUseException, LicenseDeactivatedException and
      // LicenseExpiredException propagate untouched and uncounted.
    }

    final license = LicenseState(
      tier: tier,
      code: code,
      activatedAt: DateTime.now().toUtc(),
      deviceId: deviceId,
      serverVerified: serverVerified,
    );
    final file = await _licenseFile();
    await file.writeAsString(jsonEncode(license.toJson()));
    state = AsyncData(license);
    // Any successful activation — server-verified or offline fallback —
    // resets the lockout cycle completely (attempts, lock, escalation).
    await _clearLockout();
    return tier;
  }
}

final licenseRepositoryProvider =
    AsyncNotifierProvider<LicenseRepository, LicenseState?>(
      LicenseRepository.new,
    );
