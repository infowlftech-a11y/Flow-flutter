import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/date_x.dart';
import '../data/models/app_user.dart';
import '../data/models/booking.dart';
import '../data/models/catalogue.dart';
import '../data/models/schedule.dart';
import '../data/models/social.dart';
import '../data/models/support.dart';
import '../data/models/audit.dart';
import '../data/models/report.dart';
import '../data/models/wind.dart';
import '../data/repositories/admin_repository.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/booking_repository.dart';
import '../data/repositories/chat_repository.dart';
import '../data/repositories/notification_repository.dart';
import '../data/repositories/review_repository.dart';
import '../data/repositories/schedule_repository.dart';
import '../data/repositories/storage_repository.dart';
import '../data/repositories/support_repository.dart';
import '../data/repositories/user_repository.dart';
import '../services/wind_service.dart';

// ── Infrastructure & repositories (§7.1) ─────────────────────────────────

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);
final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);
final firebaseStorageProvider = Provider<FirebaseStorage>(
  (ref) => FirebaseStorage.instance,
);

final authRepositoryProvider = Provider(
  (ref) => AuthRepository(ref.watch(firebaseAuthProvider)),
);
final userRepositoryProvider = Provider(
  (ref) => UserRepository(ref.watch(firestoreProvider)),
);
final notificationRepositoryProvider = Provider(
  (ref) => NotificationRepository(ref.watch(firestoreProvider)),
);
final bookingRepositoryProvider = Provider(
  (ref) => BookingRepository(
    ref.watch(firestoreProvider),
    ref.watch(notificationRepositoryProvider),
  ),
);
final scheduleRepositoryProvider = Provider(
  (ref) => ScheduleRepository(ref.watch(firestoreProvider)),
);
final reviewRepositoryProvider = Provider(
  (ref) => ReviewRepository(
    ref.watch(firestoreProvider),
    ref.watch(notificationRepositoryProvider),
  ),
);
final chatRepositoryProvider = Provider(
  (ref) => ChatRepository(
    ref.watch(firestoreProvider),
    ref.watch(notificationRepositoryProvider),
  ),
);
final supportRepositoryProvider = Provider(
  (ref) => SupportRepository(
    ref.watch(firestoreProvider),
    ref.watch(notificationRepositoryProvider),
  ),
);
final storageRepositoryProvider = Provider(
  (ref) => StorageRepository(ref.watch(firebaseStorageProvider)),
);
final adminRepositoryProvider = Provider(
  (ref) => AdminRepository(
    ref.watch(firestoreProvider),
    ref.watch(notificationRepositoryProvider),
  ),
);

// ── Session — the gate state machine (§2.3, §7.2) ────────────────────────

final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(authRepositoryProvider).authState(),
);

final currentUidProvider = Provider<String?>(
  (ref) => ref.watch(authStateProvider).value?.uid,
);

/// Sign-out, with this device's push token released first (§11.3).
///
/// Every sign-out goes through here rather than calling
/// `authRepository.signOut()` directly. A token is bound to the *device*, not
/// the account, so one left behind on the old profile keeps delivering that
/// user's notifications to whoever signs in next. The clear has to happen
/// while the session is still alive — afterwards the rules reject the write —
/// and it is best-effort: a failed clear must never strand someone in an
/// account they are trying to leave.
final signOutProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    final uid = ref.read(currentUidProvider);
    if (uid != null) {
      try {
        await ref.read(userRepositoryProvider).clearFcmToken(uid);
      } catch (_) {
        // Offline, or the profile is already gone. Sign out regardless.
      }
    }
    await ref.read(authRepositoryProvider).signOut();
  },
);

/// The profile document is **streamed, not fetched once** — approval or a
/// block moves the app immediately, with no restart.
final currentUserProvider = StreamProvider<AppUser?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(userRepositoryProvider).watchUser(uid);
});

enum AppStage {
  loading,
  signedOut,
  chooseRole,
  blocked,
  awaitingApproval,
  rejected,

