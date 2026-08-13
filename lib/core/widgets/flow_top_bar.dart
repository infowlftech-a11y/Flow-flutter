import 'package:flutter/material.dart';

/// The header of a top-level destination (P13).
///
/// Before this, the app's top edge was its least designed zone: Explore had
/// a greeting header with round outlined actions while every other tab hung
/// a bare 20px AppBar title in empty space, and one screen centered its
/// title. This is the one shape now — a display-size title with an optional
/// small line above it, actions in the round outlined style, and an
/// optional full-width strip below for a screen that owns tabs.
///
/// Deliberately not an AppBar. These screens have no back button, no
/// scrolled-under elevation, nothing Material's toolbar does for them — and
/// the toolbar's fixed 56px is exactly what kept their titles small. Pushed
/// screens keep their AppBar; the back affordance is the point there.
class FlowTopBar extends StatelessWidget {
  const FlowTopBar({
    super.key,
    required this.title,
    this.kicker,
    this.actions = const [],
    this.bottom,
  });

  /// The small line above the title — Explore's greeting slot.
  final String? kicker;

  final String title;

  /// Round outlined actions, usually [TopBarAction]s.
  final List<Widget> actions;

  /// Rendered under the title row at full width — Sessions parks its TabBar
  /// here so the bar and its tabs read as one block.
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (kicker != null) ...[
                      Text(
                        kicker!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                  ],
                ),
              ),
              for (final (i, action) in actions.indexed) ...[
                SizedBox(width: i == 0 ? 12 : 8),
                action,
              ],
            ],
          ),
        ),
        ?bottom,
      ],
    );
  }
}

/// A round outlined header action with an optional badge count — the style
/// Explore established, now the style everywhere (P13).
class TopBarAction extends StatelessWidget {
  const TopBarAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badgeCount = 0,
    this.semanticCountLabel,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// Shown as a count badge when above zero.
  final int badgeCount;

  /// What the badge means, spoken: `(3) => '3 unread messages'`. Without it
  /// a screen reader hears the tooltip and the count stays a secret.
  final String Function(int count)? semanticCountLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: badgeCount > 0 && semanticCountLabel != null
          ? semanticCountLabel!(badgeCount)
          : tooltip,
      child: IconButton.outlined(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Badge.count(
          count: badgeCount,
          isLabelVisible: badgeCount > 0,
          child: Icon(icon),
        ),
      ),
    );
  }
}
