// A support ticket, from "something broke" to "closed" — and the ordering
// rule that decides where each message lands.
//
// The whole ticket surface had no test of any kind. It was also the only
// place left in the app still ordering a message thread server-side:
//
//     .collection(Col.messages).orderBy('createdAt')
//
// `createdAt` is a `serverTimestamp()`. Until the server acknowledges the
// write it reads as `null` in the local snapshot, Firestore sorts null
// first, and latency compensation paints the bubble immediately — so the
// message a user had just typed appeared at the *top* of their ticket,
// above the complaint it was answering, and jumped to the bottom a moment
// later. `ChatRepository.watchMessages` was fixed for exactly this and
// carries the long version of the explanation; this stream had been left
// behind, and it is the one staff read in the console.
//
// `fake_cloud_firestore` resolves `serverTimestamp()` on write, so it cannot
// reproduce the latency window. What it can do is hold the invariant that
// makes the window survivable: a message whose timestamp has not resolved is
// the newest one, never the oldest.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/data/firestore_paths.dart';
import 'package:flow/data/repositories/notification_repository.dart';
import 'package:flow/data/repositories/support_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late SupportRepository support;

  setUp(() {
    db = FakeFirebaseFirestore();
    // P2 (ordered): support replies notify the ticket owner, so the
    // repository carries the notification writer. Construction only — every
    // assertion in this file is unchanged.
    support = SupportRepository(db, NotificationRepository(db));
  });

  Future<List<String>> thread(String ticketId) async => [
    for (final m in await support.watchTicketMessages(ticketId).first) m.text,
  ];

  group('a ticket thread reads in the order it was written', () {
    test('opening a ticket puts the body in as the first message', () async {
      final id = await support.openTicket(
        userId: 'rider1',
        userName: 'Rider One',
        subject: 'Refund for a cancelled session',
        body: 'My trainer cancelled and I have not been refunded.',
      );

      expect(await thread(id), [
        'My trainer cancelled and I have not been refunded.',
      ]);

      final ticket = await support.watchTicket(id).first;
      expect(ticket!.isOpen, isTrue);
      expect(ticket.userId, 'rider1');
    });

    test('user and staff replies append, oldest first', () async {
      final id = await support.openTicket(
        userId: 'rider1',
        userName: 'Rider One',
        subject: 'Refund',
        body: 'First',
      );
      // userId/subject: P2 needs the owner to notify — new required params.
      await support.replyAsStaff(
        ticketId: id,
        staffId: 'support1',
        text: 'Second',
        userId: 'rider1',
        subject: 'Refund',
      );
      await support.replyToTicket(
        ticketId: id,
        userId: 'rider1',
        text: 'Third',
      );

      expect(await thread(id), ['First', 'Second', 'Third']);
    });

    test('a staff reply is marked as coming from support', () async {
      final id = await support.openTicket(
        userId: 'rider1',
        userName: 'Rider One',
        subject: 'Refund',
        body: 'Mine',
      );
      await support.replyAsStaff(
        ticketId: id,
        staffId: 'support1',
        text: 'Ours',
        userId: 'rider1',
        subject: 'Refund',
      );

      final messages = await support.watchTicketMessages(id).first;
      expect(
        messages.map((m) => m.fromStaff),
        [false, true],
        reason: 'isAdmin is what renders the bubble on the support side',
      );
    });
  });

  group('a message whose timestamp has not resolved yet', () {
    // Written straight to the collection with a null `createdAt`, which is
    // what the local snapshot holds for the fraction of a second between
    // sending and the server's acknowledgement.
    Future<void> pendingMessage(String ticketId, String text) =>
        db.collection(Col.tickets).doc(ticketId).collection(Col.messages).add({
          'text': text,
          'senderId': 'rider1',
          'isAdmin': false,
          'createdAt': null,
        });

    test('sorts last, not first', () async {
      final id = await support.openTicket(
        userId: 'rider1',
        userName: 'Rider One',
        subject: 'Refund',
        body: 'The complaint',
      );
      await support.replyAsStaff(
        ticketId: id,
        staffId: 'support1',
        text: 'The answer',
        userId: 'rider1',
        subject: 'Refund',
      );
      await pendingMessage(id, 'Just typed');

      expect(
        await thread(id),
        ['The complaint', 'The answer', 'Just typed'],
        reason:
            'an unacknowledged write is the newest message in the '
            'thread — ordering on the server put it above everything',
      );
    });

    test('two of them stay adjacent rather than reordering', () async {
      final id = await support.openTicket(
        userId: 'rider1',
        userName: 'Rider One',
        subject: 'Refund',
        body: 'Settled',
      );
      await pendingMessage(id, 'Pending A');
      await pendingMessage(id, 'Pending B');

      final texts = await thread(id);
      expect(texts.first, 'Settled');
      expect(texts.sublist(1), containsAll(['Pending A', 'Pending B']));
    });
  });

  group('a ticket about one session carries its reference', () {
    test('the attached session is stored and read back', () async {
      final id = await support.openTicket(
        userId: 'rider1',
        userName: 'Rider One',
        subject: 'Trainer never showed up',
        body: 'Waited forty minutes on the beach.',
        sessionId: 'xK9fQ2abcd7x8k',
        sessionRef: 'FLW-0513-7X8K',
      );

      final ticket = await support.watchTicket(id).first;
      expect(
        ticket!.sessionId,
        'xK9fQ2abcd7x8k',
        reason: 'the raw id is the canonical key for looking the booking up',
      );
      expect(
        ticket.sessionRef,
        'FLW-0513-7X8K',
        reason: 'the rendered ref is what screens print without a read',
      );
    });

    test(
      'a ticket about nothing in particular stores no session fields',
      () async {
        final id = await support.openTicket(
          userId: 'rider1',
          userName: 'Rider One',
          subject: 'How do refunds work?',
          body: 'Just asking.',
        );

        final raw = await db.collection(Col.tickets).doc(id).get();
        expect(
          raw.data()!.containsKey('sessionId'),
          isFalse,
          reason: 'absent means absent — not null, not an empty string',
        );
        expect(raw.data()!.containsKey('sessionRef'), isFalse);

        final ticket = await support.watchTicket(id).first;
        expect(ticket!.sessionId, isNull);
        expect(ticket.sessionRef, isNull);
      },
    );

    test('a report carries the same pair when one was attached', () async {
      await support.reportUser(
        reporterId: 'rider1',
        reporterName: 'Rider One',
        reportedUserId: 'trainer1',
        reportedUserName: 'Anna Bergström',
        reason: 'No-show',
        sessionId: 'b3',
        sessionRef: 'FLW-0829-B3',
      );

      final raw = await db.collection(Col.reports).get();
      expect(raw.docs.single.data()['sessionId'], 'b3');
      expect(raw.docs.single.data()['sessionRef'], 'FLW-0829-B3');
    });
  });

  group('the queues the console reads', () {
    test('a ticket appears in its owner list and the staff list', () async {
      await support.openTicket(
        userId: 'rider1',
        userName: 'Rider One',
        subject: 'Mine',
        body: 'x',
      );
      await support.openTicket(
        userId: 'rider2',
        userName: 'Rider Two',
        subject: 'Theirs',
        body: 'y',
      );

      expect(
        (await support.watchMyTickets('rider1').first).map((t) => t.subject),
        ['Mine'],
      );
      expect(
        (await support.watchAllTickets().first).map((t) => t.subject).toSet(),
        {'Mine', 'Theirs'},
        reason: 'the console reads every ticket, not just its own',
      );
    });

    test(
      'closing takes it out of the open count, reopening puts it back',
      () async {
        final id = await support.openTicket(
          userId: 'rider1',
          userName: 'Rider One',
          subject: 'Refund',
          body: 'x',
        );

        Future<bool> isOpen() async =>
            (await support.watchTicket(id).first)!.isOpen;

        expect(await isOpen(), isTrue);
        await support.closeTicket(id, userId: 'rider1', subject: 'Refund');
        expect(await isOpen(), isFalse);
        await support.reopenTicket(id);
        expect(
          await isOpen(),
          isTrue,
          reason: 'a closed ticket is not a dead end — §3.13',
        );
      },
    );
  });

  // ── P2: support movement reaches the owner's notifications ─────────────
  group('P2 — a support reply is news, not something to discover', () {
    Future<List<Map<String, dynamic>>> notifications() async => [
      for (final d in (await db.collection(Col.notifications).get()).docs)
        d.data(),
    ];

    test('a staff reply writes support_reply carrying its thread', () async {
      final id = await support.openTicket(
        userId: 'rider1',
        userName: 'Rider One',
        subject: 'Refund',
        body: 'Where is my money?',
      );
      await support.replyAsStaff(
        ticketId: id,
        staffId: 'support1',
        text: 'On its way today.',
        userId: 'rider1',
        subject: 'Refund',
      );

      final n = (await notifications()).single;
      expect(n['targetUserId'], 'rider1');
      expect(n['type'], 'support_reply');
      expect(
        n['ticketId'],
        id,
        reason: 'the tap must land in this thread, not on the list',
      );
      expect(n['message'], 'On its way today.');
      expect(n['title'], contains('Refund'));
    });

    test('resolving writes support_closed that names the way back', () async {
      final id = await support.openTicket(
        userId: 'rider1',
        userName: 'Rider One',
        subject: 'Refund',
        body: 'x',
      );
      await support.closeTicket(id, userId: 'rider1', subject: 'Refund');

      final n = (await notifications()).single;
      expect(n['type'], 'support_closed');
      expect(n['ticketId'], id);
      expect(
        n['message'],
        contains('reopen'),
        reason:
            'a silent resolution reads as being ignored — the copy '
            'must offer the disagree path',
      );
    });
  });

  // P9 (ordered): tickets carry a topic the queue triages by.
  group('the ticket topic', () {
    test('is written when given and read back off the doc', () async {
      final id = await support.openTicket(
        userId: 'rider1',
        userName: 'Rider One',
        subject: 'Charged twice',
        body: 'The app took the payment two times.',
        topic: 'Payment or refund',
      );

      final raw = await db.collection(Col.tickets).doc(id).get();
      expect(raw.data()!['topic'], 'Payment or refund');

      final ticket = await support.watchTicket(id).first;
      expect(ticket!.topic, 'Payment or refund');
    });

    test(
      'is absent, not defaulted, on tickets from before it existed',
      () async {
        // Written the pre-P9 way: no topic key at all.
        await db.collection(Col.tickets).doc('old1').set({
          'userId': 'rider1',
          'userName': 'Rider One',
          'subject': 'Old ticket',
          'status': 'open',
        });

        final ticket = await support.watchTicket('old1').first;
        expect(
          ticket!.topic,
          isNull,
          reason:
              'inventing a topic for an old ticket would file it '
              'under a category nobody chose',
        );
      },
    );
  });
}
