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
import 'package:flow/data/repositories/support_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late SupportRepository support;

  setUp(() {
    db = FakeFirebaseFirestore();
    support = SupportRepository(db);
  });

  Future<List<String>> thread(String ticketId) async =>
      [for (final m in await support.watchTicketMessages(ticketId).first) m.text];

  group('a ticket thread reads in the order it was written', () {
    test('opening a ticket puts the body in as the first message', () async {
      final id = await support.openTicket(
        userId: 'rider1',
        userName: 'Rider One',
        subject: 'Refund for a cancelled session',
        body: 'My trainer cancelled and I have not been refunded.',
      );

      expect(await thread(id),
          ['My trainer cancelled and I have not been refunded.']);

      final ticket = await support.watchTicket(id).first;
      expect(ticket!.isOpen, isTrue);
      expect(ticket.userId, 'rider1');
    });

    test('user and staff replies append, oldest first', () async {
      final id = await support.openTicket(
        userId: 'rider1', userName: 'Rider One',
        subject: 'Refund', body: 'First',
      );
      await support.replyAsStaff(
          ticketId: id, staffId: 'support1', text: 'Second');
      await support.replyToTicket(
          ticketId: id, userId: 'rider1', text: 'Third');

      expect(await thread(id), ['First', 'Second', 'Third']);
    });

    test('a staff reply is marked as coming from support', () async {
      final id = await support.openTicket(
        userId: 'rider1', userName: 'Rider One',
        subject: 'Refund', body: 'Mine',
      );
      await support.replyAsStaff(
          ticketId: id, staffId: 'support1', text: 'Ours');

      final messages = await support.watchTicketMessages(id).first;
      expect(messages.map((m) => m.fromStaff), [false, true],
          reason: 'isAdmin is what renders the bubble on the support side');
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
        userId: 'rider1', userName: 'Rider One',
        subject: 'Refund', body: 'The complaint',
      );
      await support.replyAsStaff(
          ticketId: id, staffId: 'support1', text: 'The answer');
      await pendingMessage(id, 'Just typed');

      expect(await thread(id), ['The complaint', 'The answer', 'Just typed'],
          reason: 'an unacknowledged write is the newest message in the '
              'thread — ordering on the server put it above everything');
    });

    test('two of them stay adjacent rather than reordering', () async {
      final id = await support.openTicket(
        userId: 'rider1', userName: 'Rider One',
        subject: 'Refund', body: 'Settled',
      );
      await pendingMessage(id, 'Pending A');
      await pendingMessage(id, 'Pending B');

      final texts = await thread(id);
      expect(texts.first, 'Settled');
      expect(texts.sublist(1), containsAll(['Pending A', 'Pending B']));
    });
  });

  group('the queues the console reads', () {
    test('a ticket appears in its owner list and the staff list', () async {
      await support.openTicket(
        userId: 'rider1', userName: 'Rider One',
        subject: 'Mine', body: 'x',
      );
      await support.openTicket(
        userId: 'rider2', userName: 'Rider Two',
        subject: 'Theirs', body: 'y',
      );

      expect((await support.watchMyTickets('rider1').first).map((t) => t.subject),
          ['Mine']);
      expect(
          (await support.watchAllTickets().first).map((t) => t.subject).toSet(),
          {'Mine', 'Theirs'},
          reason: 'the console reads every ticket, not just its own');
    });

    test('closing takes it out of the open count, reopening puts it back',
        () async {
      final id = await support.openTicket(
        userId: 'rider1', userName: 'Rider One',
        subject: 'Refund', body: 'x',
      );

      Future<bool> isOpen() async =>
          (await support.watchTicket(id).first)!.isOpen;

      expect(await isOpen(), isTrue);
      await support.closeTicket(id);
      expect(await isOpen(), isFalse);
      await support.reopenTicket(id);
      expect(await isOpen(), isTrue,
          reason: 'a closed ticket is not a dead end — §3.13');
    });
  });
}
