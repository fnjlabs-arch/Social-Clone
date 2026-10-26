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

  /// Dashboard base URL — SET THIS BEFORE SHIPPING A BUILD that is
  /// meant to enforce device binding.
  ///
  /// PLACEHOLDER VALUE — DO NOT SHIP AS-IS: the dashboard is not
  /// deployed yet (its Cloudflare token lacks Workers/D1 scopes), so
  /// there is no live Worker URL to put here. Replace this entire
  /// string with the deployed Worker URL printed by `wrangler deploy`
  /// (a `*.workers.dev` address, no trailing slash, no `/api/...`
  /// path — the redeem path is appended by [_redeem]).
  /// While this placeholder is in place, [_redeem] is skipped and
  /// activation uses the offline fallback path only.
  static const dashboardBaseUrl = 'https://__SET_DEPLOYED_WORKER_URL_HERE__';

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
  /// an unexpected response shape). Throws only for the two definitive
  /// server rejections (409 already-in-use, 404 not-issued), which
  /// must never be masked by the offline fallback — falling back on
  /// those would let a code bound elsewhere activate here anyway.
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
  /// [LicenseAlreadyInUseException], or [LicenseNotIssuedException].
  ///
  /// Re-pasting the already-stored, server-verified code on the same
  /// device is a local no-op (the dashboard itself is also idempotent
  /// for this case, but no network call is needed to prove it). Any
  /// other activation retries the redeem first when configured, so an
  /// offline-activated code binds itself on its first online activation.
  Future<LicenseTier> activate(String rawCode) async {
    final code = rawCode.trim();
    final tier = validateLicenseCode(code);
    if (tier == null) {
      throw const InvalidLicenseCodeException();
    }

    final deviceId = await _deviceId();
    final existing = state.value;
    if (existing != null &&
        existing.code == code &&
        existing.serverVerified &&
        existing.deviceId == deviceId) {
      return existing.tier;
    }

    var serverVerified = false;
    if (_dashboardConfigured) {
      final confirmed = await _redeem(code, tier);
      if (confirmed != null) {
        serverVerified = true;
      }
      // _redeem throws on 409/404 (definitive rejections) and returns
      // null on network/server trouble, which falls through to the
      // offline fallback below — see the class-level tradeoff note.
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
    return tier;
  }
}

final licenseRepositoryProvider =
    AsyncNotifierProvider<LicenseRepository, LicenseState?>(
      LicenseRepository.new,
    );
