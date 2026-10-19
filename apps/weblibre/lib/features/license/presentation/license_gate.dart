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

import '../domain/license_repository.dart';
import 'welcome_screen.dart';

/// App-level gate: until a license code has been activated on this device,
/// the whole app UI stays hidden behind the welcome + activation flow.
class LicenseGate extends HookConsumerWidget {
  final Widget child;

  const LicenseGate({required this.child, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final license = ref.watch(licenseRepositoryProvider);

    return license.when(
      data: (state) => state == null ? const WelcomeScreen() : child,
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const WelcomeScreen(),
    );
  }
}
