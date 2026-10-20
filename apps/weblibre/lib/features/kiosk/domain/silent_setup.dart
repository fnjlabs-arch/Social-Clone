/*
 * This file is part of Social Clone
 * (see https://github.com/fnjlabs-arch/Social-Clone).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 */

import 'package:flutter_mozilla_components/flutter_mozilla_components.dart'
    show AppLinksMode;
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/logger.dart';
import '../../geckoview/features/browser/domain/services/browser_addon.dart';
import '../../onboarding/presentation/onboarding_defaults.dart';
import '../../user/data/models/ublock_filter_list_settings.dart';
import '../../user/domain/repositories/engine_settings.dart';
import '../../user/domain/repositories/general_settings.dart';
import '../../user/domain/repositories/onboarding.dart';

/// The uBlock Origin add-on id, as seeded by upstream's onboarding.
const _ublockAddonGuid = 'uBlock0@raymondhill.net';

/// Social Clone's own uBlock filter list (TikTok app-upsell hiders),
/// committed in this repo and fetched by uBlock as an external list.
/// Best effort by nature — TikTok rotates its markup, so the rules in
/// `filters/tiktok-upsell-filters.txt` may need refreshing over time.
const _socialCloneFilterListUrl =
    'https://raw.githubusercontent.com/fnjlabs-arch/Social-Clone/main/filters/tiktok-upsell-filters.txt';

/// Applies, silently and once per profile, everything upstream's
/// onboarding wizard would have asked about — so the wizard never has
/// to run in this app (the router no longer routes to it at all).
///
/// Mirrors the wizard's Quick Start path: privacy defaults, uBlock
/// Origin with its optimized (annoyances-inclusive) filter lists,
/// plus two kiosk decisions of our own: the Social Clone filter list
/// is added, and app links are set to NEVER leave the browser (no
/// "Open this link in Facebook?" prompt — links open inside, always).
///
/// Gated on the onboarding revision: a profile whose revision is
/// already current is left untouched. If the uBlock install does not
/// complete (e.g. no network yet), the revision is NOT pushed, so the
/// whole setup simply retries on the next app start.
Future<void> applyKioskSilentSetup(WidgetRef ref) async {
  final onboarding = ref.read(onboardingRepositoryProvider.notifier);

  if (!await onboarding.isOutdated()) {
    return;
  }

  try {
    await applyOnboardingPrivacyDefaults(ref);
    await applyOnboardingOptimizedUBlockDefaults(ref);
    await _addSocialCloneFilterList(ref);
    await _disableAppLinkHandoffs(ref);

    final installed = await ref
        .read(browserAddonServiceProvider.notifier)
        .install(_ublockAddonGuid);

    if (!installed) {
      logger.w(
        'Silent uBlock install did not complete; '
        'kiosk setup will retry on next launch',
      );
      return;
    }

    await onboarding.pushRevision(OnboardingRepository.targetRevision);
  } catch (e, s) {
    logger.w(
      'Silent kiosk setup failed; will retry on next launch',
      error: e,
      stackTrace: s,
    );
  }
}

Future<void> _addSocialCloneFilterList(WidgetRef ref) async {
  await ref
      .read(engineSettingsRepositoryProvider.notifier)
      .updateSettings((current) {
        final lists = current.ublockFilterListSettings;
        if (lists == null || !lists.enabled) {
          return current;
        }
        if (lists.externalFilterLists.any(
          (list) => list.url == _socialCloneFilterListUrl,
        )) {
          return current;
        }

        return current.copyWith.ublockFilterListSettings(
          UBlockFilterListSettings(
            enabled: lists.enabled,
            enabledStockListTokens: lists.enabledStockListTokens,
            autoEnabledStockListTokens: lists.autoEnabledStockListTokens,
            autoSelectRegionalLists: lists.autoSelectRegionalLists,
            externalFilterLists: [
              ...lists.externalFilterLists,
              UBlockExternalList(
                url: _socialCloneFilterListUrl,
                description:
                    'Social Clone — TikTok app-upsell hiders (best effort)',
              ),
            ],
          ),
        );
      });
}

Future<void> _disableAppLinkHandoffs(WidgetRef ref) async {
  await ref
      .read(generalSettingsRepositoryProvider.notifier)
      .updateSettings(
        (current) => current.copyWith(appLinksMode: AppLinksMode.never),
      );
}
