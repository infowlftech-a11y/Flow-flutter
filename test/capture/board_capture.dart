// Renders every screen to a PNG so they can actually be looked at.
//
// Not named `*_test.dart`, so a bare `flutter test` skips it. Run it directly:
//
//     flutter test test/capture/board_capture.dart
//
// It asserts almost nothing — a green run only means every screen *built*.
// The output is the point: `.impeccable/review/*.png`, one file per screen per
// text scale, rendered through the real provider graph over an in-memory
// Firestore (see test/support/screen_harness.dart).
//
// Two things silently ruin the output:
//   - Fonts must be loaded explicitly or flutter_test paints Ahem, and every
//     glyph becomes a filled box. Material Symbols must be registered under
//     `packages/material_symbols_icons/<Family>`: an IconData carrying a
//     `fontPackage` resolves to that qualified name, and registering the bare
//     family yields a screen of empty rectangles that looks like a font bug.
//   - `assets/brand/logo.png` does not decode in this harness, so FlowLogo
//     photographs as a blank square. A capture artifact, not a defect.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flow/core/theme/app_theme.dart';
import 'package:flow/data/firestore_paths.dart';
import 'package:flow/data/models/app_user.dart';
import 'package:flow/data/models/catalogue.dart';
import 'package:flow/providers/providers.dart';
import 'package:flow/providers/settings_provider.dart';
import 'package:flow/services/wind_service.dart';

import 'package:flow/features/admin/admin_screen.dart';
import 'package:flow/features/auth/reset_password_screen.dart';
import 'package:flow/features/auth/sign_up_screen.dart';
import 'package:flow/features/auth/welcome_screen.dart';
import 'package:flow/features/booking/booking_screen.dart';
import 'package:flow/features/chat/chat_screen.dart';
import 'package:flow/features/chat/inbox_screen.dart';
import 'package:flow/features/command_center/calendar_screen.dart';
import 'package:flow/features/command_center/command_center_screen.dart';
import 'package:flow/features/command_center/earnings_screen.dart';
import 'package:flow/features/explore/explore_screen.dart';
import 'package:flow/features/explore/station_profile_screen.dart';
import 'package:flow/features/explore/trainer_profile_screen.dart';
import 'package:flow/features/gates/blocked_screen.dart';
import 'package:flow/features/gates/pending_screen.dart';
import 'package:flow/features/gates/rejected_screen.dart';
import 'package:flow/features/gates/setup_required_screen.dart';
import 'package:flow/features/notifications/notifications_screen.dart';
import 'package:flow/features/onboarding/kiter_form_screen.dart';
import 'package:flow/features/onboarding/role_select_screen.dart';
import 'package:flow/features/onboarding/trainer_form_screen.dart';
import 'package:flow/features/profile/edit_profile_screen.dart';
import 'package:flow/features/profile/profile_screen.dart';
import 'package:flow/features/sessions/sessions_screen.dart';
import 'package:flow/features/sessions/ticket_screen.dart';
import 'package:flow/features/support/support_screen.dart';

import '../support/screen_harness.dart';

const _outDir = '.impeccable/review';

/// Where a screen is rendered at more than one text scale, the scale is in the
/// filename. 1.3 is the clamp the app applies, so it is the widest real text
/// any layout has to survive.
const _scales = <double>[1.0, 1.3];

