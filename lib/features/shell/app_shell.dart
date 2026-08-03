import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';

/// Four-branch tab shell. Trainers don't get the Sessions tab — their
/// bookings live in the Command Center — so their bar shows
/// Dashboard / Inbox / Profile (§4.3). Branch state is retained across
/// switches; tapping the active tab pops that branch to its root.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTrainer = ref.watch(sessionProvider.select((s) => s.isTrainer));
    final unreadChats = ref.watch(unreadChatCountProvider);

    // Visible destinations → branch indices.
    final branchOf = isTrainer ? const [0, 2, 3] : const [0, 1, 2, 3];
    final selected = branchOf.indexOf(navigationShell.currentIndex);

    final inboxIcon = _BadgedIcon(
      count: unreadChats,
      icon: Icons.forum_outlined,
      selectedIcon: Icons.forum_rounded,
      selected: branchOf[selected < 0 ? 0 : selected] == 2,
      semanticLabelBuilder: (n) => '$n unread message${n == 1 ? '' : 's'}',
    );

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
        destinations: [
          if (isTrainer)
            const NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard_rounded),
              label: 'Dashboard',
            )
          else ...[
            const NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore_rounded),
              label: 'Explore',
            ),
            const NavigationDestination(
              icon: Icon(Icons.surfing_outlined),
              selectedIcon: Icon(Icons.surfing_rounded),
              label: 'Sessions',
            ),
          ],
          NavigationDestination(
            icon: inboxIcon,
            selectedIcon: inboxIcon,
            label: 'Inbox',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _BadgedIcon extends StatelessWidget {
  const _BadgedIcon({
    required this.count,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.semanticLabelBuilder,
  });

  final int count;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final String Function(int) semanticLabelBuilder;

  @override
  Widget build(BuildContext context) {
    final base = Icon(selected ? selectedIcon : icon);
    if (count <= 0) return base;
    // Badge counts surface as spoken sentences, not bare digits (§10.8).
    return Semantics(
      label: semanticLabelBuilder(count),
      child: Badge.count(count: count, child: base),
    );
  }
}
