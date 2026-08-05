import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/palette.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/brand.dart';
import '../../providers/providers.dart';

/// "I'm a Kiter" / "I'm a Trainer". Sign-out lives in the app-bar *trailing*
/// slot — never the back slot (§3.2, §10.4).
class RoleSelectScreen extends ConsumerWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: FlowColors.ink,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            onPressed: () => ref.read(signOutProvider)(),
            icon: const Icon(Icons.logout_rounded,
                size: 18, color: FlowColors.haze),
            label:
                Text('Sign out', style: inter(14, 600, color: FlowColors.haze)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: WaveBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Text('Who are you\non the beach?',
                    style:
                        sora(34, 780, color: FlowColors.mist, spacing: -1, height: 1.1)),
                const SizedBox(height: 12),
                Text(
                  'This decides what FLOW looks like for you. You only pick once.',
                  style: inter(15, 440, color: FlowColors.haze, height: 1.5),
                ),
                const SizedBox(height: 36),
                _RoleCard(
                  icon: Icons.kitesurfing_rounded,
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
                  icon: Icons.storefront_rounded,
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
          ),
        ),
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
      color: FlowColors.navy900,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: FlowColors.navy700),
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
                      color: FlowColors.azure.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: FlowColors.azure, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(title,
                        style: sora(20, 720,
                            color: FlowColors.mist, spacing: -.3)),
                  ),
                  const Icon(Icons.arrow_forward_rounded,
                      color: FlowColors.azure),
                ],
              ),
              const SizedBox(height: 14),
              Text(body,
                  style:
                      inter(14, 440, color: FlowColors.haze, height: 1.5)),
              if (footnote != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.verified_user_outlined,
                        size: 15, color: FlowColors.slate),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(footnote!,
                          style: inter(12, 500, color: FlowColors.slate)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Text(cta.toUpperCase(),
                  style: inter(12, 760, color: FlowColors.azure, spacing: 1.4)),
            ],
          ),
        ),
      ),
    );
  }
}
