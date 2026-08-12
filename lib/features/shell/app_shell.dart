import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/sheets.dart';
import '../../providers/providers.dart';

/// Six-branch tab shell showing four destinations per role.
///
/// Riders get Discover / Sessions / Ticket / Profile; trainers get Dashboard
/// / Calendar / Earnings / Profile. Inbox is no longer a tab — it is a header
/// action on Discover, because a rider messages a trainer about a booking far
/// less often than they check one.
///
/// Branch state is retained across switches; tapping the active tab pops that
/// branch to its root.
/// Branch indices in `router.dart`'s `StatefulShellRoute`, in order.
///
/// Named rather than written as bare integers at the one call site, because
/// the mapping is positional in two files at once: reordering a branch in the
/// router silently re-points a destination here, and the symptom is a tab that
/// highlights the wrong icon rather than anything that crashes.
abstract final class ShellBranch {
  static const home = 0;
  static const sessions = 1;
  static const ticket = 2;
  static const calendar = 3;
  static const earnings = 4;
  static const profile = 5;

  /// Every branch the router declares. Kept next to the indices so a new
  /// branch cannot be added without this list noticing.
  static const count = 6;

  /// The route each branch owns, **in branch order**.
  ///
  /// `router.dart` builds its `StatefulShellBranch` list from this rather than
  /// repeating the paths, which is what makes the indices above verifiable at
  /// all: without it the constants and the router agree only by coincidence,
  /// and a test comparing the constants to themselves passes no matter how
  /// wrong they are. (It did. That is why this exists.)
  static const paths = [
    '/home',
    '/sessions',
    '/ticket',
    '/calendar',
    '/earnings',
    '/profile',
  ];
}

/// The branches each role shows, in bar order.
///
/// Pure and public so it can be asserted directly — this is index arithmetic
/// across two files, and the failure mode is silent.
List<int> branchesFor({required bool isTrainer}) => isTrainer
    ? const [
        ShellBranch.home,
        ShellBranch.calendar,
        ShellBranch.earnings,
        ShellBranch.profile,
      ]
    : const [
        ShellBranch.home,
        ShellBranch.sessions,
        ShellBranch.ticket,
        ShellBranch.profile,
      ];

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTrainer = ref.watch(sessionProvider.select((s) => s.isTrainer));

    // Visible destinations → branch indices. The branch list is shared; each
    // role shows four of the six, so a rider never has a Calendar branch
    // mounted and a trainer never has a Ticket one.
    //
    // Branches: 0 home · 1 sessions · 2 ticket · 3 calendar · 4 earnings ·
    // 5 profile.
    final branchOf = branchesFor(isTrainer: isTrainer);
    final selected = branchOf.indexOf(navigationShell.currentIndex);

    // Back at the root of a tab means "leave FLOW", and Android's back
    // gesture is an edge swipe that a thumb finds by accident. A trainer
    // mid-session or a rider holding a QR ticket at the water's edge should
    // not lose the app to a stray swipe.
    //
    // `canPop: false` + a confirmed `SystemNavigator.pop()` rather than
    // letting the pop through: the shell is the last route, so allowing it
    // *is* the exit, and there would be nothing left to ask on top of.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmAction(
          context,
          title: 'Leave FLOW?',
          body: 'Your session, bookings and messages are saved — you can '
              'come straight back.',
          confirmLabel: 'Leave',
          cancelLabel: 'Stay',
        );
        if (leave) await SystemNavigator.pop();
      },
      child: _buildShell(context, branchOf, selected, isTrainer),
    );
  }

  Widget _buildShell(BuildContext context, List<int> branchOf, int selected,
      bool isTrainer) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected < 0 ? 0 : selected,
        onDestinationSelected: (i) {
          final branch = branchOf[i];
          navigationShell.goBranch(
            branch,
            // Tapping the already-active tab pops it to its root.
            initialLocation: branch == navigationShell.currentIndex,
          );
        },
        destinations: isTrainer
            ? const [
                NavigationDestination(
                  icon: Icon(Symbols.space_dashboard_rounded),
                  selectedIcon: Icon(Symbols.space_dashboard_rounded, fill: 1),
                  label: 'Dashboard',
                ),
                NavigationDestination(
                  icon: Icon(Symbols.calendar_month_rounded),
                  selectedIcon: Icon(Symbols.calendar_month_rounded, fill: 1),
                  label: 'Calendar',
                ),
                NavigationDestination(
                  icon: Icon(Symbols.payments_rounded),
                  selectedIcon: Icon(Symbols.payments_rounded, fill: 1),
                  label: 'Earnings',
                ),
                NavigationDestination(
                  icon: Icon(Symbols.person_rounded),
                  selectedIcon: Icon(Symbols.person_rounded, fill: 1),
                  label: 'Profile',
                ),
              ]
            : const [
                NavigationDestination(
                  icon: Icon(Symbols.explore_rounded),
                  selectedIcon: Icon(Symbols.explore_rounded, fill: 1),
                  label: 'Discover',
                ),
                NavigationDestination(
                  icon: Icon(Symbols.surfing_rounded),
                  selectedIcon: Icon(Symbols.surfing_rounded, fill: 1),
                  label: 'Sessions',
                ),
                NavigationDestination(
                  icon: Icon(Symbols.confirmation_number_rounded),
                  selectedIcon: Icon(Symbols.confirmation_number_rounded, fill: 1),
                  label: 'Ticket',
                ),
                NavigationDestination(
                  icon: Icon(Symbols.person_rounded),
                  selectedIcon: Icon(Symbols.person_rounded, fill: 1),
                  label: 'Profile',
                ),
              ],
      ),
    );
  }
}
