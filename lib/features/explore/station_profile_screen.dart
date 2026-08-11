import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/flow_image.dart';
import '../../core/widgets/misc.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/app_user.dart';
import '../../data/models/catalogue.dart';
import '../../data/repositories/booking_repository.dart';
import '../../providers/providers.dart';

/// Station / safari-operator profile with type-dependent tabs (§3.5).
class StationProfileScreen extends ConsumerWidget {
  const StationProfileScreen({super.key, required this.stationId});

  final String stationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(trainerProfileProvider(stationId));
    return Scaffold(
      body: AsyncView<AppUser?>(
        value: profile,
        onRetry: () => ref.invalidate(trainerProfileProvider(stationId)),
        data: (station) {
          if (station == null) {
            return EmptyView(
              icon: Symbols.storefront_rounded,
              title: 'Not found',
              subtitle: 'This operator may have been removed.',
              action: OutlinedButton(
                  onPressed: () => context.pop(), child: const Text('Go back')),
            );
          }
          return _StationBody(station: station);
        },
      ),
    );
  }
}

class _StationBody extends ConsumerWidget {
  const _StationBody({required this.station});
  final AppUser station;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safariOnly = station.isSafariOperator && !station.isStation;
    final instructors =
        ref.watch(stationInstructorsProvider(station.uid)).value ?? const [];
    final services =
        ref.watch(stationServicesProvider(station.uid)).value ?? const [];
    final trips =
        ref.watch(safariTripsProvider(station.uid)).value ?? const [];

    final rentals =
        [for (final s in services) if (s.kind == ServiceKind.rental) s];
    final beach =
        [for (final s in services) if (s.kind == ServiceKind.beachUse) s];

    final tabs = safariOnly
        ? [Tab(text: 'EXPEDITIONS (${trips.length})')]
        : [
            Tab(text: 'LESSONS (${instructors.length})'),
            Tab(text: 'RENTALS (${rentals.length})'),
            Tab(text: 'BEACH (${beach.length})'),
          ];

    // Scrollable, because three labels that each carry a count cannot be
    // promised to fit a third of a narrow phone: at 1.3x text they ran into
    // each other, and a non-scrollable TabBar has nowhere to put the excess
    // so the labels simply overlapped. Left-aligned like the admin console's.
    final tabBar = TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      tabs: tabs,
    );

    return DefaultTabController(
      length: tabs.length,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            pinned: true,
            expandedHeight: 260,
            leading: Center(
              child: ScrimIconButton(
                icon: Symbols.arrow_back_rounded,
                tooltip: 'Back',
                onTap: () => context.pop(),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  FlowImage(
                      url: station.photoUrl,
                      placeholderIcon: Symbols.storefront_rounded),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: .55),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    // `flexibleSpace` fills the WHOLE app bar, including the
                    // strip `bottom` occupies — so anything placed against
                    // its bottom edge lands *behind* the tabs. That is what
                    // put the location and STATION chips under the tab row.
                    bottom: tabBar.preferredSize.height + 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(station.name,
                            style: display(26, 760,
                                color: Colors.white, spacing: -.5)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            TagPill(station.location ?? 'Red Sea',
                                icon: Symbols.place_rounded,
                                color: Colors.white),
                            TagPill(
                              safariOnly ? 'SAFARI OPERATOR' : 'STATION',
                              icon: safariOnly
                                  ? Symbols.sailing_rounded
                                  : Symbols.storefront_rounded,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            bottom: tabBar,
          ),
          if ((station.bio ?? '').isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text(station.bio!,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium!
                        .copyWith(height: 1.5)),
              ),
            ),
        ],
        body: TabBarView(
          children: safariOnly
              ? [_ExpeditionsTab(station: station, trips: trips)]
              : [
                  _LessonsTab(station: station, instructors: instructors),
                  _ServicesTab(
                      station: station,
                      services: rentals,
                      bookingType: 'rental',
                      emptyLabel: 'No rentals listed yet.'),
                  _ServicesTab(
                      station: station,
                      services: beach,
                      bookingType: 'beach_use',
                      emptyLabel: 'No beach passes listed yet.'),
                ],
        ),
      ),
    );
  }
}

/// Station instructors — BOOK opens the booking flow against the *station's*
/// calendar with the instructor as subTarget (§3.5).
class _LessonsTab extends StatelessWidget {
  const _LessonsTab({required this.station, required this.instructors});

  final AppUser station;
  final List<StationInstructor> instructors;

