import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/radii.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/dashboard.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/flow_image.dart';
import '../../core/widgets/media.dart';
import '../../core/widgets/misc.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/booking.dart';
import '../../data/repositories/booking_repository.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../sessions/sessions_screen.dart' show StatusPill;
import 'qr_scanner_screen.dart';

/// Scan a rider's ticket and start the session (§3.8, §3.10).
///
/// The one check-in path. It was written twice — once on the screen's State for
/// the CHECK IN action, once on `_ManifestCard` for SCAN TO START — identical
/// but for the liveness guard each context could reach: `mounted` on the State,
/// `context.mounted` on the widget. Two copies of a flow that starts a session
/// and takes money is two places for the error handling to drift, so it is one
/// function guarding on `context.mounted`, which is the stricter of the two
/// (a State's context is unmounted exactly when its State is).
Future<void> runCheckInScan(BuildContext context, WidgetRef ref) async {
  final trainerId = ref.read(sessionProvider).uid;
  final bookingId = await Navigator.of(context, rootNavigator: true)
      .push<String>(MaterialPageRoute(
          builder: (_) => QrScannerScreen(trainerId: trainerId)));
  if (bookingId == null || !context.mounted) return;
  try {
    await ref
        .read(bookingRepositoryProvider)
        .checkIn(bookingId, trainerId: trainerId);
    if (context.mounted) showFlowToast(context, 'Session started 🤙');
  } on CheckInFailure catch (e) {
    // A refused ticket is not a retry case — say which ticket it was.
    if (context.mounted) showFlowToast(context, e.message);
  } catch (_) {
    if (context.mounted) {
      showFlowToast(context, "Couldn't start the session. Try again.");
    }
  }
}

/// The one session on today's manifest that earns a card instead of a row.
///
/// A session already running wins outright — it is the only thing happening on
/// the beach. Otherwise it is the next one still ahead, which is the session
/// whose SCAN TO START button the trainer is about to need. When the day is
/// over there is no focus at all and today reads as a list of rows, which is
/// exactly what it then is.
///
/// Pure and public because the ordering is the whole point and it is invisible
/// on screen: a manifest that promoted a finished 09:00 over a live 14:00 puts
/// the wrong button under the trainer's thumb, and nothing about the layout
/// would look wrong.
Booking? todayFocus(List<Booking> today, {DateTime? now}) {
  final clock = now ?? DateTime.now();

  for (final b in today) {
    if (b.status == BookingStatus.inProgress) return b;
  }

  Booking? next;
  for (final b in today) {
    if (b.status != BookingStatus.confirmed) continue;
    final ends = b.endsAt;
    if (ends != null && clock.isAfter(ends)) continue;
    final start = b.startsAt ?? DateTime(2100);
    if (next == null || start.isBefore(next.startsAt ?? DateTime(2100))) {
      next = b;
    }
  }
  return next;
}

/// Trainer home: TODAY + SCHEDULE, with a persistent CHECK IN action (§3.8).
class CommandCenterScreen extends ConsumerStatefulWidget {
  const CommandCenterScreen({super.key});

  @override
  ConsumerState<CommandCenterScreen> createState() =>
      _CommandCenterScreenState();
}

