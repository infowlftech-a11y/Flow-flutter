// The social models are read from documents this app did not necessarily
// write well — and two of them encode deliberate product decisions that a
// refactor could quietly undo:
//
//   * An unrated trainer displays **5.0 with 0 reviews** (§8.10). Someone
//     "fixing" that to 0.0 would zero every new trainer in the marketplace.
//   * A chat id is the two uids *sorted* — deterministic from either side.
//     Break the sort and the same pair of people get two different threads
//     depending on who taps first.
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/data/models/social.dart';

void main() {
  group('Review.fromDoc', () {
    test('clamps rating into 1..5 and defaults the name', () {
      expect(Review.fromDoc('r', {'rating': 11}).rating, 5);
      expect(Review.fromDoc('r', {'rating': -3}).rating, 1);
      expect(Review.fromDoc('r', {'rating': 0}).rating, 1);
      // Absent rating is a 5, matching the unrated-trainer default.
      expect(Review.fromDoc('r', const {}).rating, 5);
      expect(Review.fromDoc('r', const {}).userName, 'Rider');
    });
  });

  group('RatingSummary', () {
    test('no reviews shows 5.0 / 0 — the marketplace default, not a zero', () {
      final s = RatingSummary.from(const []);
      expect(s.average, 5.0);
      expect(s.count, 0);
      expect(s.display, '5.0');
    });

    test('averages and rounds only at display', () {
      Review r(int rating) => Review(
          id: 'x',
          trainerId: 't',
          userId: 'u',
          userName: 'U',
          rating: rating);
      final s = RatingSummary.from([r(5), r(4), r(4)]);
      expect(s.count, 3);
      expect(s.average, closeTo(4.3333, .0001));
      expect(s.display, '4.3');
    });
  });

  group('ChatThread', () {
    test('idFor is order-independent', () {
      expect(ChatThread.idFor('zoe', 'adam'), 'adam_zoe');
      expect(ChatThread.idFor('adam', 'zoe'), 'adam_zoe');
    });

    test('unread counts survive a malformed document', () {
      final t = ChatThread.fromDoc('id', {
        'participants': ['a', 'b'],
        'participantNames': {'a': 'Ana', 'b': null},
        'unreadCount': {
          'a': '3', // string
          'b': -2, // negative
          'c': 1.9, // double
          'd': ['garbage'], // wrong type entirely
        },
      });
      expect(t.unreadFor('a'), 3);
      expect(t.unreadFor('b'), 0, reason: 'negatives clamp to zero');
      expect(t.unreadFor('c'), 1);
      expect(t.unreadFor('d'), 0);
      expect(t.unreadFor('nobody'), 0);
    });

    test('partner helpers fall back rather than crash', () {
      final t = ChatThread.fromDoc('id', {
        'participants': ['me', 'other'],
        'participantNames': {'other': ''},
      });
      expect(t.partnerId('me'), 'other');
      expect(t.partnerName('me'), 'Rider',
          reason: 'empty stored name falls back to the neutral placeholder');
      // A thread I am somehow not in yields empty, not a throw.
      final solo = ChatThread.fromDoc('id', {
        'participants': ['me'],
        'participantNames': <String, dynamic>{},
      });
      expect(solo.partnerId('me'), '');
    });
  });

  group('NotificationKind.parse', () {
    test('covers the wire aliases and fails to system', () {
      expect(NotificationKind.parse('booking_request'),
          NotificationKind.bookingRequest);
      expect(NotificationKind.parse('booking_new'),
          NotificationKind.bookingRequest,
          reason: 'legacy alias still delivered by the push backend');
      expect(NotificationKind.parse('global_broadcast'),
          NotificationKind.broadcast);
      expect(NotificationKind.parse('confetti'), NotificationKind.system);
      expect(NotificationKind.parse(null), NotificationKind.system);
    });
  });

  test('AppNotification defaults title to the brand, not to empty', () {
    final n = AppNotification.fromDoc('n', const {});
    expect(n.title, 'FLOW');
    expect(n.message, '');
    expect(n.kind, NotificationKind.system);
    expect(n.read, isFalse);
  });
}
