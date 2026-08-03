import 'package:flutter/material.dart';

/// Brand palette, sampled from assets/brand/logo.png.
///
/// The logo is three colors: a deep ink navy (#020F2B), an azure sweep
/// (#1DB0FE) and white. Everything else here is a tint or shade of those.
abstract final class FlowColors {
  // Sampled brand anchors.
  static const ink = Color(0xFF020F2B); // logo background
  static const azure = Color(0xFF1DB0FE); // logo swoosh
  static const white = Color(0xFFFFFFFF);

  // Navy ramp (dark theme surfaces, light theme text).
  static const navy950 = Color(0xFF020A1E);
  static const navy900 = Color(0xFF041530);
  static const navy850 = Color(0xFF071C3E);
  static const navy800 = Color(0xFF0B2449);
  static const navy700 = Color(0xFF143158);
  static const navy600 = Color(0xFF1F4270);

  // Azure ramp.
  static const azureDeep = Color(0xFF0077C9); // light-theme primary (AA on white)
  static const azureDim = Color(0xFF0E5E9C);
  static const azurePale = Color(0xFFE1F2FF);
  static const azureGlow = Color(0xFF63C8FF);

  // Text on dark.
  static const mist = Color(0xFFEFF5FF);
  static const haze = Color(0xFFA6BAD8);
  static const slate = Color(0xFF647CA5);

  // Text on light.
  static const inkText = Color(0xFF0A1B36);
  static const inkSub = Color(0xFF48597B);
  static const inkFaint = Color(0xFF8393B0);

  // Functional accents (tuned per brightness in FlowTones).
  static const emerald = Color(0xFF17CE92);
  static const emeraldDeep = Color(0xFF0B9A6C);
  static const amber = Color(0xFFFFB547);
  static const amberDeep = Color(0xFFB97710);
  static const coral = Color(0xFFFF5D72);
  static const coralDeep = Color(0xFFD23B50);
}
