import '../../core/utils/doc_x.dart';

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.userId,
    required this.userName,
    required this.subject,
    required this.isOpen,
    this.lastMessageAt,
  });

  final String id;
  final String userId;
  final String userName;
  final String subject;
  final bool isOpen;
  final DateTime? lastMessageAt;

  factory SupportTicket.fromDoc(String id, Map<String, dynamic> d) =>
      SupportTicket(
        id: id,
        userId: d.str('userId') ?? '',
        userName: d.str('userName') ?? '',
        subject: d.str('subject') ?? 'Support ticket',
        // Defaults to open when status is missing.
        isOpen: (d.str('status') ?? 'open') == 'open',
        lastMessageAt: d.date('lastMessageAt'),
      );
}

class TicketMessage {
  const TicketMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.fromStaff,
    this.createdAt,
  });

  final String id;
  final String text;
  final String senderId;
  final bool fromStaff;
  final DateTime? createdAt;

  factory TicketMessage.fromDoc(String id, Map<String, dynamic> d) =>
      TicketMessage(
        id: id,
        text: d.str('text') ?? '',
        senderId: d.str('senderId') ?? '',
        fromStaff: d.boolean('isAdmin'),
        createdAt: d.date('createdAt'),
      );
}

/// Blocked-user appeal. `messages` is an **array on the document**, not a
/// sub-collection — replies must use arrayUnion (§5.6, §6.3).
class Appeal {
  const Appeal({
    required this.id,
    required this.userId,
    required this.userName,
    required this.reason,
    required this.status,
    this.attachments = const [],
    this.createdAt,
    this.messages = const [],
  });

  final String id;
  final String userId;
  final String userName;
  final String reason;

  /// `pending` / `reviewed` / `resolved`.
  final String status;
  final List<String> attachments;
  final DateTime? createdAt;
  final List<AppealMessage> messages;

  factory Appeal.fromDoc(String id, Map<String, dynamic> d) => Appeal(
        id: id,
        userId: d.str('userId') ?? '',
        userName: d.str('userName') ?? '',
        reason: d.str('reason') ?? '',
        status: d.str('status') ?? 'pending',
        attachments: d.strList('attachments'),
        createdAt: d.date('createdAt'),
        messages: [
          for (final m in d.nestedList('messages')) AppealMessage.fromMap(m),
        ],
      );
}

class AppealMessage {
  const AppealMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    this.attachments = const [],
    this.timestamp,
  });

  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final List<String> attachments;
  final DateTime? timestamp;

  factory AppealMessage.fromMap(Map<String, dynamic> d) => AppealMessage(
        id: d.str('id') ?? '',
        senderId: d.str('senderId') ?? '',
        senderName: d.str('senderName') ?? '',
        text: d.str('text') ?? '',
        attachments: d.strList('attachments'),
        timestamp: d.date('timestamp'),
      );

  /// Written as an ISO string, matching the web client (§5.6).
  Map<String, dynamic> toMap() => {
        'id': id,
        'senderId': senderId,
        'senderName': senderName,
        'text': text,
        'attachments': attachments,
        'timestamp': (timestamp ?? DateTime.now()).toIso8601String(),
      };
}
