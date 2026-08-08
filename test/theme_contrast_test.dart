// The two themes have to be legible to the same standard.
//
// They drifted once: the light theme reused the raw logo azure (#1DB0FE) as a
// foreground, which measured 2.1:1 on a tinted pill and 2.4:1 on a white card
// against 6.0 and 7.5 for the same token in dark. Nothing in the widget code
// looked wrong — both themes named the same token — so only measurement found
// it. Hence this test rather than a comment.
//
// The bar is 3.0:1. Several tinted pills sit just above it and would need
// visibly deeper tones to reach 4.5, which is a design call rather than a bug;
// the point of the floor is to catch a token that is legible in one brightness
// and invisible in the other.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/theme/app_theme.dart';

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

/// Alpha-composite [fg] over an opaque [bg] — tints are what most of these
/// labels actually sit on, and the tint is what makes or breaks the ratio.
Color _over(Color fg, Color bg) => Color.from(
      alpha: 1,
      red: fg.r * fg.a + bg.r * (1 - fg.a),
      green: fg.g * fg.a + bg.g * (1 - fg.a),
      blue: fg.b * fg.a + bg.b * (1 - fg.a),
    );

double _contrast(Color fg, Color bg) {
  final a = _luminance(fg);
  final b = _luminance(bg);
  return (math.max(a, b) + .05) / (math.min(a, b) + .05);
}

/// Every foreground/background pair the app actually paints, keyed by name.
Map<String, (Color, Color)> _pairs(ThemeData theme) {
  final tones = theme.extension<FlowTones>()!;
  final scheme = theme.colorScheme;
  final card = tones.card;
  // Pills paint `onTint(tone)` on a tint of `tone` — the two differ in light,
  // where the label has to go deeper than the fill to carry the ratio.
  return {
    'TagPill label on its tint': (
      tones.onTint(tones.azureBrand),
      _over(tones.azureBrand.withValues(alpha: .14), card)
    ),
    'success pill': (tones.onTint(tones.success), _over(tones.successTint, card)),
    'warning pill': (tones.onTint(tones.warning), _over(tones.warningTint, card)),
    'danger pill': (tones.onTint(tones.danger), _over(tones.dangerTint, card)),
    'body text on card': (scheme.onSurface, card),
    'secondary text on card': (scheme.onSurfaceVariant, card),
    'tertiary text on card': (tones.textFaint, card),
    'filled button label': (scheme.onPrimary, scheme.primary),
    'accent text on card': (tones.azureBrand, card),
  };
}

void main() {
  const floor = 4.5;

  for (final (name, theme) in [
    ('dark', FlowTheme.dark()),
    ('light', FlowTheme.light()),
  ]) {
    test('$name theme keeps every tone above $floor:1', () {
      final failures = <String>[];
      _pairs(theme).forEach((label, pair) {
        final ratio = _contrast(pair.$1, pair.$2);
        if (ratio < floor) {
          failures.add('$label — ${ratio.toStringAsFixed(2)}:1');
        }
      });
      expect(failures, isEmpty,
          reason: 'unreadable in $name theme:\n  ${failures.join('\n  ')}');
    });
  }

  test('neither theme is markedly less legible than the other', () {
    final dark = _pairs(FlowTheme.dark());
    final light = _pairs(FlowTheme.light());
    final drifted = <String>[];

    for (final label in dark.keys) {
      final d = _contrast(dark[label]!.$1, dark[label]!.$2);
      final l = _contrast(light[label]!.$1, light[label]!.$2);
      // A token that reads twice as well in one brightness as the other is
      // the drift this test exists to catch.
      if (math.max(d, l) / math.min(d, l) > 2.0) {
        drifted.add('$label — dark ${d.toStringAsFixed(2)}:1 '
            'vs light ${l.toStringAsFixed(2)}:1');
      }
    }

    expect(drifted, isEmpty,
        reason: 'these tones are tuned for one theme only:\n  '
            '${drifted.join('\n  ')}');
  });
}
