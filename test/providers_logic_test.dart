// The gate state machine and the derived booking/trainer providers.
//
// sessionProvider's evaluation order IS the spec (§2.3) — eight numbered
// checks whose precedence decides who sees the app. Nothing else asserts it:
// the router only consumes the result, and a reordering that, say, let a
// blocked trainer reach `ready` would look completely normal in every widget
// test. Each stage gets a test named for the person it gates.
//
// The Firebase `User` is faked through `noSuchMethod` — only `uid` is ever
// read by this layer. Streams are overridden per test and settled with
// `container.read(provider.future)` before the synchronous gate is read.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/utils/date_x.dart';
import 'package:flow/data/models/app_user.dart';
import 'package:flow/data/models/booking.dart';
import 'package:flow/data/models/payment.dart';
import 'package:flow/providers/providers.dart';

class _FakeUser implements User {
  _FakeUser(this.uid);
  @override
  final String uid;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('session layer should only read uid');
}

AppUser appUser({
  UserRole role = UserRole.kiter,
  AccountStatus status = AccountStatus.active,
  String? blockedUntil,
  List<String> favorites = const [],
  String name = 'Seif',
  String? location,
  String? bio,
  List<String> languages = const [],
  String uid = 'u1',
}) =>
    AppUser(
      uid: uid,
      name: name,
      email: 'x@y.z',
      role: role,
      status: status,
      blockedUntilRaw: blockedUntil,
      favorites: favorites,
      location: location,
      bio: bio,
      languages: languages,
    );

