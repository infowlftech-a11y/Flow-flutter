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

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Registered before runApp so killed-state pushes are handled (§11.3).
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Portrait only; edge-to-edge with transparent system bars (§10.8).
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Prefs load *before* the first frame, so the theme read is synchronous
  // and the first frame already has the right brightness (§7.4).
  final prefs = await SharedPreferences.getInstance();

  runApp(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const FlowApp(),
  ));
}
