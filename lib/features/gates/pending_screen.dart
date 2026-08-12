import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/radii.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/gate.dart';
import '../../providers/providers.dart';

/// The trainer approval gate. The profile is streamed, so admin approval in
/// the web console releases this screen live — no restart (§2.3).
class PendingScreen extends ConsumerWidget {
  const PendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return GateScaffold(
      onSignOut: () => ref.read(signOutProvider)(),
      child: Column(
        children: [
          const Spacer(),
          GateHeadline(
            icon: Symbols.hourglass_top_rounded,
            color: context.scheme.primary,
            title: 'Under review',
            body: 'Thanks ${session.displayName} — your trainer profile is '
                'with our crew. We check every certification by hand so '
                'riders can book with total confidence.',
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: context.tones.card.withValues(alpha: .7),
              borderRadius: FlowRadii.inset,
              border:
                  Border.all(color: context.scheme.primary.withValues(alpha: .25)),
            ),
            // No spinner. A CircularProgressIndicator promises something is
            // happening *now* and will finish shortly; a certification review
            // is a person reading a document, possibly tomorrow. A permanent
            // spinner on a screen with nothing to wait for reads as the app
            // being stuck. The static mark says the same thing honestly.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Symbols.schedule_rounded,
                    size: 18, color: context.scheme.primary),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    "This screen unlocks the moment you're approved.",
                    style: inter(14, 560, color: context.scheme.onSurface),
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
    );
  }
}