  @override
  Widget build(BuildContext context) {
    if (instructors.isEmpty) {
      return const EmptyView(
          icon: Symbols.school_rounded,
          title: 'No instructors listed',
          subtitle: 'Check back soon.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: instructors.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final ins = instructors[i];
        final tones = context.tones;
        return FlowCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              FlowAvatar(url: ins.photoUrl, name: ins.name, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ins.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (ins.level != null) ins.level!,
                        '${euro(ins.displayRate)}/h',
                      ].join(' · '),
                      style: inter(12.5, 500, color: tones.textFaint),
                    ),
                  ],
                ),
              ),
              MicroAction(
                label: 'BOOK',
                onPressed: () => context.push(
                  '/book/${station.uid}',
                  extra: BookingTarget(
                    providerId: station.uid,
                    title: station.name,
                    rate: ins.displayRate,
                    subtitle: station.location,
                    imageUrl: ins.photoUrl ?? station.photoUrl,
                    bookingType: 'station_lesson',
                    subTarget: ins.name,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ServicesTab extends StatelessWidget {
  const _ServicesTab({
    required this.station,
    required this.services,
    required this.bookingType,
    required this.emptyLabel,
  });

  final AppUser station;
  final List<StationService> services;
  final String bookingType;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (services.isEmpty) {
      return EmptyView(
          icon: bookingType == 'rental'
              ? Symbols.surfing_rounded
              : Symbols.beach_access_rounded,
          title: emptyLabel);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: services.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final s = services[i];
        final tones = context.tones;
        return FlowCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    if ((s.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(s.description!,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      '${euro(s.price)}${s.unit != null ? ' / ${s.unit}' : ''}',
                      style: interNum(15, 760, color: tones.azureBrand),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              MicroAction(
                label: 'BOOK',
                onPressed: () => context.push(
                  '/book/${station.uid}',
                  extra: BookingTarget(
                    providerId: station.uid,
                    title: station.name,
                    rate: s.price,
                    subtitle: station.location,
                    imageUrl: station.photoUrl,
                    unit: s.unit ?? 'hour',
                    bookingType: bookingType,
                    subTarget: s.name,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Safari trips with a seats-left counter and transactional reservation
/// (§3.5, §8.6).
class _ExpeditionsTab extends ConsumerWidget {
  const _ExpeditionsTab({required this.station, required this.trips});

  final AppUser station;
  final List<SafariTrip> trips;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (trips.isEmpty) {
      return const EmptyView(
          icon: Symbols.sailing_rounded,
          title: 'No expeditions scheduled',
          subtitle: 'New trips appear here as soon as they open.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: trips.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, i) => _TripCard(station: station, trip: trips[i]),
    );
  }
}

class _TripCard extends ConsumerStatefulWidget {
  const _TripCard({required this.station, required this.trip});

  final AppUser station;
  final SafariTrip trip;

  @override
  ConsumerState<_TripCard> createState() => _TripCardState();
}

class _TripCardState extends ConsumerState<_TripCard> {
  bool _busy = false;

  Future<void> _reserve() async {
    final trip = widget.trip;
    final ok = await confirmAction(
      context,
      title: 'Reserve your seat?',
      body:
          '${trip.title} · departs ${prettyYmd(trip.startDate)} · ${euro(trip.price)} per seat, settled in person.',
      confirmLabel: 'Reserve',
      cancelLabel: 'Not yet',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final session = ref.read(sessionProvider);
      await ref.read(bookingRepositoryProvider).reserveSafariSeat(
            trip: trip,
            hostName: widget.station.name,
            riderUid: session.uid,
            riderName: session.displayName,
          );
      Haptics.medium();
      if (mounted) {
        showFlowToast(context, 'Seat reserved — see you on board 🛥️');
      }
    } on SlotTakenFailure {
      if (mounted) {
        showFlowToast(context, 'The manifest just filled up. Trip is full.');
      }
    } catch (_) {
      if (mounted) {
        showFlowToast(context, "Couldn't reserve. Try again.");
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final tones = context.tones;
    return FlowCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(trip.title,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              if (trip.duration != null)
                TagPill(trip.duration!, icon: Symbols.schedule_rounded),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Symbols.event_rounded, size: 15, color: tones.textFaint),
              const SizedBox(width: 4),
              // Expanded rather than a trailing Spacer: the date and the
              // price both grow with the text scale, and a Spacer can only
              // give away slack that exists. This lets the date yield.
              Expanded(
                child: Text('Departs ${prettyYmd(trip.startDate)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: inter(14, 540, color: tones.textFaint)),
              ),
              const SizedBox(width: 8),
              Text(euro(trip.price),
                  style: interNum(17, 760, color: tones.azureBrand)),
              Text(' / seat', style: inter(12.5, 540, color: tones.textFaint)),
            ],
          ),
          if ((trip.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(trip.description!,
                style:
                    Theme.of(context).textTheme.bodyMedium!.copyWith(height: 1.5)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: trip.fillRatio,
                    minHeight: 6,
                    color: trip.isSoldOut ? tones.danger : tones.success,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                trip.isSoldOut
                    ? 'Manifest full'
                    : '${trip.seatsLeft} seat${trip.seatsLeft == 1 ? '' : 's'} left',
                style: inter(12.5, 640,
                    color: trip.isSoldOut ? tones.danger : tones.success),
              ),
            ],
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: trip.isSoldOut ? 'Manifest full' : 'Reserve my seat',
            icon: trip.isSoldOut ? null : Symbols.sailing_rounded,
            busy: _busy,
            onPressed: trip.isSoldOut ? null : _reserve,
          ),
        ],
      ),
    );
  }
}
