import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/typography.dart';

/// One column of a [WeekBars] chart.
class WeekBar {
  const WeekBar({
    required this.label,
    required this.value,
    required this.semanticValue,
    this.highlighted = false,
  });

  /// Axis label — `Mon`. Short by necessity: seven of these share a phone.
  final String label;

  final double value;

  /// Pre-formatted for a screen reader — `€180`. The chart does not know the
  /// currency (§3.7), so it never formats money itself.
  final String semanticValue;

  /// The column worth pointing at: today, or the day being inspected.
  final bool highlighted;
}

/// Seven days of earnings, as bars.
///
/// ## Why this shape
///
/// One series of magnitudes over an ordered, bounded period. That is a bar
/// chart and very little else — a line would imply that the value between
/// Tuesday and Wednesday means something, and a donut would throw the
/// ordering away entirely.
///
/// ## Decisions worth keeping if this is restyled
///
///   * **Zero baseline, always.** Bar height is `value / max`, so a bar's
///     area is honest. Starting the axis anywhere else is the oldest way to
///     make a flat week look like a good one.
///   * **No legend.** One series needs none; the heading above it already
///     says what the bars are. A legend box for a single colour is furniture.
///   * **One label, not seven.** Only the highlighted column carries its
///     number. A value printed over every bar turns the chart into a table
///     that is harder to read than a table.
///   * **Colour is not the only encoding.** The highlighted column is taller-
///     contrast *and* labelled *and* named in its semantics, so it survives
///     colourblindness, a greyscale screenshot, and a screen reader.
///   * **Labels wear text tokens.** The weekday under a bar is muted ink, not
///     a tinted version of the bar — the mark carries identity, the text does
///     not repeat it.
class WeekBars extends StatelessWidget {
  const WeekBars({
    super.key,
    required this.bars,
    this.height = 96,
    this.emptyLabel = 'Nothing earned this week yet',
  });

  final List<WeekBar> bars;
  final double height;

  /// A week of zeroes is a real and common state — a trainer between blocks.
  /// Seven flat stubs read as a broken chart, so it says so in words instead.
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final scheme = context.scheme;

    final max = bars.fold<double>(0, (m, b) => b.value > m ? b.value : m);
    if (bars.isEmpty || max <= 0) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(emptyLabel,
              textAlign: TextAlign.center,
              style: inter(12.5, 500, color: tones.textFaint)),
        ),
      );
    }

    return Semantics(
      container: true,
      label: 'Earnings by day',
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final bar in bars)
              Expanded(
                child: Padding(
                  // A 2px surface gap either side — adjacent fills must not
                  // touch, or two bars read as one wide one.
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _Bar(
                    bar: bar,
                    fraction: bar.value / max,
                    fill: bar.highlighted
                        ? scheme.primary
                        : tones.azureBrand.withValues(alpha: .22),
                    ink: tones.textFaint,
                    labelInk: scheme.onSurface,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.bar,
    required this.fraction,
    required this.fill,
    required this.ink,
    required this.labelInk,
  });

  final WeekBar bar;
  final double fraction;
  final Color fill;
  final Color ink;
  final Color labelInk;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${bar.label}, ${bar.semanticValue}',
      excludeSemantics: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (bar.highlighted)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(bar.semanticValue,
                    style: interNum(11, 760, color: labelInk)),
              ),
            ),
          Expanded(
            child: FractionallySizedBox(
              alignment: Alignment.bottomCenter,
              // A zero-value day still gets a sliver, so the column reads as
              // "nothing here" rather than as missing.
              heightFactor: fraction.clamp(0.04, 1.0),
              child: TweenAnimationBuilder<double>(
                duration: FlowMotion.slow,
                curve: FlowMotion.curve,
                tween: Tween(begin: 0, end: 1),
                builder: (context, t, child) => Align(
                  alignment: Alignment.bottomCenter,
                  heightFactor: t,
                  child: child,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: fill,
                    // Rounded at the data end only; the baseline stays square
                    // so every bar sits on the same line.
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              bar.label,
              style: inter(10.5, bar.highlighted ? 700 : 560, color: ink),
            ),
          ),
        ],
      ),
    );
  }
}
