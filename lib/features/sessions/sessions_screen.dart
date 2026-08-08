import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/radii.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/misc.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/booking.dart';
import '../../providers/providers.dart';
import 'review_composer.dart';

/// Rider sessions — UPCOMING / ACTIVE / HISTORY (§3.7).
/// `?highlight=<bookingId>` selects the tab that actually contains that
/// booking, scrolls it into view and tints it ~4s.
class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key, this.highlightBookingId});

  final String? highlightBookingId;

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  String? _highlight;
  bool _highlightHandled = false;
  final Map<String, GlobalKey> _cardKeys = {};

  @override
  void initState() {
    super.initState();
    _highlight = widget.highlightBookingId;
  }

  @override
  void didUpdateWidget(SessionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightBookingId != oldWidget.highlightBookingId &&
        widget.highlightBookingId != null) {
      _highlight = widget.highlightBookingId;
      _highlightHandled = false;
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _handleHighlight(BookingBuckets buckets) {
    if (_highlight == null || _highlightHandled) return;
    final id = _highlight!;
    for (final (i, bucket) in const [
      BookingBucket.upcoming,
      BookingBucket.active,
      BookingBucket.history
    ].indexed) {
      if (buckets[bucket]!.any((b) => b.id == id)) {
        _highlightHandled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _tabs.animateTo(i);
          // Give the tab switch a beat, then scroll the card into view.
          Future.delayed(const Duration(milliseconds: 350), () {
            if (!mounted) return;
            final ctx = _cardKeys[id]?.currentContext;
            if (ctx == null || !ctx.mounted) return;
            Scrollable.ensureVisible(ctx,
                duration: const Duration(milliseconds: 400),
                alignment: .2,
                curve: Curves.easeOutCubic);
          });
          // Drop the tint after ~4s.
          Future.delayed(const Duration(seconds: 4), () {
            if (mounted) setState(() => _highlight = null);
          });
        });
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final buckets = ref.watch(riderBucketsProvider);

    if (buckets case AsyncData(:final value)) {
      _handleHighlight(value);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My sessions'),
        // All three tabs carry their count once data lands. Labelling only
        // one of them made the other two read as empty at a glance.
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(child: Text(_tabLabel(buckets, 'UPCOMING', BookingBucket.upcoming))),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_tabLabel(buckets, 'ACTIVE', BookingBucket.active)),
                  if (buckets.value?[BookingBucket.active]?.isNotEmpty ??
                      false) ...[
                    const SizedBox(width: 6),
                    const _LiveDot(),
                  ],
                ],
              ),
            ),
            Tab(child: Text(_tabLabel(buckets, 'HISTORY', BookingBucket.history))),
          ],
        ),
      ),
      body: AsyncView<BookingBuckets>(
        value: buckets,
        onRetry: () => ref.invalidate(riderBookingsProvider),
        skeleton: const SkeletonList(count: 4, itemHeight: 120),
        data: (data) => TabBarView(
          controller: _tabs,
          children: [
            _BookingList(
              bookings: data[BookingBucket.upcoming]!,
              cardKeys: _cardKeys,
              highlight: _highlight,
              empty: const EmptyView(
                icon: Icons.event_available_outlined,
                title: 'Nothing booked yet',
                subtitle:
                    'Find a trainer in Explore and lock in your next session.',
              ),
              onRefresh: _refresh,
            ),
            _BookingList(
              bookings: data[BookingBucket.active]!,
              cardKeys: _cardKeys,
              highlight: _highlight,
              empty: const EmptyView(
                icon: Icons.surfing_rounded,
                title: 'No live session',
                subtitle:
                    'When your trainer scans you in, your session shows here.',
              ),
              onRefresh: _refresh,
            ),
            _BookingList(
              bookings: data[BookingBucket.history]!,
              cardKeys: _cardKeys,
              highlight: _highlight,
              empty: const EmptyView(
                icon: Icons.history_rounded,
                title: 'No history yet',
                subtitle: 'Completed and past sessions land here.',
              ),
              onRefresh: _refresh,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(riderBookingsProvider);
    await ref.read(riderBookingsProvider.future);
  }

  /// `UPCOMING (3)` once loaded, bare `UPCOMING` while it isn't — a count of
  /// zero has to mean zero, so it can't be shown before data arrives.
  String _tabLabel(
      AsyncValue<BookingBuckets> buckets, String label, BookingBucket bucket) {
    final list = buckets.value?[bucket];
    return list == null ? label : '$label (${list.length})';
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: FlowMotion.pulse)
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: .4, end: 1.0).animate(_c),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
            color: context.tones.success, shape: BoxShape.circle),
      ),
    );
  }
}

