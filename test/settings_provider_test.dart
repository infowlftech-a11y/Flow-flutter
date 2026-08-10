// Theme mode and onboarding-flag persistence. The one decision here worth a
// test: ThemeMode.system is stored as *absence* — set() must REMOVE the key,
// not write 'system', or a fresh install and an explicit "Auto" choice become
// distinguishable states that drift apart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flow/core/constants.dart';
import 'package:flow/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> containerWith(Map<String, Object> seed) async {
    SharedPreferences.setMockInitialValues(seed);
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    return c;
  }

  test('reads the persisted mode, treating absence as system', () async {
    expect((await containerWith({FlowConst.themeModeKey: 'dark'}))
        .read(themeModeProvider), ThemeMode.dark);
    expect((await containerWith({FlowConst.themeModeKey: 'light'}))
        .read(themeModeProvider), ThemeMode.light);
    expect((await containerWith({})).read(themeModeProvider),
        ThemeMode.system);
    expect((await containerWith({FlowConst.themeModeKey: 'disco'}))
        .read(themeModeProvider), ThemeMode.system,
        reason: 'garbage falls back to system, never crashes the first frame');
  });

  test('set() persists light/dark and removes the key for system', () async {
    final c = await containerWith({});
    final prefs = c.read(sharedPreferencesProvider);

    await c.read(themeModeProvider.notifier).set(ThemeMode.dark);
    expect(prefs.getString(FlowConst.themeModeKey), 'dark');
    expect(c.read(themeModeProvider), ThemeMode.dark);

    await c.read(themeModeProvider.notifier).set(ThemeMode.system);
    expect(prefs.getString(FlowConst.themeModeKey), isNull,
        reason: 'system is stored as absence, not as a third value');
    expect(c.read(themeModeProvider), ThemeMode.system);
  });

  test('trainer tour flags are per uid', () async {
    final c = await containerWith({});
    final flags = c.read(onboardingFlagsProvider.notifier);
    expect(flags.trainerTourDone('u1'), isFalse);
    await flags.setTrainerTourDone('u1');
    expect(flags.trainerTourDone('u1'), isTrue);
    expect(flags.trainerTourDone('u2'), isFalse,
        reason: 'a second account on the device gets its own tour');
  });
}
