import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/payment.dart';
import '../theme/motion.dart';
import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import '../utils/date_x.dart';

/// Uppercase section header with optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {super.key, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label.toUpperCase(),
                style: microLabel(context.tones.textFaint)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Where a booking's money stands, as a tag.
///
/// Renders **nothing** for [PaymentStatus.unknown]. Every booking made before
/// payments were tracked carries that status, and a "Not tracked" pill on all
/// of them would be noise on exactly the screens where the pill needs to mean
/// something — people learn to ignore a badge that is always present.
class PaymentPill extends StatelessWidget {
  const PaymentPill(this.payment, {super.key});

  final PaymentInfo payment;

  @override
  Widget build(BuildContext context) {
    if (!payment.status.isDisplayable) return const SizedBox.shrink();
    final tones = context.tones;

    final (color, icon) = switch (payment.status) {
      PaymentStatus.paid => (tones.success, Symbols.check_circle_rounded),
      PaymentStatus.unpaid => (tones.warning, Symbols.payments_rounded),
      PaymentStatus.processing => (tones.azureBrand, Symbols.sync_rounded),
      PaymentStatus.failed => (tones.danger, Symbols.error_outline_rounded),
      PaymentStatus.refunded => (tones.textFaint, Symbols.undo_rounded),
      PaymentStatus.unknown => (tones.textFaint, Symbols.help_outline_rounded),
    };

    return TagPill(payment.status.label, color: color, icon: icon);
  }
}

/// Small tinted tag ("Station", "Needs gear", "Walk-in", "CONFIRMED"…).
///
/// The one pill. There were three: this, `StatusPill` on the sessions screen
/// (its own container at radius 7 with a heavier, tighter label) and an inline
/// appeal-status pill on the blocked gate (radius 8, different weight again).
/// Three renderings of "a short tinted label" is three things to keep in sync,
/// and they had already drifted.
///
/// [dense] is the old `StatusPill` treatment — marginally tighter and heavier,
/// for pills that sit in a row of metadata rather than standing alone.
class TagPill extends StatelessWidget {
  const TagPill(
    this.label, {
    super.key,
    this.color,
    this.icon,
    this.dense = false,
    this.iconFill = 0,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final bool dense;

  /// Material Symbols fill axis. 1 for glyphs that only read solid — the
  /// LIVE dot is a disc, not a ring.
  final double iconFill;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final c = color ?? tones.azureBrand;
    // Fill stays at the tone; the label goes a few steps deeper in light,
    // where a 14% tint over white leaves the text carrying the whole ratio.
    // These labels are 10–11.5px, so they need the full 4.5:1, not the 3:1
    // large-text allowance.
    final ink = tones.onTint(c);
    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5)
          : const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .14),
        borderRadius: FlowRadii.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, fill: iconFill, color: ink),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: dense
                ? inter(10, 740, color: ink, spacing: .8)
                : inter(11.5, 680, color: ink, spacing: .4),
          ),
        ],
      ),
    );
  }
}

/// Filter/selection chip with brand-selected state and a selection haptic
/// handled by callers.
class FlowChoiceChip extends StatelessWidget {
  const FlowChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onDeleted,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final tones = context.tones;
    final selectedFg = Theme.of(context).brightness == Brightness.dark
        ? tones.azureBrand
        : scheme.primary;

