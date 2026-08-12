/// Dates, slots and booking arithmetic (APP_LOGIC_BLUEPRINT.md §8.1–8.3).
///
/// Egypt is UTC+2/+3, so **every date is a local `YYYY-MM-DD` string** — never
/// an ISO timestamp, because `toIso8601String()` in UTC would shift the
/// calendar day. This is load-bearing across the whole schema.
library;

/// Local calendar date → `YYYY-MM-DD`.
String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String todayYmd() => ymd(DateTime.now());

/// Current `YYYY-MM` — earnings month bucket.
String thisMonthYm() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
}

DateTime? parseYmd(String? s) {
  if (s == null || s.length < 10) return null;
  final y = int.tryParse(s.substring(0, 4));
  final m = int.tryParse(s.substring(5, 7));
  final d = int.tryParse(s.substring(8, 10));
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

const monthsShort = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
const monthsLong = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const weekdaysShort = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const weekdaysLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// `2026-08-14` → `Fri 14 Aug` (with graceful `--` fallback).
String prettyYmd(String? s) {
  final d = parseYmd(s ?? '');
  if (d == null) return '--';
  return '${weekdaysLong[d.weekday - 1].substring(0, 3)} ${d.day} '
      '${monthsLong[d.month - 1].substring(0, 3)}';
}

String longYmd(String? s) {
  final d = parseYmd(s ?? '');
  if (d == null) return '--';
  return '${weekdaysLong[d.weekday - 1]}, ${d.day} ${monthsLong[d.month - 1]}';
}

/// Compact relative time — `now`, `4m`, `2h`, `3d`, else `12 Mar`.
String timeAgo(DateTime? t) {
  if (t == null) return '';
  final diff = DateTime.now().difference(t);
  if (diff.inSeconds < 60) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${t.day} ${monthsLong[t.month - 1].substring(0, 3)}';
}

/// Money display — `EGP 1,200`, or `EGP 72.50` when fractional.
///
/// Egyptian pounds, because the app launches in Egypt only. This used to be
/// `money()` and printed `€120`: the Red Sea trade quotes euro to European
/// riders, but the market being served is domestic, and a price a rider
/// cannot pay in the currency they hold is worse than no price.
///
/// Thousands separators are not decoration here — the numbers grew by two
/// orders of magnitude when the currency changed, and `EGP 12000` is a price
/// nobody can read at a glance.
///
/// `EGP` rather than `E£`: the symbol is easy to misread as a pound sterling
/// sign, and the ISO code is what every Egyptian bank app and receipt uses.
String money(num? amount) {
  if (amount == null) return '—';
  final a = amount.toDouble();
  final whole = a == a.roundToDouble();
  final digits = whole ? a.round().abs().toString() : a.abs().truncate().toString();
  final grouped = _group(digits);
  final sign = a < 0 ? '-' : '';
  if (whole) return 'EGP $sign$grouped';
  final fraction = a.abs().toStringAsFixed(2).split('.').last;
  return 'EGP $sign$grouped.$fraction';
}

/// `1234567` → `1,234,567`.
String _group(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// An `HH:mm` time-of-day string with slot arithmetic.
extension type const Slot(String value) {
  static Slot? tryParse(String? raw) {
    if (raw == null) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(raw.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return null;
    return Slot('${h.toString().padLeft(2, '0')}:${m.group(2)!}');
  }

  static Slot fromHour(int hour) => Slot('${hour.toString().padLeft(2, '0')}:00');

  int get hour => int.parse(value.substring(0, 2));
  int get minute => int.parse(value.substring(3, 5));
  int get minutesOfDay => hour * 60 + minute;

  Slot plusMinutes(int minutes) {
    final total = minutesOfDay + minutes;
    final h = (total ~/ 60) % 24;
    final m = total % 60;
    return Slot('${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}');
  }

  Slot plusHours(int hours) => plusMinutes(hours * 60);

  /// Would adding [minutes] cross midnight?
  bool overflowsDay(int minutes) => minutesOfDay + minutes > 24 * 60;
}

class BookingWindow {
  const BookingWindow({required this.end, required this.bufferedEnd, required this.isValid, this.error});
  final Slot end;
  final Slot bufferedEnd;
  final bool isValid;
  final String? error;
}

abstract final class BookingMath {
  /// Bookable start hours: 08:00 … 17:00 inclusive — 10 slots; the last
  /// lesson ends at 18:00.
  static const firstHour = 8;
  static const lastHour = 18;

  static List<Slot> slots() =>
      [for (var h = firstHour; h < lastHour; h++) Slot.fromHour(h)];

  /// Same-day lead time: for today, every slot with `hour <= now.hour + 1` is
  /// unavailable. Any other date → nothing is past.
  static Set<Slot> pastSlots(String date, {DateTime? now}) {
    final n = now ?? DateTime.now();
    if (date != ymd(n)) return const {};
    final cutoff = n.hour + 1;
    return {for (final s in slots()) if (s.hour <= cutoff) s};
  }

  /// Does a [durationHours] session from [start] finish by the 18:00 close?
  ///
  /// `DayAvailability.isFree` answers "is this hour taken", and for an hour
  /// outside 08:00–17:00 the answer is vacuously *no* — nothing is ever
  /// booked, blocked or past at 19:00, because all three sets are built from
  /// [slots]. Walking a range with `isFree` alone therefore strolls straight
  /// through closing time, and the resulting hours are held on the calendar
  /// but never drawn by any timeline that iterates [slots].
  static bool fitsInDay(Slot start, int durationHours) =>
      durationHours > 0 &&
      start.hour >= firstHour &&
      start.hour + durationHours <= lastHour;

  /// The leading back-to-back run of [sorted].
  ///
  /// A selection must never contain a gap (§8.4): the write derives
  /// `endTime` from first→last, so a gapped selection books straight across
  /// the missing hour. Tapping enforces this, but pruning an hour that was
  /// taken mid-session can split a run, and then only the leading part is
  /// still honest about what was reserved.
  static List<Slot> leadingRun(Iterable<Slot> sorted) {
    final run = <Slot>[];
    for (final s in sorted) {
      if (run.isEmpty || s.hour == run.last.hour + 1) {
        run.add(s);
      } else {
        break;
      }
    }
    return run;
  }

  static BookingWindow window(Slot start, int durationHours,
      {int bufferMinutes = 60}) {
    final end = start.plusHours(durationHours);
    final buffered = start.plusMinutes(durationHours * 60 + bufferMinutes);
    final overflows = start.overflowsDay(durationHours * 60 + bufferMinutes);
    return BookingWindow(
      end: end,
      bufferedEnd: buffered,
      isValid: !overflows,
      error: overflows ? 'Booking extends past midnight' : null,
    );
  }
}
