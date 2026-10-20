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

/// One plan "flash" screen in the pre-activation funnel: the 5-profile
/// plan first, then the 10-profile plan, then activation.
///
/// Each plan is visualized as one Facebook badge + one TikTok badge per
/// profile — 5 profiles means 5 Facebook accounts and 5 TikTok accounts.
class PlanScreen extends StatelessWidget {
  /// Number of profiles in this plan (also the badge count per brand).
  final int profiles;

  /// Display price, e.g. '$5'.
  final String price;

  /// Highlights this plan as the recommended one.
  final bool bestValue;

  /// Label of the main button at the bottom.
  final String ctaLabel;

  /// Main button: advances the funnel.
  final VoidCallback onCta;

  /// "I have a license code" shortcut: straight to activation.
  final VoidCallback onHaveCode;

  /// Back button; null hides it.
  final VoidCallback? onBack;

  const PlanScreen({
    required this.profiles,
    required this.price,
    required this.bestValue,
    required this.ctaLabel,
    required this.onCta,
    required this.onHaveCode,
    this.onBack,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Your Plan'),
        leading: onBack == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
              ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 8),
              if (bestValue)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'BEST VALUE',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              if (bestValue) const SizedBox(height: 12),
              Text(
                '$profiles Profiles',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                price,
                style: theme.textTheme.displaySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              _BadgeRow(count: profiles, facebook: true),
              const SizedBox(height: 4),
              Text(
                'Facebook accounts',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              _BadgeRow(count: profiles, facebook: false),
              const SizedBox(height: 4),
              Text(
                'TikTok accounts',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              _DetailRow(text: '$profiles fully separate profiles'),
              const SizedBox(height: 10),
              const _DetailRow(
                text: 'TikTok and Facebook ready in every profile',
              ),
              const SizedBox(height: 10),
              const _DetailRow(
                text: 'Each profile stays isolated from the others',
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onCta,
                  child: Text(ctaLabel),
                ),
              ),
              TextButton(
                onPressed: onHaveCode,
                child: const Text('I have a license code'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// A centered, wrapping row of brand badges (one per profile).
class _BadgeRow extends StatelessWidget {
  final int count;
  final bool facebook;

  const _BadgeRow({required this.count, required this.facebook});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < count; i++) _BrandBadge(facebook: facebook),
      ],
    );
  }
}

/// Circular brand badge: blue "f" for Facebook, dark note for TikTok.
class _BrandBadge extends StatelessWidget {
  final bool facebook;

  const _BrandBadge({required this.facebook});

  @override
  Widget build(BuildContext context) {
    const size = 34.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: facebook ? const Color(0xFF1877F2) : Colors.black,
        shape: BoxShape.circle,
        border: facebook
            ? null
            : Border.all(color: Colors.white24),
      ),
      child: Center(
        child: Text(
          facebook ? 'f' : '♪',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 19,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String text;

  const _DetailRow({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.check_circle, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
