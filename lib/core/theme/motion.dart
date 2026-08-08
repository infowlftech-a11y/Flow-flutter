import 'package:flutter/animation.dart';

/// The motion scale.
///
/// In-place transitions had drifted to eight different durations — 150, 160,
/// 180, 200, 220, 240, 260 and 280ms — chosen a screen at a time. Nobody can
/// tell 200 from 220 in isolation, but they are visible next to each other:
/// the chip on the filter sheet settled at a different speed from the chip on
/// the booking sheet. Three steps cover everything the app actually does.
///
/// Deliberately *not* covered here, because they are different problems with
/// different right answers:
///
///  - Debounces and delays (`Timer`, `Future.delayed`) — those are tuned to
///    typing speed and camera behaviour, not to how a transition should feel.
///  - Scroll and page travel (`animateTo`, `PageController`) — duration there
///    is a function of distance.
///  - The route transition in `router.dart`, which is flow, not presentation.
abstract final class FlowMotion {
  /// A control reacting under the finger: chip selection, press states, a
  /// reveal toggle. Fast enough to feel like a direct response.
  static const fast = Duration(milliseconds: 150);

  /// The default. Anything changing in place — recolour, resize, cross-fade,
  /// a banner growing into the layout.
  static const base = Duration(milliseconds: 200);

  /// Content arriving or leaving, where the eye needs to follow it.
  static const slow = Duration(milliseconds: 300);

  /// Looping attention pulses: skeleton shimmer, the live-session dot. Not a
  /// transition — it never ends, so it is tuned to be ignorable.
  static const pulse = Duration(milliseconds: 1100);

  /// Easing for everything above.
  ///
  /// `AnimatedContainer` and friends default to `Curves.linear`, which is the
  /// one curve nothing in the physical world moves along; several call sites
  /// had already reached for `easeOut` individually.
  static const curve = Curves.easeOutCubic;
}