  /// An admin, owner or support account: the console, and nothing else.
  ///
  /// Staff used to resolve to [ready] and got the rider's app with an extra
  /// row in Settings. That is not a smaller problem than it sounds: the shell
  /// gave them Explore, Sessions and a Ticket tab that were empty by
  /// construction — a staff account has no bookings — and Explore's booking
  /// button would happily write a booking under a staff uid, creating a
  /// rider who does not exist and a session nobody will teach. The console is
  /// the whole app for these accounts.
  staff,

  ready,
}

class Session {
  const Session({required this.stage, this.user, this.firebaseUser});

  final AppStage stage;
  final AppUser? user;
  final User? firebaseUser;

  bool get isTrainer => user?.isTrainer ?? false;
  bool get isStaff => user?.isStaff ?? false;

  String get uid => user?.uid ?? firebaseUser?.uid ?? '';

  /// The user's real name, or empty when nobody has told us one yet.
  ///
  /// Registration no longer asks for a name, so between sign-up and the
  /// onboarding form this is genuinely blank. Anywhere that *prefills an
  /// input* must use this rather than [displayName]: seeding the onboarding
  /// name field with the "Rider" placeholder would put a fake name one tap
  /// away from being saved as the real one.
  String get knownName {
    final n = user?.name.trim();
    if (n != null && n.isNotEmpty) return n;
    final fn = firebaseUser?.displayName?.trim();
    if (fn != null && fn.isNotEmpty) return fn;
    return '';
  }

  /// For display only — falls back to a neutral placeholder.
  String get displayName {
    final known = knownName;
    return known.isEmpty ? 'Rider' : known;
  }
}

/// Collapses auth + profile into one [AppStage]. **Evaluation order matters**
/// — this is the exact precedence from §2.3.
final sessionProvider = Provider<Session>((ref) {
  final auth = ref.watch(authStateProvider);

  // 1. auth stream loading
  if (auth.isLoading && !auth.hasValue) {
    return const Session(stage: AppStage.loading);
  }
  final firebaseUser = auth.value;

  // 2. no Firebase user
  if (firebaseUser == null) return const Session(stage: AppStage.signedOut);

  final profile = ref.watch(currentUserProvider);

  // 3. profile stream loading
  if (profile.isLoading && !profile.hasValue) {
    return Session(stage: AppStage.loading, firebaseUser: firebaseUser);
  }
  final user = profile.value;

  // 4. profile missing OR role unknown → onboarding
  if (user == null || user.role == UserRole.unknown) {
    return Session(
      stage: AppStage.chooseRole,
      user: user,
      firebaseUser: firebaseUser,
    );
  }

  // 5. blocked — only while the ban is actually in force. §2.4 requires a
  // lapsed suspension to release the user automatically, and the blocked
  // screen's ticker invalidates this stream expecting exactly that. Gating
  // on `status` alone made every timed suspension permanent, because the
  // rules forbid the user from clearing their own status and only a manual
  // admin unblock ever rewrites it.
  if (user.status == AccountStatus.blocked && user.isBlockInForce) {
    return Session(
      stage: AppStage.blocked,
      user: user,
      firebaseUser: firebaseUser,
    );
  }

  // 6. staff — the console is their entire app.
  //
  // Placed after the block gate so a suspended staff account is still
  // suspended, and before the approval gates so a staff member is never held
  // in a queue they are the one who empties.
  if (user.isStaff) {
    return Session(
      stage: AppStage.staff,
      user: user,
      firebaseUser: firebaseUser,
    );
  }

  // 7. trainer pending approval
  if (user.isTrainer && user.status == AccountStatus.pending) {
    return Session(
      stage: AppStage.awaitingApproval,
      user: user,
      firebaseUser: firebaseUser,
    );
  }

  // 8. trainer whose application was declined.
  //
  // v2.6 let `rejected` fall through to `ready` (§2.4/§14.3): the trainer got
  // a full Command Center while being invisible in Explore, so they could
  // manage a calendar nobody could book. That was latent because nothing in
  // the app could set the status — now the admin console can, so it is a
  // real state and gets a real gate.
  if (user.isTrainer && user.status == AccountStatus.rejected) {
    return Session(
      stage: AppStage.rejected,
      user: user,
      firebaseUser: firebaseUser,
    );
  }

  // 9. ready
  return Session(stage: AppStage.ready, user: user, firebaseUser: firebaseUser);
});

// ── Explore (§7.3, §8.8) ─────────────────────────────────────────────────

