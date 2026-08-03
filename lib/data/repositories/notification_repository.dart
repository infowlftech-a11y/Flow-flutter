import 'package:cloud_firestore/cloud_firestore.dart';

import '../firestore_paths.dart';
import '../models/social.dart';

class NotificationRepository {
  NotificationRepository(this._db);
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(Col.notifications);

  /// Newest first, sorted client-side (§6.2).
  Stream<List<AppNotification>> watchFor(String uid) => _col
      .where('targetUserId', isEqualTo: uid)
      .snapshots()
      .map((qs) {
        final list = [
          for (final doc in qs.docs) AppNotification.fromDoc(doc.id, doc.data()),
        ];
        list.sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0)));
        return list;
      });

  /// Writes `targetUserId` only.
  ///
  /// v2.6 dual-wrote `userId` as well, because a web client wrote only that
  /// field and those notifications were invisible to this listener (§11.1).
  /// With a single writer the alias is dead weight — and the
  /// `onNewNotification` Cloud Function reads
  /// `data.userId || data.targetUserId`, so it still resolves the recipient.
  Future<void> notify({
    required String targetUserId,
    required String title,
    required String message,
    required String type,
    String? bookingId,
  }) {
    if (targetUserId.isEmpty) return Future.value();
    final data = <String, dynamic>{
      'targetUserId': targetUserId,
      'title': title,
      'message': message,
      'type': type,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (bookingId != null) data['bookingId'] = bookingId;
    return _col.add(data);
  }

  /// Fire-and-forget by design — navigation must not wait on the network
  /// (§10.6).
  void markRead(String id) {
    _col.doc(id).update({'read': true}).ignore();
  }

  Future<void> markAllRead(List<String> ids) async {
    final batch = _db.batch();
    for (final id in ids) {
      batch.update(_col.doc(id), {'read': true});
    }
    await batch.commit();
  }

  Future<void> markAllUnread(List<String> ids) async {
    final batch = _db.batch();
    for (final id in ids) {
      batch.update(_col.doc(id), {'read': false});
    }
    await batch.commit();
  }

  Future<void> delete(String id) => _col.doc(id).delete();
}
