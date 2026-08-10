// Station services and safari seats. The seat arithmetic guards real money:
// an overbooked trip must clamp to zero seats left, and a zero-capacity trip
// must never divide by zero or report itself sold out (capacity 0 means "not
// configured", and sold-out would hide it from sale forever).
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/constants.dart';
import 'package:flow/data/models/catalogue.dart';

void main() {
  group('StationService kind', () {
    ServiceKind kindOf(Map<String, dynamic> d) =>
        StationService.fromDoc('s', d).kind;

    test('beach_use and beach both mean beach pass', () {
      expect(kindOf({'kind': 'beach_use'}), ServiceKind.beachUse);
      expect(kindOf({'kind': 'Beach'}), ServiceKind.beachUse,
          reason: 'case-insensitive');
    });

    test('falls back to the legacy `type` key, then to rental', () {
      expect(kindOf({'type': 'beach_use'}), ServiceKind.beachUse);
      expect(kindOf({'kind': 'rental'}), ServiceKind.rental);
      expect(kindOf(const {}), ServiceKind.rental);
      expect(kindOf({'kind': 'kayak'}), ServiceKind.rental);
    });
  });

  group('SafariTrip seats', () {
    SafariTrip trip({int capacity = 0, int booked = 0}) => SafariTrip.fromDoc(
        't', {'capacity': capacity, 'bookedSeats': booked});

    test('seatsLeft clamps an overbooked trip to zero', () {
      expect(trip(capacity: 8, booked: 3).seatsLeft, 5);
      expect(trip(capacity: 8, booked: 8).seatsLeft, 0);
      expect(trip(capacity: 8, booked: 11).seatsLeft, 0,
          reason: 'an oversold trip must not show negative seats');
    });

    test('zero capacity is unconfigured, not sold out', () {
      final t = trip(capacity: 0, booked: 5);
      expect(t.isSoldOut, isFalse);
      expect(t.fillRatio, 0, reason: 'no division by zero');
    });

    test('fillRatio clamps into 0..1', () {
      expect(trip(capacity: 10, booked: 5).fillRatio, .5);
      expect(trip(capacity: 10, booked: 15).fillRatio, 1.0);
    });

    test('sold out exactly at capacity', () {
      expect(trip(capacity: 6, booked: 6).isSoldOut, isTrue);
      expect(trip(capacity: 6, booked: 5).isSoldOut, isFalse);
    });
  });

  test('StationInstructor rate falls back to the display default', () {
    expect(StationInstructor.fromDoc('i', const {}).displayRate,
        FlowConst.defaultDisplayRate);
    expect(StationInstructor.fromDoc('i', {'rate': 70}).displayRate, 70);
  });
}
