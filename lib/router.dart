import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/widgets/feedback.dart';
import 'data/models/catalogue.dart';
import 'features/admin/admin_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/booking/booking_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/chat/inbox_screen.dart';
import 'features/command_center/command_center_screen.dart';
import 'features/explore/explore_screen.dart';
import 'features/explore/station_profile_screen.dart';
import 'features/explore/trainer_profile_screen.dart';
import 'features/gates/blocked_screen.dart';
import 'features/gates/pending_screen.dart';
import 'features/gates/rejected_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/onboarding/kiter_form_screen.dart';
import 'features/onboarding/role_select_screen.dart';
import 'features/onboarding/trainer_form_screen.dart';
import 'features/profile/edit_profile_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/sessions/sessions_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/splash/splash_screen.dart';
import 'features/support/support_screen.dart';
import 'providers/providers.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Gate routes cross-fade (260 ms) instead of sliding (§10.9).
CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) =>
    CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 260),
      transitionsBuilder: (context, animation, secondary, child) =>
          FadeTransition(opacity: animation, child: child),
    );

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.onDispose(refresh.dispose);
  // Re-evaluate every redirect whenever the session changes (§4.2).
  ref.listen(sessionProvider, (_, _) => refresh.value++);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final loc = state.matchedLocation;

      switch (session.stage) {
        case AppStage.loading:
          return loc == '/' ? null : '/';
        case AppStage.signedOut:
          return loc == '/auth' ? null : '/auth';
        case AppStage.chooseRole:
          return loc.startsWith('/onboarding') ? null : '/onboarding/role';
        case AppStage.awaitingApproval:
          return loc == '/pending' ? null : '/pending';
        case AppStage.blocked:
          return loc == '/blocked' ? null : '/blocked';
        case AppStage.rejected:
          // Support stays reachable so a declined trainer can appeal to a
          // human instead of hitting a dead end.
          return (loc == '/rejected' || loc == '/support')
              ? null
              : '/rejected';
        case AppStage.ready:
          if (loc == '/' ||
              loc == '/auth' ||
              loc == '/pending' ||
              loc == '/blocked' ||
              loc == '/rejected' ||
              loc.startsWith('/onboarding')) {
            return '/home';
          }
          // The console is staff-only; anyone else is sent home.
          if (loc == '/admin' && !session.isStaff) return '/home';
          // Trainers are never routed to the Sessions branch (§14.3).
          if (session.isTrainer && loc.startsWith('/sessions')) return '/home';
          return null;
      }
    },
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) =>
            _fadePage(state, const SplashScreen()),
      ),
      GoRoute(
        path: '/auth',
        pageBuilder: (context, state) => _fadePage(state, const AuthScreen()),
      ),
      GoRoute(
        path: '/onboarding/role',
        pageBuilder: (context, state) =>
            _fadePage(state, const RoleSelectScreen()),
      ),
      GoRoute(
        path: '/onboarding/rider',
        builder: (context, state) => const KiterFormScreen(),
      ),
      GoRoute(
        path: '/onboarding/trainer',
        builder: (context, state) => const TrainerFormScreen(),
      ),
      GoRoute(
        path: '/pending',
        pageBuilder: (context, state) =>
            _fadePage(state, const PendingScreen()),
      ),
      GoRoute(
        path: '/blocked',
        pageBuilder: (context, state) =>
            _fadePage(state, const BlockedScreen()),
      ),
      GoRoute(
        path: '/rejected',
        pageBuilder: (context, state) =>
            _fadePage(state, const RejectedScreen()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          // Branch 0 resolves through a Consumer so a role change swaps
          // Explore ⇄ Command Center without a restart (§4.3).
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => Consumer(
                builder: (context, ref, _) =>
                    ref.watch(sessionProvider).isTrainer
                        ? const CommandCenterScreen()
                        : const ExploreScreen(),
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/sessions',
              builder: (context, state) => SessionsScreen(
                  highlightBookingId: state.uri.queryParameters['highlight']),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/inbox',
              builder: (context, state) => const InboxScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfileScreen(),
            ),
          ]),
        ],
      ),
      GoRoute(
        path: '/trainer/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            TrainerProfileScreen(trainerId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/station/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            StationProfileScreen(stationId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/chat/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => ChatScreen(
          partnerId: state.pathParameters['id']!,
          partnerName: state.uri.queryParameters['name'] ?? 'Chat',
        ),
      ),
      GoRoute(
        path: '/book/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            BookingScreen(target: state.extra as BookingTarget),
      ),
      GoRoute(
        path: '/notifications',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/support',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SupportScreen(),
      ),
      GoRoute(
        path: '/admin',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AdminScreen(),
      ),
      GoRoute(
        path: '/profile/edit',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const EditProfileScreen(),
      ),
    ],
    errorBuilder: (context, state) => const _NotFoundScreen(),
  );
});

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: EmptyView(
        icon: Icons.explore_off_rounded,
        title: 'That page drifted offshore.',
        subtitle: "The route you followed doesn't exist anymore.",
        action: FilledButton(
          onPressed: () => context.go('/home'),
          child: const Text('Back to shore'),
        ),
      ),
    );
  }
}
