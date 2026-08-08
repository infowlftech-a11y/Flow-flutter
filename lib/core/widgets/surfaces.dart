import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/radii.dart';

/// The card surface, in one place.
///
/// `color: tones.card` + a rounded rectangle + `Border.all(tones.line)` was
/// open-coded eleven times at four different radii. Nothing distinguished
/// them; the variation was accidental. This is that decoration, once.
///
/// [onTap] wires the ripple correctly — the previous inline copies split
/// between `Material`-wrapping (ripple clipped to the radius) and a bare
/// `Container` inside an `InkWell` (ripple painted square, under the card),
/// so tapping a card looked different depending on which screen you were on.
class FlowCard extends StatelessWidget {
  const FlowCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.borderRadius = FlowRadii.card,
    this.borderColor,
    this.color,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;

  /// Defaults to the hairline. Pass a tinted colour to mark a card that wants
  /// attention — a pending request, an open report.
  final Color? borderColor;

  /// Defaults to the resting card surface.
  final Color? color;

  /// Overrides [color] when set — for hero tiles.
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? tones.card) : null,
        gradient: gradient,
        borderRadius: borderRadius,
        border: Border.all(color: borderColor ?? tones.line),
      ),
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: content,
        ),
      );
    }

    return margin == null ? content : Padding(padding: margin!, child: content);
  }
}

/// A tinted rounded square with an icon in it.
///
/// Eleven copies of this existed, sized 40–88 and radiused 10–28, each
/// recomputing the same `withValues(alpha: .12)` fill. The tint derives from
/// [color] so a caller states the semantic colour once.
class FlowIconChip extends StatelessWidget {
  const FlowIconChip({
    super.key,
    required this.icon,
    this.color,
    this.size = 40,
    this.borderRadius,
    this.tintOpacity = .12,
  });

  final IconData icon;

  /// Defaults to the brand azure.
  final Color? color;
  final double size;

  /// Defaults to a radius proportional to [size], which is what the hand-rolled
  /// copies were all approximating (a 40 px chip took 12–13, an 88 px one 28).
  final BorderRadius? borderRadius;
  final double tintOpacity;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.tones.azureBrand;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: tintOpacity),
        borderRadius:
            borderRadius ?? BorderRadius.circular(size * .32),
      ),
      child: Icon(icon, size: size * .48, color: c),
    );
  }
}

/// The bar pinned under a screen's content: booking's running total, the
/// trainer profile's Book CTA, and the chat and support composers.
///
/// Four copies, all spelling out the same surface tint, hairline and
/// `MediaQuery.paddingOf(context).bottom` — which is the part worth having in
/// one place, since forgetting it puts the CTA under the home indicator.
class StickyBar extends StatelessWidget {
  const StickyBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  });

  final Widget child;

  /// Safe-area inset is added underneath this, not replaced by it.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding.copyWith(
          bottom: padding.bottom + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: context.scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: context.tones.line)),
      ),
      child: child,
    );
  }
}

/// A tinted callout: icon, title, optional body.
///
/// Six variants of this existed — the booking screen's away/fully-booked
/// notice, the schedule tab's time-off banner, two trainer-onboarding
/// callouts, the earnings sheet's outstanding banner and the auth error
/// banner — at six radii and three internal layouts.
class FlowNotice extends StatelessWidget {
  const FlowNotice({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.tone,
    this.bordered = false,
  });

  final IconData icon;
  final String title;
  final String? body;

  /// The semantic colour. Defaults to warning — the common case.
  final Color? tone;

  /// Adds a matching outline. The banners that sit on their own use it; the
  /// ones inside a card do not.
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final c = tone ?? tones.warning;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Blended over the card rather than laid straight onto the page. A
        // flat 12% of the tone composited against whatever was behind it made
        // the default warning tone — a brown — into a beige slab in light and
        // a warm grey one in dark: the only warm surfaces anywhere in a cool
        // navy palette. Anchoring to `card` keeps the surface family intact
        // and leaves the tone to the icon and the rim, where it reads as a
        // signal instead of a wash.
        color: Color.alphaBlend(c.withValues(alpha: dark ? .07 : .06),
            tones.card),
        borderRadius: FlowRadii.inset,
        // Always outlined now. Without the heavy fill the shape needs an edge,
        // and a hairline in the tone carries the semantics the fill used to.
        border: Border.all(
            color: c.withValues(alpha: bordered ? .45 : .22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (body != null) ...[
                  const SizedBox(height: 3),
                  Text(body!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
