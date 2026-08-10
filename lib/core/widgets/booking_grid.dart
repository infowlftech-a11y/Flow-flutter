import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// The five states an hour can be in, as the booking grid paints them.
///
/// These mirror the reasons `DayAvailability.reasonFor` already produces
/// (Away → Too soon → Booked → Unavailable) rather than inventing a parallel
/// vocabulary. The one addition is [selected], which is a UI state and has no
/// business in the schedule model.
///
/// They are distinct on purpose. Collapsing them to "not available" loses the
/// only thing the rider can act on: *booked* means try another hour, *too
/// soon* means try another day, *away* means try another trainer.
enum SlotState { free, selected, booked, tooSoon, away, unavailable }

/// Maps a reason string from the schedule model onto a paint state.
SlotState slotStateForReason(String? reason) => switch (reason) {
      null => SlotState.free,
      'Away' => SlotState.away,
      'Too soon' => SlotState.tooSoon,
      'Booked' => SlotState.booked,
      _ => SlotState.unavailable,
    };

extension SlotStateX on SlotState {
  bool get isBookable => this == SlotState.free || this == SlotState.selected;

  String get label => switch (this) {
        SlotState.free => 'Free',
        SlotState.selected => 'Selected',
        SlotState.booked => 'Booked',
        SlotState.tooSoon => 'Too soon',
        SlotState.away => 'Away',
        SlotState.unavailable => 'Unavailable',
      };

  /// Fill, border, ink — resolved per theme.
  (Color, Color, Color) colors(BuildContext context) {
    final tones = context.tones;
    final scheme = context.scheme;
    return switch (this) {
      SlotState.selected => (scheme.primary, scheme.primary, scheme.onPrimary),
      SlotState.free => (tones.card, tones.line, scheme.onSurface),
      // The three unavailable states share a muted treatment and differ by
      // word. Giving each its own colour would turn a five-step legend into a
      // colour-matching exercise, and two of them are not actionable anyway.
      _ => (
          tones.cardHigh.withValues(alpha: .55),
          Colors.transparent,
          tones.textFaint,
        ),
    };
  }
}

/// One hour in the grid.
class SlotTile extends StatelessWidget {
  const SlotTile({
    super.key,
    required this.range,
    required this.state,
    this.onTap,
  });

  /// Pre-formatted `09:00 – 10:00`. The caller owns time formatting.
  final String range;
  final SlotState state;

  /// Ignored unless the state is bookable — an unavailable hour must not be
  /// tappable, which is the rule the old grid enforced and this keeps.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (fill, border, ink) = state.colors(context);
    final tappable = state.isBookable && onTap != null;

    return Semantics(
      button: tappable,
      selected: state == SlotState.selected,
      enabled: tappable,
      label: '$range, ${state.label}',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: FlowMotion.fast,
        curve: FlowMotion.curve,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: FlowRadii.chip,
          border: Border.all(color: border),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: FlowRadii.chip,
            onTap: tappable ? onTap : null,
            child: ConstrainedBox(
              // Constrains the InkWell's child, not the decorated box: a
              // Border insets what it wraps, so a minHeight on the container
              // yields a target 2px under the number written.
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(range,
                          style: interNum(12.5, 700, color: ink)),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(state.label,
                          style: inter(10.5, 560,
                              color: state == SlotState.selected
                                  ? ink
                                  : ink.withValues(alpha: .75))),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The key under the day strip.
///
/// Exists because the grid's muted states are indistinguishable without it —
/// three of the five look the same and are told apart only by their word.
class SlotLegend extends StatelessWidget {
  const SlotLegend({super.key, this.states = SlotState.values});

  final List<SlotState> states;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final s in states)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  // Below the radius scale — a 7px dot is not a surface.
                  shape: BoxShape.circle,
                  color: s == SlotState.free
                      ? context.tones.textFaint
                      : s.colors(context).$1,
                  border: s == SlotState.free
                      ? null
                      : Border.all(color: context.tones.line),
                ),
              ),
              const SizedBox(width: 6),
              Text(s.label,
                  style: inter(11.5, 560, color: context.tones.textFaint)),
            ],
          ),
      ],
    );
  }
}

/// Horizontal day selector — weekday over date.
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.days,
    required this.selected,
    required this.onSelect,
    this.labelFor,
    this.enabledFor,
  });

  final List<DateTime> days;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  /// Weekday abbreviation. Defaults to a fixed English three-letter form; the
  /// caller passes a localised one where it has it.
  final String Function(DateTime)? labelFor;

  /// Lets the caller grey a day out — a date entirely on vacation, say —
  /// without the strip needing to know why.
  final bool Function(DateTime)? enabledFor;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final scheme = context.scheme;

    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final day = days[i];
          final isSelected = _same(day, selected);
          final enabled = enabledFor?.call(day) ?? true;
          final label = labelFor?.call(day) ?? _weekdays[day.weekday - 1];

          return Semantics(
            button: true,
            selected: isSelected,
            enabled: enabled,
            label: '$label ${day.day}',
            excludeSemantics: true,
            child: AnimatedContainer(
              duration: FlowMotion.fast,
              curve: FlowMotion.curve,
              width: 52,
              decoration: BoxDecoration(
                color: isSelected ? scheme.primary : tones.card,
                borderRadius: FlowRadii.chip,
                border: Border.all(
                    color: isSelected ? scheme.primary : tones.line),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: FlowRadii.chip,
                  onTap: enabled ? () => onSelect(day) : null,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: inter(11, 600,
                            color: isSelected
                                ? scheme.onPrimary.withValues(alpha: .85)
                                : tones.textFaint),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${day.day}',
                        style: interNum(17, 760,
                            color: isSelected
                                ? scheme.onPrimary
                                : enabled
                                    ? scheme.onSurface
                                    : tones.textFaint),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
