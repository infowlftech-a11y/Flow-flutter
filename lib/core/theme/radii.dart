import 'package:flutter/widgets.dart';

/// The corner-radius scale.
///
/// Before this there was no scale — cards were drawn at 14, 16, 18 and 20
/// across the app with nothing distinguishing them, and `cardTheme` declared a
/// fifth value that almost nothing used because almost nothing used `Card`.
/// Four radii for one component is not a system, it is four people guessing.
///
/// The steps below are semantic rather than numeric (`card`, not `r20`) so a
/// call site says what it is drawing, and so the scale can be retuned in one
/// place without a find-and-replace over 129 `BorderRadius.circular` calls.
abstract final class FlowRadius {
  /// Tags, status pills, payment pills. Small enough to read as a label.
  static const pill = 8.0;

  /// Choice chips, gallery thumbnails, attachment previews.
  static const chip = 12.0;

  /// Inputs, buttons, compact list rows — anything a finger drives directly.
  /// Matches the 14 already baked into `inputDecorationTheme` and the button
  /// themes, so those are unchanged.
  static const control = 14.0;

  /// Icon chips and inner containers sitting *inside* a card.
  static const inset = 16.0;

  /// Content cards. The one card radius; 16 and 18 fold into this.
  static const card = 20.0;

  /// Dialogs.
  static const dialog = 24.0;

  /// Modal bottom sheets.
  static const sheet = 28.0;
}

/// `BorderRadius.circular` for each step, so call sites read
/// `FlowRadii.card` rather than `BorderRadius.circular(FlowRadius.card)`.
abstract final class FlowRadii {
  static const pill = BorderRadius.all(Radius.circular(FlowRadius.pill));
  static const chip = BorderRadius.all(Radius.circular(FlowRadius.chip));
  static const control = BorderRadius.all(Radius.circular(FlowRadius.control));
  static const inset = BorderRadius.all(Radius.circular(FlowRadius.inset));
  static const card = BorderRadius.all(Radius.circular(FlowRadius.card));
  static const dialog = BorderRadius.all(Radius.circular(FlowRadius.dialog));
  static const sheet = BorderRadius.all(Radius.circular(FlowRadius.sheet));
}