    // The fill and border carry the selected state, so they are what has to
    // animate. (The old AnimatedContainer sat outside them and animated
    // nothing, making selection snap.)
    return AnimatedContainer(
      duration: FlowMotion.fast,
      curve: FlowMotion.curve,
      // The minimum is on the InkWell's child below, not here. A `Border`
      // insets whatever a Container holds, so a 40 here produced a 38 tap
      // target — the measurement the platform actually reports. Constraining
      // the content instead makes the number that matters the one being set.
      decoration: BoxDecoration(
        color: selected ? tones.azureBrand.withValues(alpha: .16) : tones.card,
        borderRadius: FlowRadii.chip,
        border: Border.all(
            color: selected
                ? tones.azureBrand.withValues(alpha: .6)
                : tones.line),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: FlowRadii.chip,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: EdgeInsets.only(
                  left: 14, right: onDeleted == null ? 14 : 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedDefaultTextStyle(
                    curve: FlowMotion.curve,
                    duration: FlowMotion.fast,
                    style: inter(14, selected ? 660 : 540,
                        color: selected ? selectedFg : scheme.onSurface),
                    child: Text(label),
                  ),
                  if (onDeleted != null)
                    // A square the full height of the chip. It was 27x27 — a
                    // 15dp glyph in 6dp of padding — for the one control that
                    // destroys the user's selection. The glyph stays 15; the
                    // box around it is what changed.
                    Semantics(
                      button: true,
                      // Named, not just "button". A screen reader landing on
                      // a row of these would otherwise announce four
                      // identical unlabelled buttons and no way to tell which
                      // filter each one drops.
                      label: 'Remove $label',
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: InkResponse(
                          onTap: onDeleted,
                          radius: 22,
                          child: Icon(Symbols.close_rounded,
                              size: 15,
                              color: selected
                                  ? tones.azureBrand
                                  : tones.textFaint),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Label-over-value on a card: profile facts (Location, Certification…) and
/// the schedule tab's from/to date buttons, which were a private near-copy
/// with no tap affordance at all.
class InfoTile extends StatelessWidget {
  const InfoTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.onTap,
    this.trailingIcon = Symbols.north_east_rounded,
  });

  /// Omit for a tile that is only a label and a value.
  final IconData? icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  /// Shown only when [onTap] is set. Override it when the tap does something
  /// other than navigate — opening a picker, say — and null it to show
  /// nothing.
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Material(
      color: tones.card,
      borderRadius: FlowRadii.inset,
      child: InkWell(
        borderRadius: FlowRadii.inset,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: FlowRadii.inset,
            border: Border.all(color: tones.line),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: tones.azureBrand),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label.toUpperCase(),
                        style: microLabel(tones.textFaint, size: 10)),
                    const SizedBox(height: 3),
                    Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall),
                  ],
                ),
              ),
              if (onTap != null && trailingIcon != null)
                Icon(trailingIcon, size: 16, color: tones.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/// The month-over-day block that fronts a booking row.
///
/// Two copies: the rider's session cards (52 px, azure-tinted) and the
/// trainer's compact schedule rows (44 px, bare). Both spelled out the same
/// `date == null ? '--'` fallback, which is the part that matters — a booking
/// whose stored date fails to parse must still render a row.
class DateBlock extends StatelessWidget {
  const DateBlock({super.key, required this.date, this.compact = false});

  final DateTime? date;

  /// The trainer's denser, untinted variant.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final d = date;
    return Container(
      width: compact ? 44 : 52,
      padding: compact
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(vertical: 8),
      decoration: compact
          ? null
          : BoxDecoration(
              color: tones.azureBrand.withValues(alpha: .1),
              borderRadius: FlowRadii.chip,
            ),
      child: Column(
        children: [
          Text(d == null ? '--' : monthsShort[d.month - 1],
              style: inter(compact ? 9.5 : 10, 720,
                  // Tinted variant only: the month sits on 10% of this same
                  // azure, which on white left it at 3.8:1 for a 10px label.
                  color: compact
                      ? tones.textFaint
                      : tones.onTint(tones.azureBrand),
                  spacing: .8)),
          Text(d == null ? '--' : '${d.day}',
              style: interNum(compact ? 16 : 20, compact ? 740 : 760,
                  color: context.scheme.onSurface)),
        ],
      ),
    );
  }
}

/// Star rating — display and input. Input taps get ≥48dp targets.
class Stars extends StatelessWidget {
  const Stars({
    super.key,
    required this.value,
    this.size = 16,
    this.onChanged,
  });

  final double value;
  final double size;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = value >= i + .75;
        final half = !filled && value >= i + .25;
        // Fill is the axis now: a solid star is star + fill, an empty star
        // is the same glyph at fill 0 — only the half state is its own glyph.
        final star = Icon(
          half ? Symbols.star_half_rounded : Symbols.star_rounded,
          fill: filled ? 1 : 0,
          size: onChanged == null ? size : 34,
          color: filled || half ? tones.warning : tones.textFaint,
        );
        if (onChanged == null) return star;
        return Semantics(
          button: true,
          label: '${i + 1} star${i == 0 ? '' : 's'}',
          child: InkResponse(
            radius: 26,
            onTap: () => onChanged!(i + 1),
            child: SizedBox(width: 48, height: 48, child: Center(child: star)),
          ),
        );
      }),
    );
  }
}

/// An icon carrying an unread count.
///
/// Lived privately in the tab shell. It moved here when Inbox stopped being a
/// tab: the badge is now a header action on Discover, and a second copy of
/// "icon plus a spoken count" is exactly the kind of near-duplicate the
/// refactor spent its time removing.
class BadgedIcon extends StatelessWidget {
  const BadgedIcon({
    super.key,
    required this.count,
    required this.icon,
    required this.semanticLabelBuilder,
  });

  final int count;
  final IconData icon;

  /// Badge counts surface as spoken sentences, not bare digits — a screen
  /// reader announcing "3" beside an icon tells nobody what three of.
  final String Function(int) semanticLabelBuilder;

  @override
  Widget build(BuildContext context) {
    final base = Icon(icon);
    if (count <= 0) return base;
    return Semantics(
      label: semanticLabelBuilder(count),
      child: Badge.count(count: count, child: base),
    );
  }
}
