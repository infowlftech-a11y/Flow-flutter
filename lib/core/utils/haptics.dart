import 'package:flutter/services.dart';

/// Haptic vocabulary (APP_LOGIC_BLUEPRINT.md §10.10). One place, so intent is
/// named at the call site instead of a raw HapticFeedback call.
abstract final class Haptics {
  /// Slot / day / chip / star taps.
  static void select() => HapticFeedback.selectionClick();

  /// Favourite, chat send, appeal reply, toasts.
  static void light() => HapticFeedback.lightImpact();

  /// Booking confirm, approve, decline, check-in, onboarding completion,
  /// ticket flipping to "started".
  static void medium() => HapticFeedback.mediumImpact();

  /// The point of no return — account deletion.
  static void heavy() => HapticFeedback.heavyImpact();

  /// A bad QR scan.
  static void error() => HapticFeedback.vibrate();
}
