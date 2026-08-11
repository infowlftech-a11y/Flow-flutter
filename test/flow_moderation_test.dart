// FLOW 6 — report a user, suspend them, hear their appeal, let them back in.
//
// admin_test.dart covers Report and Appeal as models and the blockedUntil
// lapse arithmetic. What is not covered is the round trip between the three
// parties, which is where this flow actually lives:
//
//   reporter → files, and must never be able to see what happened next
//   admin    → watchReports / watchAppeals / blockUser / setAppealStatus
//   subject  → watchMyAppeal, and what their account can still do
//
// The last of those is the one the prompt asks about directly, and it has a
// blunt answer: no Firestore rule anywhere reads `status`, so a suspension is
// enforced by the client's gate routing and nothing else. That is BUG-007,
// established against the real rules in test_rules/misc.test.mjs. Here the
// concern is the moderation state machine itself.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/data/firestore_paths.dart';
import 'package:flow/data/models/app_user.dart';
import 'package:flow/data/models/report.dart';
import 'package:flow/data/models/support.dart';
import 'package:flow/data/repositories/admin_repository.dart';
import 'package:flow/data/repositories/notification_repository.dart';
import 'package:flow/data/repositories/support_repository.dart';
import 'package:flow/data/repositories/user_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late AdminRepository admin;
  late SupportRepository support;
  late UserRepository users;
  late NotificationRepository notifications;

  setUp(() async {
    db = FakeFirebaseFirestore();
    notifications = NotificationRepository(db);
    admin = AdminRepository(db, notifications);
    support = SupportRepository(db);
    users = UserRepository(db);

    for (final (uid, role) in [
      ('rider1', 'kiter'), ('rider2', 'kiter'), ('trainer1', 'business'),
    ]) {
      await db.collection(Col.users).doc(uid).set({
        'name': uid, 'email': '$uid@test.dev', 'role': role, 'status': 'active',
      });
    }
  });

  Future<void> fileReport({
    String reporter = 'rider1',
    String reported = 'trainer1',
    String reason = 'Safety concerns',
    String? details,
  }) =>
      support.reportUser(
        reporterId: reporter, reporterName: reporter,
        reportedUserId: reported, reportedUserName: reported,
        reason: reason, details: details,
      );

  /// Reads the profile with a direct `get`, not `watchUser(...).first`.
  ///
  /// blockUser and unblockUser write inside a transaction, and
  /// fake_cloud_firestore's snapshot streams do not reliably re-emit after
  /// one — `.first` hands back the pre-transaction document, so an assertion
  /// on it reports `active` for an account the database says is `blocked`.
  /// Real Firestore notifies listeners on a transactional commit; this is the
  /// double, not the app. Same parsing either way.
  Future<AppUser> profile(String uid) async {
    final snap = await db.collection(Col.users).doc(uid).get();
    return AppUser.fromDoc(snap.id, snap.data()!);
  }

  group('filing a report', () {
    test('lands on the admin queue as pending (§6.3)', () async {
      await fileReport();

      final queue = await admin.watchReports().first;
      expect(queue, hasLength(1));
      expect(queue.single.isOpen, isTrue);
      expect(queue.single.reporterId, 'rider1');
      expect(queue.single.reportedUserId, 'trainer1');
      expect(queue.single.reason, 'Safety concerns');
    });

    test('trims the details, and an absent one is empty not null', () async {
      await fileReport(details: '  he was on the water drunk  ');
      final raw = (await db.collection(Col.reports).get()).docs.single.data();
      expect(raw['details'], 'he was on the water drunk');

      await fileReport(reporter: 'rider2');
      final all = (await db.collection(Col.reports).get()).docs;
      expect(all.map((d) => d.data()['details']), contains(''));
    });

    test('the reported user is not notified — they must not learn of it',
        () async {
      await fileReport();

      expect(await notifications.watchFor('trainer1').first, isEmpty,
          reason: '§3.12: you cannot discover that you have been reported');
      expect(await notifications.watchFor('rider1').first, isEmpty);
    });

    test('two riders can report the same person independently', () async {
      await fileReport(reporter: 'rider1');
      await fileReport(reporter: 'rider2');

      final queue = await admin.watchReports().first;
      expect(queue, hasLength(2));
      expect(queue.map((r) => r.reporterId).toSet(), {'rider1', 'rider2'});
    });

    test('the queue is newest first', () async {
      for (var i = 0; i < 3; i++) {
        await db.collection(Col.reports).add({
          'reporterId': 'rider1', 'reportedUserId': 'trainer1',
          'reason': 'Other', 'status': 'pending',
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, i + 1)),
        });
      }

      final queue = await admin.watchReports().first;
      expect(queue.first.createdAt!.day, 3);
      expect(queue.last.createdAt!.day, 1);
    });
  });

  group('resolving a report', () {
    test('upholding it closes the report as resolved', () async {
      await fileReport();
      final r = (await admin.watchReports().first).single;
      await admin.closeReport(r.id, upheld: true, note: 'Suspended 7 days');

      final closed = (await admin.watchReports().first).single;
      expect(closed.status, 'resolved');
      expect(closed.isOpen, isFalse);
      final raw = (await db.collection(Col.reports).doc(r.id).get()).data()!;
      expect(raw['resolutionNote'], 'Suspended 7 days');
      expect(raw['resolvedAt'], isNotNull);
    });

    test('dismissing it closes the report as dismissed', () async {
      await fileReport();
      final r = (await admin.watchReports().first).single;
      await admin.closeReport(r.id, upheld: false);

      expect((await admin.watchReports().first).single.status,
          'dismissed');
    });

    test('a blank note leaves no empty resolutionNote behind', () async {
      await fileReport();
      final r = (await admin.watchReports().first).single;
      await admin.closeReport(r.id, upheld: true, note: '   ');

      final raw = (await db.collection(Col.reports).doc(r.id).get()).data()!;
      expect(raw.containsKey('resolutionNote'), isFalse);
    });

    test('closing a report does not by itself suspend anyone', () async {
      await fileReport();
      final r = (await admin.watchReports().first).single;
      await admin.closeReport(r.id, upheld: true);

      expect((await profile('trainer1')).status, AccountStatus.active,
          reason: 'upholding a report and blocking are separate acts');
    });
  });

  group('suspension', () {
    test('a timed block records when it lifts and what came before', () async {
      await admin.blockUser('rider1', until: '2030-01-01');

      final raw = (await db.collection(Col.users).doc('rider1').get()).data()!;
      expect(raw['status'], 'blocked');
      expect(raw['blockedUntil'], '2030-01-01');
      expect(raw['statusBeforeBlock'], 'active');
      expect(raw['blockedAt'], isNotNull);
    });

    test('the gate holds while the date is in the future', () async {
      await admin.blockUser('rider1', until: '2030-01-01');
      expect((await profile('rider1')).isBlockInForce, isTrue);
    });

    test('the gate releases on its own once the date passes (§2.4)', () async {
      await admin.blockUser('rider1', until: '2020-01-01');

      final u = await profile('rider1');
      expect(u.status, AccountStatus.blocked,
          reason: 'the stored status does not change by itself');
      expect(u.isBlockInForce, isFalse,
          reason: 'but the gate stops holding them, with no admin action');
    });

    test('forever never lapses', () async {
      await admin.blockUser('rider1', until: 'forever');
      expect((await profile('rider1')).isBlockInForce, isTrue);
    });

    test('an unparseable date fails closed — a malformed value is not a way '
        'out', () async {
      await db.collection(Col.users).doc('rider1').update({
        'status': 'blocked', 'blockedUntil': 'next tuesday',
      });
      expect((await profile('rider1')).isBlockInForce, isTrue);
    });

    test('a blocked status with no date at all fails closed', () async {
      await db.collection(Col.users).doc('rider1')
          .update({'status': 'blocked'});
      expect((await profile('rider1')).isBlockInForce, isTrue);
    });

    test('lifting restores the prior status and clears the markers', () async {
      await admin.blockUser('rider1', until: 'forever');
      await admin.unblockUser('rider1');

      final raw = (await db.collection(Col.users).doc('rider1').get()).data()!;
      expect(raw['status'], 'active');
      expect(raw.containsKey('blockedUntil'), isFalse);
      expect(raw.containsKey('statusBeforeBlock'), isFalse);
    });

    test('lifting notifies the account that it is back', () async {
      await admin.blockUser('rider1', until: 'forever');
      await admin.unblockUser('rider1');

      final n = await notifications.watchFor('rider1').first;
      expect(n.single.title, 'Your account is active again');
    });

    test('the blocked list shows exactly who is suspended', () async {
      await admin.blockUser('rider1', until: 'forever');

      final blocked = await admin.watchBlockedUsers().first;
      expect([for (final u in blocked) u.uid], ['rider1']);
    });
  });

  group('the appeal round trip', () {
    Future<String> appealFrom(String uid) async {
      await support.submitAppeal(
          userId: uid, userName: uid, reason: 'It was not me');
      return (await admin.watchAppeals().first).single.id;
    }

    test('a suspended user can file one — the account is suspended, not gone',
        () async {
      await admin.blockUser('rider1', until: 'forever');
      await appealFrom('rider1');

      final mine = await support.watchMyAppeal('rider1').first;
      expect(mine, isNotNull);
      expect(mine!.status, 'pending');
      expect(mine.messages, isEmpty);
    });

    test('it reaches the admin queue', () async {
      await appealFrom('rider1');
      expect(await admin.watchAppeals().first, hasLength(1));
    });

    test('another user cannot see it through watchMyAppeal', () async {
      await appealFrom('rider1');
      expect(await support.watchMyAppeal('rider2').first, isNull);
    });

    test('both sides append without overwriting each other (§6.3)', () async {
      final id = await appealFrom('rider1');

      await support.replyToAppeal(id,
          const AppealMessage(id: 'm', senderId: 'rider1', senderName: 'rider1', text: 'Any news?'));
      await admin.replyToAppeal(id,
          const AppealMessage(id: 'm', senderId: 'admin', senderName: 'Admin', text: 'Reviewing it now.'));
      await support.replyToAppeal(id,
          const AppealMessage(id: 'm', senderId: 'rider1', senderName: 'rider1', text: 'Thank you.'));

      final thread = (await support.watchMyAppeal('rider1').first)!.messages;
      expect(thread, hasLength(3),
          reason: 'arrayUnion, so a concurrent reply is not dropped');
      expect([for (final m in thread) m.senderId], ['rider1', 'admin', 'rider1']);
    });

    // arrayUnion de-duplicates by value on real Firestore, so a user sending
    // the identical reply twice sees one message — which looks exactly like a
    // lost message. fake_cloud_firestore appends both, so the claim cannot be
    // settled here; it is verified in test_rules/arrays.test.mjs instead.

    test('the admin decides, and the decision is visible to the user',
        () async {
      final id = await appealFrom('rider1');
      await admin.setAppealStatus(id, 'rejected');

      expect((await support.watchMyAppeal('rider1').first)!.status, 'rejected');
      final raw = (await db.collection(Col.appeals).doc(id).get()).data()!;
      expect(raw['reviewedAt'], isNotNull);
    });

    test('accepting an appeal does not lift the block by itself', () async {
      await admin.blockUser('rider1', until: 'forever');
      final id = await appealFrom('rider1');
      await admin.setAppealStatus(id, 'accepted');

      expect((await profile('rider1')).status, AccountStatus.blocked,
          reason: 'the appeal records the decision; unblockUser enacts it');
      expect((await profile('rider1')).isBlockInForce, isTrue);
    });

    test('the full round trip: report -> block -> appeal -> accept -> unblock',
        () async {
      await fileReport(reporter: 'rider2', reported: 'rider1');
      final report = (await admin.watchReports().first).single;

      await admin.blockUser('rider1', until: 'forever');
      await admin.closeReport(report.id, upheld: true, note: 'Blocked');
      expect((await profile('rider1')).isBlockInForce, isTrue);

      final appeal = await appealFrom('rider1');
      await admin.replyToAppeal(appeal,
          const AppealMessage(id: 'm', senderId: 'admin', senderName: 'Admin', text: 'Understood.'));
      await admin.setAppealStatus(appeal, 'accepted');
      await admin.unblockUser('rider1');

      final restored = await profile('rider1');
      expect(restored.status, AccountStatus.active);
      // The gate is the *conjunction* (providers.dart:177), and only the
      // conjunction is meaningful: with blockedUntil cleared, isBlockInForce
      // on its own reads true, because it fails closed on a missing date.
      expect(
          restored.status == AccountStatus.blocked && restored.isBlockInForce,
          isFalse);
      expect((await admin.watchReports().first).single.status,
          'resolved');
      expect((await support.watchMyAppeal('rider1').first)!.status, 'accepted');
    });
  });

  group('adversarial — moderation state under pressure', () {
    test('a report about an account that has since been deleted still reads',
        () async {
      await fileReport(reported: 'trainer1');
      await users.deleteProfile('trainer1');

      final r = (await admin.watchReports().first).single;
      expect(r.reportedUserName, 'trainer1',
          reason: 'the name is denormalised so the queue survives deletion');
    });

    // "blocking an account that no longer exists throws" cannot be settled
    // here either: real Firestore rejects a transactional update of a missing
    // document with NOT_FOUND, fake_cloud_firestore accepts it and creates
    // one. Verified in test_rules/arrays.test.mjs.

    test('a second appeal from the same user does not replace the first',
        () async {
      await support.submitAppeal(
          userId: 'rider1', userName: 'rider1', reason: 'First');
      await support.submitAppeal(
          userId: 'rider1', userName: 'rider1', reason: 'Second');

      expect(await admin.watchAppeals().first, hasLength(2));
      // watchMyAppeal is limit 1 (§6.2), so the user sees one of them and
      // the admin sees both. Pinned as current behaviour — BUG-016.
      expect(await support.watchMyAppeal('rider1').first, isNotNull);
    });

    test('closing the same report twice is not an error', () async {
      await fileReport();
      final r = (await admin.watchReports().first).single;
      await admin.closeReport(r.id, upheld: true);
      await admin.closeReport(r.id, upheld: false);

      expect((await admin.watchReports().first).single.status,
          'dismissed',
          reason: 'last write wins; there is no guard on re-deciding');
    });
  });
}
