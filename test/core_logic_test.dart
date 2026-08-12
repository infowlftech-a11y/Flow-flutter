import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/constants.dart';
import 'package:flow/core/utils/date_x.dart';
import 'package:flow/core/utils/doc_x.dart';
import 'package:flow/features/onboarding/onboarding_validators.dart';
import 'package:flow/data/models/booking.dart';
import 'package:flow/data/models/schedule.dart';
import 'package:flow/data/models/payment.dart';
import 'package:flow/dev/seed_data.dart';
import 'package:flow/data/models/wind.dart';

void main() {
  group('Slot', () {
    test('parses H:mm and HH:mm, rejects invalid', () {
      expect(Slot.tryParse('9:30')?.value, '09:30');
      expect(Slot.tryParse('09:30 extra')?.value, '09:30');
      expect(Slot.tryParse('24:00'), isNull);
      expect(Slot.tryParse('10:61'), isNull);
    });

    test('arithmetic and overflow', () {
      expect(const Slot('17:00').plusHours(1).value, '18:00');
      expect(const Slot('23:30').overflowsDay(45), isTrue);
    });
  });

  group('BookingMath', () {
    test('exactly 10 bookable slots, 08:00–17:00', () {
      final slots = BookingMath.slots();
      expect(slots.length, 10);
      expect(slots.first.value, '08:00');
      expect(slots.last.value, '17:00');
    });

    test('same-day lead time: at 09:30 the first bookable hour is 11:00', () {
      final now = DateTime(2026, 8, 2, 9, 30);
      final past = BookingMath.pastSlots(ymd(now), now: now);
      expect(past.contains(const Slot('10:00')), isTrue);
      expect(past.contains(const Slot('11:00')), isFalse);
    });

    test('other days have no past slots', () {
      expect(BookingMath.pastSlots('2099-01-01'), isEmpty);
    });

    test('window flags past-midnight overflow', () {
      final w = BookingMath.window(const Slot('17:00'), 6, bufferMinutes: 90);
      expect(w.isValid, isFalse);
      expect(w.error, 'Booking extends past midnight');
    });
  });

  group('Booking', () {
    test('bucketing: unanswered past request expires to history', () {
      final b = Booking.fromDoc('x', {
        'date': '2020-01-01',
        'status': 'pending',
        'startTime': '09:00',
        'durationHours': 2,
      });
      expect(b.bucket(DateTime(2026)), BookingBucket.history);
      expect(b.subLabel, 'Expired — never confirmed');
    });

    test('no usable time → runs to end of day, never prematurely expired',
        () {
      final b = Booking.fromDoc('x', {
        'date': '2026-08-02',
        'status': 'confirmed',
      });
      expect(b.bucket(DateTime(2026, 8, 2, 12)), BookingBucket.upcoming);
    });

    test('canonical field names parse', () {
      final b = Booking.fromDoc('x', {
        'date': '2026-08-14',
        'status': 'active',
        'instructorId': 'trainer1',
        'kiterId': 'rider1',
        'studentName': 'Lina',
        'startTime': '09:00',
        'totalPrice': 72.5,
        'type': 'lesson',
      });
      expect(b.status, BookingStatus.inProgress);
      expect(b.instructorId, 'trainer1');
      expect(b.kiterId, 'rider1');
      expect(b.studentName, 'Lina');
      expect(b.startTime, '09:00');
      expect(b.totalPrice, 72.5);
    });

    // The legacy web client is gone, so alias spellings are no longer read.
    // Tolerance to *malformed* values is a separate guarantee and survives.
    test('legacy aliases are no longer honoured', () {
      final b = Booking.fromDoc('x', {
        'date': '2026-08-14',
        'status': 'confirmed',
        'stationId': 'station1',
        'guestId': 'rider1',
        'guestName': 'Lina',
        'time': '09:00',
        'price': 90,
      });
      expect(b.instructorId, isEmpty);
      expect(b.kiterId, isEmpty);
      expect(b.studentName, 'Rider');
      expect(b.totalPrice, isNull);
    });

    test('a malformed document still never crashes a screen', () {
      final b = Booking.fromDoc('x', {
        'date': 42,
        'status': {'nope': true},
        'totalPrice': 'not a number',
        'selectedTimes': '09:00',
        'durationHours': '3',
        'gearNeeded': 'true',
      });
      expect(b.status, BookingStatus.unknown);
      expect(b.totalPrice, isNull);
      expect(b.selectedTimes, ['09:00']);
      expect(b.durationHours, 3);
      expect(b.gearNeeded, isTrue);
      expect(b.timeRange, '—');
    });
  });

  group('DayAvailability', () {
    test('blocked reason precedence: Away wins over everything', () {
      final day = DayAvailability.compose(
        date: '2099-01-01',
        blocks: [
          Availability.fromDoc('b1', {
            'instructorId': 't',
            'date': '2099-01-01',
            'startTime': '09:00',
            'endTime': '10:00',
            'status': 'host-blocked',
          }),
        ],
        bookings: const [],
        vacations: [
          Vacation.fromDoc('v1', {
            'instructorId': 't',
            'startDate': '2099-01-01',
            'endDate': '2099-01-02',
          }),
        ],
      );
      expect(day.blockedReason(const Slot('09:00')), 'Away');
      expect(day.isFree(const Slot('12:00')), isFalse);
    });

    test('vacation covers() is inclusive', () {
      final v = Vacation.fromDoc('v', {
        'instructorId': 't',
        'startDate': '2026-08-10',
        'endDate': '2026-08-12',
      });
      expect(v.covers('2026-08-10'), isTrue);
      expect(v.covers('2026-08-12'), isTrue);
      expect(v.covers('2026-08-13'), isFalse);
    });
  });

  group('money', () {
    test('whole vs fractional display', () {
      expect(money(120), 'EGP 120');
      expect(money(72.5), 'EGP 72.50');
      expect(money(null), '—');
    });

    test('thousands are grouped — EGP prices have four figures', () {
      // The reason this exists: the currency switch multiplied every number
      // by ~50, and `EGP 12000` is a price nobody reads correctly at a glance.
      expect(money(1200), 'EGP 1,200');
      expect(money(12000), 'EGP 12,000');
      expect(money(1234567), 'EGP 1,234,567');
      expect(money(999), 'EGP 999');
      expect(money(1200.5), 'EGP 1,200.50');
    });

    test('a refund reads as negative, with the sign before the digits', () {
      expect(money(-350), 'EGP -350');
      expect(money(-1200.25), 'EGP -1,200.25');
    });
  });

  group('BookingMath.leadingRun', () {
    // Regression: pruning an hour that was taken mid-session used to leave a
    // gapped selection. The write derives endTime from first→last, so
    // {09,11} was written as 09:00–11:00 — booking straight across the 10:00
    // someone else had just taken, and showing the trainer one unbroken
    // 2-hour block.
    test('an untouched run survives whole', () {
      final run = BookingMath.leadingRun(
          const [Slot('09:00'), Slot('10:00'), Slot('11:00')]);
      expect([for (final s in run) s.value], ['09:00', '10:00', '11:00']);
    });

    test('a gap truncates to the leading run', () {
      final run = BookingMath.leadingRun(
          const [Slot('09:00'), Slot('11:00'), Slot('12:00')]);
      expect([for (final s in run) s.value], ['09:00']);
    });

    test('a hole punched mid-run drops everything after it', () {
      // 09,10,11,12 with 11:00 taken → prune leaves 09,10,12.
      final run = BookingMath.leadingRun(
          const [Slot('09:00'), Slot('10:00'), Slot('12:00')]);
      expect([for (final s in run) s.value], ['09:00', '10:00']);
    });

    test('empty in, empty out', () {
      expect(BookingMath.leadingRun(const <Slot>[]), isEmpty);
    });
  });

  group('BookingMath.fitsInDay', () {
    // Regression: the walk-in sheet probed a range with DayAvailability.isFree
    // alone, which is vacuously true past 17:00 — nothing is ever booked,
    // blocked or past at 19:00. A 4h walk-in was offered a 17:00 start and
    // written as 17:00–21:00, holding hours no timeline renders.
    test('a session ending exactly at the 18:00 close fits', () {
      expect(BookingMath.fitsInDay(const Slot('17:00'), 1), isTrue);
      expect(BookingMath.fitsInDay(const Slot('14:00'), 4), isTrue);
    });

    test('a session running past the close does not', () {
      expect(BookingMath.fitsInDay(const Slot('17:00'), 4), isFalse);
      expect(BookingMath.fitsInDay(const Slot('16:00'), 3), isFalse);
    });

    test('a start before opening does not', () {
      expect(BookingMath.fitsInDay(const Slot('07:00'), 1), isFalse);
    });

    test('a non-positive duration does not', () {
      expect(BookingMath.fitsInDay(const Slot('09:00'), 0), isFalse);
    });
  });

  group('OnboardingValidators', () {
    test('name: rejects empty, too short, symbol-only and overlong', () {
      expect(OnboardingValidators.name('Lina'), isNull);
      expect(OnboardingValidators.name('  Omar Farouk  '), isNull);
      expect(OnboardingValidators.name(''), isNotNull);
      expect(OnboardingValidators.name('   '), isNotNull);
      expect(OnboardingValidators.name('L'), isNotNull);
      // Symbols and digits are not a name — the old check only tested empty.
      expect(OnboardingValidators.name('...'), isNotNull);
      expect(OnboardingValidators.name('12345'), isNotNull);
      expect(OnboardingValidators.name('x' * 61), isNotNull);
    });

    test('name: accepts non-Latin scripts', () {
      // Arabic is a first-class case on this coast; a Latin-only rule would
      // reject a real name.
      expect(OnboardingValidators.name('كريم'), isNull);
    });

    test('age: bounded 8–99 and numeric', () {
      expect(OnboardingValidators.age('27'), isNull);
      expect(OnboardingValidators.age('8'), isNull);
      expect(OnboardingValidators.age('99'), isNull);
      expect(OnboardingValidators.age('7'), isNotNull);
      expect(OnboardingValidators.age(''), isNotNull);
      expect(OnboardingValidators.age('abc'), isNotNull);
    });

    test('bio: optional but bounded', () {
      expect(OnboardingValidators.bio(''), isNull);
      expect(OnboardingValidators.bio('Short and sweet.'), isNull);
      expect(
          OnboardingValidators.bio(
              'x' * (OnboardingValidators.maxBioLength + 1)),
          isNotNull);
    });

    test('phone: optional, shape-checked, not locale-locked', () {
      expect(OnboardingValidators.phone(''), isNull);
      expect(OnboardingValidators.phone('+20 100 123 4567'), isNull);
      expect(OnboardingValidators.phone('(020) 7946-0958'), isNull);
      expect(OnboardingValidators.phone('not a phone'), isNotNull);
      expect(OnboardingValidators.phone('123'), isNotNull);
    });

    test('rate: trainers price themselves, within a typo guard', () {
      // The €60–€110 platform band is gone: a marketplace that refuses a
      // trainer's real rate loses that trainer. What is left catches a
      // mistyped field, not a policy.
      String? check(String v) => OnboardingValidators.rate(v);
      expect(check('250'), isNull);
      expect(check('1200'), isNull, reason: 'four figures is an ordinary EGP rate');
      expect(check('40'), isNull, reason: 'a cheap rate is still a real rate');
      expect(check('${FlowConst.maxSaneHourlyRate}'), isNull);

      expect(check(''), isNotNull);
      expect(check('0'), isNotNull, reason: 'an unfinished form, not a gift');
      expect(check('-100'), isNotNull);
      expect(check('abc'), isNotNull);
      expect(check('${FlowConst.maxSaneHourlyRate + 1}'), isNotNull,
          reason: 'a slipped keypad');
    });
  });

  group('nationality list', () {
    test('has no duplicates', () {
      final seen = <String>{};
      final dupes = [
        for (final n in FlowConst.nationalities)
          if (!seen.add(n)) n,
      ];
      expect(dupes, isEmpty, reason: 'duplicate demonyms: $dupes');
    });

    test('is long enough to be worth searching', () {
      expect(FlowConst.nationalities.length, greaterThan(150));
    });
  });

  group('DocX.date normalises to local', () {
    // Regression: DateTime.tryParse returns a *UTC* instance for anything
    // carrying a Z or an offset, while Timestamp.toDate() and
    // fromMillisecondsSinceEpoch both return local. Downstream code reads
    // .day/.month/.hour off the result, so a UTC leak showed the wrong
    // calendar day — in Egypt (UTC+2/+3) a 23:00Z stamp is already tomorrow.
    test('a Z-suffixed ISO string is converted, not left in UTC', () {
      final d = <String, dynamic>{'createdAt': '2026-08-04T23:00:00Z'}
          .date('createdAt');
      expect(d, isNotNull);
      expect(d!.isUtc, isFalse, reason: 'must be local for .day/.hour reads');
      // Same instant — only the field accessors change.
      expect(d.toUtc(), DateTime.utc(2026, 8, 4, 23));
    });

    test('an explicit offset is also converted', () {
      final d =
          <String, dynamic>{'t': '2026-08-04T23:00:00+05:00'}.date('t');
      expect(d!.isUtc, isFalse);
      expect(d.toUtc(), DateTime.utc(2026, 8, 4, 18));
    });

    test('a naive ISO string keeps its wall-clock reading', () {
      final d = <String, dynamic>{'t': '2026-08-04T23:00:00'}.date('t');
      expect(d!.isUtc, isFalse);
      expect(d.hour, 23);
    });

    test('epoch seconds and millis resolve to the same local instant', () {
      final millis = <String, dynamic>{'t': 1785970800000}.date('t');
      final seconds = <String, dynamic>{'t': 1785970800}.date('t');
      expect(millis, seconds);
      expect(millis!.isUtc, isFalse);
    });
  });

  group('seed cast', () {
    test('every email is unique', () {
      // A duplicate would make two accounts collide on the same auth user and
      // silently overwrite one profile with the other.
      final emails = [for (final a in seedAccounts) a.email];
      expect(emails.toSet(), hasLength(emails.length));
    });

    test('every account sits on a real kite spot', () {
      for (final a in seedAccounts) {
        expect(FlowConst.kiteSpots.contains(a.spot), isTrue,
            reason: '${a.email} is at "${a.spot}"');
      }
    });

    test('every spot has at least one bookable business', () {
      // The point of the cast: no spot filter in Explore should come back
      // empty, because an empty result is indistinguishable from a bug.
      final covered = {
        for (final a in seedAccounts)
          if (a.isBusiness && !a.keepPending) a.spot,
      };
      for (final spot in FlowConst.kiteSpots) {
        expect(covered.contains(spot), isTrue, reason: 'nothing at $spot');
      }
    });

    test('every seeded rate is one a trainer could really have set', () {
      // The platform band this used to assert is gone — trainers price
      // themselves. What still has to hold is that the seed data would pass
      // the form's own validator, so a seeded trainer is indistinguishable
      // from one who signed up.
      for (final a in seedAccounts.where((a) => a.isBusiness)) {
        expect(OnboardingValidators.rate('${a.rate}'), isNull,
            reason: a.email);
      }
      // And the seeded prices are not all the same number, or the Explore
      // sort by price would be untested by construction.
      final rates = {
        for (final a in seedAccounts.where((a) => a.isBusiness)) a.rate,
      };
      expect(rates.length, greaterThan(1));
    });

    test('all three operator kinds are represented', () {
      final types = {
        for (final a in seedAccounts.where((a) => a.isBusiness))
          a.businessType,
      };
      expect(types, containsAll(['Instructor', 'Station', 'Safari operator']));
    });

    test('some accounts stay pending, and approve-all excludes them', () {
      final pending = seedAccounts.where((a) => a.keepPending);
      expect(pending, isNotEmpty,
          reason: 'the admin console needs something in its queue');
      for (final a in pending) {
        expect(approvableAccounts.contains(a), isFalse, reason: a.email);
      }
      // And approve-all never reaches a rider or the admin.
      for (final a in approvableAccounts) {
        expect(a.isBusiness, isTrue, reason: a.email);
      }
    });

    test('the layout stress cases are present', () {
      final businesses = seedAccounts.where((a) => a.isBusiness).toList();
      expect(businesses.any((a) => a.bio.isEmpty), isTrue,
          reason: 'need a coach with no bio');
      expect(businesses.any((a) => a.bio.length >= 200), isTrue,
          reason: 'need a coach with a near-max bio');
      expect(businesses.any((a) => a.languages.length >= 5), isTrue,
          reason: 'need a coach with many languages');
      expect(seedAccounts.any((a) => a.name.length >= 25), isTrue,
          reason: 'need a long name');
      // Non-Latin script, for RTL and avatar initials.
      expect(seedAccounts.any((a) => RegExp(r'[؀-ۿ]').hasMatch(a.name)),
          isTrue, reason: 'need a name in Arabic script');
    });

    test('bios respect the onboarding ceiling', () {
      // Seeded profiles must be values the app itself would have accepted.
      for (final a in seedAccounts) {
        expect(OnboardingValidators.bio(a.bio), isNull, reason: a.email);
        expect(OnboardingValidators.name(a.name), isNull, reason: a.email);
      }
    });
  });

  group('payments', () {
    Booking bookingWith(Map<String, dynamic> extra) => Booking.fromDoc('b1', {
          'date': '2026-08-05',
          'status': 'completed',
          'instructorId': 't1',
          'kiterId': 'r1',
          'totalPrice': 160,
          ...extra,
        });

    test('a booking with no payment fields is "unknown", never "unpaid"', () {
      // The whole point of the extra state. Every session written before
      // payments were tracked would otherwise be reported as money owed, and
      // every trainer would open the app to a debt that does not exist.
      final legacy = bookingWith({});
      expect(legacy.payment.status, PaymentStatus.unknown);
      expect(legacy.payment.isOutstanding, isFalse);
      expect(legacy.awaitsPayment, isFalse);
      expect(legacy.payment.status.isDisplayable, isFalse);
    });

    test('an explicitly unpaid completed session is outstanding', () {
      final owing = bookingWith({'paymentStatus': 'unpaid'});
      expect(owing.payment.isOutstanding, isTrue);
      expect(owing.awaitsPayment, isTrue);
      expect(owing.payment.status.isDisplayable, isTrue);
    });

    test('an unpaid session that is not finished is not yet owed', () {
      // You do not owe for a lesson you have not had.
      final upcoming =
          bookingWith({'paymentStatus': 'unpaid', 'status': 'confirmed'});
      expect(upcoming.payment.isOutstanding, isTrue);
      expect(upcoming.awaitsPayment, isFalse);
    });

    test('paid and refunded read back correctly', () {
      expect(bookingWith({'paymentStatus': 'paid'}).payment.isSettled, isTrue);
      expect(bookingWith({'paymentStatus': 'paid'}).awaitsPayment, isFalse);
      final refunded = bookingWith({'paymentStatus': 'refunded'});
      expect(refunded.payment.status, PaymentStatus.refunded);
      // A refund is not an amount owing — nobody is chasing it.
      expect(refunded.payment.isOutstanding, isFalse);
    });

    test('a failed card payment is money still owed', () {
      final failed = bookingWith({'paymentStatus': 'failed'});
      expect(failed.payment.isOutstanding, isTrue);
      expect(failed.awaitsPayment, isTrue);
    });

    test('amountDue prefers the amount captured at booking time', () {
      // If a trainer raises their rate, an old booking must still show what
      // was agreed, not what the lesson would cost today.
      final captured =
          bookingWith({'amountDue': 140, 'totalPrice': 160});
      expect(captured.amountDue, 140);
      // And falls back for documents written before amountDue existed.
      expect(bookingWith({}).amountDue, 160);
      expect(bookingWith({'totalPrice': null}).amountDue, 0);
    });

    test('unrecognised wire values degrade instead of throwing', () {
      expect(PaymentStatus.parse('something-new'), PaymentStatus.unknown);
      expect(PaymentStatus.parse(null), PaymentStatus.unknown);
      expect(PaymentMethod.parse('crypto'), PaymentMethod.cash);
      expect(PaymentMethod.parse(null), PaymentMethod.cash);
    });

    test('only cash is offered, and only cash is settled by a person', () {
      // Guards the seam: when a processor is wired in, these change together
      // or the UI offers a method nothing can actually take.
      expect(PaymentMethod.cash.isAvailable, isTrue);
      expect(PaymentMethod.cash.isCollectedInPerson, isTrue);
      for (final m in [
        PaymentMethod.card,
        PaymentMethod.wallet,
        PaymentMethod.transfer,
      ]) {
        expect(m.isAvailable, isFalse, reason: m.name);
        expect(m.isCollectedInPerson, isFalse, reason: m.name);
      }
    });

    test('a new booking records what is owed, never that it is settled', () {
      final fields = PaymentInfo.initialFields(amount: 160);
      expect(fields['paymentStatus'], 'unpaid');
      expect(fields['paymentMethod'], 'cash');
      expect(fields['currency'], 'EGP');
      expect(fields['amountDue'], 160);
      // No paidAt on creation — nothing has been collected yet.
      expect(fields.containsKey('paidAt'), isFalse);
    });
  });

  group('wind', () {
    test('every kite spot has coordinates', () {
      // A spot missing here silently shows no wind. The lists are edited in
      // different places, so this is the only thing keeping them in step.
      for (final spot in FlowConst.kiteSpots) {
        expect(FlowConst.spotCoordinates.containsKey(spot), isTrue,
            reason: '$spot has no coordinates');
      }
      // And nothing coordinates a spot that no longer exists.
      for (final spot in FlowConst.spotCoordinates.keys) {
        expect(FlowConst.kiteSpots.contains(spot), isTrue,
            reason: '$spot is not a kite spot');
      }
    });

    test('coordinates land on the Egyptian Red Sea', () {
      // Catches a transposed lat/lon or a stray sign, which would otherwise
      // silently forecast the wrong hemisphere.
      for (final entry in FlowConst.spotCoordinates.entries) {
        final (lat, lon) = entry.value;
        expect(lat, inInclusiveRange(22, 32), reason: entry.key);
        expect(lon, inInclusiveRange(32, 37), reason: entry.key);
      }
    });

    test('rating bands are the ones riders actually use', () {
      expect(WindRating.fromKnots(0), WindRating.calm);
      expect(WindRating.fromKnots(9.9), WindRating.calm);
      expect(WindRating.fromKnots(10), WindRating.light);
      expect(WindRating.fromKnots(14.9), WindRating.light);
      expect(WindRating.fromKnots(15), WindRating.good);
      expect(WindRating.fromKnots(24.9), WindRating.good);
      expect(WindRating.fromKnots(25), WindRating.strong);
      expect(WindRating.fromKnots(33.9), WindRating.strong);
      expect(WindRating.fromKnots(34), WindRating.extreme);
    });

    test('only the middle bands suit beginners', () {
      expect(WindRating.calm.suitsBeginners, isFalse);
      expect(WindRating.light.suitsBeginners, isTrue);
      expect(WindRating.good.suitsBeginners, isTrue);
      expect(WindRating.strong.suitsBeginners, isFalse);
      expect(WindRating.extreme.suitsBeginners, isFalse);
    });

    test('compass sectors centre on their label, and wrap', () {
      WindDay at(int degrees) => WindDay(
          date: '2026-08-05',
          knots: 18,
          gustKnots: 24,
          directionDegrees: degrees);
      expect(at(0).compass, 'N');
      expect(at(359).compass, 'N');
      expect(at(22).compass, 'N'); // Still inside N's sector, not NE.
      expect(at(23).compass, 'NE');
      expect(at(90).compass, 'E');
      expect(at(180).compass, 'S');
      expect(at(270).compass, 'W');
      expect(at(315).compass, 'NW');
      // 333° is the dominant direction El Gouna actually reported.
      expect(at(333).compass, 'NW');
      // Out-of-range values must not crash or index off the end.
      expect(at(720).compass, 'N');
      expect(at(-90).compass, 'W');
    });

    test('parses a real Open-Meteo daily block', () {
      // Trimmed from the live response for El Gouna.
      final forecast = WindForecast.fromOpenMeteo('El Gouna', {
        'daily': {
          'time': ['2026-08-05', '2026-08-06', '2026-08-11'],
          'wind_speed_10m_max': [17.0, 18.5, 7.6],
          'wind_gusts_10m_max': [31.9, 34.0, 20.2],
          'wind_direction_10m_dominant': [333, 322, 34],
        },
      });

      expect(forecast.days, hasLength(3));
      final first = forecast.forDate('2026-08-05')!;
      expect(first.displayKnots, 17);
      expect(first.displayGustKnots, 32);
      expect(first.compass, 'NW');
      expect(first.rating, WindRating.good);
      expect(forecast.forDate('2026-08-11')!.rating, WindRating.calm);
      expect(forecast.forDate('2026-01-01'), isNull);
    });

    test('a ragged or malformed block degrades instead of throwing', () {
      // Wind decorates the booking flow; it must never be able to break it.
      final short = WindForecast.fromOpenMeteo('El Gouna', {
        'daily': {
          'time': ['2026-08-05', '2026-08-06', '2026-08-07'],
          // Shorter than `time`, with a null hole.
          'wind_speed_10m_max': [17.0, null],
          'wind_gusts_10m_max': <dynamic>[],
          'wind_direction_10m_dominant': <dynamic>[],
        },
      });
      expect(short.days, hasLength(1));
      final only = short.forDate('2026-08-05')!;
      // Missing gust falls back to the sustained speed, never to zero.
      expect(only.displayGustKnots, 17);
      expect(only.directionDegrees, 0);

      expect(WindForecast.fromOpenMeteo('x', {}).isEmpty, isTrue);
      expect(
          WindForecast.fromOpenMeteo('x', {'daily': 'nonsense'}).isEmpty,
          isTrue);
      expect(
          WindForecast.fromOpenMeteo('x', {
            'daily': {'time': 'not-a-list'},
          }).isEmpty,
          isTrue);
    });
  });
}
