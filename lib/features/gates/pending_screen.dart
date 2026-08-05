import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/palette.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/brand.dart';
import '../../providers/providers.dart';

/// The trainer approval gate. The profile is streamed, so admin approval in
/// the web console releases this screen live — no restart (§2.3).
class PendingScreen extends ConsumerWidget {
  const PendingScreen({super.key});

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
                    onPressed: () => ref.read(signOutProvider)(),
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
                    color: FlowColors.azure.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Icon(Icons.hourglass_top_rounded,
                      color: FlowColors.azure, size: 40),
                ),
                const SizedBox(height: 28),
                Text('Under review',
                    style: sora(28, 760, color: FlowColors.mist, spacing: -.6)),
                const SizedBox(height: 14),
                Text(
                  'Thanks ${session.displayName} — your trainer profile is with '
                  'our crew. We check every certification by hand so riders can '
                  'book with total confidence.',
                  textAlign: TextAlign.center,
                  style: inter(15, 440, color: FlowColors.haze, height: 1.55),
                ),
                const SizedBox(height: 22),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: FlowColors.navy900.withValues(alpha: .7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: FlowColors.azure.withValues(alpha: .25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: FlowColors.azure),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          "This screen unlocks the moment you're approved.",
                          style: inter(13, 560, color: FlowColors.mist),
                        ),
                      ),
                    ],
                  ),
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
