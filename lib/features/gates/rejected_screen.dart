import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/palette.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/buttons.dart';
import '../../providers/providers.dart';

/// The gate for a declined trainer application.
///
/// v2.6 had no such gate: `status == 'rejected'` fell through to `ready`, so
/// a declined trainer got a full Command Center while being invisible in
/// Explore — a calendar nobody could book (§2.4, §14.3). That was harmless
/// only because nothing in the app could set the status. The admin console
/// can, so the state is now real and handled.
class RejectedScreen extends ConsumerWidget {
  const RejectedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return Scaffold(
      backgroundColor: FlowColors.ink,
      body: WaveBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: TextButton.icon(
                    onPressed: () =>
                        ref.read(authRepositoryProvider).signOut(),
                    icon: const Icon(Icons.logout_rounded,
                        size: 18, color: FlowColors.haze),
                    label: Text('Sign out',
                        style: inter(14, 600, color: FlowColors.haze)),
                  ),
                ),
                const Spacer(),
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: FlowColors.amber.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Icon(Icons.assignment_late_outlined,
                      color: FlowColors.amber, size: 40),
                ),
                const SizedBox(height: 28),
                Text('Application not approved',
                    textAlign: TextAlign.center,
                    style:
                        sora(26, 760, color: FlowColors.mist, spacing: -.5)),
                const SizedBox(height: 14),
                Text(
                  'Hi ${session.displayName.split(' ').first} — we could not '
                  'verify your trainer application this time. This is usually '
                  'a certification we could not confirm, and it is often '
                  'fixable.',
                  textAlign: TextAlign.center,
                  style: inter(15, 440, color: FlowColors.haze, height: 1.55),
                ),
                const SizedBox(height: 12),
                Text(
                  'Check your notifications for the reason, then talk to us — '
                  'we can re-open your application.',
                  textAlign: TextAlign.center,
                  style: inter(13.5, 440,
                      color: FlowColors.slate, height: 1.5),
                ),
                const SizedBox(height: 28),
                PrimaryButton(
                  label: 'Contact support',
                  icon: Icons.support_agent_rounded,
                  onPressed: () => context.push('/support'),
                ),
                const Spacer(flex: 2),
                const FlowWordmark(),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
