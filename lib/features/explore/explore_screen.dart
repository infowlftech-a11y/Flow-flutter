import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/radii.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/flow_image.dart';
import '../../core/widgets/misc.dart';
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
                        child: const Icon(Icons.notifications_outlined),
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
                              const Icon(Icons.search_rounded, size: 22),
                          suffixIcon: value.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: _clearQuery,
                                  icon:
                                      const Icon(Icons.close_rounded, size: 20),
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
                          child: const Icon(Icons.tune_rounded),
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
                          ? Icons.favorite_outline_rounded
                          : Icons.kitesurfing_rounded,
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
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 260,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            childAspectRatio: .72,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => _TrainerCard(
                              trainer: list[i],
                              rating: ratings[list[i].uid] ??
                                  RatingSummary.none,
                            ),
                            childCount: list.length,
                          ),
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

class _TrainerCard extends ConsumerWidget {
  const _TrainerCard({required this.trainer, required this.rating});

  final AppUser trainer;
  final RatingSummary rating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final me = ref.watch(currentUserProvider).value;
    final isFav = me?.favorites.contains(trainer.uid) ?? false;

    return Material(
      color: tones.card,
      borderRadius: FlowRadii.card,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(trainer.isStation || trainer.isSafariOperator
            ? '/station/${trainer.uid}'
            : '/trainer/${trainer.uid}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FlowImage(url: trainer.photoUrl),
                  Positioned(
                    // 3 + the 5dp of transparent padding inside the 48dp hit
                    // box = the puck still sits 8dp off the corner.
                    top: 3,
                    right: 3,
                    child: _FavHeart(
                      isFav: isFav,
                      onTap: me == null
                          ? null
                          : () {
                              Haptics.light();
                              // Optimistic — Firestore latency compensation
                              // flips the stream instantly.
                              ref
                                  .read(userRepositoryProvider)
                                  .setFavorite(me.uid, trainer.uid, !isFav)
                                  .ignore();
                            },
                    ),
                  ),
                  if (trainer.isStation)
                    const Positioned(
                        left: 8,
                        top: 8,
                        child: TagPill('STATION',
                            icon: Icons.storefront_rounded)),
                  if (trainer.isSafariOperator)
                    const Positioned(
                        left: 8,
                        top: 8,
                        child:
                            TagPill('SAFARI', icon: Icons.sailing_rounded)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          trainer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Icon(Icons.star_rounded,
                          size: 15, color: tones.warning),
                      const SizedBox(width: 2),
                      Text(rating.display,
                          style: interNum(12.5, 700,
                              color: context.scheme.onSurface)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.place_outlined,
                          size: 13, color: tones.textFaint),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          trainer.location ?? 'Red Sea',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: inter(12.5, 480, color: tones.textFaint),
                        ),
                      ),
                      Text(euro(trainer.displayRate),
                          style: interNum(14, 760,
                              color: tones.azureBrand)),
                      Text('/h',
                          style: inter(11.5, 560, color: tones.textFaint)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavHeart extends StatelessWidget {
  const _FavHeart({required this.isFav, required this.onTap});

  final bool isFav;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isFav ? 'Remove from favourites' : 'Add to favourites',
      // The visible puck stays 38dp so it doesn't crowd the photo, but the
      // hit area is padded out to the 48dp minimum — this sits in a card
      // corner, where a near-miss navigates to the profile instead.
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .35),
                shape: BoxShape.circle,
              ),
              child: AnimatedSwitcher(
                duration: FlowMotion.base,
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  isFav
                      ? Icons.favorite_rounded
                      : Icons.favorite_outline_rounded,
                  key: ValueKey(isFav),
                  size: 20,
                  color: isFav ? const Color(0xFFFF5D72) : Colors.white,
                ),
              ),
            ),
          ),
        ),
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
