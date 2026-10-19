/*
 * This file is part of Social Clone
 * (see https://github.com/fnjlabs-arch/Social-Clone).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 */

/// Kiosk allowlist: the only hosts Social Clone may navigate to.
///
/// Besides the apps themselves, the CDNs and auth helpers they need are
/// included. Everything else is blocked by [AllowlistGuard].
const _allowedHostSuffixes = <String>[
  // TikTok
  'tiktok.com',
  'tiktokv.com',
  'tiktokcdn.com',
  'tiktokcdn-us.com',
  'tiktokcdn-eu.com',
  'ibyteimg.com',
  'ibytedtos.com',
  // Facebook
  'facebook.com',
  'fbcdn.net',
  'fbsbx.com',
  'fb.com',
  'facebook.net',
];

/// Home destinations offered on the Social Clone home screen.
const tiktokHomeUrl = 'https://www.tiktok.com/';
const facebookHomeUrl = 'https://www.facebook.com/';

/// Returns true when [url] may load inside Social Clone.
///
/// Blank/unparsed/non-http(s) URLs (about:blank, loading states) are
/// allowed: they carry no external destination.
bool isAllowedUrl(String? url) {
  if (url == null || url.isEmpty) {
    return true;
  }
  final uri = Uri.tryParse(url);
  if (uri == null) {
    return true;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return true;
  }
  final host = uri.host.toLowerCase();
  if (host.isEmpty) {
    return true;
  }
  return _allowedHostSuffixes.any(
    (suffix) => host == suffix || host.endsWith('.$suffix'),
  );
}
