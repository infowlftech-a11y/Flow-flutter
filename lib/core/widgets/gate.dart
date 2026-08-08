import 'package:flutter/material.dart';

import '../theme/typography.dart';
import 'brand.dart';
import 'surfaces.dart';

/// The full-bleed ink screen behind every gate: role choice, pending approval,
/// rejection and suspension.
///
/// Five screens repeated the same six lines of chrome, and the sign-out button
/// they all carry had drifted into two different places — the app-bar trailing
/// slot on role select, and a `Align(topRight)` floating inside the content on
/// the other three. Only the first is what §3.2 asks for, and only the first
/// keeps the button off the content's scroll: on the suspension gate the
/// sign-out scrolled away with the appeal thread, so the way out of a locked
/// account was reachable only by scrolling back up.
///
/// Takes [onSignOut] as a callback rather than reading the provider, so the
/// component library stays clear of the provider graph.
class GateScaffold extends StatelessWidget {
  const GateScaffold({
    super.key,
    required this.onSignOut,
    required this.child,
    this.padding = const EdgeInsets.all(28),
  });

  final VoidCallback onSignOut;
  final Widget child;

  /// Pass [EdgeInsets.zero] when [child] is itself scrollable and wants to own
  /// its padding, so content scrolls to the edges instead of being clipped.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Colours come from the scheme so the gates follow the app's theme rather
    // than standing as dark islands in a light one; WaveBackdrop behind them
    // switches ground the same way.
    final subdued = scheme.onSurfaceVariant;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            onPressed: onSignOut,
            icon: Icon(Icons.logout_rounded, size: 18, color: subdued),
            label: Text('Sign out', style: inter(14, 600, color: subdued)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: WaveBackdrop(
        child: SafeArea(
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// The chip, headline and explanation every gate opens with.
///
/// The headline was 28 on one gate and 26 on the other two for no reason
/// beyond the length of the string that happened to be there; 26 is the size
/// that survives a long title at a large text scale, so it is the one kept.
class GateHeadline extends StatelessWidget {
  const GateHeadline({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        FlowIconChip(icon: icon, color: color, size: 88, tintOpacity: .14),
        const SizedBox(height: 28),
        Text(title,
            textAlign: TextAlign.center,
            style: sora(26, 760, color: scheme.onSurface, spacing: -.5)),
        const SizedBox(height: 14),
        Text(body,
            textAlign: TextAlign.center,
            style:
                inter(15, 440, color: scheme.onSurfaceVariant, height: 1.55)),
      ],
    );
  }
}