class _CommandCenterScreenState extends ConsumerState<CommandCenterScreen> {
  final _requestsKey = GlobalKey();
  final _todayScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTour());
  }

  @override
  void dispose() {
    _todayScroll.dispose();
    super.dispose();
  }

  /// 4-step first-run tour, shown once per uid (§3.8).
  Future<void> _maybeShowTour() async {
    final uid = ref.read(sessionProvider).uid;
    if (uid.isEmpty) return;
    final flags = ref.read(onboardingFlagsProvider.notifier);
    if (flags.trainerTourDone(uid)) return;
    if (!mounted) return;
    await showTrainerTour(context);
    await flags.setTrainerTourDone(uid);
  }

  void _scrollToRequests() {
    // No tab to switch to any more — the requests are on this screen, so this
    // is now purely a scroll.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _requestsKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 350),
            alignment: .05,
            curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadNotificationCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Command Center'),
        actions: [
          Semantics(
            label: unread > 0
                ? '$unread unread notification${unread == 1 ? '' : 's'}'
                : 'Notifications',
            button: true,
            child: IconButton(
              onPressed: () => context.push('/notifications'),
              tooltip: 'Notifications',
              icon: Badge.count(
                count: unread,
                isLabelVisible: unread > 0,
                child: const Icon(Symbols.notifications_rounded),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => runCheckInScan(context, ref),
        icon: const Icon(Symbols.qr_code_scanner_rounded),
        label: const Text('CHECK IN'),
      ),
      // No tabs. The redesign lifted the schedule to its own destination in
      // the navigation bar, and leaving the SCHEDULE tab here as well gave a
      // trainer the same screen in two places — one of them reachable only by
      // remembering it was behind a tab on a different screen. The dashboard
      // is now what its name says: today.
      body: _TodayTab(
        requestsKey: _requestsKey,
        scrollController: _todayScroll,
        onRequestsTap: _scrollToRequests,
      ),
    );
  }
}

class _TodayTab extends ConsumerWidget {
  const _TodayTab({
    required this.requestsKey,
    required this.scrollController,
    required this.onRequestsTap,
  });

  final GlobalKey requestsKey;
  final ScrollController scrollController;
  final VoidCallback onRequestsTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(trainerBookingsProvider);
    final requests = ref.watch(pendingRequestsProvider);
    final manifest = ref.watch(todayManifestProvider);
    final buckets = ref.watch(trainerBucketsProvider);
    final revenue = ref.watch(trainerRevenueProvider);

    return AsyncView<List<Booking>>(
      value: bookings,
      onRetry: () => ref.invalidate(trainerBookingsProvider),
      onRefresh: () async {
        ref.invalidate(trainerBookingsProvider);
        await ref.read(trainerBookingsProvider.future);
      },
      // Cold start must not claim 0/0/€0 (§10.2).
      skeleton: const SkeletonList(count: 5, itemHeight: 100),
      data: (_) {
        final upcoming =
            buckets.value?[BookingBucket.upcoming] ?? const <Booking>[];
        final pending = requests.value ?? const <Booking>[];
        final today = manifest.value ?? const <Booking>[];
        final comingUp = [
          for (final b in upcoming)
            if (b.date != todayYmd()) b,
        ].take(FlowConst.comingUpLimit).toList();
        final focus = todayFocus(today);

        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
          children: [
            Row(
              children: [
                _StatTile(
                  label: 'Requests',
                  value: '${pending.length}',
                  icon: Symbols.pending_actions_rounded,
                  emphasized: pending.isNotEmpty,
                  onTap: onRequestsTap,
                ),
                const SizedBox(width: 10),
                _StatTile(
                  label: 'Upcoming',
                  value: '${upcoming.length}',
                  icon: Symbols.event_rounded,
                ),
                const SizedBox(width: 10),
                _StatTile(
                  // One word, like the two beside it — REQUESTS · UPCOMING ·
                  // EARNED. The payments icon and the figure carry the rest.
                  label: 'Earned',
                  value: money(revenue.value ?? 0),
                  icon: Symbols.payments_rounded,
                  // The ledger is a tab now. It was a sheet behind this tile,
                  // which made "how am I doing" a thing you had to already
                  // know where to find.
                  onTap: () => context.go('/earnings'),
                ),
              ],
            ),
            if (pending.isNotEmpty) ...[
              const SizedBox(height: 28),
              KeyedSubtree(
                key: requestsKey,
                child: const SectionHeader('Action required'),
              ),
              for (final b in pending) _RequestCard(booking: b),
            ] else
              KeyedSubtree(key: requestsKey, child: const SizedBox.shrink()),
            const SizedBox(height: 28),
            SectionHeader('Today · ${prettyYmd(todayYmd())}'),
            if (today.isEmpty)
              const _EmptyToday()
            else
              // One card, the rest rows. Six sessions used to mean six tall
              // cards each offering SCAN TO START, and only one of them was
              // ever the next thing to do — so the button that matters was
              // indistinguishable from five that did not.
              for (final b in today)
                if (b.id == focus?.id)
                  _ManifestCard(booking: b)
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AgendaRow(
                      time: b.startTime ?? '--:--',
                      name: b.studentName,
                      live: b.status == BookingStatus.inProgress,
                      statusLabel: switch (b.status) {
                        BookingStatus.completed => 'Done',
                        BookingStatus.pending => 'Pending',
                        _ => null,
                      },
                      onTap: () => openManifestDetails(context, ref, b),
                    ),
                  ),
            if (comingUp.isNotEmpty) ...[
              const SizedBox(height: 28),
              const SectionHeader('Coming up'),
              for (final b in comingUp) _ComingUpRow(booking: b),
            ],
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        borderRadius: FlowRadii.card,
        child: InkWell(
          borderRadius: FlowRadii.card,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              gradient: emphasized ? tones.heroGradient : null,
              color: emphasized ? null : tones.card,
              borderRadius: FlowRadii.card,
              border: Border.all(
                  color: emphasized
                      ? tones.azureBrand.withValues(alpha: .5)
                      : tones.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon,
                    size: 19,
                    color: emphasized
                        ? tones.azureBrand
                        : tones.textFaint),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value,
                      style: display(22, 760,
                          color: emphasized
                              ? Colors.white
                              : context.scheme.onSurface,
                          spacing: -.5)),
                ),
                const SizedBox(height: 2),
                // Scaled down like the value above it. A third of a 360px row
                // leaves 72px inside the padding, and a letterspaced caps
                // label crosses that at 1.3x — `UPCOMING` by a hair, and
                // `TOTAL EARNED` by enough to read as `TOTAL EA…`.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label.toUpperCase(),
                      maxLines: 1,
                      style: microLabel(
                          emphasized
                              ? Colors.white.withValues(alpha: .75)
                              : tones.textFaint,
                          size: 10)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyToday extends StatelessWidget {
  const _EmptyToday();

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return FlowCard(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Icon(Symbols.air_rounded, color: tones.azureBrand, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No sessions today',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text('Enjoy the wind.',
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pending request: APPROVE is confirmed + busy-guarded + haptic + UNDO in
/// the toast; DECLINE opens a sheet for an optional reason (§3.8, §10.4).
class _RequestCard extends ConsumerStatefulWidget {
  const _RequestCard({required this.booking});
  final Booking booking;

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  bool _busy = false;

  Future<void> _approve() async {
    if (_busy) return;
    // Confirmed, with the terms restated: approving commits the hours and
    // the price, and APPROVE sits one thumb-width from DECLINE on a card
    // read outdoors. The UNDO toast covers a change of mind for a few
    // seconds; this covers the tap itself.
    final b = widget.booking;
    final ok = await confirmAction(
      context,
      title: 'Approve this booking?',
      body: '${b.studentName} · ${b.startTime}–${b.endTime} · '
          '${money(b.totalPrice)}. They are notified and the hours are '
          'committed to your calendar.',
      confirmLabel: 'Approve',
      cancelLabel: 'Not yet',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final repo = ref.read(bookingRepositoryProvider);
    try {
      Haptics.medium();
      await repo.setStatus(widget.booking, BookingStatus.confirmed);
      if (mounted) {
        showFlowToast(
          context,
          '${widget.booking.studentName} approved',
          undoLabel: 'UNDO',
          onUndo: () =>
              repo.setStatus(widget.booking, BookingStatus.pending).ignore(),
        );
      }
    } on StatusConflictFailure catch (e) {
      // The row went stale under the tap — the rider cancelled, or another
      // device already decided. Say which; "try again" would be a lie.
      if (mounted) showFlowToast(context, e.message);
    } catch (_) {
      if (mounted) showFlowToast(context, "Couldn't approve. Try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    if (_busy) return;
    final reason = TextEditingController();
    final send = await showFlowSheet<bool>(
      context,
      title: 'Decline this request?',
      subtitle: 'The rider is notified — a reason softens the blow.',
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: reason,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                  hintText: 'Reason (optional) — e.g. "No wind forecast"'),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Decline request',
              destructive: true,
              onPressed: () => Navigator.pop(sheetContext, true),
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext, false),
              child: const Text('Keep it pending'),
            ),
          ],
        ),
      ),
    );
    if (send != true || !mounted) {
      reason.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      Haptics.medium();
      await ref.read(bookingRepositoryProvider).setStatus(
          widget.booking, BookingStatus.rejected,
          declineReason: reason.text);
      if (mounted) showFlowToast(context, 'Request declined');
    } on StatusConflictFailure catch (e) {
      if (mounted) showFlowToast(context, e.message);
    } catch (_) {
      if (mounted) showFlowToast(context, "Couldn't decline. Try again.");
    } finally {
      reason.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final tones = context.tones;

    // Nothing extra to say means nothing extra to draw. A request with no
    // message and no gear need is fully described by who, when and how much,
    // and a trainer with eight of those should not scroll eight cards to
    // answer them. The ones that carry a message keep the card, because the
    // message is the part of the decision a row cannot hold.
    if ((b.message ?? '').isEmpty && !b.gearNeeded) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: RequestRow(
          when: '${prettyYmd(b.date)} · ${b.timeRange}',
          name: b.studentName,
          location: [
            if (b.studentLevel != null) b.studentLevel!,
            money(b.totalPrice),
          ].join(' · '),
          busy: _busy,
          onApprove: _approve,
          onDecline: _decline,
        ),
      );
    }

    return FlowCard(
      margin: const EdgeInsets.only(bottom: 12),
      borderColor: tones.warning.withValues(alpha: .45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FlowAvatar(name: b.studentName, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.studentName,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      [
                        if (b.studentLevel != null) b.studentLevel!,
                        '${prettyYmd(b.date)} · ${b.timeRange}',
                      ].join(' · '),
                      style: inter(12.5, 500, color: tones.textFaint),
                    ),
                  ],
                ),
              ),
              Text(money(b.totalPrice),
                  style: interNum(17, 760, color: tones.azureBrand)),
            ],
          ),
          if ((b.message ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: context.scheme.surfaceContainerHighest
                    .withValues(alpha: .5),
                borderRadius: FlowRadii.chip,
              ),
              child: Text('"${b.message}"',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium!
                      .copyWith(fontStyle: FontStyle.italic)),
            ),
          ],
          if (b.gearNeeded) ...[
            const SizedBox(height: 10),
            const TagPill('NEEDS GEAR', icon: Symbols.settings_input_component_rounded),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: MicroAction(
                  label: 'DECLINE',
                  filled: false,
                  color: tones.danger,
                  onPressed: _busy ? null : _decline,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: MicroAction(
                  label: _busy ? '…' : 'APPROVE',
                  icon: Symbols.check_rounded,
                  onPressed: _busy ? null : _approve,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Today's manifest card (§3.8).
class _ManifestCard extends ConsumerWidget {
  const _ManifestCard({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = booking;
    final tones = context.tones;
    return FlowCard(
      margin: const EdgeInsets.only(bottom: 12),
      borderColor: b.status == BookingStatus.inProgress
          ? tones.success.withValues(alpha: .5)
          : null,
      onTap: () => _openDetails(context, ref),
      child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: tones.azureBrand.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(b.startTime ?? '--:--',
                          style: interNum(14, 740,
                              color: tones.azureBrand)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.studentName,
                              style:
                                  Theme.of(context).textTheme.titleMedium),
                          Row(
                            children: [
                              Text(b.timeRange,
                                  style: inter(12.5, 500,
                                      color: tones.textFaint)),
                              if (b.isManual) ...[
                                const SizedBox(width: 8),
                                const TagPill('WALK-IN'),
                              ],
                              if (b.gearNeeded) ...[
                                const SizedBox(width: 6),
                                const TagPill('GEAR'),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Text(money(b.totalPrice),
                        style:
                            interNum(15, 760, color: tones.azureBrand)),
                  ],
                ),
                const SizedBox(height: 12),
                if (b.status == BookingStatus.confirmed)
                  SizedBox(
                    width: double.infinity,
                    child: MicroAction(
                      label: 'SCAN TO START',
                      icon: Symbols.qr_code_scanner_rounded,
                      onPressed: () => runCheckInScan(context, ref),
                    ),
                  )
                else if (b.status == BookingStatus.inProgress)
                  SizedBox(
                    width: double.infinity,
                    child: MicroAction(
                      label: 'FINISH SESSION',
                      icon: Symbols.flag_rounded,
                      color: tones.success,
                      onPressed: () => _finish(context, ref),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    // Finishing and settling are one decision on the beach, so they are one
    // sheet. Asking "finish?" and then "paid?" back to back would be two
    // dialogs for a moment where the trainer is standing in the wind holding
    // a kite — and the second one would get dismissed unread.
    final paid = await _askSettlement(context, ref);
    if (paid == null) return; // Cancelled.

    Haptics.medium();
    // Guarded like _approve/_decline above. Unhandled, a rejected write threw
    // into the zone and the trainer saw nothing at all happen — no error, no
    // toast, the card still offering FINISH SESSION.
    try {
      await ref
          .read(bookingRepositoryProvider)
          .setStatus(booking, BookingStatus.completed);
    } on StatusConflictFailure catch (e) {
      if (context.mounted) showFlowToast(context, e.message);
      return;
    } catch (_) {
      if (context.mounted) {
        showFlowToast(context, "Couldn't finish the session. Try again.");
      }
      return;
    }

    // Settlement is a second write on purpose. If it fails the session is
    // still finished — the trainer can settle it later from the ledger — and
    // reporting "couldn't finish" for a session that *did* finish is the kind
    // of lie that makes people tap the button twice.
    if (paid) {
      try {
        await ref.read(bookingRepositoryProvider).markPaid(
              booking.id,
              trainerId: booking.instructorId,
            );
      } on PaymentFailure catch (e) {
        if (context.mounted) showFlowToast(context, e.message);
        return;
      } catch (_) {
        if (context.mounted) {
          showFlowToast(context,
              'Session finished, but the payment did not save. '
              'Mark it paid from your earnings.');
        }
        return;
      }
    }

    if (context.mounted) {
      showFlowToast(
          context,
          paid
              ? '${money(booking.amountDue)} collected 💶'
              : '${money(booking.amountDue)} still owing — '
                  'settle it from your earnings.');
    }
  }

  /// Finish + settle in one sheet. `true` = paid, `false` = still owing,
  /// `null` = cancelled.
  Future<bool?> _askSettlement(BuildContext context, WidgetRef ref) {
    final amount = money(booking.amountDue);
    return showFlowSheet<bool>(
      context,
      title: 'Finish this session?',
      subtitle: "${booking.studentName} · $amount",
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Did you take the $amount?',
              style: inter(14, 520,
                  color: sheetContext.tones.textFaint, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(sheetContext, true),
              icon: const Icon(Symbols.check_circle_outline_rounded),
              label: Text('Yes — $amount collected'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(sheetContext, false),
              icon: const Icon(Symbols.schedule_rounded),
              label: const Text('Not yet — still owing'),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetails(BuildContext context, WidgetRef ref) =>
      openManifestDetails(context, ref, booking);
}

/// Read-only details + Message rider (§3.8).
///
/// Top-level since the manifest stopped being cards all the way down: an
/// [AgendaRow] has no card of its own to hang this off, and both need to open
/// the same sheet.
void openManifestDetails(BuildContext context, WidgetRef ref, Booking b) {
    showFlowSheet<void>(
      context,
      title: b.studentName,
      subtitle: '${longYmd(b.date)} · ${b.timeRange}',
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusPill(status: b.status),
                const SizedBox(width: 8),
                if (b.studentLevel != null) TagPill(b.studentLevel!),
                if (b.gearNeeded) ...[
                  const SizedBox(width: 6),
                  const TagPill('NEEDS GEAR'),
                ],
                const Spacer(),
                Text(money(b.totalPrice),
                    style: interNum(17, 760,
                        color: sheetContext.tones.azureBrand)),
              ],
            ),
            if ((b.message ?? '').isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('MESSAGE',
                  style: microLabel(sheetContext.tones.textFaint)),
              const SizedBox(height: 6),
              Text('"${b.message}"',
                  style: Theme.of(sheetContext)
                      .textTheme
                      .bodyLarge!
                      .copyWith(fontStyle: FontStyle.italic, height: 1.5)),
            ],
            const SizedBox(height: 20),
            if (!b.isManual && b.kiterId.isNotEmpty)
              PrimaryButton(
                label: 'Message rider',
                icon: Symbols.chat_bubble_outline_rounded,
                onPressed: () {
                  final session = ref.read(sessionProvider);
                  ref.read(chatRepositoryProvider).openThread(
                        me: session.uid,
                        myName: session.displayName,
                        partnerId: b.kiterId,
                        partnerName: b.studentName,
                      );
                  Navigator.pop(sheetContext);
                  sheetContext.push(
                      '/chat/${b.kiterId}?name=${Uri.encodeComponent(b.studentName)}');
                },
              ),
          ],
        ),
      ),
    );
}

class _ComingUpRow extends StatelessWidget {
  const _ComingUpRow({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final day = parseYmd(booking.date);
    return FlowCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      // Control radius, not card: this is a dense schedule row, not content.
      borderRadius: FlowRadii.control,
      child: Row(
        children: [
          DateBlock(date: day, compact: true),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(booking.studentName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall),
                Text(booking.timeRange,
                    style: inter(11.5, 500, color: tones.textFaint)),
              ],
            ),
          ),
          StatusPill(status: booking.status),
          const SizedBox(width: 10),
          Text(money(booking.totalPrice),
              style: interNum(14, 720, color: tones.azureBrand)),
        ],
      ),
    );
  }
}

/// The 4-step first-run tour (§3.8).
Future<void> showTrainerTour(BuildContext context) {
  var step = 0;
  const steps = [
    (
      Symbols.space_dashboard_rounded,
      'Your Command Center',
      'Everything for the day in one place: requests, the manifest and your earnings.'
    ),
    (
      Symbols.how_to_reg_rounded,
      'Approve or decline',
      'New requests appear under "Action required". Approve in one tap — undo is right there in the toast.'
    ),
    (
      Symbols.qr_code_scanner_rounded,
      'Scan riders in',
      'Sessions only start when you scan the rider\'s QR ticket on the beach. Tap CHECK IN from anywhere.'
    ),
    (
      Symbols.edit_calendar_rounded,
      'Own your calendar',
      'Block hours, add walk-ins and set time off in the Schedule tab. Riders only ever see true availability.'
    ),
  ];

  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialog) {
        final (icon, title, body) = steps[step];
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 30, 26, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FlowIconChip(icon: icon, size: 72),
                const SizedBox(height: 18),
                Text(title,
                    style: Theme.of(dialogContext).textTheme.headlineSmall,
                    textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text(body,
                    textAlign: TextAlign.center,
                    style: Theme.of(dialogContext).textTheme.bodyMedium),
                const SizedBox(height: 20),
                PageDots(count: steps.length, index: step),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: step < steps.length - 1 ? 'Next' : "Let's go",
                  onPressed: () {
                    if (step < steps.length - 1) {
                      setDialog(() => step++);
                    } else {
                      Haptics.medium();
                      Navigator.pop(dialogContext);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