void main() {
  setUpAll(() async {
    await _loadFonts();
    Directory(_outDir).createSync(recursive: true);
  });

  // Rider-facing.
  _shoot('explore', () => const ExploreScreen());
  _shoot('sessions', () => const SessionsScreen());
  _shoot('ticket', () => const TicketScreen());
  _shoot('inbox', () => const InboxScreen());
  _shoot('notifications', () => const NotificationsScreen());
  _shoot('profile', () => const ProfileScreen());
  _shoot('trainer-profile',
      () => const TrainerProfileScreen(trainerId: 'u_trainer'));
  _shoot('station-profile',
      () => const StationProfileScreen(stationId: 'u_station'));
  _shoot(
    'booking',
    () => const BookingScreen(
      target: BookingTarget(
        providerId: 'u_trainer',
        title: 'Anna Bergström',
        rate: 95,
        subtitle: 'Soma Bay',
      ),
    ),
  );
  _shoot('chat',
      () => const ChatScreen(partnerId: 'u_trainer', partnerName: 'Anna Bergström'));
  _shoot('support', () => const SupportScreen());

  // Trainer-facing.
  _shoot('command-center', () => const CommandCenterScreen(), as: trainer);
  _shoot('calendar', () => const CalendarScreen(), as: trainer);
  _shoot('earnings', () => const EarningsScreen(), as: trainer);

  // Staff. Pumped as an actual admin with every queue populated — as a
  // trainer this screen renders its "Staff only" gate and nothing else, which
  // is what test/screen_overlap_test.dart has been photographing all along.
  _shoot('admin-console', () => const AdminScreen(),
      as: _admin, stage: AppStage.staff, staffData: true);

  // Auth, onboarding and the gates.
  _shoot('welcome', () => const WelcomeScreen());
  _shoot('sign-up', () => const SignUpScreen());
  _shoot('reset-password', () => const ResetPasswordScreen());
  _shoot('role-select', () => const RoleSelectScreen());
  _shoot('rider-form', () => const KiterFormScreen());
  _shoot('trainer-form', () => const TrainerFormScreen());
  _shoot('trainer-form-reapply', () => const TrainerFormScreen(reapply: true));
  _shoot('gate-pending', () => const PendingScreen());
  _shoot('gate-rejected', () => const RejectedScreen());
  _shoot('gate-blocked', () => const BlockedScreen());
  _shoot('gate-setup-required', () => const SetupRequiredScreen());
  _shoot('edit-profile', () => const EditProfileScreen());

  // Empty states — the shape the placeholder-centring work changed, and the
  // one a populated seed never shows.
  _shoot('empty-sessions', () => const SessionsScreen(), empty: true);
  _shoot('empty-inbox', () => const InboxScreen(), empty: true);
  _shoot('empty-notifications', () => const NotificationsScreen(), empty: true);
  _shoot('empty-explore', () => const ExploreScreen(), empty: true);
  _shoot('empty-command-center', () => const CommandCenterScreen(),
      as: trainer, empty: true);

  // A 320px phone, the narrowest the app claims to support, at the largest
  // text — where "it fits on mine" stops being true.
  _shoot('narrow-explore', () => const ExploreScreen(),
      size: const Size(320, 640), only: 1.3);
  _shoot('narrow-trainer-profile',
      () => const TrainerProfileScreen(trainerId: 'u_trainer'),
      size: const Size(320, 640), only: 1.3);
  _shoot('narrow-command-center', () => const CommandCenterScreen(),
      as: trainer, size: const Size(320, 640), only: 1.3);
  _shoot('narrow-booking',
      () => const BookingScreen(
            target: BookingTarget(
              providerId: 'u_trainer',
              title: 'Anna Bergström',
              rate: 95,
              subtitle: 'Soma Bay',
            ),
          ),
      size: const Size(320, 640), only: 1.3);
}

/// The staff account the console is pumped as.
const _admin = AppUser(
  uid: 'u_admin',
  name: 'Nadia Fouad',
  email: 'nadia@flow.app',
  role: UserRole.admin,
  status: AccountStatus.active,
);

/// Registers a capture for [name] at every scale in [_scales], or only [only].
void _shoot(
  String name,
  Widget Function() build, {
  AppUser as = rider,
  Size size = const Size(360, 780),
  bool empty = false,
  bool staffData = false,
  AppStage stage = AppStage.ready,
  double? only,
}) {
  for (final scale in only == null ? _scales : [only]) {
    final label = scale == 1.0 ? name : '$name@${scale}x';
    testWidgets(label, (tester) async {
      final db = empty
          ? await _emptyDb()
          : staffData
              ? await _staffDb()
              : await seededDb();
      await _pumpAndShoot(tester, build(), db: db, as: as, size: size,
          textScale: scale, name: label, stage: stage);
    });
  }
}

