/// The public name of a session.
///
/// `FLW-<MMDD>-<last four of the booking id>` — e.g. `FLW-0829-7X8K`. Born on
/// the beach ticket so a rider and a trainer could say the same thing out
/// loud when a camera would not cooperate; promoted to the session's id
/// everywhere once tickets and reports started carrying it, because a support
/// conversation needs a name for "that lesson" that both sides and staff can
/// quote.
///
/// Derived from the booking's document id and date, never stored on the
/// booking: every booking ever written already has one, and the console can
/// search history from before the ref existed. Tickets and reports *do*
/// store the rendered ref alongside the raw id — the same denormalisation
/// reports apply to names — so displaying one never needs a booking read.
///
/// The tail is four characters of a Firestore auto-id: unique enough to tell
/// two of the day's sessions apart in conversation. The raw document id
/// stays the canonical key for anything that actually looks a booking up.
String sessionRef(String id, String date) {
  final clean = id.replaceAll(RegExp('[^A-Za-z0-9]'), '').toUpperCase();
  final tail = clean.length <= 4 ? clean : clean.substring(clean.length - 4);
  final digits = date.replaceAll('-', '');
  // A well-formed `YYYY-MM-DD` compresses to eight digits and drops its year;
  // anything else (test fixtures, corrupt data) is kept whole rather than
  // thrown on.
  final day = digits.length == 8 ? digits.substring(4) : digits;
  return day.isEmpty ? 'FLW-$tail' : 'FLW-$day-$tail';
}

/// The public name of a person: `FLW-R-7X8K` for a rider, `FLW-C-7X8K` for a
/// coach (trainers, stations, safari operators — everyone who sells hours).
///
/// Exists for the console: "suspend FLW-R-7X8K" survives being said aloud,
/// typed into the directory search, and pasted into a ticket, where a name
/// does not — the cast has two Ahmeds and support cannot suspend "Ahmed".
///
/// Derived from the uid the same way [sessionRef] derives from the booking
/// id, never stored: every account that has ever existed already has one,
/// and nothing needs a migration. The uid stays the canonical key; the tail
/// is for telling people apart in conversation, and the directory search
/// matches it by containment so a collision costs one extra row on screen,
/// not a wrong ban.
String memberRef(String uid, {required bool coach}) {
  final clean = uid.replaceAll(RegExp('[^A-Za-z0-9]'), '').toUpperCase();
  final tail = clean.length <= 4 ? clean : clean.substring(clean.length - 4);
  return 'FLW-${coach ? 'C' : 'R'}-$tail';
}
