// Pumps a real screen with a real provider graph on top of an in-memory
// Firestore.
//
// Screen tests in this repo used to be impossible to write cheaply: every
// screen watches four or five derived providers, and overriding them one by
// one is both laborious and a lie — it tests the screen against data shapes
// the app never produces. Overriding `firestoreProvider` instead means the
// repositories, the derived providers and the buckets all run for real, and
// the only fakes are the database and who is signed in.
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flow/core/theme/app_theme.dart';
import 'package:flow/data/firestore_paths.dart';
import 'package:flow/data/models/app_user.dart';
import 'package:flow/providers/providers.dart';
import 'package:flow/providers/settings_provider.dart';
import 'package:flow/services/wind_service.dart';

/// The signed-in rider every rider screen is pumped as.
const rider = AppUser(
  uid: 'u_rider',
  name: 'Seif Ahmed',
  email: 'seif@example.com',
  role: UserRole.kiter,
  status: AccountStatus.active,
  level: 'Independent',
  nationality: 'Egyptian',
  favorites: ['u_trainer'],
);

/// The signed-in trainer every trainer screen is pumped as.
const trainer = AppUser(
  uid: 'u_trainer',
  name: 'Anna Bergström',
  email: 'anna@example.com',
  role: UserRole.business,
  status: AccountStatus.active,
  location: 'Soma Bay',
  bio: 'Freestyle and foil coaching. Video analysis after every session.',
  languages: ['Italian', 'English'],
  ikoId: 'IKO-0ZMVF2',
  hourlyRate: 95,
);

/// A station — the screen the reported overlap was found on.
const station = AppUser(
  uid: 'u_station',
  name: 'Safaga Watersports',
  email: 'station@example.com',
  role: UserRole.business,
  status: AccountStatus.active,
  location: 'Safaga',
  bio: 'Small centre, big lagoon. Gear is new this season.',
  businessType: 'Station',
  hourlyRate: 68,
);

/// A station whose name and location are long enough to push the header
/// layout — the shape that turns a near-miss into a collision.
const wideStation = AppUser(
  uid: 'u_station_wide',
  name: 'Hurghada–Magawish Kite & Watersports Centre',
  email: 'wide@example.com',
  role: UserRole.business,
  status: AccountStatus.active,
  location: 'Hurghada-Magawish Village Road',
  businessType: 'Safari operator',
);

Map<String, dynamic> _userDoc(AppUser u) => {
      'name': u.name,
      'email': u.email,
      'role': switch (u.role) {
        UserRole.business => 'business',
        UserRole.admin => 'admin',
        UserRole.support => 'support',
        _ => 'kiter',
      },
      'status': 'active',
      if (u.location != null) 'location': u.location,
      if (u.bio != null) 'bio': u.bio,
      if (u.businessType != null) 'businessType': u.businessType,
      if (u.ikoId != null) 'ikoId': u.ikoId,
      if (u.hourlyRate != null) 'hourlyRate': u.hourlyRate,
      if (u.level != null) 'level': u.level,
      if (u.nationality != null) 'nationality': u.nationality,
      'languages': u.languages,
      'favorites': u.favorites,
    };

