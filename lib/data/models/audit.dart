import '../../core/utils/doc_x.dart';

/// One staff action, as the accountability trail records it (P6).
///
/// The log answers exactly one question — *who did this to whom, when, and
/// what did they say about it* — so the shape carries nothing else. Entries
/// are written by the console in the same call as the action they record and
/// are immutable by rules: staff may append and read, nobody may edit or
/// delete, including staff.
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.staffId,
    this.targetUserId,
    this.targetName,
    this.detail,
    this.createdAt,
  });

  /// Wire values: `trainer_approved`, `trainer_rejected`, `suspend`,
  /// `lift`, `report_upheld`, `report_dismissed`, `appeal_resolved`.
  /// New actions are new strings — the log renders unknown ones verbatim
  /// rather than dropping them.
  final String action;

  final String id;
  final String staffId;
  final String? targetUserId;
  final String? targetName;

  /// The human half: the suspension length, the rejection reason, the
  /// closing note. Absent when the action had nothing to say.
  final String? detail;
  final DateTime? createdAt;

  factory AuditEntry.fromDoc(String id, Map<String, dynamic> d) => AuditEntry(
    id: id,
    action: d.str('action') ?? 'unknown',
    staffId: d.str('staffId') ?? '',
    targetUserId: d.str('targetUserId'),
    targetName: d.str('targetName'),
    detail: d.str('detail'),
    createdAt: d.date('createdAt'),
  );

  /// `Suspended · Karim Adel` — the row's one-line story.
  String get label => switch (action) {
    'trainer_approved' => 'Approved trainer',
    'trainer_rejected' => 'Rejected trainer',
    'suspend' => 'Suspended',
    'lift' => 'Lifted suspension',
    'report_upheld' => 'Upheld report against',
    'report_dismissed' => 'Dismissed report against',
    'appeal_resolved' => 'Resolved appeal from',
    _ => action,
  };
}
