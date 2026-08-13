import 'package:cloud_firestore/cloud_firestore.dart';

import '../firestore_paths.dart';
import '../models/app_user.dart';
import '../models/audit.dart';
import '../models/report.dart';
import '../models/support.dart';
import 'notification_repository.dart';

/// Staff moderation, ported in-app.
///
/// The v2.6 blueprint (§14.2) left trainer approvals, report handling and
/// appeal moderation in a separate web console. On a database this app is the
/// sole writer of, that console no longer exists — and without approvals no
/// trainer can ever become visible to riders, so the marketplace would have
/// no supply. Everything here is guarded by `isStaff` in the UI and by
/// Firestore rules on the server.
class AdminRepository {
  AdminRepository(this._db, this._notifications);
  final FirebaseFirestore _db;
  final NotificationRepository _notifications;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection(Col.users);
  CollectionReference<Map<String, dynamic>> get _reports =>
      _db.collection(Col.reports);
  CollectionReference<Map<String, dynamic>> get _appeals =>
      _db.collection(Col.appeals);
  CollectionReference<Map<String, dynamic>> get _audit =>
      _db.collection(Col.auditLog);

  // ── Audit trail (P6) ───────────────────────────────────────────────────

  /// Newest first, client-side (§6.2). Staff-only by rules.
  Stream<List<AuditEntry>> watchAuditLog() => _audit.snapshots().map((qs) {
    final list = [
      for (final doc in qs.docs) AuditEntry.fromDoc(doc.id, doc.data()),
    ];
    list.sort(
      (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
    return list;
  });

  /// One appended line per staff action, written after the action lands so
  /// the log never claims something that failed. [byStaff] is optional on
  /// every method for source compatibility, but a missing actor writes
  /// nothing — an unattributed audit line is noise wearing a uniform.
  Future<void> _auditWrite({
    required String action,
    required String? byStaff,
    String? targetUserId,
    String? targetName,
    String? detail,
  }) {
    if (byStaff == null || byStaff.isEmpty) return Future.value();
    final note = (detail ?? '').trim();
    return _audit
        .add({
          'action': action,
          'staffId': byStaff,
          'targetUserId': ?targetUserId,
          if ((targetName ?? '').isNotEmpty) 'targetName': targetName,
          if (note.isNotEmpty) 'detail': note,
          'createdAt': FieldValue.serverTimestamp(),
        })
        .then((_) {});
  }

  // ── Trainer approvals ──────────────────────────────────────────────────

  /// Trainers waiting on review. Sorted client-side (oldest first, so the
  /// longest-waiting applicant is handled first) to avoid a composite index.
  Stream<List<AppUser>> watchPendingTrainers() => _users
      .where('role', isEqualTo: 'business')
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((qs) {
        final list = [
          for (final doc in qs.docs) AppUser.fromDoc(doc.id, doc.data()),
        ];
        list.sort((a, b) => a.name.compareTo(b.name));
        return list;
      });

  /// Everyone currently suspended, so a block can be lifted from one place.
  Stream<List<AppUser>> watchBlockedUsers() => _users
      .where('status', isEqualTo: 'blocked')
      .snapshots()
      .map(
        (qs) => [
          for (final doc in qs.docs) AppUser.fromDoc(doc.id, doc.data()),
        ],
      );

  /// A review decision is an explicit statement of what the account now IS,
  /// so it supersedes any suspension in force: the block markers are cleared
  /// rather than left stale on the document. Leaving them was BUG-012 — the
  /// gate kept counting down a `blockedUntil` that no longer applied, and a
  /// later [unblockUser] restored `statusBeforeBlock`, pulling an approved,
  /// bookable trainer back to `pending` and out of Explore.
  static Map<String, dynamic> get _clearBlockMarkers => {
    'blockedUntil': FieldValue.delete(),
    'statusBeforeBlock': FieldValue.delete(),
  };

  /// Approve a trainer — this is what makes them visible in Explore, which
  /// queries `role == 'business' && status == 'active'`.
  Future<void> approveTrainer(AppUser trainer, {String? byStaff}) async {
    await _users.doc(trainer.uid).update({
      'status': 'active',
      'reviewedAt': FieldValue.serverTimestamp(),
      ..._clearBlockMarkers,
    });
    await _auditWrite(
      action: 'trainer_approved',
      byStaff: byStaff,
      targetUserId: trainer.uid,
      targetName: trainer.name,
    );
    await _notifications.notify(
      targetUserId: trainer.uid,
      title: "You're live on Flow 🤙",
      message:
          'Your trainer profile is approved. Riders can find and book '
          'you from now on.',
      type: 'account_approved',
    );
  }

  /// Decline an application. The rider-facing app holds rejected accounts at
  /// a gate rather than handing them a dashboard nobody can book.
  Future<void> rejectTrainer(
    AppUser trainer, {
    String? reason,
    String? byStaff,
  }) async {
    await _users.doc(trainer.uid).update({
      'status': 'rejected',
      'reviewedAt': FieldValue.serverTimestamp(),
      if ((reason ?? '').trim().isNotEmpty) 'reviewNote': reason!.trim(),
      ..._clearBlockMarkers,
    });
    await _auditWrite(
      action: 'trainer_rejected',
      byStaff: byStaff,
      targetUserId: trainer.uid,
      targetName: trainer.name,
      detail: reason,
    );
    final note = (reason ?? '').trim();
    await _notifications.notify(
      targetUserId: trainer.uid,
      title: 'Application not approved',
      message:
          'We could not verify your trainer application.'
          '${note.isEmpty ? '' : ' Reason: $note'}',
      type: 'account_rejected',
    );
  }

  /// Return a previously reviewed account to the pending queue.
  Future<void> restoreToPending(String uid) =>
      _users.doc(uid).update({'status': 'pending', ..._clearBlockMarkers});

  // ── Suspensions ────────────────────────────────────────────────────────

  /// [until] is an ISO date string, or the literal `'forever'` (§5.1).
  /// Suspends [uid], remembering what the account was before.
  ///
  /// The prior status has to be recorded here or [unblockUser] has nothing to
  /// restore and can only guess.
  Future<void> blockUser(
    String uid, {
    required String until,
    String? byStaff,
    String? targetName,
  }) async {
    final ref = _users.doc(uid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final previous = snap.data()?['status'];
      tx.update(ref, {
        'status': 'blocked',
        'blockedUntil': until,
        'blockedAt': FieldValue.serverTimestamp(),
        // Guarded against a double-block overwriting the real prior status
        // with 'blocked' and stranding the account there.
        if (previous is String && previous.isNotEmpty && previous != 'blocked')
          'statusBeforeBlock': previous,
      });
    });
    await _auditWrite(
      action: 'suspend',
      byStaff: byStaff,
      targetUserId: uid,
      targetName: targetName,
      detail: until == 'forever' ? 'permanent' : 'until $until',
    );
  }

  /// Lifts a block, restoring the status the account actually had.
  ///
  /// This used to hardcode `status: 'active'`, which quietly promoted every
  /// suspended account: a trainer still `pending` in the approvals queue — or
  /// one already `rejected` — came back `active`, and `watchActiveTrainers()`
  /// lists exactly `role == 'business' && status == 'active'`. Suspending and
  /// unsuspending was therefore a way to make a never-reviewed trainer
  /// bookable in Explore.
  ///
  /// With no recorded prior status (a block written before this field
  /// existed) it fails **safe**: a business account returns to `pending` and
  /// goes back through approvals rather than going live unreviewed.
  Future<void> unblockUser(
    String uid, {
    String? byStaff,
    String? targetName,
  }) async {
    final ref = _users.doc(uid);
    final lifted = await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      // The blocked-users list is a live stream, so a row can be tapped
      // moments after a colleague lifted the block — or after an approval
      // superseded it. An account that is not blocked has nothing to
      // restore; writing the business-account fallback here would demote an
      // approved trainer to pending (BUG-012). A retry, not an error — the
      // same reading _writeIfLive and markPaid take of a stale copy.
      if (data?['status'] != 'blocked') return false;
      final recorded = data?['statusBeforeBlock'];
      final restored = (recorded is String && recorded.isNotEmpty)
          ? recorded
          : (data?['role'] == 'business' ? 'pending' : 'active');
      tx.update(ref, {
        'status': restored,
        // Cleared alongside: the blocked gate reads blockedUntil for its
        // countdown, and a stale value would keep the ban in force.
        'blockedUntil': FieldValue.delete(),
        'statusBeforeBlock': FieldValue.delete(),
      });
      return true;
    });
    if (!lifted) return;
    await _notifications.notify(
      targetUserId: uid,
      title: 'Your account is active again',
      message: 'Welcome back. Your suspension has been lifted.',
      type: 'account_restored',
    );
    await _auditWrite(
      action: 'lift',
      byStaff: byStaff,
      targetUserId: uid,
      targetName: targetName,
    );
  }

  // ── Leave reasons (§3.13) ──────────────────────────────────────────────

  /// The exit interviews, newest first.
  ///
  /// Written on account deletion and, until now, read by nobody — the sheet
  /// asked "why are you leaving? it genuinely helps" and then filed the
  /// answer where no one on the team could reach it.
  Stream<List<LeaveReason>> watchLeaveReasons() =>
      _db.collection(Col.leaveReasons).snapshots().map((qs) {
        final list = [
          for (final doc in qs.docs) LeaveReason.fromDoc(doc.id, doc.data()),
        ];
        list.sort(
          (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
            a.createdAt ?? DateTime(0),
          ),
        );
        return list;
      });

  // ── Reports ────────────────────────────────────────────────────────────

  /// Newest first, client-side (§6.2).
  Stream<List<Report>> watchReports() => _reports.snapshots().map((qs) {
    final list = [
      for (final doc in qs.docs) Report.fromDoc(doc.id, doc.data()),
    ];
    list.sort(
      (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
    return list;
  });

  /// [reporterId]/[reportedUserName] come from the Report the caller is
  /// holding; they close the loop the reporter was left out of — a filed
  /// complaint used to resolve into a collection its author cannot read,
  /// so from their side every report vanished (P2).
  Future<void> closeReport(
    String reportId, {
    required bool upheld,
    String? note,
    String? reporterId,
    String? reportedUserName,
    String? byStaff,
  }) async {
    await _reports.doc(reportId).update({
      'status': upheld ? 'resolved' : 'dismissed',
      'resolvedAt': FieldValue.serverTimestamp(),
      if ((note ?? '').trim().isNotEmpty) 'resolutionNote': note!.trim(),
    });
    await _auditWrite(
      action: upheld ? 'report_upheld' : 'report_dismissed',
      byStaff: byStaff,
      targetName: reportedUserName,
      detail: note,
    );
    if (reporterId == null || reporterId.isEmpty) return;
    final who = (reportedUserName ?? '').isEmpty
        ? 'the person'
        : reportedUserName!;
    final closing = (note ?? '').trim();
    await _notifications.notify(
      targetUserId: reporterId,
      title: upheld ? 'Your report led to action' : 'Your report was reviewed',
      message: upheld
          ? 'Thank you for flagging $who — the team reviewed your report '
                'and acted on it.'
                '${closing.isEmpty ? '' : ' $closing'}'
          : 'The team reviewed your report about $who and did not find '
                'grounds to act on it this time.'
                '${closing.isEmpty ? '' : ' $closing'}',
      type: 'report_update',
    );
  }

  // ── Appeals ────────────────────────────────────────────────────────────

  Stream<List<Appeal>> watchAppeals() => _appeals.snapshots().map((qs) {
    final list = [
      for (final doc in qs.docs) Appeal.fromDoc(doc.id, doc.data()),
    ];
    list.sort(
      (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
    return list;
  });

  /// arrayUnion, matching the rider side — a read-modify-write would drop a
  /// reply the user sent concurrently (§6.3).
  ///
  /// [notifyUserId]: the suspended account the appeal belongs to. In-app
  /// they live behind the blocked gate, where the thread already shows the
  /// reply — the notification exists for the push, which is the only channel
  /// that reaches someone who has stopped opening the app (P2).
  Future<void> replyToAppeal(
    String appealId,
    AppealMessage message, {
    String? notifyUserId,
  }) async {
    await _appeals.doc(appealId).update({
      'messages': FieldValue.arrayUnion([message.toMap()]),
    });
    if (notifyUserId == null || notifyUserId.isEmpty) return;
    await _notifications.notify(
      targetUserId: notifyUserId,
      title: 'Support replied to your appeal',
      message: message.text,
      type: 'appeal_update',
    );
  }

  Future<void> setAppealStatus(
    String appealId,
    String status, {
    String? byStaff,
    String? targetName,
  }) async {
    await _appeals.doc(appealId).update({
      'status': status,
      'reviewedAt': FieldValue.serverTimestamp(),
    });
    await _auditWrite(
      action: 'appeal_$status',
      byStaff: byStaff,
      targetName: targetName,
    );
  }
}
