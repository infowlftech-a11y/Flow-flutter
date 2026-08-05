import '../../core/utils/doc_x.dart';

/// What a day's wind means to someone deciding whether to book it.
///
/// The bands are the ones riders actually use, not meteorological ones: the
/// question is never "how fast is the wind" but "can I ride, and on what".
/// Deliberately coarse — a forecast eight days out is not accurate to the
/// knot, and a scale with more steps than the data supports invites people to
/// trust the difference between 17 and 19.
enum WindRating {
  /// Nothing to fly. A lesson still runs — theory, body-dragging, rigging.
  calm('Too light', 'Not enough wind to ride'),

  /// Rideable on a big kite by someone who already knows how.
  light('Light', 'Big kite, experienced riders'),

  /// The reason people come to the Red Sea.
  good('Good', 'Prime conditions'),

  /// Fine for confident riders; not a beginner's first day.
  strong('Strong', 'Small kite, not for beginners'),

  /// Above what a school will safely teach in.
  extreme('Too strong', 'Lessons usually cancelled');

  const WindRating(this.label, this.detail);
  final String label;
  final String detail;

  /// Thresholds in knots, at the daily maximum.
  static WindRating fromKnots(double knots) {
    if (knots < 10) return calm;
    if (knots < 15) return light;
    if (knots < 25) return good;
    if (knots < 34) return strong;
    return extreme;
  }

  /// Whether a beginner lesson is realistic. Used only for wording — it never
  /// blocks a booking, because the trainer is the one who decides that on the
  /// day, and a forecast is not an authority.
  bool get suitsBeginners => this == light || this == good;
}

/// One day of forecast at one spot.
class WindDay {
  const WindDay({
    required this.date,
    required this.knots,
    required this.gustKnots,
    required this.directionDegrees,
  });

  /// Local `YYYY-MM-DD`, matching how bookings store dates.
  final String date;

  /// Daily maximum sustained wind, knots.
  final double knots;

  /// Daily maximum gust, knots.
  final double gustKnots;

  final int directionDegrees;

  WindRating get rating => WindRating.fromKnots(knots);

  /// Eight-point compass. Sixteen points would imply a precision a daily
  /// dominant direction does not have.
  String get compass {
    const points = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final normalised = ((directionDegrees % 360) + 360) % 360;
    // +22.5 so each 45° sector centres on its label rather than starting at it.
    final index = (((normalised + 22.5) % 360) / 45).floor() % 8;
    return points[index];
  }

  /// Rounded for display — the underlying model has no business claiming
  /// tenths of a knot.
  int get displayKnots => knots.round();

  int get displayGustKnots => gustKnots.round();

  /// **There is deliberately no `isGusty` flag.**
  ///
  /// There was one, thresholded at "gusts 8kt above sustained". Checking it
  /// against sixteen real days at El Gouna killed it: the gust delta there
  /// ranged 11–18 knots, so the badge would have been lit on every single
  /// day. A flag that is always on is not a warning, it is decoration.
  ///
  /// The gust number itself is genuinely useful to a kiter — it is the
  /// difference between a smooth day and a hard one — so it is shown as a
  /// number and the reader draws their own conclusion. That is the honest
  /// version of what the flag was trying to say.
  bool get hasUsefulGust => gustKnots > knots;
}

/// A spot's forecast, indexed by date for a direct lookup from the day strip.
class WindForecast {
  const WindForecast({required this.spot, required this.days});

  final String spot;
  final Map<String, WindDay> days;

  static const empty = WindForecast(spot: '', days: {});

  WindDay? forDate(String ymd) => days[ymd];

  bool get isEmpty => days.isEmpty;

  /// Parses an Open-Meteo `daily` block.
  ///
  /// Tolerant on purpose, in the same spirit as the Firestore readers (§5): a
  /// short or ragged array must degrade to fewer days, never throw. Wind is a
  /// decoration on the booking flow — it must never be able to break it.
  factory WindForecast.fromOpenMeteo(String spot, Map<String, dynamic> json) {
    final daily = json.nested('daily');
    final dates = daily.strList('time');
    final speeds = _numList(daily['wind_speed_10m_max']);
    final gusts = _numList(daily['wind_gusts_10m_max']);
    final directions = _numList(daily['wind_direction_10m_dominant']);

    final days = <String, WindDay>{};
    for (var i = 0; i < dates.length; i++) {
      final speed = i < speeds.length ? speeds[i] : null;
      if (speed == null) continue; // A null entry means "no data", not zero.
      days[dates[i]] = WindDay(
        date: dates[i],
        knots: speed,
        gustKnots: (i < gusts.length ? gusts[i] : null) ?? speed,
        directionDegrees: ((i < directions.length ? directions[i] : null) ?? 0)
            .round(),
      );
    }
    return WindForecast(spot: spot, days: days);
  }

  static List<double?> _numList(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final v in raw)
        switch (v) {
          num n => n.toDouble(),
          String s => double.tryParse(s),
          _ => null,
        },
    ];
  }
}
