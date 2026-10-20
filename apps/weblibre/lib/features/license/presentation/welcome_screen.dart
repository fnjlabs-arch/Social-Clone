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

/// First screen an unlicensed user sees: what Social Clone gives them,
/// then a button into the license activation.
class WelcomeScreen extends StatelessWidget {
  /// Called when the user taps "Activate License". Navigation is owned
  /// by the caller (the license gate lives above the app router, so no
  /// Navigator is available here).
  final VoidCallback onActivate;

  const WelcomeScreen({required this.onActivate, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              Center(
                child: Image.asset(
                  'assets/icon/icon.png',
                  width: 96,
                  height: 96,
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'Social Clone',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Many accounts. One app.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const _BenefitRow(
                icon: Icons.people_outline,
                text: '5 or 10 fully separate profiles, as per your license',
              ),
              const SizedBox(height: 16),
              const _BenefitRow(
                icon: Icons.phone_android_outlined,
                text: 'TikTok and Facebook ready in every profile',
              ),
              const SizedBox(height: 16),
              const _BenefitRow(
                icon: Icons.lock_outline,
                text: 'Each profile stays isolated from the others',
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onActivate,
                  child: const Text('Activate License'),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Powered by SadSha',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
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

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _BenefitRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: 14),
        Expanded(
          child: Text(text, style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }
}
