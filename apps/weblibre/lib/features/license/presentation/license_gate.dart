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
import 'welcome_screen.dart';

/// Wraps the whole app: without an activated license the user only sees
/// the welcome screen and the license activation screen; the real app is
/// not built at all.
///
/// The gate lives above the app router (MaterialApp.builder), so no
/// Navigator is available here — welcome ↔ activation switching is done
/// with local state, not routes.
class LicenseGate extends HookConsumerWidget {
  final Widget child;

  const LicenseGate({required this.child, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final license = ref.watch(licenseRepositoryProvider);
    final showActivation = useState(false);

    Widget locked() {
      return showActivation.value
          ? LicenseActivationScreen(
              onBack: () => showActivation.value = false,
            )
          : WelcomeScreen(onActivate: () => showActivation.value = true);
    }

    return license.when(
      data: (state) => state != null ? child : locked(),
      // While the stored license is being read, stay on the locked side.
      loading: locked,
      error: (_, _) => locked(),
    );
  }
}
