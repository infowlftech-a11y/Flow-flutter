import 'package:flutter/material.dart';

/// Sora (display) + Inter (text), both bundled as variable fonts.
///
/// Weight is driven through the `wght` variation axis; `fontWeight` is set to
/// the nearest static weight too so fallback fonts (and TalkBack's bold-text
/// setting) still behave.
TextStyle sora(
  double size,
  double weight, {
  Color? color,
  double? spacing,
  double? height,
}) {
  return TextStyle(
    fontFamily: 'Sora',
    fontSize: size,
    color: color,
    letterSpacing: spacing,
    height: height,
    fontWeight: _nearest(weight),
    fontVariations: [FontVariation('wght', weight)],
  );
}

TextStyle inter(
  double size,
  double weight, {
  Color? color,
  double? spacing,
  double? height,
  List<FontFeature>? features,
}) {
  return TextStyle(
    fontFamily: 'Inter',
    fontSize: size,
    color: color,
    letterSpacing: spacing,
    height: height,
    fontWeight: _nearest(weight),
    fontVariations: [FontVariation('wght', weight)],
    fontFeatures: features,
  );
}

/// Tabular numerals — money, counters, timers never jitter as digits change.
TextStyle interNum(double size, double weight,
        {Color? color, double? spacing, double? height}) =>
    inter(size, weight,
        color: color,
        spacing: spacing,
        height: height,
        features: const [FontFeature.tabularFigures()]);

/// Uppercase micro-label (section headers, pills, tab labels).
TextStyle microLabel(Color color, {double size = 11.5}) =>
    inter(size, 700, color: color, spacing: 1.1);

FontWeight _nearest(double w) => switch (w) {
      < 350 => FontWeight.w300,
      < 450 => FontWeight.w400,
      < 550 => FontWeight.w500,
      < 650 => FontWeight.w600,
      < 750 => FontWeight.w700,
      _ => FontWeight.w800,
    };
