import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/misc.dart';
import '../../core/widgets/provider_card.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/app_user.dart';
import '../../data/models/social.dart';
import '../../providers/providers.dart';

/// Rider home — grid of every approved trainer/station (§3.3).
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(exploreFilterProvider).query;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Every keystroke re-ran the filter over the whole trainer list and rebuilt
  /// the grid, which shows up as lag while typing. A short debounce keeps the
  /// field responsive; the clear button still applies immediately.
  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      ref.read(exploreFilterProvider.notifier).setQuery(q);
    });
  }

  void _clearQuery() {
    _debounce?.cancel();
    _search.clear();
    ref.read(exploreFilterProvider.notifier).setQuery('');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final filter = ref.watch(exploreFilterProvider);
    final trainers = ref.watch(filteredTrainersProvider);
    final ratings = ref.watch(ratingsProvider).value ?? const {};
    final unread = ref.watch(unreadNotificationCountProvider);
    final tones = context.tones;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hey ${session.displayName.split(' ').first} 🤙',
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 2),
                        Text('Find your trainer',
                            style: Theme.of(context).textTheme.displaySmall),
                      ],
                    ),
                  ),
                  // Messages. Inbox stopped being a tab in the redesign, so
                  // this is now its only entry point — it is a header action
                  // rather than a destination because a rider messages a
                  // trainer far less often than they browse or check a
                  // booking, and it was taking a quarter of the bar.
                  Consumer(builder: (context, ref, _) {
                    final unreadChats = ref.watch(unreadChatCountProvider);
                    return Semantics(
                      button: true,
                      child: IconButton.outlined(
                        onPressed: () => context.push('/inbox'),
                        tooltip: 'Messages',
                        icon: BadgedIcon(
                          count: unreadChats,
                          icon: Symbols.forum_rounded,
                          semanticLabelBuilder: (n) =>
                              '$n unread message${n == 1 ? '' : 's'}',
                        ),
                      ),
                    );
                  }),
                  const SizedBox(width: 8),
                  Semantics(
                    label: unread > 0
                        ? '$unread unread notification${unread == 1 ? '' : 's'}'
                        : 'Notifications',
                    button: true,
                    child: IconButton.outlined(
                      onPressed: () => context.push('/notifications'),
                      tooltip: 'Notifications',
                      icon: Badge.count(
                        count: unread,
                        isLabelVisible: unread > 0,
                        child: const Icon(Symbols.notifications_rounded),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    // Listening to the controller rather than the debounced
                    // filter keeps the clear affordance in sync with what the
                    // user has typed, and confines the per-keystroke rebuild
                    // to the field instead of the whole grid.
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _search,
                      builder: (context, value, _) => TextField(
                        controller: _search,
                        onChanged: _onQueryChanged,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search trainers, spots…',
                          prefixIcon:
                              const Icon(Symbols.search_rounded, size: 22),
                          suffixIcon: value.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: _clearQuery,
                                  icon:
                                      const Icon(Symbols.close_rounded, size: 20),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Semantics(
                    label: filter.activeCount > 0
                        ? '${filter.activeCount} active filters'
                        : 'Filters',
                    button: true,
                    child: SizedBox(
                      height: 52,
                      width: 52,
                      child: IconButton.filledTonal(
                        onPressed: () => _openFilterSheet(context),
                        tooltip: 'Filters',
                        icon: Badge.count(
                          count: filter.activeCount,
                          isLabelVisible: filter.activeCount > 0,
                          child: const Icon(Symbols.tune_rounded),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  FlowChoiceChip(
                    label: 'All trainers',
                    selected: !filter.favouritesOnly,
                    onTap: () {
                      Haptics.select();
                      ref
                          .read(exploreFilterProvider.notifier)
                          .setFavouritesOnly(false);
                    },
                  ),
                  const SizedBox(width: 8),
                  FlowChoiceChip(
                    label: 'Favourites',
                    selected: filter.favouritesOnly,
                    onTap: () {
                      Haptics.select();
                      ref
                          .read(exploreFilterProvider.notifier)
                          .setFavouritesOnly(true);
                    },
                  ),
                  if (filter.spot != null) ...[
                    const SizedBox(width: 8),
                    FlowChoiceChip(
                      label: filter.spot!,
                      selected: true,
                      onTap: () {},
                      onDeleted: () => ref
                          .read(exploreFilterProvider.notifier)
                          .setSpot(null),
                    ),
                  ],
                  for (final lang in filter.languages) ...[
                    const SizedBox(width: 8),
                    FlowChoiceChip(
                      label: lang,
                      selected: true,
                      onTap: () {},
                      onDeleted: () => ref
                          .read(exploreFilterProvider.notifier)
                          .toggleLanguage(lang),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: AsyncView<List<AppUser>>(
                value: trainers,
                onRetry: () => ref.invalidate(activeTrainersProvider),
                onRefresh: () async {
                  ref.invalidate(activeTrainersProvider);
                  ref.invalidate(ratingsProvider);
                  await ref.read(activeTrainersProvider.future);
                },
                skeleton: const _GridSkeleton(),
                data: (list) {
                  if (list.isEmpty) {
                    return EmptyView.scrollable(
                      topGap: 40,
                      icon: filter.favouritesOnly
                          ? Symbols.favorite_rounded
                          : Symbols.kitesurfing_rounded,
                      title: filter.favouritesOnly
                          ? 'No favourites yet'
                          : 'No trainers match',
                      subtitle: filter.favouritesOnly
                          ? 'Tap the heart on any trainer to keep them here.'
                          : 'Try widening your filters or clearing the search.',
                      action:
                          (filter.activeCount > 0 || filter.query.isNotEmpty)
                              ? OutlinedButton(
                                  onPressed: _resetAll,
                                  child: const Text('RESET'),
                                )
                              : null,
                    );
                  }
                  return CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                        sliver: SliverToBoxAdapter(
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${list.length} trainer${list.length == 1 ? '' : 's'}',
                                  style: microLabel(tones.textFaint),
                                ),
                              ),
                              if (filter.activeCount > 0 ||
                                  filter.query.isNotEmpty)
                                TextButton(
                                  onPressed: _resetAll,
                                  child: const Text('RESET'),
                                ),
                            ],
                          ),
                        ),
                      ),
                      // A list, not a grid. The four facts a rider compares —
                      // rating, spot, price, and the face — read faster
                      // stacked against a fixed photo than tiled, and a grid
                      // tile forces every name longer than two words to
                      // ellipse. `Konstantinos Papadopoulos` is a real seeded
                      // trainer and was unreadable at 260px.
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                        sliver: SliverList.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final t = list[i];
                            final r =
                                ratings[t.uid] ?? RatingSummary.none;
                            return ProviderCard(
                              name: t.name,
                              photoUrl: t.photoUrl,
                              rating: r.count > 0 ? r.average : null,
                              reviewCount: r.count > 0 ? r.count : null,
                              location: t.location ?? t.homeSpot,
                              priceLabel: t.hourlyRate == null
                                  ? null
                                  : euro(t.hourlyRate!),
                              badge: t.isStation || t.isSafariOperator
                                  ? const _KindBadge(icon: Symbols.storefront_rounded)
                                  : null,
                              onTap: () => context.push(
                                  t.isStation || t.isSafariOperator
                                      ? '/station/${t.uid}'
                                      : '/trainer/${t.uid}'),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _resetAll() {
    // Cancel first — an in-flight debounce would otherwise re-apply the query
    // we just cleared.
    _debounce?.cancel();
    _search.clear();
    ref.read(exploreFilterProvider.notifier).reset();
  }

  /// Spot (single-select) + languages (multi-select) (§3.3).
  void _openFilterSheet(BuildContext context) {
    showFlowSheet<void>(
      context,
      title: 'Filter trainers',
      builder: (sheetContext) => Consumer(
        builder: (sheetContext, sheetRef, _) {
          final f = sheetRef.watch(exploreFilterProvider);
          final notifier = sheetRef.read(exploreFilterProvider.notifier);
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            children: [
              const SectionHeader('Spot'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final spot in FlowConst.kiteSpots)
                    FlowChoiceChip(
                      label: spot,
                      selected: f.spot == spot,
                      onTap: () {
                        Haptics.select();
                        notifier.setSpot(f.spot == spot ? null : spot);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 24),
              const SectionHeader('Languages'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final lang in FlowConst.languages)
                    FlowChoiceChip(
                      label: lang,
                      selected: f.languages.contains(lang),
                      onTap: () {
                        Haptics.select();
                        notifier.toggleLanguage(lang);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        notifier.setSpot(null);
                        for (final l in {...f.languages}) {
                          notifier.toggleLanguage(l);
                        }
                      },
                      child: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Show results'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonGrid(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: .72,
      ),
      tile: FlowCard(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SkeletonPulse(
                  width: double.infinity, height: 999, radius: 12),
            ),
            SizedBox(height: 12),
            SkeletonPulse(width: 110),
            SizedBox(height: 8),
            SkeletonPulse(width: 70, height: 10),
          ],
        ),
      ),
    );
  }
}

/// Marks a listing that is a centre or a safari operator rather than a person.
///
/// Sits over the photo because that is where the eye already is, and because
/// the alternative — a pill in the text column — competes with the name for
/// the one line that matters most.
class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        // Fixed dark: this sits on a photograph in both themes.
        color: const Color(0xCC04121F),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 13, color: Colors.white),
    );
  }
}
