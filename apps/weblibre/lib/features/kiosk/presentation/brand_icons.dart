/*
 * This file is part of Social Clone
 * (see https://github.com/fnjlabs-arch/Social-Clone).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 */

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Real TikTok and Facebook brand glyphs, drawn as vector paths.
///
/// The path data is the official logo geometry from the Simple Icons
/// set (CC0). Drawing the actual glyphs matters: the plan screens and
/// the profile home are the whole product surface for non-technical
/// users, and a generic music note does not read as "TikTok" to them.
const _tiktokPath =
    'M12.525.02c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z';

const _facebookPath =
    'M9.101 23.691v-7.98H6.627v-3.667h2.474v-1.58c0-4.085 1.848-5.978 5.858-5.978.401 0 .955.042 1.468.103a8.68 8.68 0 0 1 1.141.195v3.325a8.623 8.623 0 0 0-.653-.036 26.805 26.805 0 0 0-.733-.009c-.707 0-1.259.096-1.675.309a1.686 1.686 0 0 0-.679.622c-.258.42-.374.995-.374 1.752v1.297h3.919l-.386 2.103-.287 1.564h-3.246v8.245C19.396 23.238 24 18.179 24 12.044c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.628 3.874 10.35 9.101 11.647Z';

const _tiktokSvg =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="$_tiktokPath"/></svg>';

const _facebookSvg =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="$_facebookPath"/></svg>';

/// Facebook brand blue, shared by badges, buttons and plan screens.
const facebookBrandColor = Color(0xFF1877F2);

/// The TikTok note glyph in [color] (white on dark by default).
class TikTokMark extends StatelessWidget {
  final double size;
  final Color color;

  const TikTokMark({required this.size, this.color = Colors.white, super.key});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      _tiktokSvg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

/// Circular TikTok badge: black disc with the white note glyph.
class TikTokBadge extends StatelessWidget {
  final double size;

  const TikTokBadge({this.size = 34, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.black,
        shape: BoxShape.circle,
      ),
      child: Center(child: TikTokMark(size: size * 0.58)),
    );
  }
}

/// Circular Facebook badge: the official glyph is a blue disc with the
/// "f" knocked out of it, so it is drawn in brand blue over a white
/// disc — the cut-out then reads as the white "f" of the real logo.
class FacebookBadge extends StatelessWidget {
  final double size;

  const FacebookBadge({this.size = 34, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black12),
      ),
      child: ClipOval(
        child: SvgPicture.string(
          _facebookSvg,
          width: size,
          height: size,
          colorFilter: const ColorFilter.mode(
            facebookBrandColor,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}
