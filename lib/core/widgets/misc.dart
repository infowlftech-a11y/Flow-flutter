import 'package:flutter/material.dart';

import '../../data/models/payment.dart';
import '../theme/app_theme.dart';
import '../theme/typography.dart';

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
      PaymentStatus.paid => (tones.success, Icons.check_circle_rounded),
      PaymentStatus.unpaid => (tones.warning, Icons.payments_outlined),
      PaymentStatus.processing => (tones.azureBrand, Icons.sync_rounded),
      PaymentStatus.failed => (tones.danger, Icons.error_outline_rounded),
      PaymentStatus.refunded => (tones.textFaint, Icons.undo_rounded),
      PaymentStatus.unknown => (tones.textFaint, Icons.help_outline_rounded),
    };

    return TagPill(payment.status.label, color: color, icon: icon);
  }
}

/// Small tinted tag ("Station", "Needs gear", "Walk-in"…).
class TagPill extends StatelessWidget {
  const TagPill(this.label, {super.key, this.color, this.icon});
  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.tones.azureBrand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 4),
          ],
          Text(label, style: inter(11, 680, color: c, spacing: .4)),
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
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      constraints: const BoxConstraints(minHeight: 40),
      decoration: BoxDecoration(
        color: selected ? tones.azureBrand.withValues(alpha: .16) : tones.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: selected
                ? tones.azureBrand.withValues(alpha: .6)
                : tones.line),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 150),
                  style: inter(13.5, selected ? 660 : 540,
                      color: selected ? selectedFg : scheme.onSurface),
                  child: Text(label),
                ),
                if (onDeleted != null) ...[
                  const SizedBox(width: 4),
                  // Was a bare 15dp icon — too small to hit reliably for a
                  // control whose whole job is removing an active filter.
                  InkResponse(
                    onTap: onDeleted,
                    radius: 18,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.close_rounded,
                          size: 15,
                          color:
                              selected ? tones.azureBrand : tones.textFaint),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Info tile used on profile screens (Location, Certification…).
class InfoTile extends StatelessWidget {
  const InfoTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Material(
      color: tones.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tones.line),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: tones.azureBrand),
              const SizedBox(width: 12),
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
              if (onTap != null)
                Icon(Icons.north_east_rounded,
                    size: 16, color: tones.textFaint),
            ],
          ),
        ),
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
        final star = Icon(
          filled
              ? Icons.star_rounded
              : half
                  ? Icons.star_half_rounded
                  : Icons.star_outline_rounded,
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
