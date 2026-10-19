/*
 * This file is part of Social Clone
 * (see https://github.com/fnjlabs-arch/Social-Clone).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 */

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'license_code.dart';

/// A license activated on this device.
class LicenseState {
  final LicenseTier tier;
  final String code;
  final DateTime activatedAt;

  const LicenseState({
    required this.tier,
    required this.code,
    required this.activatedAt,
  });

  Map<String, dynamic> toJson() => {
    'tier': tier.name,
    'code': code,
    'activatedAt': activatedAt.toIso8601String(),
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
    );
  }
}

/// Thrown when a license code fails offline validation.
class InvalidLicenseCodeException implements Exception {
  const InvalidLicenseCodeException();
}

/// Holds the device license. Stored app-global (not per-profile) so it
/// survives profile switches, and checked before any profile may be added.
///
/// Validation is offline (format + checksum). When the Social Clone
/// dashboard API is live, [activate] should POST the code there first and
/// only fall back to offline validation when the network is unavailable.
class LicenseRepository extends StateNotifier<AsyncValue<LicenseState?>> {
  LicenseRepository() : super(const AsyncValue.loading()) {
    _load();
  }

  static const _fileName = 'social_clone_license.json';

  Future<File> _licenseFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<void> _load() async {
    try {
      final file = await _licenseFile();
      if (!await file.exists()) {
        state = const AsyncValue.data(null);
        return;
      }
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      state = AsyncValue.data(LicenseState.fromJson(json));
    } catch (_) {
      // A damaged license file must not brick the app: treat as unlicensed.
      state = const AsyncValue.data(null);
    }
  }

  /// Validates [rawCode] and persists the resulting license.
  /// Returns the activated tier, or throws [InvalidLicenseCodeException].
  Future<LicenseTier> activate(String rawCode) async {
    final tier = validateLicenseCode(rawCode);
    if (tier == null) {
      throw const InvalidLicenseCodeException();
    }

    // TODO(social-clone): when the dashboard API is live, verify the code
    // server-side here (POST /api/v1/licenses/redeem) before persisting.

    final license = LicenseState(
      tier: tier,
      code: rawCode.trim(),
      activatedAt: DateTime.now().toUtc(),
    );
    final file = await _licenseFile();
    await file.writeAsString(jsonEncode(license.toJson()));
    state = AsyncValue.data(license);
    return tier;
  }
}

final licenseRepositoryProvider =
    StateNotifierProvider<LicenseRepository, AsyncValue<LicenseState?>>(
      (ref) => LicenseRepository(),
    );
