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
import '../data/models/report.dart';
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

// ── Infrastructure & repositories (§7.1) ─────────────────────────────────

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);
final firestoreProvider =
    Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);
final firebaseStorageProvider =
    Provider<FirebaseStorage>((ref) => FirebaseStorage.instance);

final authRepositoryProvider =
    Provider((ref) => AuthRepository(ref.watch(firebaseAuthProvider)));
final userRepositoryProvider =
    Provider((ref) => UserRepository(ref.watch(firestoreProvider)));
final notificationRepositoryProvider =
    Provider((ref) => NotificationRepository(ref.watch(firestoreProvider)));
final bookingRepositoryProvider = Provider((ref) => BookingRepository(
    ref.watch(firestoreProvider), ref.watch(notificationRepositoryProvider)));
final scheduleRepositoryProvider =
    Provider((ref) => ScheduleRepository(ref.watch(firestoreProvider)));
final reviewRepositoryProvider =
    Provider((ref) => ReviewRepository(ref.watch(firestoreProvider)));
final chatRepositoryProvider = Provider((ref) => ChatRepository(
    ref.watch(firestoreProvider), ref.watch(notificationRepositoryProvider)));
final supportRepositoryProvider =
    Provider((ref) => SupportRepository(ref.watch(firestoreProvider)));
final storageRepositoryProvider =
    Provider((ref) => StorageRepository(ref.watch(firebaseStorageProvider)));
final adminRepositoryProvider = Provider((ref) => AdminRepository(
    ref.watch(firestoreProvider), ref.watch(notificationRepositoryProvider)));

// ── Session — the gate state machine (§2.3, §7.2) ────────────────────────

final authStateProvider = StreamProvider<User?>(
    (ref) => ref.watch(authRepositoryProvider).authState());

final currentUidProvider =
    Provider<String?>((ref) => ref.watch(authStateProvider).value?.uid);

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
  ready,
}

class Session {
  const Session({
    required this.stage,
    this.user,
    this.firebaseUser,
  });

  final AppStage stage;
  final AppUser? user;
  final User? firebaseUser;

  bool get isTrainer => user?.isTrainer ?? false;
  bool get isStaff => user?.isStaff ?? false;

  String get uid => user?.uid ?? firebaseUser?.uid ?? '';

  String get displayName {
    final n = user?.name.trim();
    if (n != null && n.isNotEmpty) return n;
    final fn = firebaseUser?.displayName?.trim();
    if (fn != null && fn.isNotEmpty) return fn;
    return 'Rider';
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
        stage: AppStage.chooseRole, user: user, firebaseUser: firebaseUser);
  }

  // 5. blocked
  if (user.status == AccountStatus.blocked) {
    return Session(
        stage: AppStage.blocked, user: user, firebaseUser: firebaseUser);
  }

  // 6. trainer pending approval (staff bypass)
  if (!user.isStaff &&
      user.isTrainer &&
      user.status == AccountStatus.pending) {
    return Session(
        stage: AppStage.awaitingApproval,
        user: user,
        firebaseUser: firebaseUser);
  }

  // 7. trainer whose application was declined.
  //
  // v2.6 let `rejected` fall through to `ready` (§2.4/§14.3): the trainer got
  // a full Command Center while being invisible in Explore, so they could
  // manage a calendar nobody could book. That was latent because nothing in
  // the app could set the status — now the admin console can, so it is a
  // real state and gets a real gate.
  if (!user.isStaff &&
      user.isTrainer &&
      user.status == AccountStatus.rejected) {
    return Session(
        stage: AppStage.rejected, user: user, firebaseUser: firebaseUser);
  }

  // 8. ready
  return Session(stage: AppStage.ready, user: user, firebaseUser: firebaseUser);
});

// ── Explore (§7.3, §8.8) ─────────────────────────────────────────────────

final activeTrainersProvider = StreamProvider<List<AppUser>>(
    (ref) => ref.watch(userRepositoryProvider).watchActiveTrainers());

final ratingsProvider = StreamProvider<Map<String, RatingSummary>>(
    (ref) => ref.watch(reviewRepositoryProvider).watchAllRatings());

final trainerReviewsProvider = StreamProvider.family<List<Review>, String>(
    (ref, trainerId) =>
        ref.watch(reviewRepositoryProvider).watchForTrainer(trainerId));

/// Also used for stations.
final trainerProfileProvider = StreamProvider.family<AppUser?, String>(
    (ref, uid) => ref.watch(userRepositoryProvider).watchUser(uid));

final stationInstructorsProvider =
    StreamProvider.family<List<StationInstructor>, String>((ref, id) =>
        ref.watch(userRepositoryProvider).watchStationInstructors(id));

final stationServicesProvider =
    StreamProvider.family<List<StationService>, String>((ref, id) =>
        ref.watch(userRepositoryProvider).watchStationServices(id));

final safariTripsProvider = StreamProvider.family<List<SafariTrip>, String>(
    (ref, hostId) => ref.watch(userRepositoryProvider).watchSafariTrips(hostId));

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
  }) =>
      ExploreFilter(
        query: query ?? this.query,
        spot: spot != null ? spot() : this.spot,
        languages: languages ?? this.languages,
        favouritesOnly: favouritesOnly ?? this.favouritesOnly,
      );
}

final exploreFilterProvider =
    NotifierProvider<ExploreFilterNotifier, ExploreFilter>(
        ExploreFilterNotifier.new);

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

  void setFavouritesOnly(bool v) =>
      state = state.copyWith(favouritesOnly: v);

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
                (t.location ?? '')
                    .toLowerCase()
                    .contains(filter.spot!.toLowerCase())) &&
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
    (ref, id) => ref.watch(bookingRepositoryProvider).watchBooking(id));

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

