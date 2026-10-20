// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'kiosk_home_level.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(KioskHomeLevel)
final kioskHomeLevelProvider = KioskHomeLevelProvider._();

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
final class KioskHomeLevelProvider
    extends $NotifierProvider<KioskHomeLevel, bool> {
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
  KioskHomeLevelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'kioskHomeLevelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$kioskHomeLevelHash();

  @$internal
  @override
  KioskHomeLevel create() => KioskHomeLevel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$kioskHomeLevelHash() => r'8f3a1c9d4e5b60718293a4b5c6d7e8f90a1b2c3d';

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

abstract class _$KioskHomeLevel extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
