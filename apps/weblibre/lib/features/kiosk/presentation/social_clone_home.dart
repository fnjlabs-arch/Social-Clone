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
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../geckoview/domain/repositories/tab.dart';
import '../../geckoview/features/tabs/data/entities/tab_mode.dart';
import 'allowlist.dart';

/// Social Clone home: two big buttons, TikTok and Facebook. No address bar,
/// no search, nothing else. Each tap opens the site in a new regular tab.
class SocialCloneHome extends HookConsumerWidget {
  const SocialCloneHome({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, String url) async {
    await ref
        .read(tabRepositoryProvider.notifier)
        .addTab(
          url: Uri.parse(url),
          tabMode: TabMode.regular,
          selectTab: true,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Image.asset('assets/icon/icon.png', width: 88, height: 88),
              const SizedBox(height: 16),
              Text(
                'Social Clone',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose an app to continue',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 40),
              _AppButton(
                label: 'TikTok',
                // TikTok brand-ish: near-black with cyan accent
                background: const Color(0xFF111111),
                foreground: Colors.white,
                accent: const Color(0xFF25F4EE),
                onTap: () => _open(context, ref, tiktokHomeUrl),
              ),
              const SizedBox(height: 16),
              _AppButton(
                label: 'Facebook',
                background: const Color(0xFF1877F2),
                foreground: Colors.white,
                accent: Colors.white,
                onTap: () => _open(context, ref, facebookHomeUrl),
              ),
              const Spacer(flex: 3),
              Text(
                'Powered by SadSha',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
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
  final VoidCallback onTap;

  const _AppButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.accent,
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
        child: Text(
          label,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
