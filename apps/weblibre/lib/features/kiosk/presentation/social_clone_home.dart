/*
 * This file is part of Social Clone
 * (see https://github.com/fnjlabs-arch/Social-Clone).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 */

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/filesystem.dart';
import '../../../domain/entities/profile.dart';
import '../../geckoview/domain/providers/tab_state.dart';
import '../../geckoview/domain/repositories/tab.dart';
import '../../geckoview/features/tabs/data/entities/tab_mode.dart';
import '../../license/domain/license_repository.dart';
import '../../user/domain/presentation/utils/profile_switch_handler.dart';
import '../../user/domain/repositories/profile.dart';
import '../domain/allowlist.dart';
import '../domain/kiosk_home_level.dart';
import 'brand_icons.dart';

/// Social Clone home — the profiles door that never closes.
///
/// Two levels (see [KioskHomeLevel]): the profiles list, where
/// profiles are created and switched, and one profile's home with its
/// two big app buttons. Android Back walks the same staircase in
/// reverse: site → profile home → profiles list.
class SocialCloneHome extends HookConsumerWidget {
  const SocialCloneHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inProfileHome = ref.watch(kioskHomeLevelProvider);

    return inProfileHome ? const _ProfileHome() : const _ProfilesList();
  }
}

/// Level 1: the profiles list — the biggest, clearest thing in the app.
class _ProfilesList extends HookConsumerWidget {
  const _ProfilesList();

