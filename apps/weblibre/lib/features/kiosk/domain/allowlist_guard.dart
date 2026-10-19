/*
 * This file is part of Social Clone
 * (see https://github.com/fnjlabs-arch/Social-Clone).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * Kiosk enforcement: watches every tab's main-frame URL and closes tabs
 * that navigate outside the allowlist (see [isAllowedUrl]). The address
 * bar / search input is disabled separately (SearchRoute), so this only
 * has to catch in-page external links.
 */

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../geckoview/domain/providers/tab_state.dart';
import '../../geckoview/domain/repositories/tab.dart';
import '../domain/allowlist.dart';

class AllowlistGuard extends HookConsumerWidget {
  final Widget child;

  const AllowlistGuard({required this.child, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Tabs already dealt with, so a close racing a URL update cannot
    // re-trigger on the same tab.
    final handled = useState(<String>{});

    ref.listen(tabSortKeysProvider, (previous, next) {
      final entries = next.value;
      for (final entry in entries.entries) {
        final tabId = entry.key;
        if (handled.value.contains(tabId)) {
          continue;
        }
        if (!isAllowedUrl(entry.value.url)) {
          handled.value = {...handled.value, tabId};
          ref.read(tabRepositoryProvider.notifier).closeTab(tabId);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Only TikTok and Facebook are available here.'),
              ),
            );
          }
        }
      }
    });

    return child;
  }
}
