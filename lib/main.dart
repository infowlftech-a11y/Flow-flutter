import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/firebase_config.dart';
import 'features/gates/setup_required_screen.dart';
import 'firebase_options.dart';
import 'providers/settings_provider.dart';
import 'services/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fail loudly and immediately on a placeholder API key. Firebase accepts a
  // bogus key at init and only rejects it on the first real call, which is
  // how a build problem ends up surfacing as "Something went wrong" under a
  // user's registration form.
  if (!FlowFirebase.isConfigured) {
    runApp(const SetupRequiredScreen());
    return;
  }

  // Started now, awaited later. Startup was five `await`s in a row, and only
  // one of those dependencies is real: Messaging needs Firebase. Reading the
  // preferences file and setting the orientation have nothing to do with
  // Firebase and were simply queued behind its network-bound init.
  //
  // Measured on the API 37 emulator in profile mode: 3,953ms to framework
  // init versus 140ms for everything after it. The startup cost of this app is
  // entirely in this function, not in any `build()`.
  //
  // Neither invariant below changes — prefs are still resolved before the
  // first frame (§7.4) and the background handler is still registered before
  // `runApp` (§11.3). Only the waiting is now concurrent.
  final prefsFuture = SharedPreferences.getInstance();
  final chromeFuture = Future.wait([
    // Portrait only; edge-to-edge with transparent system bars (§10.8).
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]),
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
  ]);

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Registered before runApp so killed-state pushes are handled (§11.3).
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Prefs load *before* the first frame, so the theme read is synchronous
  // and the first frame already has the right brightness (§7.4).
  final prefs = await prefsFuture;
  await chromeFuture;

  runApp(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const FlowApp(),
  ));
}