final activeTrainersProvider = StreamProvider<List<AppUser>>(
  (ref) => ref.watch(userRepositoryProvider).watchActiveTrainers(),
);

final ratingsProvider = StreamProvider<Map<String, RatingSummary>>(
  (ref) => ref.watch(reviewRepositoryProvider).watchAllRatings(),
);

final trainerReviewsProvider = StreamProvider.family<List<Review>, String>(
  (ref, trainerId) =>
      ref.watch(reviewRepositoryProvider).watchForTrainer(trainerId),
);

/// Also used for stations.
final trainerProfileProvider = StreamProvider.family<AppUser?, String>(
  (ref, uid) => ref.watch(userRepositoryProvider).watchUser(uid),
);

final stationInstructorsProvider =
    StreamProvider.family<List<StationInstructor>, String>(
      (ref, id) =>
          ref.watch(userRepositoryProvider).watchStationInstructors(id),
    );

final stationServicesProvider =
    StreamProvider.family<List<StationService>, String>(
      (ref, id) => ref.watch(userRepositoryProvider).watchStationServices(id),
    );

final safariTripsProvider = StreamProvider.family<List<SafariTrip>, String>(
  (ref, hostId) => ref.watch(userRepositoryProvider).watchSafariTrips(hostId),
);

class ExploreFilter {
  const ExploreFilter({
    this.query = '',
    this.spot,
    this.languages = const {},
    this.favouritesOnly = false,
  });

  final String query;
  final String? spot;
  final Set<String> languages;
  final bool favouritesOnly;

  /// The filter badge counts spot + each language + favourites — **not** the
  /// search text, which has its own field (§8.8).
  int get activeCount =>
      (spot != null ? 1 : 0) + languages.length + (favouritesOnly ? 1 : 0);

  ExploreFilter copyWith({
    String? query,
    String? Function()? spot,
    Set<String>? languages,
    bool? favouritesOnly,
  }) => ExploreFilter(
    query: query ?? this.query,
    spot: spot != null ? spot() : this.spot,
    languages: languages ?? this.languages,
    favouritesOnly: favouritesOnly ?? this.favouritesOnly,
  );
}

final exploreFilterProvider =
    NotifierProvider<ExploreFilterNotifier, ExploreFilter>(
      ExploreFilterNotifier.new,
    );

class ExploreFilterNotifier extends Notifier<ExploreFilter> {
  @override
  ExploreFilter build() => const ExploreFilter();

  void setQuery(String q) => state = state.copyWith(query: q);
  void setSpot(String? spot) => state = state.copyWith(spot: () => spot);
  void toggleLanguage(String lang) {
    final langs = {...state.languages};
    langs.contains(lang) ? langs.remove(lang) : langs.add(lang);
    state = state.copyWith(languages: langs);
  }

  void setFavouritesOnly(bool v) => state = state.copyWith(favouritesOnly: v);

  void reset() => state = const ExploreFilter();
}

/// active trainers ∩ filter ∩ favourites — order of checks per §8.8.
final filteredTrainersProvider = Provider<AsyncValue<List<AppUser>>>((ref) {
  final trainers = ref.watch(activeTrainersProvider);
  final filter = ref.watch(exploreFilterProvider);
  final favorites = ref.watch(currentUserProvider).value?.favorites ?? const [];

  return trainers.whenData((list) {
    final q = filter.query.trim().toLowerCase();
    return [
      for (final t in list)
        if ((!filter.favouritesOnly || favorites.contains(t.uid)) &&
            (q.isEmpty ||
                '${t.name} ${t.location ?? ''} ${t.bio ?? ''}'
                    .toLowerCase()
                    .contains(q)) &&
            (filter.spot == null ||
                (t.location ?? '').toLowerCase().contains(
                  filter.spot!.toLowerCase(),
                )) &&
            (filter.languages.isEmpty ||
                t.languages.any(filter.languages.contains)))
          t,
    ];
  });
});

// ── Bookings (§7.3, §8.7) ────────────────────────────────────────────────

final riderBookingsProvider = StreamProvider<List<Booking>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(bookingRepositoryProvider).watchRiderBookings(uid);
});

