import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants.dart';
import '../firestore_paths.dart';
import '../models/social.dart';
import 'notification_repository.dart';

class ChatRepository {
  ChatRepository(this._db, this._notifications);
  final FirebaseFirestore _db;
  final NotificationRepository _notifications;

  CollectionReference<Map<String, dynamic>> get _chats =>
      _db.collection(Col.chats);

  /// Inbox — client-side sort by lastMessageAt desc (§6.2).
  Stream<List<ChatThread>> watchInbox(String uid) =>
      _chats.where('participants', arrayContains: uid).snapshots().map((qs) {
        final list = [
          for (final d in qs.docs) ChatThread.fromDoc(d.id, d.data()),
        ];
        list.sort(
          (a, b) => (b.lastMessageAt ?? DateTime(0)).compareTo(
            a.lastMessageAt ?? DateTime(0),
          ),
        );
        return list;
      });

  /// Messages oldest-first, sorted **client-side** — and that is the fix, not
  /// a stylistic choice.
  ///
  /// `orderBy('createdAt')` was wrong for the one message that matters most:
  /// your own, a millisecond after you send it. `createdAt` is a
  /// `serverTimestamp()`, which reads as `null` in the local snapshot until
  /// the server acknowledges the write — and Firestore sorts null *first*. So
  /// a message you just sent appeared at the very top of the thread, above
  /// conversations from last week, then jumped to the bottom when the ack
  /// landed. Latency compensation was painting the bubble instantly, in the
  /// wrong place.
  ///
  /// The Dart SDK has no `ServerTimestampBehavior.estimate` to reach for
  /// (it exists in the native SDKs, not in `cloud_firestore` for Flutter), so
  /// the sort moves here, where a pending timestamp can be treated as what it
  /// actually is: the newest message in the thread. Sorting client-side is
  /// also what the rest of the app already does (§6.2).
  Stream<List<ChatMessage>> watchMessages(String chatId) =>
      _chats.doc(chatId).collection(Col.messages).snapshots().map((qs) {
        final list = [
          for (final d in qs.docs) ChatMessage.fromDoc(d.id, d.data()),
        ];
        list.sort((a, b) {
          final at = a.createdAt;
          final bt = b.createdAt;
          // Both pending: keep them adjacent and stable rather than letting
          // the comparator reorder them arbitrarily between frames.
          if (at == null && bt == null) return 0;
          // A pending write is the message being sent right now — newest.
          if (at == null) return 1;
          if (bt == null) return -1;
          return at.compareTo(bt);
        });
        return list;
      });

  /// Creates the thread document if needed and clears my unread counter
  /// (merge — only my entry changes) (§3.11, §6.3).
  Future<void> openThread({
    required String me,
    required String myName,
    required String partnerId,
    required String partnerName,
  }) async {
    final id = ChatThread.idFor(me, partnerId);
    await _chats.doc(id).set({
      'participants': [me, partnerId]..sort(),
      'participantNames': {me: myName, partnerId: partnerName},
      'unreadCount': {me: 0},
    }, SetOptions(merge: true));
  }

  void markThreadRead(String chatId, String me) {
    _chats.doc(chatId).set({
      'unreadCount': {me: 0},
    }, SetOptions(merge: true)).ignore();
  }

  /// Fire-and-forget by design: Firestore's latency compensation paints the
  /// bubble instantly, and awaiting the server ack would hang forever
  /// offline (§10.6). Failures surface through the returned future.
  Future<void> send({
    required String me,
    required String myName,
    required String partnerId,
    required String text,
  }) {
    final chatId = ChatThread.idFor(me, partnerId);
    final threadRef = _chats.doc(chatId);
    final messageRef = threadRef.collection(Col.messages).doc();

    final batch = _db.batch();
    batch.set(messageRef, {
      'senderId': me,
      'receiverId': partnerId,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });
    batch.set(threadRef, {
      'lastMessage': text,
      // v2.6 wrote lastMessageTimestamp + updatedAt for the web client.
      'lastMessageAt': FieldValue.serverTimestamp(),
      // FieldValue.increment, not a hardcoded 1 (§14.1).
      'unreadCount': {partnerId: FieldValue.increment(1)},
    }, SetOptions(merge: true));
    final future = batch.commit();

    // The in-app + push notification for the recipient (§11.1).
    var preview = text;
    if (preview.length > FlowConst.messagePreviewMaxChars) {
      preview = '${preview.substring(0, FlowConst.messagePreviewMaxChars)}…';
    }
    _notifications
        .notify(
          targetUserId: partnerId,
          title: 'Message from $myName',
          message: preview,
          type: 'message',
          // From the recipient's side the sender is the chat partner — this
          // is what lets the notification tap land in the conversation
          // itself instead of the inbox (P2).
          chatPartnerId: me,
          chatPartnerName: myName,
        )
        .ignore();

    return future;
  }
}
