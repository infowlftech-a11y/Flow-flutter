/// Firestore / generic error → human words (APP_LOGIC_BLUEPRINT.md §10.3).
///
/// This lived on `ErrorView` in `core/widgets/feedback.dart`, which put a rule
/// about what users are told when the database refuses them inside the widget
/// library — the FREE zone of the UI refactor. Restyling the error state and
/// rewriting error semantics are different jobs, and only one of them is safe
/// to do without thinking about it.
///
/// Its sibling is [AuthRepository.message], which does the same job for auth
/// and has always lived in the data layer. This is the non-auth half.
library;

/// Turns anything thrown by Firestore into a sentence worth reading.
///
/// Matches on the lowercased string form rather than a typed code because the
/// failures arrive from several layers — `FirebaseException`, a plugin
/// `PlatformException`, or a plain error forwarded by a stream — and the code
/// is not reliably reachable on all of them. Anything unrecognised falls back
/// to the generic line: a wrong specific message is worse than a vague true
/// one.
String friendlyError(Object error) {
  final s = error.toString().toLowerCase();
  if (s.contains('permission-denied')) {
    return "You don't have access to this yet.";
  }
  if (s.contains('unavailable') || s.contains('network')) {
    return 'No connection. Check your internet and try again.';
  }
  if (s.contains('failed-precondition') && s.contains('index')) {
    return "This view needs a database index that hasn't been created yet.";
  }
  return 'Something went wrong. Please try again.';
}