final trainerBookingsProvider = StreamProvider<List<Booking>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(bookingRepositoryProvider).watchTrainerBookings(uid);
});

final bookingByIdProvider = StreamProvider.family<Booking?, String>(
  (ref, id) => ref.watch(bookingRepositoryProvider).watchBooking(id),
);

typedef BookingBuckets = Map<BookingBucket, List<Booking>>;

BookingBuckets _bucketize(List<Booking> source, {required bool forInstructor}) {
  final now = DateTime.now();
  final buckets = <BookingBucket, List<Booking>>{
    BookingBucket.upcoming: [],
    BookingBucket.active: [],
    BookingBucket.history: [],
  };
  for (final b in source) {
    if (forInstructor ? b.hiddenByInstructor : b.hiddenByGuest) continue;
    buckets[b.bucket(now)]!.add(b);
  }
  // Upcoming and active soonest first; history keeps source order (§8.7).
  int soonest(Booking a, Booking b) =>
      (a.startsAt ?? DateTime(2100)).compareTo(b.startsAt ?? DateTime(2100));
  buckets[BookingBucket.upcoming]!.sort(soonest);
  buckets[BookingBucket.active]!.sort(soonest);
  return buckets;
}

final riderBucketsProvider = Provider<AsyncValue<BookingBuckets>>(
  (ref) => ref
      .watch(riderBookingsProvider)
      .whenData((list) => _bucketize(list, forInstructor: false)),
);

final trainerBucketsProvider = Provider<AsyncValue<BookingBuckets>>(
  (ref) => ref
      .watch(trainerBookingsProvider)
      .whenData((list) => _bucketize(list, forInstructor: true)),
);

final pendingRequestsProvider = Provider<AsyncValue<List<Booking>>>((ref) {
  final today = todayYmd();
  return ref.watch(trainerBookingsProvider).whenData((list) {
    final pending = [
      for (final b in list)
        if (b.status == BookingStatus.pending && b.date.compareTo(today) >= 0)
          b,
    ];
    pending.sort((a, b) => a.date.compareTo(b.date));
    return pending;
  });
});

final todayManifestProvider = Provider<AsyncValue<List<Booking>>>((ref) {
  final today = todayYmd();
  return ref.watch(trainerBookingsProvider).whenData((list) {
    final manifest = [
      for (final b in list)
        if (b.date == today && b.status.isLive) b,
    ];
    manifest.sort((a, b) => (a.startTime ?? '').compareTo(b.startTime ?? ''));
    return manifest;
  });
});

final trainerCompletedProvider = Provider<AsyncValue<List<Booking>>>(
  (ref) => ref
      .watch(trainerBookingsProvider)
      .whenData(
        (list) => [
          for (final b in list)
            if (b.status == BookingStatus.completed) b,
        ],
      ),
);

// Every trainer-facing money figure is the trainer's *take-home* — net of
// FLOW's platform commission (P14, `Booking.trainerEarning`). The rider still
// pays the full price everywhere it is shown to them (profile rate, booking,
// receipt); only what the trainer earns is the 80%.
final trainerRevenueProvider = Provider<AsyncValue<double>>(
  (ref) => ref
      .watch(trainerCompletedProvider)
      .whenData(
        (list) => list.fold<double>(0, (acc, b) => acc + b.trainerEarning),
      ),
);

final trainerMonthRevenueProvider = Provider<AsyncValue<double>>((ref) {
  final ym = thisMonthYm();
  return ref
      .watch(trainerCompletedProvider)
      .whenData(
        (list) => list
            .where((b) => b.date.startsWith(ym))
            .fold<double>(0, (acc, b) => acc + b.trainerEarning),
      );
});

/// Completed sessions the trainer has not been paid for.
///
/// Deliberately *not* subtracted from [trainerRevenueProvider]: "earned" has
/// always meant work delivered, and silently redefining it as "cash in hand"
/// would drop every historical session — none of which carry payment data —
/// out of a number trainers already know. This is an additional figure, and
/// it only ever counts bookings that explicitly say they are owing.
final trainerUnpaidProvider = Provider<AsyncValue<List<Booking>>>(
  (ref) => ref
      .watch(trainerCompletedProvider)
      .whenData(
        (list) => [
          for (final b in list)
            if (b.payment.isOutstanding) b,
        ],
      ),
);

