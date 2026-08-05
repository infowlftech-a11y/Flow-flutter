import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/palette.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/buttons.dart';
import 'auth_controller.dart';

/// The front door.
///
/// Replaces a combined form whose first control was a Log in / Create account
/// toggle. Asking that question as a *choice between two screens* rather than
/// a mode switch above a form means the user answers it once, deliberately,
/// and every screen after it has exactly one job.
///
/// New riders are the majority of arrivals, so "Create account" is the filled
/// button and signing in is the quieter one — but both are full-width targets,
/// because guessing wrong is the single most annoying thing an auth screen
/// can do.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: FlowColors.ink,
      body: WaveBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),
                const Center(child: FlowLogo(size: 92)),
                const SizedBox(height: 22),
                const Center(child: FlowWordmark()),
                const SizedBox(height: 18),
                Text(
                  'Kitesurfing lessons on the Egyptian Red Sea.\n'
                  'Find a certified trainer, book hours on the water, '
                  'check in on the beach.',
                  textAlign: TextAlign.center,
                  style: inter(14.5, 460,
                      color: FlowColors.haze, height: 1.55),
                ),
                const Spacer(flex: 3),
                PrimaryButton(
                  label: 'Create an account',
                  icon: Icons.kitesurfing_rounded,
                  onPressed: () {
                    Haptics.select();
                    // Each entry point starts from a clean slate — an error
                    // from a previous attempt must not greet a fresh form.
                    ref.read(authControllerProvider.notifier).reset();
                    context.push('/auth/sign-up');
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    Haptics.select();
                    ref.read(authControllerProvider.notifier).reset();
                    context.push('/auth/sign-in');
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    side: BorderSide(
                        color: FlowColors.mist.withValues(alpha: .28)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('I already have an account',
                      style: inter(15, 640, color: FlowColors.mist)),
                ),
                const SizedBox(height: 18),
                Text(
                  'By continuing you agree to ride within your limits and '
                  'follow your trainer’s safety briefing.',
                  textAlign: TextAlign.center,
                  style: inter(11.5, 440,
                      color: FlowColors.haze.withValues(alpha: .75),
                      height: 1.45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
