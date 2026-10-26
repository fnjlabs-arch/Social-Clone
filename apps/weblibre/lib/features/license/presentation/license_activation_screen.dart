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
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../domain/license_code.dart';
import '../domain/license_repository.dart';

/// First-run activation: the user enters the license code bought
/// from their teacher (30 chars for the 5-profile plan, 40 for the
/// 10-profile plan — one field accepts both). Until a valid code is
/// stored, the rest of the app stays hidden behind [LicenseGate].
class LicenseActivationScreen extends HookConsumerWidget {
  /// Called when the user taps back (returns to the welcome screen).
  /// There is no Navigator above the license gate, so the gate owns
  /// this switching.
  final VoidCallback? onBack;

  const LicenseActivationScreen({this.onBack, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final codeController = TextEditingController();
    final error = ValueNotifier<String?>(null);
    final busy = ValueNotifier(false);

    Future<void> activate() async {
      error.value = null;
      final code = codeController.text.trim();
      if (code.isEmpty) {
        error.value = 'Please enter your license code.';
        return;
      }
      busy.value = true;
      try {
        final tier = await ref
            .read(licenseRepositoryProvider.notifier)
            .activate(code);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Activated! ${tier.maxProfiles} profiles unlocked.',
              ),
            ),
          );
        }
      } on InvalidLicenseCodeException {
        error.value = 'This code is not valid. Please check and try again.';
      } on LicenseAlreadyInUseException catch (e) {
        // The dashboard's own message, shown verbatim: this code is
        // bound to a different device and cannot activate here.
        error.value = e.message;
      } on LicenseNotIssuedException {
        error.value =
            'This code was not issued by the dashboard. Please check '
            'with your teacher and try again.';
      } catch (_) {
        error.value = 'Something went wrong. Please try again.';
      } finally {
        busy.value = false;
      }
    }

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activate License'),
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
              const Spacer(flex: 2),
              Image.asset('assets/icon/icon.png', width: 96, height: 96),
              const SizedBox(height: 20),
              Text(
                'Social Clone',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the license code from your teacher to unlock the app.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              ValueListenableBuilder<String?>(
                valueListenable: error,
                builder: (context, errorText, _) => TextField(
                  controller: codeController,
                  maxLength: 40,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    letterSpacing: 1.2,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'License code',
                    hintText: 'SC5-… or SC10-…',
                    border: const OutlineInputBorder(),
                    errorText: errorText,
                    counterText: '',
                  ),
                  onSubmitted: (_) => activate(),
                ),
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<bool>(
                valueListenable: busy,
                builder: (context, isBusy, _) => SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: isBusy ? null : activate,
                    child: isBusy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Activate'),
                  ),
                ),
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
