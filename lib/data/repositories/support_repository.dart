import 'package:cloud_firestore/cloud_firestore.dart';

import '../firestore_paths.dart';
import '../models/support.dart';

/// An appeal was refused because one is already under review (BUG-016).
///
/// Its own type, in the [CheckInFailure] pattern, because the recovery is
/// specific: the case they need is already open — reply into it — and the
/// generic "Something went wrong. Please try again." would invite exactly
/// the retry this guard exists to refuse.
class DuplicateAppealFailure implements Exception {
  const DuplicateAppealFailure();
  String get message =>
      'Your appeal is already under review. Reply to it below instead.';
  @override
  String toString() => message;
}

class SupportRepository {
  SupportRepository(this._db);
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _tickets =>
      _db.collection(Col.tickets);
  CollectionReference<Map<String, dynamic>> get _appeals =>
      _db.collection(Col.appeals);

  // ── Tickets (§3.14) ────────────────────────────────────────────────────

  Stream<List<SupportTicket>> watchMyTickets(String uid) => _tickets
      .where('userId', isEqualTo: uid)
      .snapshots()
      .map((qs) {
        final list = [
          for (final d in qs.docs) SupportTicket.fromDoc(d.id, d.data()),
        ];
        list.sort((a, b) => (b.lastMessageAt ?? DateTime(0))
            .compareTo(a.lastMessageAt ?? DateTime(0)));
        return list;
      });

  /// Every ticket, for the staff queue — open ones first, then by recency.
  ///
  /// The rider side of support has existed since §3.14; the staff side of it
  /// never had a screen, so a ticket a user opened went into a collection
  /// nobody could read and was answered by nobody. Sorted client-side like
  /// every other list (§6.2), and unfiltered because staff need the answered
  /// ones too — "what did we tell them last time" is most of support.
  Stream<List<SupportTicket>> watchAllTickets() =>
      _tickets.snapshots().map((qs) {
        final list = [
          for (final d in qs.docs) SupportTicket.fromDoc(d.id, d.data()),
        ];
        list.sort((a, b) {
          if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
          return (b.lastMessageAt ?? DateTime(0))
              .compareTo(a.lastMessageAt ?? DateTime(0));
        });
        return list;
      });

  /// Staff reply on a ticket. `isAdmin` is what renders it on the other side
  /// as coming from support rather than from the user themselves.
  Future<void> replyAsStaff({
    required String ticketId,
    required String staffId,
    required String text,
  }) async {
    await _tickets.doc(ticketId).collection(Col.messages).add({
      'text': text,
      'senderId': staffId,
      'isAdmin': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _tickets
        .doc(ticketId)
        .update({'lastMessageAt': FieldValue.serverTimestamp()});
  }

  Future<void> closeTicket(String ticketId) =>
      _tickets.doc(ticketId).update({'status': 'closed'});

  Stream<SupportTicket?> watchTicket(String id) => _tickets
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? SupportTicket.fromDoc(d.id, d.data()!) : null);

  Stream<List<TicketMessage>> watchTicketMessages(String ticketId) => _tickets
      .doc(ticketId)
      .collection(Col.messages)
      .orderBy('createdAt')
      .snapshots()
      .map((qs) =>
          [for (final d in qs.docs) TicketMessage.fromDoc(d.id, d.data())]);

  Future<String> openTicket({
    required String userId,
    required String userName,
    required String subject,
    required String body,
  }) async {
    final doc = _tickets.doc();
    await doc.set({
      'userId': userId,
      'userName': userName,
      'subject': subject,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
    await doc.collection(Col.messages).add({
      'text': body,
      'senderId': userId,
      'isAdmin': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> replyToTicket({
    required String ticketId,
    required String userId,
    required String text,
  }) async {
    await _tickets.doc(ticketId).collection(Col.messages).add({
      'text': text,
      'senderId': userId,
      'isAdmin': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _tickets
        .doc(ticketId)
        .update({'lastMessageAt': FieldValue.serverTimestamp()});
  }

  Future<void> reopenTicket(String ticketId) =>
      _tickets.doc(ticketId).update({'status': 'open'});

  // ── Appeals (§3.14, §6.3) ──────────────────────────────────────────────

  /// The user's **most recent** appeal.
  ///
  /// An unordered `limit(1)` returns an arbitrary document — Firestore falls
  /// back to `__name__` ascending and auto-IDs are random — so a user
  /// suspended a second time was handed their old *resolved* appeal. That
  /// hides the "Appeal this decision" button (the screen only offers it when
  /// there is no appeal), leaving them able to do nothing but reply into a
  /// closed thread that the staff queue, which counts only `pending`, never
  /// surfaces. Sorted client-side because an `orderBy` alongside the `where`
  /// would require a composite index, which this app avoids by design (§6.2).
  Stream<Appeal?> watchMyAppeal(String uid) => _appeals
      .where('userId', isEqualTo: uid)
      .snapshots()
      .map((qs) {
        if (qs.docs.isEmpty) return null;
        final appeals = [
          for (final d in qs.docs) Appeal.fromDoc(d.id, d.data()),
        ]..sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0)));
        return appeals.first;
      });

  /// Refuses a second appeal while one is still `pending` — per open case,
  /// not per lifetime; a user suspended again may appeal again.
  ///
  /// Two open appeals split the conversation: `watchMyAppeal` surfaces one,
  /// the admin queue lists both, and staff can answer the one the user is
  /// not looking at — a thread that then looks dead from both ends (BUG-016).
  Future<void> submitAppeal({
    required String userId,
    required String userName,
    required String reason,
    List<String> attachments = const [],
  }) async {
    final open = await _appeals
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    if (open.docs.isNotEmpty) throw const DuplicateAppealFailure();
    await _appeals.add({
      'userId': userId,
      'userName': userName,
      'reason': reason,
      'attachments': attachments,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'messages': <Map<String, dynamic>>[],
    });
  }

  /// arrayUnion — a read-modify-write would drop concurrent admin replies
  /// (§6.3, §14.1).
  Future<void> replyToAppeal(String appealId, AppealMessage message) {
    return _appeals.doc(appealId).update({
      'messages': FieldValue.arrayUnion([message.toMap()]),
    });
  }

  // ── Reports & leave reasons (§6.3) ─────────────────────────────────────

  Future<void> reportUser({
    required String reporterId,
    required String reporterName,
    required String reportedUserId,
    required String reportedUserName,
    required String reason,
    String? details,
    List<String> attachments = const [],
  }) {
    return _db.collection(Col.reports).add({
      'reporterId': reporterId,
      'reporterName': reporterName,
      'reportedUserId': reportedUserId,
      'reportedUserName': reportedUserName,
      'reason': reason,
      'details': (details ?? '').trim(),
      'attachments': attachments,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> recordLeaveReason({
    required String userId,
    required String userName,
    required String userEmail,
    required String reason,
  }) {
    return _db.collection(Col.leaveReasons).add({
      'userId': userId,
      'userName': userName,
      'userEmail': userEmail,
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