class _BookingList extends ConsumerWidget {
  const _BookingList({
    required this.bookings,
    required this.cardKeys,
    required this.highlight,
    required this.empty,
    required this.onRefresh,
  });

  final List<Booking> bookings;
  final Map<String, GlobalKey> cardKeys;
  final String? highlight;
  final Widget empty;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (bookings.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [const SizedBox(height: 60), empty]),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        itemCount: bookings.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final b = bookings[i];
          return SessionCard(
            key: cardKeys.putIfAbsent(b.id, GlobalKey.new),
            booking: b,
            highlighted: b.id == highlight,
          );
        },
      ),
    );
  }
}

/// One rider booking card: date block, title, time, price, status pill,
/// sub-label, and status-dependent actions (§3.7).
class SessionCard extends ConsumerWidget {
  const SessionCard({
    super.key,
    required this.booking,
    this.highlighted = false,
  });

  final Booking booking;
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final day = parseYmd(booking.date);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlighted
            ? tones.azureBrand.withValues(alpha: .1)
            : tones.card,
        borderRadius: FlowRadii.card,
        border: Border.all(
            color: highlighted
                ? tones.azureBrand.withValues(alpha: .6)
                : tones.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DateBlock(date: day),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(booking.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      '${booking.instructorName} · ${booking.timeRange}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: inter(12.5, 500, color: tones.textFaint),
                    ),
                    const SizedBox(height: 6),
                    // Wraps rather than overflows: a completed session shows
                    // two pills plus its sub-label, which does not fit on one
                    // line on a small phone at the largest text scale.
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusPill(status: booking.status),
                        // Only once the session is over. Before that "Unpaid"
                        // is technically true and completely unhelpful —
                        // nobody pays for a lesson they have not had.
                        if (booking.status == BookingStatus.completed)
                          PaymentPill(booking.payment),
                        Text(booking.subLabel,
                            style:
                                inter(11.5, 520, color: tones.textFaint)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(euro(booking.totalPrice),
                  style: interNum(17, 760, color: tones.azureBrand)),
            ],
          ),
          ..._actions(context, ref),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context, WidgetRef ref) {
    final actions = <Widget>[];
    switch (booking.status) {
      case BookingStatus.pending:
        actions.add(_cancelButton(context, ref));
      case BookingStatus.confirmed:
        if (!booking.isPast && !booking.isSafari) {
          actions.add(Expanded(
            child: MicroAction(
              label: 'CHECK IN',
              icon: Icons.qr_code_2_rounded,
              onPressed: () => showQrTicket(context, booking),
            ),
          ));
        }
        actions.add(_cancelButton(context, ref));
      case BookingStatus.inProgress:
        actions.add(Expanded(
          child: MicroAction(
            label: 'SHOW TICKET',
            icon: Icons.qr_code_2_rounded,
            onPressed: () => showQrTicket(context, booking),
          ),
        ));
      case BookingStatus.completed:
        actions.add(Expanded(
          child: MicroAction(
            label: 'RATE',
            icon: Icons.star_outline_rounded,
            filled: false,
            onPressed: () => _openRateSheet(context),
          ),
        ));
      case _:
        break;
    }
    if (actions.isEmpty) return const [];
    return [
      const SizedBox(height: 12),
      Row(
        children: [
          for (final (i, a) in actions.indexed) ...[
            if (i > 0) const SizedBox(width: 10),
            a,
          ],
        ],
      ),
    ];
  }

  Widget _cancelButton(BuildContext context, WidgetRef ref) => Expanded(
        child: MicroAction(
          label: 'CANCEL',
          filled: false,
          color: context.tones.danger,
          onPressed: () async {
            // Confirmation names the session and date; warns the trainer is
            // notified (§10.4).
            final ok = await confirmAction(
              context,
              title: 'Cancel this session?',
              body:
                  '${booking.title} on ${longYmd(booking.date)} will be cancelled '
                  'and your trainer will be notified.',
              confirmLabel: 'Cancel session',
              cancelLabel: 'Keep it',
              destructive: true,
            );
            if (!ok) return;
            try {
              await ref.read(bookingRepositoryProvider).cancelByRider(booking);
              if (context.mounted) {
                showFlowToast(context, 'Session cancelled');
              }
            } catch (_) {
              // The rider was told their trainer would be notified. If the
              // write failed they must not be left assuming it went through
              // — they would simply not turn up.
              if (context.mounted) {
                showFlowToast(
                    context, "Couldn't cancel the session. Try again.");
              }
            }
          },
        ),
      );

  /// Inline rate — stars + comment without leaving the screen (§3.7).
  void _openRateSheet(BuildContext context) {
    showFlowSheet<void>(
      context,
      title: 'Rate your session',
      subtitle: '${booking.instructorName} · ${prettyYmd(booking.date)}',
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: ReviewComposerCard(
          trainerId: booking.instructorId,
          bookingId: booking.id,
          onSubmitted: () => Navigator.pop(sheetContext),
        ),
      ),
    );
  }
}

