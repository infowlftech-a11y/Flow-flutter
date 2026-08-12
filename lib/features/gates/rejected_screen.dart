import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/radii.dart';
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
///
/// It is also, deliberately, not a dead end. `rejectTrainer` has always
/// written the admin's reason to `reviewNote`, and this screen used to tell
/// the trainer to "check your notifications for the reason" — sending them
/// to a text sheet to read something already sitting on their own profile.
/// The reason is shown here, next to the button that acts on it: most
/// declines are a certification that could not be verified, which is a
/// fixable problem, and a marketplace that loses a real trainer to an
/// unreadable rejection has lost supply for nothing.
class RejectedScreen extends ConsumerWidget {
  const RejectedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final reason = session.user?.reviewNote?.trim() ?? '';

    return GateScaffold(
      onSignOut: () => ref.read(signOutProvider)(),
      child: Column(
        children: [
          const Spacer(),
          GateHeadline(
            icon: Symbols.assignment_late_rounded,
            color: context.tones.warning,
            title: 'Application not approved',
            body: 'Hi ${session.displayName.split(' ').first} — we could not '
                'verify your trainer application this time. This is usually '
                'a certification we could not confirm, and it is often '
                'fixable.',
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 24),
            _ReasonCard(reason: reason),
          ],
          const SizedBox(height: 28),
          PrimaryButton(
            label: 'Fix and resubmit',
            icon: Symbols.edit_document_rounded,
            onPressed: () => context.push('/onboarding/trainer/reapply'),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => context.push('/support'),
            icon: const Icon(Symbols.support_agent_rounded, size: 18),
            label: const Text('Talk to support'),
          ),
          const Spacer(flex: 2),
          const FlowWordmark(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// The admin's own words, quoted rather than paraphrased.
///
/// Left-aligned and set as a quote: this is the one piece of text on the
/// screen written by a person about *this* application, and centring it with
/// the rest of the gate copy would bury it in the apology around it.
class _ReasonCard extends StatelessWidget {
  const _ReasonCard({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: tones.card.withValues(alpha: .7),
        borderRadius: FlowRadii.inset,
        border: Border(
          left: BorderSide(color: tones.warning, width: 3),
          top: BorderSide(color: tones.line),
          right: BorderSide(color: tones.line),
          bottom: BorderSide(color: tones.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.rate_review_rounded, size: 16, color: tones.warning),
              const SizedBox(width: 8),
              Text('What our reviewer said',
                  style: inter(12.5, 700,
                      color: tones.warning, spacing: .4)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            reason,
            style: inter(14.5, 480,
                color: context.scheme.onSurface, height: 1.5),
          ),
        ],
      ),
    );
  }
}