/// The seed plus one item in every staff queue, so the console renders with
/// content in all six tabs rather than six empty states.
Future<FakeFirebaseFirestore> _staffDb() async {
  final db = await seededDb();
  await db.collection(Col.users).doc(_admin.uid).set({
    'name': _admin.name, 'email': _admin.email,
    'role': 'admin', 'status': 'active',
  });
  await db.collection(Col.users).doc('u_applicant').set({
    'name': 'Mostafa El-Sharkawy',
    'email': 'mostafa@example.com',
    'role': 'business',
    'status': 'pending',
    'location': 'Ras Sudr',
    'bio': 'IKO Level 2. Teaching since 2019, mostly beginners and freestyle.',
    'ikoId': 'IKO-4471PQ',
    'hourlyRate': 55,
  });
  await db.collection(Col.users).doc('u_suspended').set({
    'name': 'Karim Adel', 'email': 'karim@example.com',
    'role': 'kiter', 'status': 'blocked',
    'blockedUntil': '2099-09-01', 'statusBeforeBlock': 'active',
  });
  await db.collection(Col.reports).doc('rp1').set({
    'reporterId': rider.uid, 'reporterName': rider.name,
    'reportedUserId': 'u_suspended', 'reportedUserName': 'Karim Adel',
    'reason': 'Unsafe behaviour on the water',
    'details': 'Rode straight through the beginner zone twice.',
    'status': 'pending',
  });
  await db.collection(Col.appeals).doc('ap1').set({
    'userId': 'u_suspended', 'userName': 'Karim Adel',
    'reason': 'I was outside the marked zone, happy to explain.',
    'status': 'pending', 'messages': <Map<String, dynamic>>[],
  });
  await db.collection(Col.tickets).doc('t1').set({
    'userId': rider.uid, 'userName': rider.name,
    'subject': 'Refund for a cancelled session',
    'status': 'open',
  });
  await db.collection(Col.leaveReasons).doc('l1').set({
    'userId': 'u_gone', 'userName': 'Former Rider',
    'userEmail': 'gone@example.com',
    'reason': 'Moving away from the coast — thanks for everything.',
  });
  return db;
}

/// A database with the four profiles and nothing else — every list empty.
Future<FakeFirebaseFirestore> _emptyDb() async {
  final full = await seededDb();
  for (final c in ['bookings', 'reviews', 'notifications', 'safari_trips']) {
    final qs = await full.collection(c).get();
    for (final d in qs.docs) {
      await d.reference.delete();
    }
  }
  return full;
}

Future<void> _pumpAndShoot(
  WidgetTester tester,
  Widget screen, {
  required FakeFirebaseFirestore db,
  required AppUser as,
  required Size size,
  required double textScale,
  required String name,
  AppStage stage = AppStage.ready,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  final key = GlobalKey();
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => RepaintBoundary(key: key, child: screen)),
  ]);
  addTearDown(router.dispose);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      windServiceProvider.overrideWithValue(WindService(clientFactory: _Dead.new)),
      currentUidProvider.overrideWithValue(as.uid),
      currentUserProvider.overrideWith((ref) => Stream.value(as)),
      sessionProvider.overrideWithValue(Session(stage: stage, user: as)),
    ],
    child: MaterialApp.router(
      theme: FlowTheme.light(),
      routerConfig: router,
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: child!,
      ),
    ),
  ));

  // Never pumpAndSettle: the skeleton shimmer and the live dot animate
  // forever, so it hangs rather than fails.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  // Inside runAsync: toImage and toByteData are engine calls that complete on
  // the real event loop. Awaited in the ordinary fake-async zone the PNG is
  // still written, but the zone is left with work it can never drain and the
  // test hangs until the 10-minute timeout instead of finishing.
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

/// Real fonts, or every screen photographs as Ahem boxes.
Future<void> _loadFonts() async {
  const families = <String, String>{
    'SpaceGrotesk': 'assets/fonts/SpaceGrotesk.ttf',
    'Inter': 'assets/fonts/Inter.ttf',
    'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    // Qualified, because these IconData carry a fontPackage.
    'packages/material_symbols_icons/MaterialSymbolsRounded':
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf',
    'packages/material_symbols_icons/MaterialSymbolsOutlined':
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf',
  };
  for (final entry in families.entries) {
    try {
      final data = await rootBundle.load(entry.value);
      await (FontLoader(entry.key)..addFont(Future.value(data))).load();
    } catch (e) {
      // Loud, because the failure mode downstream is a screenful of boxes
      // that looks like a rendering defect rather than a missing asset.
      // ignore: avoid_print
      print('FONT MISSING: ${entry.key} <- ${entry.value}  ($e)');
    }
  }
}

class _Dead implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.isSetter || i.memberName.toString().contains('close')) return null;
    throw Exception('offline in capture');
  }
}
