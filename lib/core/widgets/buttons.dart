import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/palette.dart';

/// Primary CTA. While busy it swaps the label for a spinner and **keeps its
/// brand fill** — a disabled grey pill reads as dead (§10.5).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.expand = true,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final bool expand;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final button = FilledButton(
      style: destructive
          ? FilledButton.styleFrom(
              backgroundColor: scheme.error, foregroundColor: scheme.onError)
          : null,
      // Busy keeps the fill: onPressed stays non-null but ignores taps.
      onPressed: busy ? () {} : onPressed,
      child: AnimatedSwitcher(
        duration: FlowMotion.fast,
        switchInCurve: FlowMotion.curve,
        switchOutCurve: FlowMotion.curve,
        child: busy
            ? SizedBox(
                key: const ValueKey('busy'),
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: destructive ? scheme.onError : scheme.onPrimary,
                ),
              )
            : Row(
                key: const ValueKey('label'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  // Flexible, because the label is the one part of a button
                  // nobody controls: "Reserve my seat" at 1.3x on a narrow
                  // phone is wider than the button, and an unflexed Text in a
                  // Row cannot shrink — it overflows past the edge instead.
                  //
                  // Scaled down rather than ellipsized. A clipped call to
                  // action is worse than a small one: `Book now` came out as
                  // `Book …` on a 320px phone at 1.3x, which reads as a
                  // broken button, and `Review & co…` said nothing at all.
                  // A couple of lost points of type still says what it does.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label, maxLines: 1),
                    ),
                  ),
                ],
              ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// A circular icon button on a scrim, for controls that float over media.
///
/// Three of these existed: `_ScrimButton` on the trainer profile (42 px,
/// alpha .35), `_RoundButton` in the QR scanner (48 px, alpha .4, with an
/// active state for the torch) and an inline copy on the station profile with
/// no size box at all — so the station's back button had a smaller tap target
/// than the identical-looking one a screen away.
///
/// Defaults to 48 px: these sit over photography and in screen corners, where
/// a near-miss navigates somewhere you did not intend.
class ScrimIconButton extends StatelessWidget {
  const ScrimIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
    this.active = false,
    this.size = 48,
    this.fill = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  /// Tints the glyph. Ignored while [active].
  final Color? color;

  /// Material Symbols fill axis — 1 for a solid glyph (the favourited
  /// heart), 0 for the outline everything else uses. State must not be
  /// carried by colour alone.
  final double fill;

  /// Inverts the button — brand fill, ink glyph. Used for the scanner torch.
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? FlowColors.azure
            : Colors.black.withValues(alpha: .38),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: size * .44,
              fill: fill,
              color: active ? FlowColors.ink : (color ?? Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact uppercase action used on cards (APPROVE, SCAN TO START, BOOK…).
class MicroAction extends StatelessWidget {
  const MicroAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = true,
    this.icon,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 40)),
      padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
      shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))),
      textStyle: WidgetStatePropertyAll(Theme.of(context)
          .textTheme
          .labelSmall!
          .copyWith(fontSize: 11.5, letterSpacing: 1)),
    );
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 17), const SizedBox(width: 6)],
        // Scaled, not clipped — see PrimaryButton. These sit in pairs inside
        // a card, so each gets half of an already-narrow row: `DECLINE` next
        // to `APPROVE` on a 320px phone at 1.3x read `DEC…`, which is a
        // destructive action with its name cut off.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, maxLines: 1),
          ),
        ),
      ],
    );
    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        style: style.copyWith(
          backgroundColor: WidgetStatePropertyAll(c),
          foregroundColor: WidgetStatePropertyAll(
              filled ? scheme.onPrimary : c),
        ),
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: style.copyWith(
        foregroundColor: WidgetStatePropertyAll(c),
        side: WidgetStatePropertyAll(
            BorderSide(color: c.withValues(alpha: .5))),
      ),
      child: child,
    );
  }
}
