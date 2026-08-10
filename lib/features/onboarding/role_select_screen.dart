import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/radii.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/gate.dart';
import '../../providers/providers.dart';

/// "I'm a Kiter" / "I'm a Trainer". Sign-out lives in the app-bar *trailing*
/// slot — never the back slot (§3.2, §10.4).
class RoleSelectScreen extends ConsumerWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GateScaffold(
      onSignOut: () => ref.read(signOutProvider)(),
      child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Text('Who are you\non the beach?',
                    style:
                        display(32, 780, color: context.scheme.onSurface, spacing: -1, height: 1.1)),
                const SizedBox(height: 12),
                Text(
                  'This decides what FLOW looks like for you. You only pick once.',
                  style: inter(15, 440, color: context.scheme.onSurfaceVariant, height: 1.5),
                ),
                const SizedBox(height: 32),
                _RoleCard(
                  icon: Symbols.kitesurfing_rounded,
                  title: "I'm a Kiter",
                  body:
                      'Find certified trainers, book hours on the water and check in with a QR ticket.',
                  cta: 'Ride with FLOW',
                  onTap: () {
                    Haptics.select();
                    // push, not go: `go` replaces the location outright, so
                    // the form had nothing to pop back to and a mistapped
                    // role was a dead end short of signing out.
                    context.push('/onboarding/rider');
                  },
                ),
                const SizedBox(height: 18),
                _RoleCard(
                  icon: Symbols.storefront_rounded,
                  title: "I'm a Trainer",
                  body:
                      'Run your calendar, approve requests, scan riders in and track earnings.',
                  cta: 'Work with FLOW',
                  footnote:
                      'Trainer accounts are reviewed by our team before going live.',
                  onTap: () {
                    Haptics.select();
                    // See the rider branch — pushed so Back returns here.
                    context.push('/onboarding/trainer');
                  },
                ),
                const Spacer(),
              ],
            ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.cta,
    required this.onTap,
    this.footnote,
  });

  final IconData icon;
  final String title;
  final String body;
  final String cta;
  final VoidCallback onTap;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.tones.card,
      borderRadius: FlowRadii.dialog,
      child: InkWell(
        borderRadius: FlowRadii.dialog,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: FlowRadii.dialog,
            border: Border.all(color: context.tones.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: context.scheme.primary.withValues(alpha: .15),
                      borderRadius: FlowRadii.inset,
                    ),
                    child: Icon(icon, color: context.scheme.primary, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(title,
                        style: display(20, 720,
                            color: context.scheme.onSurface, spacing: -.3)),
                  ),
                  Icon(Symbols.arrow_forward_rounded,
                      color: context.scheme.primary),
                ],
              ),
              const SizedBox(height: 14),
              Text(body,
                  style:
                      inter(14, 440, color: context.scheme.onSurfaceVariant, height: 1.5)),
              if (footnote != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Symbols.verified_user_rounded,
                        size: 15, color: context.tones.textFaint),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(footnote!,
                          style: inter(12.5, 500, color: context.tones.textFaint)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Text(cta.toUpperCase(),
                  style: inter(12.5, 760, color: context.scheme.primary, spacing: 1.4)),
            ],
          ),
        ),
      ),
    );
  }
}
