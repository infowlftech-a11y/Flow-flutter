import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/date_x.dart';
import '../firestore_paths.dart';
import '../models/schedule.dart';

class ScheduleRepository {
  ScheduleRepository(this._db);
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _blocks =>
      _db.collection(Col.availability);
  CollectionReference<Map<String, dynamic>> get _vacations =>
      _db.collection(Col.vacations);

  Stream<List<Availability>> watchDayBlocks(String instructorId, String date) =>
      _blocks
          .where('instructorId', isEqualTo: instructorId)
          .where('date', isEqualTo: date)
          .snapshots()
          .map((qs) => [
                for (final d in qs.docs) Availability.fromDoc(d.id, d.data()),
              ]);

  Stream<List<Availability>> watchAllBlocks(String instructorId) => _blocks
      .where('instructorId', isEqualTo: instructorId)
      .snapshots()
      .map((qs) =>
          [for (final d in qs.docs) Availability.fromDoc(d.id, d.data())]);

  /// Client-side sort by startDate (§6.2).
  Stream<List<Vacation>> watchVacations(String instructorId) => _vacations
      .where('instructorId', isEqualTo: instructorId)
      .snapshots()
      .map((qs) {
        final list = [
          for (final d in qs.docs) Vacation.fromDoc(d.id, d.data()),
        ];
        list.sort((a, b) => a.startDate.compareTo(b.startDate));
        return list;
      });

  /// Block one hour (§6.3).
  Future<String> blockHour({
    required String instructorId,
    required String date,
    required Slot start,
    String label = 'Blocked',
  }) async {
    final doc = await _blocks.add({
      'instructorId': instructorId,
      'date': date,
      'startTime': start.value,
      'endTime': start.plusHours(1).value,
      'status': 'host-blocked',
      'label': label,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> releaseBlock(String blockId) => _blocks.doc(blockId).delete();

  Future<String> addVacation({
    required String instructorId,
    required String startDate,
    required String endDate,
    String label = 'Time off',
  }) async {
    final doc = await _vacations.add({
      'instructorId': instructorId,
      'startDate': startDate,
      'endDate': endDate,
      'label': label,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> removeVacation(String id) => _vacations.doc(id).delete();

  /// Re-create a vacation with the same data — the UNDO in the toast.
  Future<void> restoreVacation(Vacation v) async {
    await _vacations.doc(v.id).set({
      'instructorId': v.instructorId,
      'startDate': v.startDate,
      'endDate': v.endDate,
      'label': v.label ?? 'Time off',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
