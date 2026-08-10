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
  //
  // Retuned to the redesign reference, which sits a few steps lighter and
  // markedly cooler than the original ramp. The old values ran from #020A1E
  // to #1F4270 — close enough to black that a card never read as a distinct
  // surface, only as a slightly different black, and the whole dark theme
  // flattened into one plane. These keep the same six steps and the same
  // hue family, but start where a surface is legible as a surface.
  static const navy950 = Color(0xFF07121E); // page
  static const navy900 = Color(0xFF0E1E2E); // resting card
  static const navy850 = Color(0xFF14263A); // elevated card
  static const navy800 = Color(0xFF1B3048);
  static const navy700 = Color(0xFF23405C);
  static const navy600 = Color(0xFF2E5379);

  // Azure ramp.
  static const azureDeep = Color(0xFF0077C9); // light-theme primary (AA on white)
  static const azureDim = Color(0xFF0E5E9C);
  static const azurePale = Color(0xFFE1F2FF);
  static const azureGlow = Color(0xFF63C8FF);

  // Text on dark.
  static const mist = Color(0xFFEFF5FF);
  static const haze = Color(0xFFA6BAD8);
  // Tertiary text on dark. Rises with the card ramp: against the old near-black
  // card this measured comfortably, but on the retuned #0E1E2E surface it fell
  // to 4.45:1 — under AA by a hair, and only measurement caught it.
  static const slate = Color(0xFF7590B8);

  // Text on light.
  static const inkText = Color(0xFF0A1B36);
  static const inkSub = Color(0xFF48597B);
  // Tertiary text on light. Cleared AA on a white *card* but measured 4.37:1
  // on the page tint behind it, which is where the booking legend sits — the
  // token was only ever checked against the surface that flattered it.
  static const inkFaint = Color(0xFF5F6E88);

  // Functional accents (tuned per brightness in FlowTones).
  //
  // The `Deep` shades are the light-theme foregrounds. They sit on a tint of
  // themselves over white, which lands a hair under white — so they have to
  // carry nearly the whole contrast ratio themselves, and the first pass at
  // them did not: success measured 3.2:1 and warning 3.4:1 where the dark
  // theme's equivalents were 6.8 and 7.9. See test/theme_contrast_test.dart.
  static const emerald = Color(0xFF17CE92);
  static const emeraldDeep = Color(0xFF07714F);
  static const amber = Color(0xFFFFB547);
  static const amberDeep = Color(0xFF8F5C0C);
  static const coral = Color(0xFFFF5D72);
  static const coralDeep = Color(0xFFC22C42);
}
