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
  Stream<List<ChatThread>> watchInbox(String uid) => _chats
      .where('participants', arrayContains: uid)
      .snapshots()
      .map((qs) {
        final list = [
          for (final d in qs.docs) ChatThread.fromDoc(d.id, d.data()),
        ];
        list.sort((a, b) => (b.lastMessageAt ?? DateTime(0))
            .compareTo(a.lastMessageAt ?? DateTime(0)));
        return list;
      });

  Stream<List<ChatMessage>> watchMessages(String chatId) => _chats
      .doc(chatId)
      .collection(Col.messages)
      .orderBy('createdAt')
      .snapshots()
      .map((qs) =>
          [for (final d in qs.docs) ChatMessage.fromDoc(d.id, d.data())]);

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
    _chats
        .doc(chatId)
        .set({'unreadCount': {me: 0}}, SetOptions(merge: true)).ignore();
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
    batch.set(
        threadRef,
        {
          'lastMessage': text,
          // v2.6 wrote lastMessageTimestamp + updatedAt for the web client.
          'lastMessageAt': FieldValue.serverTimestamp(),
          // FieldValue.increment, not a hardcoded 1 (§14.1).
          'unreadCount': {partnerId: FieldValue.increment(1)},
        },
        SetOptions(merge: true));
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
        )
        .ignore();

    return future;
  }
}
