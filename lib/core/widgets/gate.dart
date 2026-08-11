import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

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
/// A column that fills the viewport and starts scrolling once it cannot.
///
/// The `minHeight` + [IntrinsicHeight] pair is what lets `Spacer` and
/// `Expanded` keep working inside a scroll view: the child is handed at least
/// the viewport's height to distribute, and only grows past it — into a
/// scroll — when the content genuinely needs more. A plain
/// [SingleChildScrollView] gives its child unbounded height, where a flex
/// child throws instead.
///
/// [IntrinsicHeight] cannot measure a viewport, so the child must not be
/// scrollable itself. Anything that already scrolls does not need this.
class ScrollableFill extends StatelessWidget {
  const ScrollableFill({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(child: child),
          ),
        ),
      );
}

class GateScaffold extends StatelessWidget {
  const GateScaffold({
    super.key,
    required this.onSignOut,
    required this.child,
    this.padding = const EdgeInsets.all(28),
    this.ownsScroll = false,
  });

  final VoidCallback onSignOut;
  final Widget child;

  /// Pass [EdgeInsets.zero] when [child] is itself scrollable and wants to own
  /// its padding, so content scrolls to the edges instead of being clipped.
  final EdgeInsetsGeometry padding;

  /// Set when [child] already scrolls. The gate then adds no scroll view of
  /// its own — [ScrollableFill] measures its child's intrinsic height, and a
  /// viewport has none to give.
  final bool ownsScroll;

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
            icon: Icon(Symbols.logout_rounded, size: 18, color: subdued),
            label: Text('Sign out', style: inter(14, 600, color: subdued)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: WaveBackdrop(
        child: SafeArea(
          // Gates are read, not skimmed: an explanation, a reason, an appeal
          // form. Held in a bare Column they had exactly one screen to fit
          // in, and at 1.3x text they overflowed by as much as 639px — the
          // sign-out button and half the explanation simply gone.
          child: ownsScroll
              ? Padding(padding: padding, child: child)
              : ScrollableFill(
                  child: Padding(padding: padding, child: child),
                ),
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
            style: display(26, 760, color: scheme.onSurface, spacing: -.5)),
        const SizedBox(height: 14),
        Text(body,
            textAlign: TextAlign.center,
            style:
                inter(15, 440, color: scheme.onSurfaceVariant, height: 1.55)),
      ],
    );
  }
}
