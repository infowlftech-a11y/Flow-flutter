import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/theme_swap.dart';
import 'providers/providers.dart';
import 'providers/settings_provider.dart';
import 'router.dart';
import 'services/push_service.dart';

class FlowApp extends ConsumerStatefulWidget {
  const FlowApp({super.key});

  @override
  ConsumerState<FlowApp> createState() => _FlowAppState();
}

class _FlowAppState extends ConsumerState<FlowApp> {
  @override
  void initState() {
    super.initState();
    final push = ref.read(pushControllerProvider);
    push.contextSupplier = () => rootNavigatorKey.currentContext;
    push.start();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Permission + token the first time a uid appears (§11.3). On sign-out
    // the token row is cleared by signOutProvider while the session is still
    // valid; here we only drop the local latch so a re-login rewrites it.
    ref.listen(currentUidProvider, (_, uid) {
      final push = ref.read(pushControllerProvider);
      if (uid != null) {
        push.syncTokenFor(uid);
      } else {
        push.forgetSyncedUid();
      }
    });

    return ThemeSwap(
        child: MaterialApp.router(
      // Task-switcher / accessibility title. The uppercase "FLOW" wordmark is
      // a branding treatment inside the UI, not the app's name.
      title: 'Flow',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: FlowTheme.light(),
      darkTheme: FlowTheme.dark(),
      // The theme snaps in one rebuild; ThemeSwap fades the old frame's
      // pixels out over it. The built-in animation lerped the whole
      // ThemeData per tick and rebuilt every mounted screen — see
      // core/widgets/theme_swap.dart for the numbers.
      themeAnimationStyle: AnimationStyle.noAnimation,
      routerConfig: router,
      builder: (context, child) {
        // Text scaling clamped 0.9–1.3 app-wide so dense uppercase labels
        // don't overflow their pills (§10.8).
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: FlowConst.minTextScale,
              maxScaleFactor: FlowConst.maxTextScale,
            ),
          ),
          child: child!,
        );
      },
    ));
  }
}
