import '../../core/utils/doc_x.dart';

/// A rider-submitted report against a trainer (§3.4, §6.3).
///
/// Previously write-only from this client — moderation lived in the web
/// console. The in-app admin console now reads and resolves these.
class Report {
  const Report({
    required this.id,
    required this.reporterId,
    required this.reporterName,
    required this.reportedUserId,
    required this.reportedUserName,
    required this.reason,
    this.details,
    this.attachments = const [],
    required this.status,
    this.createdAt,
    this.resolutionNote,
    this.sessionId,
    this.sessionRef,
  });

  final String id;
  final String reporterId;
  final String reporterName;
  final String reportedUserId;
  final String reportedUserName;
  final String reason;
  final String? details;
  final List<String> attachments;

  /// The booking the complaint is about, when the reporter attached one —
  /// raw id as the canonical key, plus its rendered `FLW-…` name so the
  /// console can print it without a booking read.
  final String? sessionId;
  final String? sessionRef;

  /// `pending` · `resolved` · `dismissed`.
  final String status;
  final DateTime? createdAt;
  final String? resolutionNote;

  factory Report.fromDoc(String id, Map<String, dynamic> d) => Report(
        id: id,
        reporterId: d.str('reporterId') ?? '',
        reporterName: d.str('reporterName') ?? 'Someone',
        reportedUserId: d.str('reportedUserId') ?? '',
        reportedUserName: d.str('reportedUserName') ?? 'Unknown',
        reason: d.str('reason') ?? 'Unspecified',
        details: d.str('details'),
        attachments: d.strList('attachments'),
        status: d.str('status') ?? 'pending',
        createdAt: d.date('createdAt'),
        resolutionNote: d.str('resolutionNote'),
        sessionId: d.str('sessionId'),
        sessionRef: d.str('sessionRef'),
      );

  bool get isOpen => status == 'pending';
}
