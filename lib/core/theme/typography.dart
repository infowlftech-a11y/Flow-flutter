import 'package:flutter/material.dart';

/// Space Grotesk (display) + Inter (text), both bundled as variable fonts.
///
/// Weight is driven through the `wght` variation axis; `fontWeight` is set to
/// the nearest static weight too so fallback fonts (and TalkBack's bold-text
/// setting) still behave.
TextStyle display(
  double size,
  double weight, {
  Color? color,
  double? spacing,
  double? height,
}) {
  // Space Grotesk's wght axis runs 300–700; the scale asks for up to 780,
  // which some engines would treat as out-of-range rather than clamping.
  final w = weight.clamp(300.0, 700.0);
  return TextStyle(
    fontFamily: 'SpaceGrotesk',
    fontSize: size,
    color: color,
    letterSpacing: spacing,
    height: height,
    fontWeight: _nearest(w),
    fontVariations: [FontVariation('wght', w)],
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
