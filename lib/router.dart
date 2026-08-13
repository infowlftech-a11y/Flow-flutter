import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/widgets/feedback.dart';
import 'data/models/catalogue.dart';
import 'features/admin/admin_screen.dart';
import 'features/auth/reset_password_screen.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/auth/sign_up_screen.dart';
import 'features/auth/welcome_screen.dart';
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
import 'features/command_center/calendar_screen.dart';
import 'features/command_center/earnings_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/sessions/sessions_screen.dart';
import 'features/sessions/ticket_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/splash/splash_screen.dart';
import 'features/support/support_screen.dart';
import 'providers/providers.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Gate routes cross-fade (260 ms) instead of sliding (§10.9).
///
/// P12 gave the fade the app's easing — it ran linear, the one curve
/// nothing physical moves along.
CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) =>
    CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 260),
      transitionsBuilder: (context, animation, secondary, child) =>
          FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          ),
    );

/// Every pushed route rises in (P12): fade plus a short upward drift on the
/// app's own easing, replacing the platform default so a push feels the
/// same on every screen and every device. Durations live here, not in
/// FlowMotion — the route transition is flow, not presentation (see
/// motion.dart's header), and 300/240 are tuned to travel with the finger:
/// the reverse leg reads sluggish at full length.
CustomTransitionPage<void> _detailPage(GoRouterState state, Widget child) =>
    CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      transitionsBuilder: (context, animation, secondary, child) {
        final eased = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: eased,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, .04),
              end: Offset.zero,
            ).animate(eased),
            child: child,
          ),
        );
      },
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
          // Any /auth/* route is a legitimate place to be while signed out —
          // pinning to a single path would bounce the user off Create
          // account and Reset the moment they navigated there.
          return loc == '/auth' || loc.startsWith('/auth/') ? null : '/auth';
        case AppStage.chooseRole:
          return loc.startsWith('/onboarding') ? null : '/onboarding/role';
        case AppStage.awaitingApproval:
          return loc == '/pending' ? null : '/pending';
        case AppStage.blocked:
          return loc == '/blocked' ? null : '/blocked';
        case AppStage.rejected:
          // Support and the correction form stay reachable: a declined
          // trainer can fix what was wrong and go back in the queue, or talk
          // to a human. Anything else would make a decline a dead end.
          return (loc == '/rejected' ||
                  loc == '/support' ||
                  loc == '/onboarding/trainer/reapply')
              ? null
              : '/rejected';
        case AppStage.staff:
          // The console *is* the app for staff. Everything they legitimately
          // do hangs off it, so the only other routes worth allowing are the
          // ones the console pushes: a profile it is moderating, and the
          // conversation behind a support ticket.
          return (loc == '/admin' ||
                  loc.startsWith('/trainer/') ||
                  loc.startsWith('/station/') ||
                  loc == '/notifications')
              ? null
              : '/admin';
        case AppStage.ready:
          if (loc == '/' ||
              loc == '/auth' ||
              loc.startsWith('/auth/') ||
              loc == '/pending' ||
              loc == '/blocked' ||
              loc == '/rejected' ||
              loc.startsWith('/onboarding')) {
            return '/home';
          }
          // Non-staff never reach the console. (Staff never reach *here* —
          // they resolve to AppStage.staff above.)
          if (loc == '/admin') return '/home';
          // Trainers are never routed to the Sessions branch (§14.3).
          if (session.isTrainer && loc.startsWith('/sessions')) return '/home';
          return null;
      }
    },
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => _fadePage(state, const SplashScreen()),
      ),
      // Auth is four routes, not one screen with a mode toggle: the front
      // door, and the three things you can do from it.
      GoRoute(
        path: '/auth',
        pageBuilder: (context, state) =>
            _fadePage(state, const WelcomeScreen()),
        routes: [
          GoRoute(
            path: 'sign-in',
            pageBuilder: (context, state) =>
                _detailPage(state, const SignInScreen()),
          ),
          GoRoute(
            path: 'sign-up',
            pageBuilder: (context, state) =>
                _detailPage(state, const SignUpScreen()),
          ),
          GoRoute(
            path: 'reset',
            pageBuilder: (context, state) =>
                _detailPage(state, const ResetPasswordScreen()),
          ),
        ],
      ),
      GoRoute(
        path: '/onboarding/role',
        pageBuilder: (context, state) =>
            _fadePage(state, const RoleSelectScreen()),
      ),
      GoRoute(
        path: '/onboarding/rider',
        pageBuilder: (context, state) =>
            _detailPage(state, const KiterFormScreen()),
      ),
      GoRoute(
        path: '/onboarding/trainer',
        pageBuilder: (context, state) =>
            _detailPage(state, const TrainerFormScreen()),
      ),
      // The same form, prefilled, for a declined trainer correcting their
      // application. A distinct path rather than a query flag so the
      // `rejected` redirect above can name exactly what it allows.
      GoRoute(
        path: '/onboarding/trainer/reapply',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _detailPage(state, const TrainerFormScreen(reapply: true)),
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
      // The base constructor, not `.indexedStack` (P12): branch switches
      // cross-fade instead of hard-cutting. The container keeps the
      // state-preservation contract indexedStack had; see
      // AnimatedBranchContainer for what "inert" has to mean in a Stack.
      StatefulShellRoute(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        navigatorContainerBuilder: (context, navigationShell, children) =>
            AnimatedBranchContainer(
              currentIndex: navigationShell.currentIndex,
              children: children,
            ),
        branches: [
          // Branch 0 resolves through a Consumer so a role change swaps
          // Explore ⇄ Command Center without a restart (§4.3).
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: ShellBranch.paths[ShellBranch.home],
                builder: (context, state) => Consumer(
                  builder: (context, ref, _) =>
                      ref.watch(sessionProvider).isTrainer
                      ? const CommandCenterScreen()
                      : const ExploreScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: ShellBranch.paths[ShellBranch.sessions],
                builder: (context, state) => SessionsScreen(
                  highlightBookingId: state.uri.queryParameters['highlight'],
                ),
              ),
            ],
          ),
          // Branch 2 — the rider's check-in credential, promoted from a
          // dialog to a destination (§3.6). Trainers never see this tab; the
          // scanner is their side of the same transaction.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: ShellBranch.paths[ShellBranch.ticket],
                builder: (context, state) => const TicketScreen(),
              ),
            ],
          ),
          // Branch 3 — the trainer's calendar, which used to be a tab *inside*
          // the Command Center. Lifting it to the bar makes the two things a
          // trainer does all day reachable in one tap each rather than one
          // plus a tab.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: ShellBranch.paths[ShellBranch.calendar],
                builder: (context, state) => const CalendarScreen(),
              ),
            ],
          ),
          // Branch 4 — earnings, likewise promoted from a sheet behind a stat
          // tile.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: ShellBranch.paths[ShellBranch.earnings],
                builder: (context, state) => const EarningsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: ShellBranch.paths[ShellBranch.profile],
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/trainer/:id',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _detailPage(
          state,
          TrainerProfileScreen(trainerId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/station/:id',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _detailPage(
          state,
          StationProfileScreen(stationId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/chat/:id',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _detailPage(
          state,
          ChatScreen(
            partnerId: state.pathParameters['id']!,
            partnerName: state.uri.queryParameters['name'] ?? 'Chat',
          ),
        ),
      ),
      GoRoute(
        path: '/book/:id',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _detailPage(
          state,
          BookingScreen(target: state.extra as BookingTarget),
        ),
      ),
      // Inbox is no longer a tab — it is reached from the Discover header, so
      // it is a pushed route with its own back affordance rather than a shell
      // branch that nothing selects.
      GoRoute(
        path: '/inbox',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _detailPage(state, const InboxScreen()),
      ),
      GoRoute(
        path: '/notifications',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _detailPage(state, const NotificationsScreen()),
      ),
      GoRoute(
        path: '/support',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _detailPage(state, const SupportScreen()),
        routes: [
          // The destination a support notification deep-links to (P2). As a
          // child of /support, Back from a pushed thread falls out to the
          // ticket list — the same place the in-app path comes from.
          GoRoute(
            path: 'ticket/:id',
            parentNavigatorKey: rootNavigatorKey,
            pageBuilder: (context, state) => _detailPage(
              state,
              TicketThreadScreen(ticketId: state.pathParameters['id']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/admin',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _detailPage(state, const AdminScreen()),
      ),
      GoRoute(
        path: '/profile/edit',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _detailPage(state, const EditProfileScreen()),
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
        icon: Symbols.explore_off_rounded,
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
