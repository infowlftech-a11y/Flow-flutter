import 'package:flutter_test/flutter_test.dart';

import 'package:flow/data/models/app_user.dart';
import 'package:flow/data/models/report.dart';
import 'package:flow/data/models/support.dart';

void main() {
  group('staff identification', () {
    test('admin, owner and support are staff; kiter and business are not', () {
      AppUser user(String role) =>
          AppUser.fromDoc('u', {'role': role, 'status': 'active'});

      expect(user('admin').isStaff, isTrue);
      expect(user('owner').isStaff, isTrue);
      expect(user('support').isStaff, isTrue);
      expect(user('kiter').isStaff, isFalse);
      expect(user('business').isStaff, isFalse);
    });

    test('owner maps onto the admin role', () {
      expect(UserRole.parse('owner'), UserRole.admin);
      expect(UserRole.parse('admin'), UserRole.admin);
    });

    test('an unknown role triggers onboarding rather than granting access',
        () {
      final user = AppUser.fromDoc('u', {'role': 'wizard'});
      expect(user.role, UserRole.unknown);
      expect(user.isStaff, isFalse);
      expect(user.isTrainer, isFalse);
    });
  });

  group('account status', () {
    test('rejected is a distinct state, not a fallback to active', () {
      final user = AppUser.fromDoc('u', {
        'role': 'business',
        'status': 'rejected',
      });
      expect(user.status, AccountStatus.rejected);
      expect(user.isTrainer, isTrue);
    });

    test('a missing status is none, never active', () {
      expect(AppUser.fromDoc('u', {'role': 'kiter'}).status,
          AccountStatus.none);
    });

    test("blockedUntil accepts 'forever' and ISO dates", () {
      final forever = AppUser.fromDoc('u', {'blockedUntil': 'forever'});
      expect(forever.isPermanentlyBlocked, isTrue);
      expect(forever.blockedUntil, isNull);

      final timed = AppUser.fromDoc('u', {'blockedUntil': '2026-09-01'});
      expect(timed.isPermanentlyBlocked, isFalse);
      expect(timed.blockedUntil, DateTime(2026, 9, 1));
    });

    group('a timed suspension lapses on its own (§2.4)', () {
      // Regression: the session gate read only `status`, so a 7-day ban was
      // permanent — the rules forbid a user rewriting their own status, and
      // only a manual admin unblock ever cleared it. The blocked screen's
      // one-minute ticker invalidates the profile stream expecting exactly
      // this check.
      AppUser blocked(String until) => AppUser.fromDoc('u', {
            'role': 'kiter',
            'status': 'blocked',
            'blockedUntil': until,
          });

      test('a past date releases the account', () {
        final past = DateTime.now().subtract(const Duration(days: 1));
        expect(blocked(past.toIso8601String()).isBlockInForce, isFalse);
      });

      test('a future date keeps it blocked', () {
        final future = DateTime.now().add(const Duration(days: 1));
        expect(blocked(future.toIso8601String()).isBlockInForce, isTrue);
      });

      test("'forever' never lapses", () {
        expect(blocked('forever').isBlockInForce, isTrue);
      });

      test('a missing or unparseable date fails closed', () {
        // Failing open would let a malformed value unblock someone.
        expect(
            AppUser.fromDoc('u', {'status': 'blocked'}).isBlockInForce, isTrue);
        expect(blocked('not-a-date').isBlockInForce, isTrue);
      });
    });
  });

  group('Report', () {
    test('parses and defaults to open', () {
      final r = Report.fromDoc('r', {
        'reporterId': 'rider1',
        'reporterName': 'Lina',
        'reportedUserId': 'trainer1',
        'reportedUserName': 'Omar',
        'reason': 'Safety concerns',
        'details': 'Took us out in 40 knots.',
      });
      expect(r.isOpen, isTrue);
      expect(r.reason, 'Safety concerns');
      expect(r.reportedUserId, 'trainer1');
    });

    test('resolved and dismissed both close the report', () {
      for (final status in ['resolved', 'dismissed']) {
        expect(Report.fromDoc('r', {'status': status}).isOpen, isFalse,
            reason: status);
      }
    });
  });

  group('Appeal', () {
    test('messages parse from the document array, not a sub-collection', () {
      final appeal = Appeal.fromDoc('a', {
        'userId': 'u1',
        'userName': 'Lina',
        'reason': 'I was not the one who cancelled.',
        'status': 'pending',
        'messages': [
          {
            'id': '1',
            'senderId': 'u1',
            'senderName': 'Lina',
            'text': 'Please review.',
            'timestamp': '2026-08-01T10:00:00.000Z',
          },
          {
            'id': '2',
            'senderId': 'staff1',
            'senderName': 'Flow Support',
            'text': 'Looking into it.',
            'timestamp': '2026-08-01T11:00:00.000Z',
          },
        ],
      });
      expect(appeal.messages, hasLength(2));
      expect(appeal.messages.last.senderName, 'Flow Support');
      expect(appeal.messages.first.timestamp, isNotNull);
    });

    test('a reply round-trips through the arrayUnion payload', () {
      final message = AppealMessage(
        id: '3',
        senderId: 'staff1',
        senderName: 'Flow Support',
        text: 'Suspension lifted.',
        timestamp: DateTime.utc(2026, 8, 2, 9),
      );
      final restored = AppealMessage.fromMap(message.toMap());
      expect(restored.text, message.text);
      expect(restored.senderName, message.senderName);

      // The *instant* is what has to survive. `DocX.date` deliberately hands
      // back local time, and Dart's DateTime.== compares the isUtc flag as
      // well as the moment, so comparing the objects directly would assert
      // the timezone rather than the payload. The web client writes these
      // with JS toISOString(), which always carries a Z — reading those back
      // as UTC is what made appeal replies show the wrong calendar day.
      expect(restored.timestamp, isNotNull);
      expect(restored.timestamp!.toUtc(), message.timestamp!.toUtc());
      expect(restored.timestamp!.isUtc, isFalse);
    });
  });
}