  Future<void> _addProfile(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(profileRepositoryProvider.notifier);

    try {
      final existing = await ref.read(profileRepositoryProvider.future);

      // Smallest free "Profile N" name, so deletions never produce
      // two profiles with the same label.
      final names = existing.map((profile) => profile.name).toSet();
      var number = 1;
      while (names.contains('Profile $number')) {
        number++;
      }

      final created = await repository.createProfile(
        name: 'Profile $number',
      );

      if (!context.mounted) return;

      // Straight into the new profile (arms the restart the switch
      // needs, with the usual confirmation).
      await handleSwitchProfile(context, ref, created);
    } on ProfileLimitReachedException catch (e) {
      if (!context.mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Profile limit reached'),
          content: Text(
            'Your plan allows up to ${e.maxProfiles} profiles. '
            'To add more, upgrade to a plan with more profiles.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not create a profile. Please try again.'),
        ),
      );
    }
  }

  /// Rename a profile (e.g. to the account's own id/handle). The name
  /// lives in the profile's metadata only — the profile directory is
  /// keyed by uuid — so renaming needs no restart and loses no data.
  /// Empty and duplicate names are rejected in the dialog.
  Future<void> _renameProfile(
    BuildContext context,
    WidgetRef ref,
    Profile profile,
  ) async {
    final controller = TextEditingController(text: profile.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename profile'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Profile name',
            hintText: 'e.g. your account id',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == profile.name) return;
    if (!context.mounted) return;

    try {
      final existing = await ref.read(profileRepositoryProvider.future);
      if (existing.any(
        (other) =>
            other.uuidValue != profile.uuidValue && other.name == newName,
      )) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Another profile already has that name.'),
          ),
        );
        return;
      }
      await ref
          .read(profileRepositoryProvider.notifier)
          .updateProfileMetadata(profile.copyWith.name(newName));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not rename the profile. Please try again.'),
        ),
      );
    }
  }

  /// Sign out of the current license so another code can be activated.
  /// Profiles are NOT deleted and the app is NOT uninstalled: the gate
  /// returns to activation, and the old code can be re-entered later
  /// on this same device.
  Future<void> _signOutLicense(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch license?'),
        content: const Text(
          'You will return to license activation, where you can enter '
          'another code. Your profiles will NOT be deleted, and you can '
          'switch back by re-entering your previous code on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Switch license'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(licenseRepositoryProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profiles = ref.watch(profileRepositoryProvider);
    final maxProfiles = ref
        .watch(licenseRepositoryProvider)
        .value
        ?.tier
        .maxProfiles;
    final activeProfile = filesystem.selectedProfile;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 8),
              child: Column(
                children: [
                  Image.asset('assets/icon/icon.png', width: 72, height: 72),
                  const SizedBox(height: 12),
                  Text(
                    'Social Clone',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose a profile',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (maxProfiles != null)
                    profiles.maybeWhen(
                      data: (list) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${list.length} of $maxProfiles profiles used',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      orElse: () => const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
            Expanded(
              child: profiles.when(
                data: (list) => ListView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  children: [
                    for (final profile in list)
                      _ProfileCard(
                        profile: profile,
                        isActive: profile.uuidValue == activeProfile,
                        onRename: () =>
                            _renameProfile(context, ref, profile),
                        onTap: () {
                          if (profile.uuidValue == activeProfile) {
                            ref
                                .read(kioskHomeLevelProvider.notifier)
                                .enterProfileHome();
                          } else {
                            handleSwitchProfile(context, ref, profile);
                          }
                        },
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 64,
                      child: FilledButton.icon(
                        onPressed: () => _addProfile(context, ref),
                        icon: const Icon(Icons.add, size: 28),
                        label: const Text(
                          'Add Profile',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => _signOutLicense(context, ref),
                      icon: const Icon(Icons.logout, size: 20),
                      label: const Text('Switch license'),
                    ),
                  ],
                ),
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: Text(
                    'Could not load profiles.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Powered by SadSha',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final Profile profile;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onRename;

  const _ProfileCard({
    required this.profile,
    required this.isActive,
    required this.onTap,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = profile.name.isEmpty
        ? '?'
        : profile.name.substring(0, 1).toUpperCase();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: isActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  foregroundColor: isActive
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isActive ? 'Current profile' : 'Tap to open',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isActive
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: isActive ? FontWeight.w600 : null,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onRename,
                  icon: const Icon(Icons.edit),
                  tooltip: 'Rename profile',
                ),
                Icon(
                  isActive ? Icons.check_circle : Icons.chevron_right,
                  color: isActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Level 2: one profile's home — its name and the two big app buttons.
class _ProfileHome extends HookConsumerWidget {
  const _ProfileHome();

  Future<void> _open(
    WidgetRef ref, {
    required String homeUrl,
    required bool Function(String host) siteMatches,
  }) async {
    final tabRepository = ref.read(tabRepositoryProvider.notifier);

    // Resume this profile's existing tab for the site instead of
    // piling up a new one per tap — invisible duplicate tabs are pure
    // memory pressure on the budget phones this app targets. Extra
    // copies left over from earlier sessions are closed.
    final existing = <String>[];
    for (final entry in ref.read(tabStatesProvider).entries) {
      if (siteMatches(entry.value.url.host.toLowerCase())) {
        existing.add(entry.key);
      }
    }

    if (existing.isNotEmpty) {
      for (final extra in existing.skip(1)) {
        await tabRepository.closeTab(extra);
      }
      await tabRepository.selectTab(existing.first);
      return;
    }

    await tabRepository.addTab(
      url: Uri.parse(homeUrl),
      tabMode: TabMode.regular,
      selectTab: true,
      // Back at the site's root returns here, to the profile home —
      // the tab is kept, nothing is closed or asked.
      onBackBehavior: const ReturnToBrowserHomeTabBackBehavior(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profiles = ref.watch(profileRepositoryProvider).value;
    final active = profiles?.firstWhereOrNull(
      (profile) => profile.uuidValue == filesystem.selectedProfile,
    );

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => ref
                    .read(kioskHomeLevelProvider.notifier)
                    .exitToProfiles(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('All profiles'),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Image.asset('assets/icon/icon.png', width: 72, height: 72),
            ),
            const SizedBox(height: 12),
            Text(
              active?.name ?? 'My Profile',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose an app to continue',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 36),
            _AppButton(
              label: 'TikTok',
              // TikTok brand-ish: near-black with cyan accent
              background: const Color(0xFF111111),
              foreground: Colors.white,
              accent: const Color(0xFF25F4EE),
              leading: const TikTokMark(size: 28),
              onTap: () => _open(
                ref,
                homeUrl: tiktokHomeUrl,
                siteMatches: (host) =>
                    host == 'tiktok.com' || host.endsWith('.tiktok.com'),
              ),
            ),
            const SizedBox(height: 16),
            _AppButton(
              label: 'Facebook',
              background: facebookBrandColor,
              foreground: Colors.white,
              accent: Colors.white,
              leading: const FacebookBadge(size: 36),
              onTap: () => _open(
                ref,
                homeUrl: facebookHomeUrl,
                siteMatches: (host) =>
                    host == 'facebook.com' || host.endsWith('.facebook.com'),
              ),
            ),
            const SizedBox(height: 36),
            Text(
              'Powered by SadSha',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _AppButton extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final Color accent;
  final Widget leading;
  final VoidCallback onTap;

  const _AppButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.accent,
    required this.leading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: accent.withValues(alpha: 0.5), width: 1.5),
          ),
        ),
        onPressed: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            leading,
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