final trainerOutstandingProvider = Provider<AsyncValue<double>>(
  (ref) => ref
      .watch(trainerUnpaidProvider)
      .whenData(
        (list) => list.fold<double>(0, (acc, b) => acc + b.trainerEarning),
      ),
);

/// What FLOW owes the trainer for delivered escrow sessions (P1) — the
/// riders already paid; the payout waits on the processor. Kept apart from
/// [trainerOutstandingProvider], which is cash a *rider* still owes: one is
/// something the trainer can act on (collect), the other is FLOW's debt.
final trainerPayoutDueProvider = Provider<AsyncValue<double>>(
  (ref) => ref
      .watch(trainerCompletedProvider)
      .whenData(
        (list) => list
            .where((b) => b.awaitsPayout)
            .fold<double>(0, (acc, b) => acc + b.trainerEarning),
      ),
);

/// A week of earnings, Monday-first, plus how it compares with the week before.
///
/// Monday-first because that is what a working week means to a centre taking
/// bookings, not because of any locale setting — the seven buckets have to
/// line up with the seven labels under the chart, and a shifting first day
/// would silently re-label every bar.
typedef EarningsWeek = ({
  /// Seven totals, `[Mon … Sun]`. Days with no completed session are 0.
  List<double> byWeekday,
  double total,

  /// Fractional change against the previous seven days: `.18` is +18%.
  ///
  /// **Null when the previous week earned nothing.** A percentage change from
  /// zero is not infinity and it is not 100% — it is undefined, and printing
  /// "+100%" for a first week of trading is a flattering lie. The UI shows
  /// nothing rather than inventing a comparison.
  double? deltaVsPrevious,

  /// Index into [byWeekday] for today, or null when today is outside the
  /// window. Drives which bar is highlighted.
  int? todayIndex,
});

/// Monday 00:00 of the week containing [from].
DateTime _weekStart(DateTime from) {
  final d = DateTime(from.year, from.month, from.day);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}

final trainerEarningsWeekProvider = Provider<AsyncValue<EarningsWeek>>((ref) {
  final now = DateTime.now();
  final start = _weekStart(now);
  final previousStart = start.subtract(const Duration(days: 7));

  return ref.watch(trainerCompletedProvider).whenData((list) {
    final week = List<double>.filled(7, 0);
    var previous = 0.0;

    for (final b in list) {
      final day = parseYmd(b.date);
      // A booking whose stored date will not parse is skipped rather than
      // bucketed into Monday — the same tolerance every other reader applies
      // (§10.7), and a silent misattribution here would be money in the
      // wrong column.
      if (day == null) continue;
      final amount = b.trainerEarning;

      if (!day.isBefore(start)) {
        final index = day.difference(start).inDays;
        if (index >= 0 && index < 7) week[index] += amount;
      } else if (!day.isBefore(previousStart)) {
        previous += amount;
      }
    }

    final total = week.fold<double>(0, (a, b) => a + b);
    final todayOffset = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(start).inDays;

    return (
      byWeekday: week,
      total: total,
      deltaVsPrevious: previous > 0 ? (total - previous) / previous : null,
      todayIndex: todayOffset >= 0 && todayOffset < 7 ? todayOffset : null,
    );
  });
});

// ── Availability (§7.5) ──────────────────────────────────────────────────

typedef DayKey = ({String instructorId, String date});

