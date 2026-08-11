// FLOW 1 — trainer applies, admin reviews, Explore reflects the decision.
//
// Multi-actor: every assertion checks that the *other* party's view agrees
// after a write, because that is where this flow can fail without any single
// repository being wrong. Three views resolve from one database:
//
//   admin   → AdminRepository.watchPendingTrainers()   (the queue)
//   trainer → UserRepository.watchUser(uid)            (their own gate)
//   rider   → UserRepository.watchActiveTrainers()     (Explore)
//
// The approval is the only thing standing between "signed up" and "bookable",
// so a trainer who is approved but invisible, or visible but unapproved, is
// the marketplace failing silently.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/data/firestore_paths.dart';
import 'package:flow/data/models/app_user.dart';
import 'package:flow/data/models/social.dart';
import 'package:flow/data/repositories/admin_repository.dart';
import 'package:flow/data/repositories/notification_repository.dart';
import 'package:flow/data/repositories/user_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late AdminRepository admin;
  late UserRepository users;
  late NotificationRepository notifications;

  setUp(() {
    db = FakeFirebaseFirestore();
    notifications = NotificationRepository(db);
    admin = AdminRepository(db, notifications);
    users = UserRepository(db);
  });

  /// Runs the real trainer onboarding write rather than a hand-made document,
  /// so the queue is tested against what the app actually produces.
  Future<void> applyAsTrainer({
    String uid = 'coach',
    String name = 'Anna',
    int rate = 85,
  }) =>
      users.createTrainerProfile(
        uid: uid,
        name: name,
        email: '$uid@test.dev',
        bio: 'IKO-certified, ten years on the Red Sea.',
        languages: const ['English', 'Arabic'],
        trainingSpot: 'El Gouna',
        hourlyRate: rate,
        ikoId: 'IKO-0001',
        photoUrl: 'https://example.test/a.jpg',
      );

  /// Reads with a direct `get`, not `watchUser(...).first`.
  ///
  /// blockUser and unblockUser write inside a transaction, and
  /// fake_cloud_firestore's snapshot streams do not reliably re-emit after
  /// one — `.first` can hand back the pre-transaction document. Real
  /// Firestore notifies listeners on commit; this is the double, not the app.
  /// The suspension tests below would otherwise be quietly flaky.
  Future<AppUser> pending(String uid) async {
    final snap = await db.collection(Col.users).doc(uid).get();
    return AppUser.fromDoc(snap.id, snap.data()!);
  }

  Future<List<String>> queueUids() async =>
      [for (final t in await admin.watchPendingTrainers().first) t.uid];

  Future<List<String>> exploreUids() async =>
      [for (final t in await users.watchActiveTrainers().first) t.uid];

  group('the queue', () {
    test('is empty when nobody has applied', () async {
      expect(await queueUids(), isEmpty);
      expect(await exploreUids(), isEmpty);
    });

    test('a new trainer lands in it, and not in Explore', () async {
      await applyAsTrainer();

      expect(await queueUids(), ['coach']);
      expect(await exploreUids(), isEmpty,
          reason: 'an unreviewed trainer must never be bookable');
      expect((await pending('coach')).status, AccountStatus.pending);
    });

    test('a rider never enters it, whatever their status', () async {
      await users.createRiderProfile(
        uid: 'rider', name: 'Seif', email: 'r@test.dev',
        nationality: 'Egyptian', age: 22, level: 'Independent',
        languages: const ['English'],
      );
      // Force the status a rider could never legitimately hold.
      await db.collection(Col.users).doc('rider').update({'status': 'pending'});

      expect(await queueUids(), isEmpty,
          reason: 'the queue filters on role == business as well as status');
    });

    test('is ordered by name so the list is stable between rebuilds',
        () async {
      await applyAsTrainer(uid: 'c3', name: 'Zoe');
      await applyAsTrainer(uid: 'c1', name: 'Anna');
      await applyAsTrainer(uid: 'c2', name: 'Mo');

      expect(await queueUids(), ['c1', 'c2', 'c3']);
    });

    test('a nameless application still sorts rather than throwing', () async {
      await applyAsTrainer(uid: 'c1', name: '');
      await applyAsTrainer(uid: 'c2', name: 'Anna');

      expect(await queueUids(), ['c1', 'c2']);
    });

    test('a document with no status at all is not treated as pending',
        () async {
      await db.collection(Col.users).doc('ghost').set({
        'role': 'business', 'name': 'No Status',
      });

      expect(await queueUids(), isEmpty);
      expect(await exploreUids(), isEmpty,
          reason: 'a missing status must fail closed in both directions');
    });
  });

  group('approve', () {
    test('all three views agree the moment it lands', () async {
      await applyAsTrainer();
      await admin.approveTrainer(await pending('coach'));

      expect(await queueUids(), isEmpty, reason: 'admin: out of the queue');
      expect((await pending('coach')).status, AccountStatus.active,
          reason: 'trainer: their own gate opens');
      expect(await exploreUids(), ['coach'], reason: 'rider: now in Explore');
    });

    test('stamps reviewedAt', () async {
      await applyAsTrainer();
      await admin.approveTrainer(await pending('coach'));

      final doc = (await db.collection(Col.users).doc('coach').get()).data()!;
      expect(doc['reviewedAt'], isNotNull);
    });

    test('notifies the trainer, and nobody else (§11.1)', () async {
      await applyAsTrainer();
      await admin.approveTrainer(await pending('coach'));

      final theirs = await notifications.watchFor('coach').first;
      expect(theirs, hasLength(1));
      expect(theirs.single.title, contains("You're live"));
      expect(theirs.single.read, isFalse);
      expect(await notifications.watchFor('someone-else').first, isEmpty);

      // The stored type is `account_approved`, which NotificationKind.parse
      // has no case for, so it degrades to `system` — routed to a plain text
      // sheet (§11.2). Pinned because it is a real gap between the admin
      // repository and the notification model, logged as BUG-011.
      expect(theirs.single.kind, NotificationKind.system);
      final raw = await db.collection(Col.notifications).get();
      expect(raw.docs.single.data()['type'], 'account_approved');
    });

    test('approving twice is harmless but does notify twice', () async {
      // IDEMPOTENCY. The status write is idempotent; the notification is not.
      // Pinned rather than asserted as a defect — the console's UNDO makes a
      // double-approve reachable, and a duplicate "you're live" message is
      // noise, not damage.
      await applyAsTrainer();
      final t = await pending('coach');
      await admin.approveTrainer(t);
      await admin.approveTrainer(t);

      expect((await pending('coach')).status, AccountStatus.active);
      expect(await exploreUids(), ['coach']);
      expect(await notifications.watchFor('coach').first, hasLength(2));
    });
  });

  group('reject', () {
    test('leaves them out of both the queue and Explore', () async {
      await applyAsTrainer();
      await admin.rejectTrainer(await pending('coach'));

      expect(await queueUids(), isEmpty);
      expect(await exploreUids(), isEmpty);
      expect((await pending('coach')).status, AccountStatus.rejected);
    });

    test('carries the reason to the trainer when one is given', () async {
      await applyAsTrainer();
      await admin.rejectTrainer(await pending('coach'),
          reason: 'Certificate unreadable');

      final doc = (await db.collection(Col.users).doc('coach').get()).data()!;
      expect(doc['reviewNote'], 'Certificate unreadable');
      expect((await notifications.watchFor('coach').first).single.message,
          contains('Certificate unreadable'));
    });

    test('writes no reviewNote when the reason is blank or whitespace',
        () async {
      await applyAsTrainer();
      await admin.rejectTrainer(await pending('coach'), reason: '   ');

      final doc = (await db.collection(Col.users).doc('coach').get()).data()!;
      expect(doc.containsKey('reviewNote'), isFalse,
          reason: 'an empty reason must not leave a blank note on the record');
      expect((await notifications.watchFor('coach').first).single.message,
          isNot(contains('Reason:')));
    });
  });

  group('restore to pending', () {
    test('puts a rejected application back in the queue', () async {
      await applyAsTrainer();
      await admin.rejectTrainer(await pending('coach'));
      await admin.restoreToPending('coach');

      expect(await queueUids(), ['coach']);
      expect(await exploreUids(), isEmpty);
    });

    test('pulls an approved trainer back out of Explore — the UNDO path',
        () async {
      await applyAsTrainer();
      await admin.approveTrainer(await pending('coach'));
      expect(await exploreUids(), ['coach']);

      await admin.restoreToPending('coach');

      expect(await exploreUids(), isEmpty,
          reason: 'UNDO must actually remove them from the marketplace');
      expect(await queueUids(), ['coach']);
    });

    test('a full reject -> restore -> approve round trip ends live', () async {
      await applyAsTrainer();
      await admin.rejectTrainer(await pending('coach'), reason: 'Blurry photo');
      await admin.restoreToPending('coach');
      await admin.approveTrainer(await pending('coach'));

      expect((await pending('coach')).status, AccountStatus.active);
      expect(await exploreUids(), ['coach']);
    });
  });

  group('suspension must not become a back door into Explore', () {
    // The repository documents this as a bug that happened: unblockUser
    // hardcoded 'active', so suspending and unsuspending promoted a
    // never-reviewed trainer straight into the marketplace.
    test('blocking a pending trainer and lifting it returns them to pending',
        () async {
      await applyAsTrainer();
      await admin.blockUser('coach', until: 'forever');
      await admin.unblockUser('coach');

      expect((await pending('coach')).status, AccountStatus.pending);
      expect(await exploreUids(), isEmpty,
          reason: 'an unreviewed trainer must not go live via unblock');
      expect(await queueUids(), ['coach']);
    });

    test('blocking a rejected trainer and lifting it returns them to rejected',
        () async {
      await applyAsTrainer();
      await admin.rejectTrainer(await pending('coach'));
      await admin.blockUser('coach', until: 'forever');
      await admin.unblockUser('coach');

      expect((await pending('coach')).status, AccountStatus.rejected);
      expect(await exploreUids(), isEmpty);
    });

    test('an approved trainer comes back active and bookable', () async {
      await applyAsTrainer();
      await admin.approveTrainer(await pending('coach'));
      await admin.blockUser('coach', until: '2026-01-01');
      expect(await exploreUids(), isEmpty, reason: 'suspended is not bookable');

      await admin.unblockUser('coach');

      expect((await pending('coach')).status, AccountStatus.active);
      expect(await exploreUids(), ['coach']);
    });

    test('a double block does not strand the account at blocked', () async {
      await applyAsTrainer();
      await admin.approveTrainer(await pending('coach'));
      await admin.blockUser('coach', until: 'forever');
      await admin.blockUser('coach', until: 'forever');
      await admin.unblockUser('coach');

      expect((await pending('coach')).status, AccountStatus.active,
          reason: 'the second block must not record "blocked" as the prior '
              'status and lose the real one');
    });

    test('a block with no recorded prior status fails safe to pending',
        () async {
      // A block written before statusBeforeBlock existed.
      await applyAsTrainer();
      await db.collection(Col.users).doc('coach').update({
        'status': 'blocked', 'blockedUntil': 'forever',
      });
      await admin.unblockUser('coach');

      expect((await pending('coach')).status, AccountStatus.pending,
          reason: 'a business account with no history goes back through '
              'approvals rather than going live unreviewed');
      expect(await exploreUids(), isEmpty);
    });

    test('unblocking clears blockedUntil so the gate does not hold them',
        () async {
      await applyAsTrainer();
      await admin.approveTrainer(await pending('coach'));
      await admin.blockUser('coach', until: '2030-01-01');
      await admin.unblockUser('coach');

      final doc = (await db.collection(Col.users).doc('coach').get()).data()!;
      expect(doc.containsKey('blockedUntil'), isFalse);
      expect(doc.containsKey('statusBeforeBlock'), isFalse);
    });
  });

  group('adversarial — the account vanishes or changes under the admin', () {
    test('approving an account that has since been deleted throws rather '
        'than resurrecting a ghost profile', () async {
      await applyAsTrainer();
      final captured = await pending('coach');
      await users.deleteProfile('coach');

      // `update` on a missing document must fail. A `set` here would create a
      // users/{uid} holding nothing but status and reviewedAt — a profile
      // with no name, role or email that Explore would then try to render.
      await expectLater(
          () => admin.approveTrainer(captured), throwsA(anything));
      expect(await exploreUids(), isEmpty);
    });

    test('restoring a non-existent account throws', () async {
      await expectLater(
          () => admin.restoreToPending('ghost'), throwsA(anything));
    });

    test('two admins approving at once converge on one live trainer',
        () async {
      await applyAsTrainer();
      final t = await pending('coach');
      await Future.wait([admin.approveTrainer(t), admin.approveTrainer(t)]);

      expect((await pending('coach')).status, AccountStatus.active);
      expect(await exploreUids(), ['coach']);
    });

    test('approving a blocked trainer lifts the suspension as a side effect',
        () async {
      // Not reachable from the console today — the queue only shows
      // status == 'pending', so a blocked account never appears in it. Pinned
      // because it becomes reachable the moment the blocked-users list gets a
      // UI (BUG-012).
      await applyAsTrainer();
      await admin.blockUser('coach', until: 'forever');
      await admin.approveTrainer(await pending('coach'));

      expect((await pending('coach')).status, AccountStatus.active);
      expect(await exploreUids(), ['coach'],
          reason: 'they are bookable again with no explicit unblock');

      final doc = (await db.collection(Col.users).doc('coach').get()).data()!;
      expect(doc['blockedUntil'], 'forever',
          reason: 'the block marker survives the approval, stale');
    });

    test('a stale statusBeforeBlock demotes a live trainer on a later unblock',
        () async {
      // The consequence of the previous test. blockedUntil and
      // statusBeforeBlock outlive the approval, so an unblock issued
      // afterwards restores the status the account had *before* it was ever
      // reviewed — pulling an approved, bookable trainer out of Explore.
      await applyAsTrainer();
      await admin.blockUser('coach', until: 'forever');
      await admin.approveTrainer(await pending('coach'));
      expect(await exploreUids(), ['coach']);

      await admin.unblockUser('coach');

      expect((await pending('coach')).status, AccountStatus.pending,
          reason: 'BUG-012: restored to the pre-block status, undoing the '
              'approval that happened in between');
      expect(await exploreUids(), isEmpty);
    });
  });

  group('Explore membership is exactly role=business AND status=active', () {
    test('a blocked trainer disappears from Explore', () async {
      await applyAsTrainer();
      await admin.approveTrainer(await pending('coach'));
      await admin.blockUser('coach', until: 'forever');

      expect(await exploreUids(), isEmpty);
    });

    test('an active rider is not in Explore', () async {
      await users.createRiderProfile(
        uid: 'rider', name: 'Seif', email: 'r@test.dev',
        nationality: 'Egyptian', age: 22, level: 'Independent',
        languages: const ['English'],
      );

      expect(await exploreUids(), isEmpty);
    });

    test('an admin account is not in Explore', () async {
      await db.collection(Col.users).doc('staff')
          .set({'role': 'admin', 'status': 'active', 'name': 'Admin'});

      expect(await exploreUids(), isEmpty);
    });
  });
}
