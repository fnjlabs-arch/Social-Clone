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
/// Code format (mixed letters/digits/symbols):
/// - 5-profile plan:  `SC5-`  + 22 random chars + 4 checksum chars = 30 total
/// - 10-profile plan: `SC10-` + 31 random chars + 4 checksum chars = 40 total
///
/// The longer SC10 code is the premium tier's distinguishing trait. The
/// 4-char checksum is a base36 encoding of a weighted sum over the body
/// (prefix + random part), so trivially forged codes are rejected offline.
/// Dashboard-issued codes always carry a valid checksum; the dashboard API
/// can additionally verify issuance server-side (see [LicenseRepository]).
enum LicenseTier {
  five(5, 'SC5-', 30),
  ten(10, 'SC10-', 40);

  final int maxProfiles;
  final String codePrefix;

  /// Total code length including prefix and checksum.
  final int codeLength;

  const LicenseTier(this.maxProfiles, this.codePrefix, this.codeLength);

  /// Body = everything except the trailing 4 checksum chars.
  int get bodyLength => codeLength - 4;

  static LicenseTier? fromCode(String code) {
    for (final tier in LicenseTier.values) {
      if (code.startsWith(tier.codePrefix)) {
        return tier;
      }
    }
    return null;
  }
}

/// Validates a license code offline and returns its tier,
/// or null when the code is malformed. A code only ever validates
/// against its own tier's length (an SC5 code is 30 chars, an SC10
/// code is 40 — they are not interchangeable).
LicenseTier? validateLicenseCode(String rawCode) {
  final code = rawCode.trim();

  final tier = LicenseTier.fromCode(code);
  if (tier == null) {
    return null;
  }

  if (code.length != tier.codeLength) {
    return null;
  }

  // Body = prefix + random part, checksum = last 4 chars.
  final body = code.substring(0, tier.bodyLength);
  final checksum = code.substring(tier.bodyLength);

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
