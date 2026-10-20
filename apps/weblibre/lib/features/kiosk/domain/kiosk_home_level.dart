/*
 * This file is part of Social Clone
 * (see https://github.com/fnjlabs-arch/Social-Clone).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 */

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'kiosk_home_level.g.dart';

/// Which level of the Social Clone home surface is showing.
///
/// The home has two levels: the profiles list (the door that never
/// closes — profile creation and switching live there) and one
/// profile's home (its TikTok / Facebook buttons). `false` is the
/// profiles list, `true` is a profile home.
///
/// The level lives in a provider rather than in the home widget's own
/// state because the home surface is unmounted while a tab is on
/// screen: leaving for a tab and coming back through Android Back has
/// to land on the profile home again, not reset to the list. Back
/// handling in the browser screen reads this too — it is what turns a
/// Back press on the profile home into a step out to the list.
@Riverpod(keepAlive: true)
class KioskHomeLevel extends _$KioskHomeLevel {
  @override
  bool build() => false;

  /// Enters the active profile's home (its two app buttons).
  void enterProfileHome() => state = true;

  /// Returns to the profiles list.
  void exitToProfiles() => state = false;

  /// Steps one level out for an Android Back press.
  ///
  /// Returns true when the press was consumed (profile home → list);
  /// false when already on the list, leaving the press to the caller's
  /// own fall-through (the browser's double-back-to-exit handling).
  bool stepBack() {
    if (!state) {
      return false;
    }
    state = false;
    return true;
  }
}
