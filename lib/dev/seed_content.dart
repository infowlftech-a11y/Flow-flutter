// The activity pass: bookings, reviews, chats, notifications, calendar blocks
// and an expedition. Run by seed_app.dart after the accounts exist.
//
// ## Why it is shaped like this
//
// There is no service account in this repo, so every document is written by
// the *client* SDK while signed in as the user who is allowed to write it —
// `firestore.rules` are enforced against the seeder exactly as against a real
// user. That dictates the whole structure:
//
//   * a booking must be created by one of its two parties  → rider pass
//   * a review must carry `userId == uid()`                → rider pass
//   * a message must carry `senderId == uid()`             → so a two-sided
//     conversation is written in two passes, riders first, trainers second
//   * a calendar block must carry `instructorId == uid()`  → trainer pass
//
// Message ordering therefore cannot use `serverTimestamp()` — the two halves
// of a conversation are written minutes apart in the wrong order. Every
// timestamp here is an explicit instant relative to "now", so the thread reads
// correctly no matter what order the passes ran in.
//
// ## Re-running
//
// Every document has a deterministic id and is written only if absent. That is
// not just tidiness: `reviews` and `chats/*/messages` are **immutable by rule**
// (`allow update: if false`), so a blind `set()` on a second run would be an
// update and would be denied. Absent-only writes make the whole pass safely
// repeatable.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/utils/date_x.dart';
import '../data/models/social.dart';
import 'seed_data.dart';

/// Wall-clock day, [offset] days from today, as the `YYYY-MM-DD` the whole app
/// stores dates in.
String _day(int offset) => ymd(DateTime.now().add(Duration(days: offset)));

DateTime _hoursAgo(int hours) =>
    DateTime.now().subtract(Duration(hours: hours));

DateTime _daysAgo(int days) => DateTime.now().subtract(Duration(days: days));

