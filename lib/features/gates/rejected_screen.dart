import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/gate.dart';
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

    return GateScaffold(
      onSignOut: () => ref.read(signOutProvider)(),
      child: Column(
        children: [
          const Spacer(),
          GateHeadline(
            icon: Icons.assignment_late_outlined,
            color: context.tones.warning,
            title: 'Application not approved',
            body: 'Hi ${session.displayName.split(' ').first} — we could not '
                'verify your trainer application this time. This is usually '
                'a certification we could not confirm, and it is often '
                'fixable.',
          ),
          const SizedBox(height: 12),
          Text(
            'Check your notifications for the reason, then talk to us — '
            'we can re-open your application.',
            textAlign: TextAlign.center,
            style: inter(14, 440, color: context.scheme.onSurfaceVariant, height: 1.5),
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
    );
  }
}
