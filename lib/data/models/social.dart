import '../../core/utils/doc_x.dart';

/// A trainer review.
///
/// The field was called `listingId` while it held the trainer's uid — a
/// historical misnomer the web client forced us to keep (§5.4, §14.3). On a
/// database only this app writes, it is stored honestly as `trainerId`.
class Review {
  const Review({
    required this.id,
    required this.trainerId,
    required this.userId,
    required this.userName,
    required this.rating,
    this.comment,
    this.bookingId,
    this.createdAt,
  });

  final String id;
  final String trainerId;
  final String userId;
  final String userName;
  final int rating;
  final String? comment;
  final String? bookingId;
  final DateTime? createdAt;

  factory Review.fromDoc(String id, Map<String, dynamic> d) => Review(
    id: id,
    trainerId: d.str('trainerId') ?? '',
    userId: d.str('userId') ?? '',
    userName: d.str('userName') ?? 'Rider',
    rating: (d.integer('rating') ?? 5).clamp(1, 5),
    comment: d.str('comment'),
    bookingId: d.str('bookingId'),
    createdAt: d.date('createdAt'),
  );
}

/// Computed rating. With no reviews the summary is **5.0 / 0** so unrated
/// trainers display "5.0" (§8.10) — a deliberate marketplace behaviour.
class RatingSummary {
  const RatingSummary({required this.average, required this.count});

  final double average;
  final int count;

  static const none = RatingSummary(average: 5.0, count: 0);

  factory RatingSummary.from(Iterable<Review> reviews) {
    final list = reviews.toList();
    if (list.isEmpty) return none;
    final sum = list.fold<int>(0, (acc, r) => acc + r.rating);
    return RatingSummary(average: sum / list.length, count: list.length);
  }

  String get display => average.toStringAsFixed(1);
}

/// Chat thread. `chatId` = the two uids sorted and joined with `_` —
/// deterministic from either side (§5.4).
class ChatThread {
  const ChatThread({
    required this.id,
    required this.participants,
    required this.participantNames,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCounts = const {},
  });

  final String id;
  final List<String> participants;
  final Map<String, String> participantNames;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final Map<String, int> unreadCounts;

  static String idFor(String uidA, String uidB) {
    final ids = [uidA, uidB]..sort();
    return ids.join('_');
  }

  factory ChatThread.fromDoc(String id, Map<String, dynamic> d) {
    final names = d
        .nested('participantNames')
        .map((k, v) => MapEntry(k, v?.toString() ?? ''));
    return ChatThread(
      id: id,
      participants: d.strList('participants'),
      participantNames: names,
      lastMessage: d.str('lastMessage'),
      lastMessageAt: d.date('lastMessageAt'),
      // Counts stay parsed tolerantly (strings accepted, negatives clamped) —
      // that guards against a malformed document, not a legacy writer.
      unreadCounts: d.nested('unreadCount').map((k, v) {
        final n = switch (v) {
          int i => i,
          num x => x.toInt(),
          String s => int.tryParse(s) ?? 0,
          _ => 0,
        };
        return MapEntry(k, n < 0 ? 0 : n);
      }),
    );
  }

  String partnerId(String me) =>
      participants.firstWhere((p) => p != me, orElse: () => '');

  String partnerName(String me) {
    final id = partnerId(me);
    final n = participantNames[id];
    return (n == null || n.isEmpty) ? 'Rider' : n;
  }

  int unreadFor(String uid) => unreadCounts[uid] ?? 0;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    this.createdAt,
    this.read = false,
  });

  final String id;
  final String senderId;
  final String text;
  final DateTime? createdAt;

  /// Written `false`, never updated or displayed — no read receipts (§14.3).
  final bool read;

  factory ChatMessage.fromDoc(String id, Map<String, dynamic> d) => ChatMessage(
    id: id,
    senderId: d.str('senderId') ?? '',
    text: d.str('text') ?? '',
    createdAt: d.date('createdAt'),
    read: d.boolean('read'),
  );
}

enum NotificationKind {
  bookingRequest,
  bookingConfirmed,
  bookingRejected,
  bookingCancelled,
  reminder,
  review,
  message,
  broadcast,

  /// A staff decision about the account itself: approved, rejected,
  /// suspension lifted (§11.1). Previously these three fell through to
  /// [system] because no case matched — the right destination by accident
  /// rather than by choice (BUG-011). Modelled so the tile can carry its own
  /// icon and the routing switch names the case it is handling.
  /// `appeal_update` joins it: a staff reply on a suspension appeal is a
  /// decision about the account, and the message is the payload.
  account,

  /// Support moved on a ticket the user opened: a staff reply, or the
  /// ticket being resolved. Carries [AppNotification.ticketId] so the tap
  /// lands in that thread, not on the list (P2).
  support,

  /// A staff outcome on a complaint the user filed. No destination screen
  /// exists for a filed report by design (reports are write-only for the
  /// reporter), so this renders as a sheet and the message carries the
  /// whole outcome.
  reportUpdate,

  /// A rider left a review — told to the trainer. Routes to the trainer's
  /// own public profile, where the review is visible.
  reviewReceived,
  system;

  static NotificationKind parse(String? raw) => switch (raw) {
    'booking_request' || 'booking_new' => bookingRequest,
    'booking_confirmed' => bookingConfirmed,
    'booking_rejected' => bookingRejected,
    'booking_cancelled' => bookingCancelled,
    'reminder' => reminder,
    'review' => review,
    'message' => message,
    'global_broadcast' => broadcast,
    'account_approved' ||
    'account_rejected' ||
    'account_restored' ||
    'appeal_update' => account,
    'support_reply' || 'support_closed' => support,
    'report_update' => reportUpdate,
    'review_received' => reviewReceived,
    _ => system,
  };
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.kind,
    required this.read,
    this.createdAt,
    this.bookingId,
    this.ticketId,
    this.chatPartnerId,
    this.chatPartnerName,
  });

  final String id;
  final String title;
  final String message;
  final NotificationKind kind;
  final bool read;
  final DateTime? createdAt;
  final String? bookingId;

  /// The support ticket a [NotificationKind.support] notification is about,
  /// so its tap opens that thread rather than the ticket list (P2).
  final String? ticketId;

  /// For [NotificationKind.message]: the *sender's* uid — which is the
  /// partner id the recipient's chat route needs. Older message
  /// notifications lack it and fall back to the inbox.
  final String? chatPartnerId;

  /// The sender's display name, so the chat screen deep-linked from a tap
  /// can title itself before the thread stream arrives.
  final String? chatPartnerName;

  factory AppNotification.fromDoc(String id, Map<String, dynamic> d) =>
      AppNotification(
        id: id,
        title: d.str('title') ?? 'FLOW',
        message: d.str('message') ?? '',
        kind: NotificationKind.parse(d.str('type')),
        read: d.boolean('read'),
        createdAt: d.date('createdAt'),
        bookingId: d.str('bookingId'),
        ticketId: d.str('ticketId'),
        chatPartnerId: d.str('chatPartnerId'),
        chatPartnerName: d.str('chatPartnerName'),
      );
}
