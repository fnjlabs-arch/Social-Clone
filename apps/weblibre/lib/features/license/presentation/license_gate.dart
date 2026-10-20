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
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../domain/license_repository.dart';
import 'license_activation_screen.dart';
import 'plan_screens.dart';

/// Wraps the whole app: without an activated license the user only sees
/// the locked funnel — the 5-profile plan, the 10-profile plan, then
/// activation; the real app is not built at all.
///
/// The gate lives above the app router (MaterialApp.builder), so no
/// Navigator is available here — funnel steps are switched with local
/// state, not routes.
class LicenseGate extends HookConsumerWidget {
  final Widget child;

  const LicenseGate({required this.child, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final license = ref.watch(licenseRepositoryProvider);
    // Funnel step: 0 plan (5 profiles) → 1 plan (10 profiles)
    // → 2 activation. The funnel starts at the first plan — there is
    // no welcome screen in front of it.
    final step = useState(0);

    Widget locked() {
      switch (step.value) {
        case 1:
          return PlanScreen(
            profiles: 10,
            price: '\$7',
            bestValue: true,
            ctaLabel: 'Activate License',
            onCta: () => step.value = 2,
            onHaveCode: () => step.value = 2,
            onBack: () => step.value = 0,
          );
        case 2:
          return LicenseActivationScreen(
            onBack: () => step.value = 1,
          );
        default:
          return PlanScreen(
            profiles: 5,
            price: '\$5',
            bestValue: false,
            ctaLabel: 'Continue',
            onCta: () => step.value = 1,
            onHaveCode: () => step.value = 2,
          );
      }
    }

    return license.when(
      data: (state) => state != null ? child : locked(),
      // While the stored license is being read, stay on the locked side.
      loading: locked,
      error: (_, _) => locked(),
    );
  }
}