/// A booking's status as a pill. The colour mapping is the only thing this
/// adds over [TagPill] — the drawing is shared, so a status pill and a tag can
/// no longer drift apart.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final color = switch (status) {
      BookingStatus.pending => tones.warning,
      BookingStatus.confirmed => tones.success,
      BookingStatus.inProgress => tones.azureBrand,
      BookingStatus.completed => context.scheme.onSurfaceVariant,
      _ => tones.danger,
    };
    return TagPill(status.label.toUpperCase(), color: color, dense: true);
  }
}

/// The QR ticket (§3.7, §12.2): encodes `{"bookingId":…,"trainerId":…}`,
/// always on white so scanners work in dark mode, watches the booking live
/// and flips to "Session started" (with a haptic) the moment the trainer
/// scans.
void showQrTicket(BuildContext context, Booking booking) {
  showDialog<void>(
    context: context,
    builder: (_) => _QrTicketDialog(booking: booking),
  );
}

class _QrTicketDialog extends ConsumerStatefulWidget {
  const _QrTicketDialog({required this.booking});
  final Booking booking;

  @override
  ConsumerState<_QrTicketDialog> createState() => _QrTicketDialogState();
}

class _QrTicketDialogState extends ConsumerState<_QrTicketDialog> {
  bool _startedHapticFired = false;

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(bookingByIdProvider(widget.booking.id)).value ??
        widget.booking;
    final started = live.status == BookingStatus.inProgress;

    if (started && !_startedHapticFired) {
      _startedHapticFired = true;
      Haptics.medium();
    }

    final payload = jsonEncode({
      'bookingId': widget.booking.id,
      'trainerId': widget.booking.instructorId,
    });

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: started
                  ? Column(
                      key: const ValueKey('started'),
                      children: [
                        FlowIconChip(
                          icon: Icons.surfing_rounded,
                          color: context.tones.success,
                          size: 76,
                          borderRadius:
                              const BorderRadius.all(Radius.circular(38)),
                        ),
                        const SizedBox(height: 16),
                        Text('Session started',
                            style:
                                Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 6),
                        Text('Have a great one out there 🤙',
                            style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    )
                  : Column(
                      key: const ValueKey('ticket'),
                      children: [
                        Text('Your beach ticket',
                            style:
                                Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 6),
                        Text(
                          'Show this to ${widget.booking.instructorName} to start.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 18),
                        // Always white — scanners must work in dark mode.
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: FlowRadii.card,
                          ),
                          child: QrImageView(
                            data: payload,
                            version: QrVersions.auto,
                            size: 196,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Color(0xFF020F2B),
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Color(0xFF020F2B),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '${prettyYmd(widget.booking.date)} · ${widget.booking.timeRange}',
                          style: interNum(14, 640,
                              color: context.scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 18),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(started ? 'Close' : 'Done'),
            ),
          ],
        ),
      ),
    );
  }
}