/// Merges three Firestore streams (blocks, day bookings, vacations) and emits
/// only once **all three** have produced a value, then on every change.
/// autoDispose cancels subscriptions and resets the has-value flags, so a
/// re-listen never accumulates dead subscriptions.
final dayAvailabilityProvider = StreamProvider.autoDispose.family<DayAvailability, DayKey>((
  ref,
  key,
) {
  final schedule = ref.watch(scheduleRepositoryProvider);
  final bookings = ref.watch(bookingRepositoryProvider);

  final controller = StreamController<DayAvailability>();
  List<Availability>? blocks;
  List<Booking>? dayBookings;
  List<Vacation>? vacations;

  void emit() {
    if (blocks == null || dayBookings == null || vacations == null) return;
    controller.add(
      DayAvailability.compose(
        date: key.date,
        blocks: blocks!,
        bookings: dayBookings!,
        vacations: vacations!,
      ),
    );
  }

  final subs = [
    schedule.watchDayBlocks(key.instructorId, key.date).listen((v) {
      blocks = v;
      emit();
    }, onError: controller.addError),
    bookings
        .watchDayBookings(key.instructorId, key.date)
        .listen(
          (v) {
            dayBookings = v;
            emit();
          },
          onError: (Object e, StackTrace st) {
            // Bookings are readable only by their own two parties (BUG-017), so
            // for anyone who is not this trainer (or staff) this stream is refused
            // wholesale. That is not an error for the grid: the same hours arrive
            // as `occupied` availability docs in the blocks stream, which is what
            // they exist for. A denial therefore reports "no bookings visible"
            // rather than killing the composed stream — but only a denial;
            // anything else is still a failure the grid must show.
            if (e is FirebaseException && e.code == 'permission-denied') {
              dayBookings = const [];
              emit();
            } else {
              controller.addError(e, st);
            }
          },
        ),
    schedule.watchVacations(key.instructorId).listen((v) {
      vacations = v;
      emit();
    }, onError: controller.addError),
  ];

  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
    controller.close();
  });

  return controller.stream;
});

/// Raw day blocks — the schedule tab needs doc ids to release blocks.
final dayBlocksProvider = StreamProvider.autoDispose
    .family<List<Availability>, DayKey>(
      (ref, key) => ref
          .watch(scheduleRepositoryProvider)
          .watchDayBlocks(key.instructorId, key.date),
    );

final myVacationsProvider = StreamProvider<List<Vacation>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(scheduleRepositoryProvider).watchVacations(uid);
});

/// One instructor's time off, for the booking day strip. `watchVacations`
/// has no date filter, so this is the *same* query `dayAvailabilityProvider`
/// already runs — Firestore serves both listeners from one subscription, so
/// flagging away days across the strip costs no extra reads.
final instructorVacationsProvider = StreamProvider.autoDispose
    .family<List<Vacation>, String>(
      (ref, id) => ref.watch(scheduleRepositoryProvider).watchVacations(id),
    );

// ── Wind (§3.6) ──────────────────────────────────────────────────────────

final windServiceProvider = Provider<WindService>((ref) => WindService());

/// The forecast for one spot.
///
/// Not autoDispose: the service caches for 30 minutes anyway, and keeping the
/// provider alive means moving between a trainer's profile and their booking
/// screen reuses the same numbers instead of showing a second spinner over
/// data that is already in memory.
final windForecastProvider = FutureProvider.family<WindForecast, String>(
  (ref, spot) => ref.watch(windServiceProvider).forSpot(spot),
);

/// The forecast at whichever spot a provider teaches from.
///
/// Resolves the spot from the trainer's profile rather than asking the caller
/// for it, so the booking screen does not have to thread a location through
/// [BookingTarget] — which is transient and deliberately knows nothing about
/// the profile behind it (§5.5).
final providerWindProvider = FutureProvider.family<WindForecast, String>((
  ref,
  providerId,
) async {
  final profile = await ref.watch(trainerProfileProvider(providerId).future);
  final spot = profile?.location ?? profile?.homeSpot;
  if (spot == null || spot.isEmpty) return WindForecast.empty;
  return ref.watch(windForecastProvider(spot).future);
});

// ── Notifications & chat (§7.3, §8.11) ───────────────────────────────────

final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(notificationRepositoryProvider).watchFor(uid);
});

final unreadNotificationCountProvider = Provider<int>(
  (ref) =>
      ref.watch(notificationsProvider).value?.where((n) => !n.read).length ?? 0,
);

final inboxProvider = StreamProvider<List<ChatThread>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(chatRepositoryProvider).watchInbox(uid);
});

/// Σ unreadFor(me) — badges the Inbox tab (§8.11).
final unreadChatCountProvider = Provider<int>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return 0;
  final threads = ref.watch(inboxProvider).value ?? const <ChatThread>[];
  return threads.fold<int>(0, (acc, t) => acc + t.unreadFor(uid));
});

final chatMessagesProvider = StreamProvider.family<List<ChatMessage>, String>(
  (ref, chatId) => ref.watch(chatRepositoryProvider).watchMessages(chatId),
);