void main() {
  late ProviderContainer container;

  ProviderContainer build({
    Stream<User?>? auth,
    Stream<AppUser?>? profile,
    Stream<List<Booking>>? riderBookings,
    Stream<List<Booking>>? trainerBookings,
    Stream<List<AppUser>>? trainers,
  }) {
    container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => auth ?? const Stream.empty()),
      currentUserProvider
          .overrideWith((ref) => profile ?? const Stream.empty()),
      if (riderBookings != null)
        riderBookingsProvider.overrideWith((ref) => riderBookings),
      if (trainerBookings != null)
        trainerBookingsProvider.overrideWith((ref) => trainerBookings),
      if (trainers != null)
        activeTrainersProvider.overrideWith((ref) => trainers),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  // Riverpod 3 pauses a provider with no active listeners, so a bare
  // `read(p.future)` on an overridden StreamProvider never subscribes to the
  // stream and waits forever. Settling = listen (unpause), then await the
  // first value; the subscription is held to test end so the cached value
  // stays warm for the synchronous derived reads.
  Future<void> settle<T>(ProviderContainer c, StreamProvider<T> p) async {
    final sub = c.listen<AsyncValue<T>>(p, (_, _) {});
    addTearDown(sub.close);
    await c.read(p.future);
  }

  Future<AppStage> stageWith({Stream<User?>? auth, Stream<AppUser?>? profile}) async {
    final c = build(auth: auth, profile: profile);
    if (auth != null) await settle(c, authStateProvider);
    if (profile != null) await settle(c, currentUserProvider);
    return c.read(sessionProvider).stage;
  }

  final user = _FakeUser('u1');

  group('sessionProvider — the §2.3 precedence', () {
    test('1. nothing known yet → loading', () async {
      expect(await stageWith(), AppStage.loading);
    });

    test('2. no Firebase user → signedOut', () async {
      expect(await stageWith(auth: Stream.value(null)), AppStage.signedOut);
    });

    test('3. signed in, profile still streaming → loading', () async {
      expect(await stageWith(auth: Stream.value(user)), AppStage.loading);
    });

    test('4. no profile document, or an unknown role → chooseRole', () async {
      expect(
          await stageWith(
              auth: Stream.value(user), profile: Stream.value(null)),
          AppStage.chooseRole);
      expect(
          await stageWith(
              auth: Stream.value(user),
              profile: Stream.value(appUser(role: UserRole.unknown))),
          AppStage.chooseRole);
    });

    test('5. blocked forever → blocked', () async {
      expect(
          await stageWith(
              auth: Stream.value(user),
              profile: Stream.value(appUser(
                  status: AccountStatus.blocked, blockedUntil: 'forever'))),
          AppStage.blocked);
    });

    test('5. blocked with a malformed date fails closed → blocked', () async {
      expect(
          await stageWith(
              auth: Stream.value(user),
              profile: Stream.value(appUser(
                  status: AccountStatus.blocked, blockedUntil: 'tuesday'))),
          AppStage.blocked);
    });

    test('5. a lapsed suspension releases on its own (§2.4)', () async {
      expect(
          await stageWith(
              auth: Stream.value(user),
              profile: Stream.value(appUser(
                  status: AccountStatus.blocked,
                  blockedUntil: '2000-01-01T00:00:00Z'))),
          AppStage.ready,
          reason: 'the user cannot rewrite their own status — the gate must');
    });

    test('6. trainer pending → awaitingApproval; staff pending bypasses',
        () async {
      expect(
          await stageWith(
              auth: Stream.value(user),
              profile: Stream.value(appUser(
                  role: UserRole.business, status: AccountStatus.pending))),
          AppStage.awaitingApproval);
      expect(
          await stageWith(
              auth: Stream.value(user),
              profile: Stream.value(appUser(
                  role: UserRole.admin, status: AccountStatus.pending))),
          AppStage.staff,
          reason: 'staff never wait for approval — they grant it');
    });

    test('6b. every staff role lands in the console, not the marketplace',
        () async {
      // An admin account is a console account. It has no rider level, no
      // trainer calendar and no bookings, so `ready` gave it a bottom bar of
      // destinations that were empty by construction — and, worse, an
      // Explore tab whose "book this trainer" button wrote a booking under a
      // staff uid.
      for (final role in [UserRole.admin, UserRole.support]) {
        expect(
            await stageWith(
                auth: Stream.value(user),
                profile: Stream.value(appUser(role: role))),
            AppStage.staff,
            reason: '$role');
      }
    });

    test('6c. a suspended admin is still suspended', () async {
      // Order matters: the block gate is evaluated before the staff gate, so
      // a compromised or misbehaving staff account can be shut out the same
      // way anyone else can.
      expect(
          await stageWith(
              auth: Stream.value(user),
              profile: Stream.value(appUser(
                  role: UserRole.admin,
                  status: AccountStatus.blocked,
                  blockedUntil: 'forever'))),
          AppStage.blocked);
    });

    test('7. rejected trainer gets a real gate, not a ghost Command Center',
        () async {
      expect(
          await stageWith(
              auth: Stream.value(user),
              profile: Stream.value(appUser(
                  role: UserRole.business, status: AccountStatus.rejected))),
          AppStage.rejected);
    });

    test('8. an active kiter is simply ready', () async {
      expect(
          await stageWith(
              auth: Stream.value(user), profile: Stream.value(appUser())),
          AppStage.ready);
    });
  });

  group('rider buckets', () {
    Booking b(String id,
            {String date = '2099-06-15',
            BookingStatus status = BookingStatus.confirmed,
            String? startTime,
            bool hiddenByGuest = false,
            bool hiddenByInstructor = false}) =>
        Booking(
          id: id,
          date: date,
          status: status,
          instructorId: 'i',
          instructorName: 'T',
          kiterId: 'k',
          studentName: 'R',
          startTime: startTime,
          hiddenByGuest: hiddenByGuest,
          hiddenByInstructor: hiddenByInstructor,
        );

    test('places, hides and sorts', () async {
      final c = build(riderBookings: Stream.value([
        b('later', startTime: '14:00'),
        b('sooner', startTime: '09:00'),
        // No startTime: `startsAt` is midnight of its day, so a date-only
        // booking (a safari) surfaces at the top of that day, ahead of every
        // timed lesson on it.
        b('untimed'),
        b('running', status: BookingStatus.inProgress),
        b('done', status: BookingStatus.completed),
        b('gone', status: BookingStatus.cancelled),
        b('hidden', hiddenByGuest: true),
        b('trainer-hid',
            startTime: '10:00', hiddenByInstructor: true), // rider sees it
      ]));
      await settle(c, riderBookingsProvider);
      final buckets = c.read(riderBucketsProvider).value!;

      expect([for (final x in buckets[BookingBucket.upcoming]!) x.id],
          ['untimed', 'sooner', 'trainer-hid', 'later'],
          reason: 'soonest first; the instructor’s hide is not the rider’s');
      expect([for (final x in buckets[BookingBucket.active]!) x.id],
          ['running']);
      expect([for (final x in buckets[BookingBucket.history]!) x.id],
          ['done', 'gone']);
    });
  });

  group('trainer day providers', () {
    Booking b(String id,
            {String? date,
            BookingStatus status = BookingStatus.confirmed,
            String? startTime,
            double? totalPrice,
            PaymentInfo payment = PaymentInfo.none}) =>
        Booking(
          id: id,
          date: date ?? todayYmd(),
          status: status,
          instructorId: 'i',
          instructorName: 'T',
          kiterId: 'k',
          studentName: 'R',
          startTime: startTime,
          totalPrice: totalPrice,
          payment: payment,
        );

    test('pending requests keep today and later, sorted by date', () async {
      final c = build(trainerBookings: Stream.value([
        b('old', date: '2000-01-01', status: BookingStatus.pending),
        b('later', date: '2099-01-02', status: BookingStatus.pending),
        b('soon', date: '2099-01-01', status: BookingStatus.pending),
        b('approved'),
      ]));
      await settle(c, trainerBookingsProvider);
      expect([for (final x in c.read(pendingRequestsProvider).value!) x.id],
          ['soon', 'later'],
          reason: 'expired requests and non-pending bookings drop out');
    });

    test('today’s manifest is live-only, ordered by start', () async {
      final c = build(trainerBookings: Stream.value([
        b('pm', startTime: '14:00'),
        b('am', startTime: '09:00'),
        b('tomorrow', date: '2099-01-01', startTime: '08:00'),
        b('done', status: BookingStatus.completed, startTime: '07:00'),
      ]));
      await settle(c, trainerBookingsProvider);
      expect([for (final x in c.read(todayManifestProvider).value!) x.id],
          ['am', 'pm']);
    });

    test('revenue counts work delivered; outstanding counts only tracked debt',
        () async {
      final c = build(trainerBookings: Stream.value([
        b('paid',
            status: BookingStatus.completed,
            totalPrice: 100,
            payment: const PaymentInfo(status: PaymentStatus.paid)),
        b('owed',
            status: BookingStatus.completed,
            totalPrice: 80,
            payment:
                const PaymentInfo(status: PaymentStatus.unpaid, amount: 95)),
        b('history', status: BookingStatus.completed, totalPrice: 60),
        b('future', totalPrice: 500),
      ]));
      await settle(c, trainerBookingsProvider);
      // P14: every trainer figure is take-home — net of FLOW's 20% fee and
      // based on the *captured* amount (`trainerEarning` ← `amountDue`), which
      // unifies revenue with outstanding/payout (they already used amountDue).
      // Revenue = 80% of (100 + 95 + 60) = 204: the 'owed' booking's captured
      // 95 wins over its listed 80, exactly as outstanding asserts below.
      // Membership is unchanged — the fee scales amounts, not which count.
      expect(c.read(trainerRevenueProvider).value, closeTo(204, 1e-9),
          reason: 'earned means delivered — unpaid history still counts, net');
      expect([for (final x in c.read(trainerUnpaidProvider).value!) x.id],
          ['owed'],
          reason: 'untracked history is not debt');
      expect(c.read(trainerOutstandingProvider).value, closeTo(76, 1e-9),
          reason: 'the captured amount wins over the listed price, net of fee');
    });
  });

  group('filteredTrainersProvider', () {
    final anna = appUser(
        uid: 'anna',
        name: 'Anna Berg',
        role: UserRole.business,
        location: 'Soma Bay',
        bio: 'Freestyle coaching',
        languages: ['German', 'English']);
    final omar = appUser(
        uid: 'omar',
        name: 'Omar Said',
        role: UserRole.business,
        location: 'El Gouna',
        bio: 'Wave specialist',
        languages: ['Arabic', 'English']);

    Future<List<String>> idsWith(
        void Function(ExploreFilterNotifier) configure,
        {List<String> favorites = const []}) async {
      final c = build(
        auth: Stream.value(user),
        profile: Stream.value(appUser(favorites: favorites)),
        trainers: Stream.value([anna, omar]),
      );
      await settle(c, currentUserProvider);
      await settle(c, activeTrainersProvider);
      configure(c.read(exploreFilterProvider.notifier));
      return [for (final t in c.read(filteredTrainersProvider).value!) t.uid];
    }

    test('search matches name, location and bio, case-insensitively',
        () async {
      expect(await idsWith((f) => f.setQuery('berg')), ['anna']);
      expect(await idsWith((f) => f.setQuery('gouna')), ['omar']);
      expect(await idsWith((f) => f.setQuery('WAVE')), ['omar']);
      expect(await idsWith((f) => f.setQuery('kite')), isEmpty);
    });

    test('spot narrows by location substring', () async {
      expect(await idsWith((f) => f.setSpot('soma')), ['anna']);
    });

    test('languages are an any-of, not an all-of', () async {
      expect(await idsWith((f) {
        f.toggleLanguage('German');
        f.toggleLanguage('Arabic');
      }), ['anna', 'omar']);
      // Toggling off restores the pool.
      expect(await idsWith((f) {
        f.toggleLanguage('German');
        f.toggleLanguage('German');
      }), ['anna', 'omar']);
    });

    test('favourites-only intersects with the profile', () async {
      expect(
          await idsWith((f) => f.setFavouritesOnly(true),
              favorites: ['omar']),
          ['omar']);
      expect(await idsWith((f) => f.setFavouritesOnly(true)), isEmpty);
    });

    test('the badge counts filters, never the search text', () {
      const f = ExploreFilter(
          query: 'anna', spot: 'Soma', languages: {'German'}, favouritesOnly: true);
      expect(f.activeCount, 3);
      expect(const ExploreFilter(query: 'anna').activeCount, 0);
    });
  });
}
