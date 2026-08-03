import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

/// Overridden in `main()` after prefs load, so theme reads are synchronous
/// and the first frame has the correct brightness (§7.4).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

/// Persisted under `themeMode`: `light` / `dark` / absent → system.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final raw = ref.watch(sharedPreferencesProvider).getString(FlowConst.themeModeKey);
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = ref.read(sharedPreferencesProvider);
    if (mode == ThemeMode.system) {
      await prefs.remove(FlowConst.themeModeKey);
    } else {
      await prefs.setString(
          FlowConst.themeModeKey, mode == ThemeMode.light ? 'light' : 'dark');
    }
  }
}

/// `trainerTourDone_{uid}` booleans (§7.4).
final onboardingFlagsProvider =
    NotifierProvider<OnboardingFlagsNotifier, int>(OnboardingFlagsNotifier.new);

class OnboardingFlagsNotifier extends Notifier<int> {
  @override
  int build() => 0; // state is a change counter; reads go to prefs

  bool trainerTourDone(String uid) =>
      ref.read(sharedPreferencesProvider)
          .getBool(FlowConst.trainerTourDoneKey(uid)) ??
      false;

  Future<void> setTrainerTourDone(String uid) async {
    await ref
        .read(sharedPreferencesProvider)
        .setBool(FlowConst.trainerTourDoneKey(uid), true);
    state++;
  }
}
