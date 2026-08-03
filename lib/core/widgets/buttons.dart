import 'package:flutter/material.dart';

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
        duration: const Duration(milliseconds: 180),
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
                  Text(label),
                ],
              ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
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
        if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
        Text(label),
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