/// A database with one of everything a screen can render.
///
/// Deliberately *populated* rather than empty: an empty screen is the easy
/// case and the one least likely to collide. Where a screen has a materially
/// different empty state, the test seeds a second, bare database.
Future<FakeFirebaseFirestore> seededDb({bool withStationDetail = true}) async {
  final db = FakeFirebaseFirestore();

  for (final u in [rider, trainer, station, wideStation]) {
    await db.collection(Col.users).doc(u.uid).set(_userDoc(u));
  }

  if (withStationDetail) {
    await db
        .collection(Col.users)
        .doc(station.uid)
        .collection(Col.stationInstructors)
        .doc('i1')
        .set({'name': 'Youssef Nabil', 'level': 'Senior', 'rate': 60});
    await db
        .collection(Col.users)
        .doc(station.uid)
        .collection(Col.stationServices)
        .doc('s1')
        .set({
      'name': 'Twin-tip + bar',
      'kind': 'rental',
      'price': 45,
      'unit': 'day',
      'description': 'Board, bar, lines and a spare leash.',
    });
    await db
        .collection(Col.users)
        .doc(station.uid)
        .collection(Col.stationServices)
        .doc('s2')
        .set({'name': 'Day pass', 'kind': 'beach_use', 'price': 12});
    await db.collection(Col.safariTrips).doc('t1').set({
      'hostId': wideStation.uid,
      'title': 'Sunset downwinder along the Gubal Strait',
      'startDate': '2099-08-29',
      'price': 95,
      'capacity': 8,
      'bookedSeats': 6,
      'duration': '6 hours',
      'description': 'Boat support the whole way, gear carried for you.',
    });
  }

  // One booking in each state the rider and trainer screens branch on.
  await db.collection(Col.bookings).doc('b_pending').set({
    'instructorId': trainer.uid,
    'instructorName': trainer.name,
    'kiterId': rider.uid,
    'studentName': rider.name,
    'listingTitle': 'Kitesurf lesson',
    'date': '2099-08-29',
    'startTime': '10:00',
    'endTime': '12:00',
    'selectedTimes': ['10:00', '11:00'],
    'durationHours': 2,
    'totalPrice': 190,
    'status': 'pending',
    'message': 'First time on a foil — happy to start slow.',
    'gearNeeded': true,
    'paymentStatus': 'unpaid',
    'amountDue': 190,
  });
  await db.collection(Col.bookings).doc('b_confirmed').set({
    'instructorId': trainer.uid,
    'instructorName': trainer.name,
    'kiterId': rider.uid,
    'studentName': rider.name,
    'listingTitle': 'Expedition: Sunset downwinder (weekly)',
    'date': '2099-08-29',
    'startTime': '14:00',
    'endTime': '15:00',
    'durationHours': 1,
    'totalPrice': 95,
    'status': 'confirmed',
    'paymentStatus': 'unpaid',
    'amountDue': 95,
  });
  await db.collection(Col.bookings).doc('b_done').set({
    'instructorId': trainer.uid,
    'instructorName': trainer.name,
    'kiterId': rider.uid,
    'studentName': rider.name,
    'listingTitle': 'Kitesurf lesson',
    'date': '2020-03-01',
    'startTime': '09:00',
    'durationHours': 1,
    'totalPrice': 80,
    'status': 'completed',
    'paymentStatus': 'unpaid',
    'amountDue': 80,
  });

  await db.collection(Col.reviews).doc('r1').set({
    'trainerId': trainer.uid,
    'userId': rider.uid,
    'userName': rider.name,
    'rating': 5,
    'comment': 'Patient, clear, and the video analysis afterwards is gold.',
  });

  await db.collection(Col.notifications).doc('n1').set({
    'targetUserId': rider.uid,
    'title': 'Booking approved ✅',
    'message': 'Your session on Sat 29 Aug is confirmed.',
    'type': 'booking_confirmed',
    'read': false,
    'bookingId': 'b_confirmed',
  });

  return db;
}

/// A [WindService] that cannot reach the network, so every screen renders its
/// no-forecast shape. Wind rendering itself is covered by the component suite.
WindService _offlineWind() => WindService(clientFactory: _DeadClient.new);

class _DeadClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isSetter ||
        invocation.memberName.toString().contains('close')) {
      return null;
    }
    throw Exception('offline in tests');
  }
}

/// Pumps [screen] inside the full app scaffolding at a given size, theme and
/// text scale.
///
/// `pumpAndSettle` is never used: the skeletons and the live dot animate
/// forever, so it would hang rather than fail — the same reason the on-device
/// walkthrough pumps against a wall clock.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  required FakeFirebaseFirestore db,
  AppUser as = rider,
  Size size = const Size(360, 780),
  bool dark = true,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => screen),
  ]);
  addTearDown(router.dispose);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      windServiceProvider.overrideWithValue(_offlineWind()),
      currentUidProvider.overrideWithValue(as.uid),
      currentUserProvider.overrideWith((ref) => Stream.value(as)),
      sessionProvider.overrideWithValue(
          Session(stage: AppStage.ready, user: as)),
    ],
    child: MaterialApp.router(
      theme: dark ? FlowTheme.dark() : FlowTheme.light(),
      routerConfig: router,
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: child!,
      ),
    ),
  ));

  // Let the Firestore streams deliver and the entry animations finish, without
  // waiting for the ones that never do.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}
