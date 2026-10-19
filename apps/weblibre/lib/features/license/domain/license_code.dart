/*
 * This file is part of Social Clone
 * (see https://github.com/fnjlabs-arch/Social-Clone).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 */

/// License tiers for Social Clone.
///
/// Code format (30 chars total, mixed letters/digits/symbols):
/// - 5-profile plan:  `SC5-`  + 22 random chars + 4 checksum chars
/// - 10-profile plan: `SC10-` + 21 random chars + 4 checksum chars
///
/// The 4-char checksum is a base36 encoding of a weighted sum over the
/// preceding 26 chars, so trivially forged codes are rejected offline.
/// Dashboard-issued codes always carry a valid checksum; the dashboard API
/// can additionally verify issuance server-side (see [LicenseRepository]).
enum LicenseTier {
  five(5, 'SC5-'),
  ten(10, 'SC10-');

  final int maxProfiles;
  final String codePrefix;

  const LicenseTier(this.maxProfiles, this.codePrefix);

  static LicenseTier? fromCode(String code) {
    for (final tier in LicenseTier.values) {
      if (code.startsWith(tier.codePrefix)) {
        return tier;
      }
    }
    return null;
  }
}

/// Validates a 30-char license code offline and returns its tier,
/// or null when the code is malformed.
LicenseTier? validateLicenseCode(String rawCode) {
  final code = rawCode.trim();
  if (code.length != 30) {
    return null;
  }

  final tier = LicenseTier.fromCode(code);
  if (tier == null) {
    return null;
  }

  // Body = first 26 chars (prefix + random part), checksum = last 4.
  final body = code.substring(0, 26);
  final checksum = code.substring(26);

  if (checksum != _checksumFor(body)) {
    return null;
  }

  // Random part may only contain the issuance alphabet.
  final randomPart = body.substring(tier.codePrefix.length);
  if (randomPart.split('').any((c) => !_codeAlphabet.contains(c))) {
    return null;
  }

  return tier;
}

/// Issuance alphabet: unambiguous letters/digits plus a few symbols.
const _codeAlphabet =
    'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#\$%&*';

const _checksumAlphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

String _checksumFor(String body) {
  var sum = 0;
  for (var i = 0; i < body.length; i++) {
    sum += body.codeUnitAt(i) * (i + 1);
  }
  var value = sum % 1296 * 1296; // 36^4
  final chars = StringBuffer();
  for (var i = 0; i < 4; i++) {
    chars.write(_checksumAlphabet[value % 36]);
    value ~/= 36;
  }
  return chars.toString().split('').reversed.join();
}