// ── Support (§7.3) ───────────────────────────────────────────────────────

final myTicketsProvider = StreamProvider<List<SupportTicket>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(supportRepositoryProvider).watchMyTickets(uid);
});

final ticketProvider = StreamProvider.family<SupportTicket?, String>(
  (ref, id) => ref.watch(supportRepositoryProvider).watchTicket(id),
);

final ticketMessagesProvider =
    StreamProvider.family<List<TicketMessage>, String>(
      (ref, id) => ref.watch(supportRepositoryProvider).watchTicketMessages(id),
    );

final myAppealProvider = StreamProvider<Appeal?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(supportRepositoryProvider).watchMyAppeal(uid);
});

// ── Admin (staff only) ───────────────────────────────────────────────────
//
// autoDispose so these collection listeners are torn down when staff leave
// the console — a rider or trainer should never be holding them open.

final pendingTrainersProvider = StreamProvider.autoDispose<List<AppUser>>((
  ref,
) {
  if (!ref.watch(sessionProvider).isStaff) return Stream.value(const []);
  return ref.watch(adminRepositoryProvider).watchPendingTrainers();
});

final blockedUsersProvider = StreamProvider.autoDispose<List<AppUser>>((ref) {
  if (!ref.watch(sessionProvider).isStaff) return Stream.value(const []);
  return ref.watch(adminRepositoryProvider).watchBlockedUsers();
});

final reportsProvider = StreamProvider.autoDispose<List<Report>>((ref) {
  if (!ref.watch(sessionProvider).isStaff) return Stream.value(const []);
  return ref.watch(adminRepositoryProvider).watchReports();
});

final appealsProvider = StreamProvider.autoDispose<List<Appeal>>((ref) {
  if (!ref.watch(sessionProvider).isStaff) return Stream.value(const []);
  return ref.watch(adminRepositoryProvider).watchAppeals();
});

/// The accountability trail (P6) — staff-only, like every console stream.
final auditLogProvider = StreamProvider.autoDispose<List<AuditEntry>>((ref) {
  if (!ref.watch(sessionProvider).isStaff) return Stream.value(const []);
  return ref.watch(adminRepositoryProvider).watchAuditLog();
});

final allTicketsProvider = StreamProvider.autoDispose<List<SupportTicket>>((
  ref,
) {
  if (!ref.watch(sessionProvider).isStaff) return Stream.value(const []);
  return ref.watch(supportRepositoryProvider).watchAllTickets();
});

final leaveReasonsProvider = StreamProvider.autoDispose<List<LeaveReason>>((
  ref,
) {
  if (!ref.watch(sessionProvider).isStaff) return Stream.value(const []);
  return ref.watch(adminRepositoryProvider).watchLeaveReasons();
});

/// Every account on the platform — the console's directory (§3.15).
final allUsersProvider = StreamProvider.autoDispose<List<AppUser>>((ref) {
  if (!ref.watch(sessionProvider).isStaff) return Stream.value(const []);
  return ref.watch(userRepositoryProvider).watchAllUsers();
});

/// Every booking on the platform — the console's sessions view (§3.15).
///
/// The staff gate here is not decoration: for anyone else the unfiltered
/// query is *rejected by the rules*, and an error stream would poison the
/// console shell for a non-staff account that somehow watched it.
final allBookingsProvider = StreamProvider.autoDispose<List<Booking>>((ref) {
  if (!ref.watch(sessionProvider).isStaff) return Stream.value(const []);
  return ref.watch(bookingRepositoryProvider).watchAllBookings();
});

/// Work waiting on staff, across every queue the console owns.
final adminQueueCountProvider = Provider.autoDispose<int>((ref) {
  final trainers = ref.watch(pendingTrainersProvider).value?.length ?? 0;
  final reports =
      ref.watch(reportsProvider).value?.where((r) => r.isOpen).length ?? 0;
  final appeals =
      ref
          .watch(appealsProvider)
          .value
          ?.where((a) => a.status == 'pending')
          .length ??
      0;
  final tickets =
      ref.watch(allTicketsProvider).value?.where((t) => t.isOpen).length ?? 0;
  return trainers + reports + appeals + tickets;
});