final riderBucketsProvider = Provider<AsyncValue<BookingBuckets>>((ref) => ref
    .watch(riderBookingsProvider)
    .whenData((list) => _bucketize(list, forInstructor: false)));

final trainerBucketsProvider = Provider<AsyncValue<BookingBuckets>>((ref) =>
    ref
        .watch(trainerBookingsProvider)
        .whenData((list) => _bucketize(list, forInstructor: true)));

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

final trainerCompletedProvider = Provider<AsyncValue<List<Booking>>>((ref) =>
    ref.watch(trainerBookingsProvider).whenData((list) => [
          for (final b in list)
            if (b.status == BookingStatus.completed) b,
        ]));

final trainerRevenueProvider = Provider<AsyncValue<double>>((ref) =>
    ref.watch(trainerCompletedProvider).whenData((list) =>
        list.fold<double>(0, (acc, b) => acc + (b.totalPrice ?? 0))));

final trainerMonthRevenueProvider = Provider<AsyncValue<double>>((ref) {
  final ym = thisMonthYm();
  return ref.watch(trainerCompletedProvider).whenData((list) =>
      list.where((b) => b.date.startsWith(ym)).fold<double>(
          0, (acc, b) => acc + (b.totalPrice ?? 0)));
});

// ── Availability (§7.5) ──────────────────────────────────────────────────

typedef DayKey = ({String instructorId, String date});

/// Merges three Firestore streams (blocks, day bookings, vacations) and emits
/// only once **all three** have produced a value, then on every change.
/// autoDispose cancels subscriptions and resets the has-value flags, so a
/// re-listen never accumulates dead subscriptions.
final dayAvailabilityProvider =
    StreamProvider.autoDispose.family<DayAvailability, DayKey>((ref, key) {
  final schedule = ref.watch(scheduleRepositoryProvider);
  final bookings = ref.watch(bookingRepositoryProvider);

  final controller = StreamController<DayAvailability>();
  List<Availability>? blocks;
  List<Booking>? dayBookings;
  List<Vacation>? vacations;

  void emit() {
    if (blocks == null || dayBookings == null || vacations == null) return;
    controller.add(DayAvailability.compose(
      date: key.date,
      blocks: blocks!,
      bookings: dayBookings!,
      vacations: vacations!,
    ));
  }

  final subs = [
    schedule.watchDayBlocks(key.instructorId, key.date).listen((v) {
      blocks = v;
      emit();
    }, onError: controller.addError),
    bookings.watchDayBookings(key.instructorId, key.date).listen((v) {
      dayBookings = v;
      emit();
    }, onError: controller.addError),
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
final dayBlocksProvider =
    StreamProvider.autoDispose.family<List<Availability>, DayKey>((ref, key) =>
        ref
            .watch(scheduleRepositoryProvider)
            .watchDayBlocks(key.instructorId, key.date));

final myVacationsProvider = StreamProvider<List<Vacation>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(scheduleRepositoryProvider).watchVacations(uid);
});

/// One instructor's time off, for the booking day strip. `watchVacations`
/// has no date filter, so this is the *same* query `dayAvailabilityProvider`
/// already runs — Firestore serves both listeners from one subscription, so
/// flagging away days across the strip costs no extra reads.
final instructorVacationsProvider =
    StreamProvider.autoDispose.family<List<Vacation>, String>((ref, id) =>
        ref.watch(scheduleRepositoryProvider).watchVacations(id));

// ── Notifications & chat (§7.3, §8.11) ───────────────────────────────────

final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(notificationRepositoryProvider).watchFor(uid);
});

final unreadNotificationCountProvider = Provider<int>((ref) =>
    ref
        .watch(notificationsProvider)
        .value
        ?.where((n) => !n.read)
        .length ??
    0);

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
    (ref, chatId) => ref.watch(chatRepositoryProvider).watchMessages(chatId));

// ── Support (§7.3) ───────────────────────────────────────────────────────

final myTicketsProvider = StreamProvider<List<SupportTicket>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(supportRepositoryProvider).watchMyTickets(uid);
});

final ticketProvider = StreamProvider.family<SupportTicket?, String>(
    (ref, id) => ref.watch(supportRepositoryProvider).watchTicket(id));

final ticketMessagesProvider = StreamProvider.family<List<TicketMessage>, String>(
    (ref, id) => ref.watch(supportRepositoryProvider).watchTicketMessages(id));

final myAppealProvider = StreamProvider<Appeal?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(supportRepositoryProvider).watchMyAppeal(uid);
});

// ── Admin (staff only) ───────────────────────────────────────────────────
//
// autoDispose so these collection listeners are torn down when staff leave
// the console — a rider or trainer should never be holding them open.

final pendingTrainersProvider =
    StreamProvider.autoDispose<List<AppUser>>((ref) {
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

/// Badge for the Profile entry point: work waiting on staff.
final adminQueueCountProvider = Provider.autoDispose<int>((ref) {
  final trainers = ref.watch(pendingTrainersProvider).value?.length ?? 0;
  final reports = ref.watch(reportsProvider).value?.where((r) => r.isOpen).length ?? 0;
  final appeals = ref
          .watch(appealsProvider)
          .value
          ?.where((a) => a.status == 'pending')
          .length ??
      0;
  return trainers + reports + appeals;
});