String _hhmm(int minutes) {
  final h = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// Mirrors `BookingRepository.reserve` field for field.
///
/// Written literally rather than by calling the repository: the repository
/// refuses past dates, enforces the same-day lead time and re-checks the slot
/// grid — all correct for a real booking and all fatal to a seeder whose whole
/// job is to manufacture history.
Map<String, dynamic> _lesson(
  String id, {
  required String instructorId,
  required String instructorName,
  required String riderId,
  required String riderName,
  required String riderLevel,
  required String date,
  required int startHour,
  required int hours,
  required num rate,
  required String status,
  String title = 'Private lesson',
  bool gear = false,
  String message = '',
  bool checkedIn = false,
  int createdDaysAgo = 4,
  /// `null` leaves the payment fields off entirely, which is how a booking
  /// written before payments were tracked looks — worth having in the test
  /// data, because that is the state most real documents are in.
  String? paymentStatus = 'unpaid',
}) {
  final startMinutes = startHour * 60;
  return {
    'id': id,
    'instructorId': instructorId,
    'instructorName': instructorName,
    'kiterId': riderId,
    'studentName': riderName,
    'studentLevel': riderLevel,
    'listingTitle': title,
    'date': date,
    'startTime': _hhmm(startMinutes),
    'endTime': _hhmm(startMinutes + hours * 60),
    // The trainer's calendar keeps an hour clear after every session (§8.1).
    'bufferedEndTime': _hhmm(startMinutes + hours * 60 + 60),
    'selectedTimes': [
      for (var i = 0; i < hours; i++) _hhmm(startMinutes + i * 60),
    ],
    'durationHours': hours,
    'totalPrice': rate * hours,
    'type': 'lesson',
    'gearNeeded': gear,
    'message': message,
    'status': status,
    'checkedIn': checkedIn,
    'reminderSent': false,
    'hiddenByGuest': false,
    'hiddenByInstructor': false,
    if (paymentStatus != null) ...{
      'paymentStatus': paymentStatus,
      'paymentMethod': 'cash',
      'currency': 'EUR',
      'amountDue': rate * hours,
      if (paymentStatus == 'paid')
        'paidAt': Timestamp.fromDate(_daysAgo(createdDaysAgo - 1)),
    },
    'createdAt': Timestamp.fromDate(_daysAgo(createdDaysAgo)),
    seedMarker: true,
  };
}

Map<String, dynamic> _notification({
  required String targetUserId,
  required String title,
  required String message,
  required String type,
  required bool read,
  required int hoursAgo,
  String? bookingId,
}) =>
    {
      'targetUserId': targetUserId,
      'title': title,
      'message': message,
      'type': type,
      'read': read,
      'createdAt': Timestamp.fromDate(_hoursAgo(hoursAgo)),
      'bookingId': ?bookingId,
      seedMarker: true,
    };

/// Writes only when the document is absent — see the header on re-running.
/// Returns true when something was actually written.
Future<bool> _createIfAbsent(
  DocumentReference<Map<String, dynamic>> ref,
  Map<String, dynamic> data,
) async {
  final snap = await ref.get();
  if (snap.exists) return false;
  await ref.set(data);
  return true;
}

/// Seeds every non-account document.
///
/// [uids] maps a seeded email to its Firebase uid, as collected by the account
/// pass. Any account that failed to be created is simply absent, and the work
/// that needed it is skipped with a warning rather than crashing the run.
Future<void> seedContent({
  required FirebaseAuth auth,
  required FirebaseFirestore db,
  required Map<String, String> uids,
  required SeedLog say,
}) async {
  final missing = [
    for (final email in const [
      emailRider1,
      emailRider2,
      emailTrainer1,
      emailTrainer2,
      emailTrainer3,
    ])
      if (!uids.containsKey(email)) email,
  ];
  if (missing.isNotEmpty) {
    say('Skipping activity — these accounts are missing: ${missing.join(", ")}',
        SeedLevel.error);
    return;
  }

  final lina = uids[emailRider1]!;
  final tomas = uids[emailRider2]!;
  final omar = uids[emailTrainer1]!;
  final sofia = uids[emailTrainer2]!;
  final yannick = uids[emailTrainer3]!;

  var written = 0;
  var skipped = 0;

  /// Runs [work] signed in as [email], then signs out again. Every write in
  /// the seeder is authorised as somebody.
  Future<void> asUser(
      String email, String label, Future<int> Function(String uid) work) async {
    say('Signed in as $label…', SeedLevel.info);
    try {
      final cred = await auth.signInWithEmailAndPassword(
          email: email, password: seedPassword);
      final n = await work(cred.user!.uid);
      written += n;
      say('  ✓ $n document${n == 1 ? "" : "s"} written', SeedLevel.ok);
    } catch (error) {
      say('  ✗ $label: $error', SeedLevel.error);
    } finally {
      await auth.signOut();
    }
  }

  Future<int> countWrites(List<Future<bool>> writes) async {
    final results = await Future.wait(writes);
    final n = results.where((w) => w).length;
    skipped += results.length - n;
    return n;
  }

  // ── Pass 1: riders ─────────────────────────────────────────────────────
  // Bookings, the reviews they earned, the rider half of each conversation,
  // and each rider's own notifications.

  await asUser(emailRider1, 'Lina Hassan (rider)', (uid) async {
    final bookings = db.collection('bookings');
    final reviews = db.collection('reviews');
    final notifications = db.collection('notifications');
    final threadId = ChatThread.idFor(uid, omar);
    final thread = db.collection('chats').doc(threadId);

    // The thread document must exist before any message: the message rule
    // reads `participants` off it to decide who is allowed to post.
    await thread.set({
      'participants': [uid, omar]..sort(),
      'participantNames': {uid: 'Lina Hassan', omar: 'Omar Farouk'},
      seedMarker: true,
    }, SetOptions(merge: true));

    return countWrites([
      // Two finished sessions — the history that makes reviews legal.
      _createIfAbsent(
        bookings.doc('seed-lina-omar-past1'),
        _lesson('seed-lina-omar-past1',
            instructorId: omar,
            instructorName: 'Omar Farouk',
            riderId: uid,
            riderName: 'Lina Hassan',
            riderLevel: 'Independent',
            date: _day(-21),
            startHour: 10,
            hours: 2,
            rate: 80,
            status: 'completed',
            checkedIn: true,
            createdDaysAgo: 25,
            paymentStatus: 'paid'),
      ),
      _createIfAbsent(
        bookings.doc('seed-lina-omar-past2'),
        _lesson('seed-lina-omar-past2',
            instructorId: omar,
            instructorName: 'Omar Farouk',
            riderId: uid,
            riderName: 'Lina Hassan',
            riderLevel: 'Independent',
            date: _day(-12),
            startHour: 9,
            hours: 2,
            rate: 80,
            status: 'completed',
            checkedIn: true,
            message: 'Working on toeside transitions.',
            createdDaysAgo: 16,
            // Left owing on purpose: this is what puts a figure in the
            // trainer's "still to collect" band and a MARK PAID button in
            // the ledger.
            paymentStatus: 'unpaid'),
      ),
      // Running right now — the Command Center "Active" card and the
      // rider's live session banner.
      _createIfAbsent(
        bookings.doc('seed-lina-omar-live'),
        _lesson('seed-lina-omar-live',
            instructorId: omar,
            instructorName: 'Omar Farouk',
            riderId: uid,
            riderName: 'Lina Hassan',
            riderLevel: 'Independent',
            date: _day(0),
            startHour: 9,
            hours: 2,
            rate: 80,
            status: 'in_progress',
            checkedIn: true,
            createdDaysAgo: 2),
      ),
      // Approved and still ahead — this is the one with a QR ticket.
      _createIfAbsent(
        bookings.doc('seed-lina-omar-next'),
        _lesson('seed-lina-omar-next',
            instructorId: omar,
            instructorName: 'Omar Farouk',
            riderId: uid,
            riderName: 'Lina Hassan',
            riderLevel: 'Independent',
            date: _day(2),
            startHour: 10,
            hours: 2,
            rate: 80,
            status: 'confirmed',
            gear: true,
            message: 'Bringing a friend to watch from the beach.',
            createdDaysAgo: 3),
      ),
      // Waiting on a trainer — shows up in Sofia's approval queue.
      _createIfAbsent(
        bookings.doc('seed-lina-sofia-pending'),
        _lesson('seed-lina-sofia-pending',
            instructorId: sofia,
            instructorName: 'Sofia Ricci',
            riderId: uid,
            riderName: 'Lina Hassan',
            riderLevel: 'Independent',
            date: _day(4),
            startHour: 12,
            hours: 3,
            rate: 95,
            status: 'pending',
            title: 'Foil intro',
            gear: true,
            message: 'First time on a foil — please go easy.',
            createdDaysAgo: 1),
      ),
      // Declined, so the "Declined" pill and its sub-label have a subject.
      _createIfAbsent(
        bookings.doc('seed-lina-yannick-rejected'),
        _lesson('seed-lina-yannick-rejected',
            instructorId: yannick,
            instructorName: 'Yannick Weber',
            riderId: uid,
            riderName: 'Lina Hassan',
            riderLevel: 'Independent',
            date: _day(-9),
            startHour: 11,
            hours: 2,
            rate: 70,
            status: 'rejected',
            createdDaysAgo: 14),
      ),

      // Reviews — one per completed session, deliberately not both 5★ so the
      // average is not a round number.
      _createIfAbsent(reviews.doc('seed-review-lina-omar-1'), {
        'trainerId': omar,
        'userId': uid,
        'userName': 'Lina Hassan',
        'rating': 5,
        'comment':
            'Omar read the wind better than the forecast did. Moved us up '
                'the beach twice and both times he was right.',
        'bookingId': 'seed-lina-omar-past1',
        'createdAt': Timestamp.fromDate(_daysAgo(20)),
        seedMarker: true,
      }),
      _createIfAbsent(reviews.doc('seed-review-lina-omar-2'), {
        'trainerId': omar,
        'userId': uid,
        'userName': 'Lina Hassan',
        'rating': 4,
        'comment':
            'Good session. Gear was a bit tired — the bar could use new lines.',
        'bookingId': 'seed-lina-omar-past2',
        'createdAt': Timestamp.fromDate(_daysAgo(11)),
        seedMarker: true,
      }),

      // Lina's half of the conversation. Omar's replies land in pass 2 and
      // interleave by timestamp.
      _createIfAbsent(thread.collection('messages').doc('m1'), {
        'senderId': uid,
        'receiverId': omar,
        'text': 'Hi Omar! Booked Thursday at 10:00 — is gear included or '
            'should I bring my own bar?',
        'createdAt': Timestamp.fromDate(_hoursAgo(50)),
        'read': false,
        seedMarker: true,
      }),
      _createIfAbsent(thread.collection('messages').doc('m3'), {
        'senderId': uid,
        'receiverId': omar,
        'text': 'Perfect. Forecast says 18 knots, does that sound right to you?',
        'createdAt': Timestamp.fromDate(_hoursAgo(48)),
        'read': false,
        seedMarker: true,
      }),
      _createIfAbsent(thread.collection('messages').doc('m5'), {
        'senderId': uid,
        'receiverId': omar,
        'text': 'See you Thursday 🤙',
        'createdAt': Timestamp.fromDate(_hoursAgo(5)),
        'read': false,
        seedMarker: true,
      }),

      // A mix of read and unread so the badge and the "mark all read" action
      // both have something to act on.
      _createIfAbsent(
        notifications.doc('seed-notif-lina-1'),
        _notification(
            targetUserId: uid,
            title: 'Omar confirmed your session',
            message: '${_day(2)} at 10:00, El Gouna north lagoon.',
            type: 'booking_confirmed',
            read: false,
            hoursAgo: 26,
            bookingId: 'seed-lina-omar-next'),
      ),
      _createIfAbsent(
        notifications.doc('seed-notif-lina-2'),
        _notification(
            targetUserId: uid,
            title: 'Message from Omar Farouk',
            message: 'See you at the north lagoon, 09:45 so we can rig early.',
            type: 'message',
            read: false,
            hoursAgo: 4),
      ),
      _createIfAbsent(
        notifications.doc('seed-notif-lina-3'),
        _notification(
            targetUserId: uid,
            title: 'Session tomorrow',
            message: 'Your lesson with Omar Farouk starts at 10:00.',
            type: 'reminder',
            read: true,
            hoursAgo: 30,
            bookingId: 'seed-lina-omar-next'),
      ),
      _createIfAbsent(
        notifications.doc('seed-notif-lina-4'),
        _notification(
            targetUserId: uid,
            title: 'Yannick could not take your request',
            message: 'He was already booked for that window.',
            type: 'booking_rejected',
            read: true,
            hoursAgo: 24 * 9,
            bookingId: 'seed-lina-yannick-rejected'),
      ),
    ]);
  });

  await asUser(emailRider2, 'Tomas Novak (rider)', (uid) async {
    final bookings = db.collection('bookings');
    final reviews = db.collection('reviews');
    final notifications = db.collection('notifications');
    final threadId = ChatThread.idFor(uid, sofia);
    final thread = db.collection('chats').doc(threadId);

    await thread.set({
      'participants': [uid, sofia]..sort(),
      'participantNames': {uid: 'Tomas Novak', sofia: 'Sofia Ricci'},
      seedMarker: true,
    }, SetOptions(merge: true));

    return countWrites([
      _createIfAbsent(
        bookings.doc('seed-tomas-sofia-past'),
        _lesson('seed-tomas-sofia-past',
            instructorId: sofia,
            instructorName: 'Sofia Ricci',
            riderId: uid,
            riderName: 'Tomas Novak',
            riderLevel: 'Advanced',
            date: _day(-25),
            startHour: 12,
            hours: 2,
            rate: 95,
            status: 'completed',
            title: 'Freestyle coaching',
            checkedIn: true,
            createdDaysAgo: 30,
            paymentStatus: 'paid'),
      ),
      _createIfAbsent(
        bookings.doc('seed-tomas-omar-past'),
        _lesson('seed-tomas-omar-past',
            instructorId: omar,
            instructorName: 'Omar Farouk',
            riderId: uid,
            riderName: 'Tomas Novak',
            riderLevel: 'Advanced',
            date: _day(-40),
            startHour: 15,
            hours: 1,
            rate: 80,
            status: 'completed',
            checkedIn: true,
            createdDaysAgo: 44,
            // No payment fields at all — the shape of every booking written
            // before payments were tracked. It must show no pill and count
            // as nothing owed.
            paymentStatus: null),
      ),
      // Cancelled by the rider — the other end of the history list.
      _createIfAbsent(
        bookings.doc('seed-tomas-omar-cancelled'),
        _lesson('seed-tomas-omar-cancelled',
            instructorId: omar,
            instructorName: 'Omar Farouk',
            riderId: uid,
            riderName: 'Tomas Novak',
            riderLevel: 'Advanced',
            date: _day(-30),
            startHour: 13,
            hours: 1,
            rate: 80,
            status: 'cancelled',
            createdDaysAgo: 35),
      ),
      _createIfAbsent(
        bookings.doc('seed-tomas-yannick-next'),
        _lesson('seed-tomas-yannick-next',
            instructorId: yannick,
            instructorName: 'Yannick Weber',
            riderId: uid,
            riderName: 'Tomas Novak',
            riderLevel: 'Advanced',
            date: _day(5),
            startHour: 14,
            hours: 2,
            rate: 70,
            status: 'confirmed',
            createdDaysAgo: 2),
      ),
      // A seat on Omar's expedition — the only booking of type 'safari', and
      // the one that exercises the trip card instead of the hour grid.
      _createIfAbsent(bookings.doc('seed-tomas-safari'), {
        'id': 'seed-tomas-safari',
        'instructorId': omar,
        'instructorName': 'Omar Farouk',
        'kiterId': uid,
        'studentName': 'Tomas Novak',
        'studentLevel': 'Rider',
        'tripId': 'seed-trip-shukeir',
        'tripTitle': 'Ras Shukeir downwinder',
        'listingTitle': 'Expedition: Ras Shukeir downwinder',
        'date': _day(9),
        'durationHours': 0,
        'totalPrice': 240,
        'type': 'safari',
        'gearNeeded': false,
        'message': '',
        'status': 'confirmed',
        'checkedIn': false,
        'createdAt': Timestamp.fromDate(_daysAgo(6)),
        seedMarker: true,
      }),

      _createIfAbsent(reviews.doc('seed-review-tomas-sofia'), {
        'trainerId': sofia,
        'userId': uid,
        'userName': 'Tomas Novak',
        'rating': 5,
        'comment': 'The video review afterwards is worth the price on its own. '
            'Finally saw what my back leg was doing.',
        'bookingId': 'seed-tomas-sofia-past',
        'createdAt': Timestamp.fromDate(_daysAgo(24)),
        seedMarker: true,
      }),
      _createIfAbsent(reviews.doc('seed-review-tomas-omar'), {
        'trainerId': omar,
        'userId': uid,
        'userName': 'Tomas Novak',
        'rating': 5,
        'comment': 'Booked an hour to fix one thing, fixed it in forty minutes.',
        'bookingId': 'seed-tomas-omar-past',
        'createdAt': Timestamp.fromDate(_daysAgo(39)),
        seedMarker: true,
      }),

      _createIfAbsent(thread.collection('messages').doc('m1'), {
        'senderId': uid,
        'receiverId': sofia,
        'text': 'Sofia — any chance of a foil session next week?',
        'createdAt': Timestamp.fromDate(_hoursAgo(30)),
        'read': false,
        seedMarker: true,
      }),
      _createIfAbsent(thread.collection('messages').doc('m3'), {
        'senderId': uid,
        'receiverId': sofia,
        'text': 'Thursday works. 1200 wing sounds right for my weight.',
        'createdAt': Timestamp.fromDate(_hoursAgo(28)),
        'read': false,
        seedMarker: true,
      }),

      _createIfAbsent(
        notifications.doc('seed-notif-tomas-1'),
        _notification(
            targetUserId: uid,
            title: 'Yannick confirmed your session',
            message: '${_day(5)} at 14:00, Safaga.',
            type: 'booking_confirmed',
            read: true,
            hoursAgo: 40,
            bookingId: 'seed-tomas-yannick-next'),
      ),
      _createIfAbsent(
        notifications.doc('seed-notif-tomas-2'),
        _notification(
            targetUserId: uid,
            title: 'Your seat is held',
            message: 'Ras Shukeir downwinder — meet at the marina 07:00.',
            type: 'booking_confirmed',
            read: false,
            hoursAgo: 12,
            bookingId: 'seed-tomas-safari'),
      ),
    ]);
  });

  // Marta (rider3) is intentionally left with nothing — see her note in
  // seed_data.dart. An account with no history is the only way to see what a
  // first-run user actually sees.
  say('Leaving Marta Kowalska empty on purpose — she is the empty-state test.',
      SeedLevel.info);

  // ── Pass 2: trainers ───────────────────────────────────────────────────
  // Calendar blocks, time off, the expedition, and the trainer half of each
  // conversation.

  await asUser(emailTrainer1, 'Omar Farouk (trainer)', (uid) async {
    final availability = db.collection('availability');
    final vacations = db.collection('vacations');
    final trips = db.collection('safari_trips');
    final notifications = db.collection('notifications');
    final threadId = ChatThread.idFor(lina, uid);
    final thread = db.collection('chats').doc(threadId);

    final n = await countWrites([
      // Blocks sit clear of Lina's 10:00–12:00 booking on day+2 so the grid
      // shows both "Booked" and "Unavailable" on one day.
      _createIfAbsent(availability.doc('seed-block-omar-1'), {
        'instructorId': uid,
        'date': _day(1),
        'startTime': '12:00',
        'endTime': '14:00',
        'status': 'host-blocked',
        'label': 'Gear service',
        'createdAt': Timestamp.fromDate(_daysAgo(3)),
        seedMarker: true,
      }),
      _createIfAbsent(availability.doc('seed-block-omar-2'), {
        'instructorId': uid,
        'date': _day(2),
        'startTime': '15:00',
        'endTime': '18:00',
        'status': 'host-blocked',
        'label': 'Centre shift',
        'createdAt': Timestamp.fromDate(_daysAgo(3)),
        seedMarker: true,
      }),
      _createIfAbsent(vacations.doc('seed-vacation-omar'), {
        'instructorId': uid,
        'startDate': _day(16),
        'endDate': _day(18),
        'label': 'Gear fair, Cologne',
        'createdAt': Timestamp.fromDate(_daysAgo(8)),
        seedMarker: true,
      }),
      _createIfAbsent(trips.doc('seed-trip-shukeir'), {
        'hostId': uid,
        'title': 'Ras Shukeir downwinder',
        'startDate': _day(9),
        'price': 240,
        'capacity': 8,
        // Tomas holds one of these three.
        'bookedSeats': 3,
        'status': 'open',
        'duration': 'Full day',
        'description': '35 km downwind run with a chase boat, lunch on the '
            'beach at the halfway point. Independent riders only.',
        'createdAt': Timestamp.fromDate(_daysAgo(12)),
        seedMarker: true,
      }),
      _createIfAbsent(thread.collection('messages').doc('m2'), {
        'senderId': uid,
        'receiverId': lina,
        'text': 'Hey Lina 🤙 Gear is included — just bring a rash guard and '
            'plenty of sunscreen.',
        'createdAt': Timestamp.fromDate(_hoursAgo(49)),
        'read': false,
        seedMarker: true,
      }),
      _createIfAbsent(thread.collection('messages').doc('m4'), {
        'senderId': uid,
        'receiverId': lina,
        'text': 'Closer to 22 by the afternoon. The morning is calmer, which '
            'is better for the transitions we talked about.',
        'createdAt': Timestamp.fromDate(_hoursAgo(47)),
        'read': false,
        seedMarker: true,
      }),
      _createIfAbsent(thread.collection('messages').doc('m6'), {
        'senderId': uid,
        'receiverId': lina,
        'text': 'See you at the north lagoon — 09:45 so we can rig early.',
        'createdAt': Timestamp.fromDate(_hoursAgo(4)),
        'read': false,
        seedMarker: true,
      }),
      _createIfAbsent(
        notifications.doc('seed-notif-omar-1'),
        _notification(
            targetUserId: uid,
            title: 'New booking request',
            message: 'Lina Hassan — ${_day(2)}, 10:00–12:00.',
            type: 'booking_request',
            read: false,
            hoursAgo: 72,
            bookingId: 'seed-lina-omar-next'),
      ),
    ]);

    // The thread summary reflects the last message, which is Omar's — so it
    // has to be written from this side. Lina is left with one unread.
    await thread.set({
      'lastMessage': 'See you at the north lagoon — 09:45 so we can rig early.',
      'lastMessageAt': Timestamp.fromDate(_hoursAgo(4)),
      'unreadCount': {lina: 1, uid: 0},
    }, SetOptions(merge: true));

    return n;
  });

  await asUser(emailTrainer2, 'Sofia Ricci (trainer)', (uid) async {
    final availability = db.collection('availability');
    final vacations = db.collection('vacations');
    final notifications = db.collection('notifications');
    final threadId = ChatThread.idFor(tomas, uid);
    final thread = db.collection('chats').doc(threadId);

    final n = await countWrites([
      _createIfAbsent(availability.doc('seed-block-sofia-1'), {
        'instructorId': uid,
        'date': _day(3),
        'startTime': '08:00',
        'endTime': '10:00',
        'status': 'host-blocked',
        'label': 'Boat prep',
        'createdAt': Timestamp.fromDate(_daysAgo(2)),
        seedMarker: true,
      }),
      // Three days away — the booking grid should refuse the whole range with
      // "Away", which outranks every other blocked reason (§5.3).
      _createIfAbsent(vacations.doc('seed-vacation-sofia'), {
        'instructorId': uid,
        'startDate': _day(6),
        'endDate': _day(8),
        'label': 'Italy — family wedding',
        'createdAt': Timestamp.fromDate(_daysAgo(20)),
        seedMarker: true,
      }),
      _createIfAbsent(thread.collection('messages').doc('m2'), {
        'senderId': uid,
        'receiverId': tomas,
        'text': 'Sì! Tuesday or Thursday, both at 12:00. I will bring the '
            '1200 wing for you.',
        'createdAt': Timestamp.fromDate(_hoursAgo(29)),
        'read': false,
        seedMarker: true,
      }),
      _createIfAbsent(
        notifications.doc('seed-notif-sofia-1'),
        _notification(
            targetUserId: uid,
            title: 'New booking request',
            message: 'Lina Hassan — foil intro, ${_day(4)}, 12:00–15:00.',
            type: 'booking_request',
            read: false,
            hoursAgo: 20,
            bookingId: 'seed-lina-sofia-pending'),
      ),
    ]);

    await thread.set({
      'lastMessage': 'Thursday works. 1200 wing sounds right for my weight.',
      'lastMessageAt': Timestamp.fromDate(_hoursAgo(28)),
      'unreadCount': {tomas: 0, uid: 1},
    }, SetOptions(merge: true));

    return n;
  });

  await asUser(emailTrainer3, 'Yannick Weber (trainer)', (uid) async {
    final availability = db.collection('availability');
    return countWrites([
      _createIfAbsent(availability.doc('seed-block-yannick-1'), {
        'instructorId': uid,
        'date': _day(5),
        'startTime': '08:00',
        'endTime': '11:00',
        'status': 'host-blocked',
        'label': 'School group',
        'createdAt': Timestamp.fromDate(_daysAgo(4)),
        seedMarker: true,
      }),
    ]);
  });

  // ── Pass 3: the station ────────────────────────────────────────────────
  // A station's instructors and services live in subcollections under its own
  // user document, and the rules only let the station itself write them —
  // hence its own pass.

  await asUser(emailStation1, 'Gouna Kite Centre (station)', (uid) async {
    final instructors = db
        .collection('users')
        .doc(uid)
        .collection('station_instructors');
    final services =
        db.collection('users').doc(uid).collection('station_services');

    return countWrites([
      // Lessons tab.
      _createIfAbsent(instructors.doc('seed-si-1'), {
        'name': 'Hassan Nour',
        'level': 'IKO Level 3',
        'rate': 85,
        seedMarker: true,
      }),
      _createIfAbsent(instructors.doc('seed-si-2'), {
        'name': 'Petra Novotná',
        'level': 'IKO Level 2',
        'rate': 75,
        seedMarker: true,
      }),
      _createIfAbsent(instructors.doc('seed-si-3'), {
        // No rate — the card falls back to FlowConst.defaultDisplayRate.
        'name': 'Sam Whitfield',
        'level': 'Assistant',
        seedMarker: true,
      }),

      // Rentals tab.
      _createIfAbsent(services.doc('seed-sv-1'), {
        'name': 'Full kite set (kite, bar, board)',
        'kind': 'rental',
        'price': 60,
        'unit': 'day',
        'description': 'Duotone 2025 range, sizes 7–14m. Harness included.',
        seedMarker: true,
      }),
      _createIfAbsent(services.doc('seed-sv-2'), {
        'name': 'Twin tip only',
        'kind': 'rental',
        'price': 25,
        'unit': 'day',
        seedMarker: true,
      }),
      _createIfAbsent(services.doc('seed-sv-3'), {
        'name': 'Foil board',
        'kind': 'rental',
        'price': 45,
        'unit': 'day',
        'description': 'Includes a 1200 and a 1700 wing.',
        seedMarker: true,
      }),
      _createIfAbsent(services.doc('seed-sv-4'), {
        'name': 'Wetsuit (3/2mm)',
        'kind': 'rental',
        'price': 10,
        'unit': 'day',
        seedMarker: true,
      }),

      // Beach tab.
      _createIfAbsent(services.doc('seed-sv-5'), {
        'name': 'Beach day pass',
        'kind': 'beach_use',
        'price': 15,
        'unit': 'day',
        'description': 'Sunbed, freshwater rinse, storage rack and showers.',
        seedMarker: true,
      }),
      _createIfAbsent(services.doc('seed-sv-6'), {
        'name': 'Weekly storage',
        'kind': 'beach_use',
        'price': 40,
        'unit': 'week',
        'description': 'Locked rack for your own gear.',
        seedMarker: true,
      }),
      _createIfAbsent(services.doc('seed-sv-7'), {
        'name': 'Rescue boat assist',
        'kind': 'beach_use',
        'price': 20,
        'unit': 'call-out',
        seedMarker: true,
      }),
    ]);
  });

  // ── Pass 4: the safari operator ────────────────────────────────────────

  await asUser(emailSafari1, 'Red Sea Downwind Co. (safari)', (uid) async {
    final trips = db.collection('safari_trips');
    return countWrites([
      _createIfAbsent(trips.doc('seed-trip-3day'), {
        'hostId': uid,
        'title': 'Three-day southern downwinder',
        'startDate': _day(14),
        'price': 640,
        'capacity': 10,
        'bookedSeats': 4,
        'status': 'open',
        'duration': '3 days',
        'description': 'Hurghada to Marsa Alam over three days, sleeping on '
            'the boat. Chase boat, cook and a spare kite for every rider.',
        'createdAt': Timestamp.fromDate(_daysAgo(20)),
        seedMarker: true,
      }),
      // Sold out — the "Manifest full" state and a maxed fill bar.
      _createIfAbsent(trips.doc('seed-trip-full'), {
        'hostId': uid,
        'title': 'Gubal Island day trip',
        'startDate': _day(7),
        'price': 180,
        'capacity': 6,
        'bookedSeats': 6,
        'status': 'full',
        'duration': 'Full day',
        'description': 'Flat water inside the reef, deep water outside it.',
        'createdAt': Timestamp.fromDate(_daysAgo(18)),
        seedMarker: true,
      }),
      // Uncapped — capacity 0 means "no limit" everywhere else, so this is
      // the case that once wrongly read as full on its first booking.
      _createIfAbsent(trips.doc('seed-trip-open'), {
        'hostId': uid,
        'title': 'Sunset downwinder (weekly)',
        'startDate': _day(21),
        'price': 95,
        'capacity': 0,
        'bookedSeats': 2,
        'status': 'open',
        'duration': '3 hours',
        'description': 'Short evening run down the coast. Independent riders.',
        'createdAt': Timestamp.fromDate(_daysAgo(9)),
        seedMarker: true,
      }),
    ]);
  });

  // ── Pass 5: ratings spread ─────────────────────────────────────────────
  // Without this every coach shows the unrated 5.0 default (§8.10) and the
  // Explore grid is a column of identical numbers — useless for judging how
  // the rating actually reads. Each of these riders leaves one review, so the
  // averages land between 3.0 and 5.0.
  //
  // These reviews carry no bookingId: the seeder writes them directly, which
  // the rules permit (they pin authorship and the 1–5 range, nothing more).
  // In the app a review requires a completed booking, and that eligibility
  // check is client-side — so the review composer still behaves correctly.

  const spread = <(String riderEmail, String coachEmail, int rating, String)>[
    (emailRider4, emailTrainer4, 5, 'مدرب ممتاز وصبور جدًا. أنصح به.'),
    (emailRider5, emailTrainer5, 4,
        'Knows everything, says most of it. Bring a notebook.'),
    (emailRider6, emailTrainer5, 5, 'Best coaching I have had anywhere.'),
    (emailRider7, emailTrainer6, 3,
        'Fine session, but turned up twenty minutes late and never said why.'),
    (emailRider8, emailTrainer7, 5, 'Took me from nervous to riding in two days.'),
    (emailRider9, emailTrainer8, 4, 'Good technique work. Gear is getting old.'),
    (emailRider4, emailTrainer9, 5, 'Flying on the foil by session three, as promised.'),
    (emailRider8, emailStation1, 4, 'Well run centre. Rentals are new and clean.'),
    (emailRider9, emailStation1, 5, 'The flat white is genuinely good.'),
    (emailRider5, emailSafari1, 5, 'Three days I will be talking about for years.'),
  ];

  for (final (riderEmail, coachEmail, rating, comment) in spread) {
    final coachUid = uids[coachEmail];
    if (coachUid == null) continue;
    final riderName = seedAccounts
        .firstWhere((a) => a.email == riderEmail,
            orElse: () => seedAccounts.first)
        .name;
    await asUser(riderEmail, '$riderName (review)', (uid) async {
      final id = 'seed-review-${riderEmail.split('@').first}-'
          '${coachEmail.split('@').first}';
      return countWrites([
        _createIfAbsent(db.collection('reviews').doc(id), {
          'trainerId': coachUid,
          'userId': uid,
          'userName': riderName,
          'rating': rating,
          'comment': comment,
          'createdAt': Timestamp.fromDate(_daysAgo(3 + rating)),
          seedMarker: true,
        }),
      ]);
    });
  }

  say('', SeedLevel.info);
  say('Activity: $written written, $skipped already existed.', SeedLevel.ok);
}
