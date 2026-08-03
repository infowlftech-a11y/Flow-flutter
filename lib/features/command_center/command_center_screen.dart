import 'package:flutter/material.dart';
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
import '../../data/models/booking.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../sessions/sessions_screen.dart' show StatusPill;
import 'qr_scanner_screen.dart';
import 'schedule_tab.dart';

/// Trainer home: TODAY + SCHEDULE, with a persistent CHECK IN action (§3.8).
class CommandCenterScreen extends ConsumerStatefulWidget {
  const CommandCenterScreen({super.key});

  @override
  ConsumerState<CommandCenterScreen> createState() =>
      _CommandCenterScreenState();
}

class _CommandCenterScreenState extends ConsumerState<CommandCenterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _requestsKey = GlobalKey();
  final _todayScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTour());
  }

  @override
  void dispose() {
    _tabs.dispose();
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

  Future<void> _openScanner() async {
    final trainerId = ref.read(sessionProvider).uid;
    final bookingId = await Navigator.of(context, rootNavigator: true)
        .push<String>(MaterialPageRoute(
            builder: (_) => QrScannerScreen(trainerId: trainerId)));
    if (bookingId == null || !mounted) return;
    try {
      await ref.read(bookingRepositoryProvider).checkIn(bookingId);
      if (mounted) showFlowToast(context, 'Session started 🤙');
    } catch (_) {
      if (mounted) {
        showFlowToast(context, "Couldn't start the session. Try again.");
      }
    }
  }

  void _scrollToRequests() {
    _tabs.animateTo(0);
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
                child: const Icon(Icons.notifications_outlined),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'TODAY'), Tab(text: 'SCHEDULE')],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openScanner,
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('CHECK IN'),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _TodayTab(
            requestsKey: _requestsKey,
            scrollController: _todayScroll,
            onRequestsTap: _scrollToRequests,
          ),
          const ScheduleTab(),
        ],
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
        ].take(10).toList();

        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
          children: [
            Row(
              children: [
                _StatTile(
                  label: 'Requests',
                  value: '${pending.length}',
                  icon: Icons.pending_actions_rounded,
                  emphasized: pending.isNotEmpty,
                  onTap: onRequestsTap,
                ),
                const SizedBox(width: 10),
                _StatTile(
                  label: 'Upcoming',
                  value: '${upcoming.length}',
                  icon: Icons.event_rounded,
                ),
                const SizedBox(width: 10),
                _StatTile(
                  label: 'Total earned',
                  value: euro(revenue.value ?? 0),
                  icon: Icons.payments_rounded,
                  onTap: () => showEarningsSheet(context, ref),
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
              for (final b in today) _ManifestCard(booking: b),
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
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              gradient: emphasized ? tones.heroGradient : null,
              color: emphasized ? null : tones.card,
              borderRadius: BorderRadius.circular(18),
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
                      style: sora(21, 760,
                          color: emphasized
                              ? Colors.white
                              : context.scheme.onSurface,
                          spacing: -.5)),
                ),
                const SizedBox(height: 2),
                Text(label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: microLabel(
                        emphasized
                            ? Colors.white.withValues(alpha: .75)
                            : tones.textFaint,
                        size: 9.5)),
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
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tones.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tones.line),
      ),
      child: Row(
        children: [
          Icon(Icons.air_rounded, color: tones.azureBrand, size: 30),
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

/// Pending request: APPROVE is busy-guarded + haptic + UNDO in the toast;
/// DECLINE opens a sheet for an optional reason (§3.8, §10.4).
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tones.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tones.warning.withValues(alpha: .45)),
      ),
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
              Text(euro(b.totalPrice),
                  style: interNum(16, 760, color: tones.azureBrand)),
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
                borderRadius: BorderRadius.circular(12),
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
            const TagPill('NEEDS GEAR', icon: Icons.settings_input_component_rounded),
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
                  icon: Icons.check_rounded,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: tones.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: b.status == BookingStatus.inProgress
                ? tones.success.withValues(alpha: .5)
                : tones.line),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openDetails(context, ref),
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                                  style: inter(12, 500,
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
                    Text(euro(b.totalPrice),
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
                      icon: Icons.qr_code_scanner_rounded,
                      onPressed: () => _scanToStart(context, ref),
                    ),
                  )
                else if (b.status == BookingStatus.inProgress)
                  SizedBox(
                    width: double.infinity,
                    child: MicroAction(
                      label: 'FINISH SESSION',
                      icon: Icons.flag_rounded,
                      color: tones.success,
                      onPressed: () => _finish(context, ref),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _scanToStart(BuildContext context, WidgetRef ref) async {
    final trainerId = ref.read(sessionProvider).uid;
    final bookingId = await Navigator.of(context, rootNavigator: true)
        .push<String>(MaterialPageRoute(
            builder: (_) => QrScannerScreen(trainerId: trainerId)));
    if (bookingId == null) return;
    try {
      await ref.read(bookingRepositoryProvider).checkIn(bookingId);
      if (context.mounted) showFlowToast(context, 'Session started 🤙');
    } catch (_) {
      if (context.mounted) {
        showFlowToast(context, "Couldn't start the session. Try again.");
      }
    }
  }

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    // Confirmation names the amount added to earnings (§10.4).
    final ok = await confirmAction(
      context,
      title: 'Finish this session?',
      body:
          "${booking.studentName}'s session will be completed and "
          '${euro(booking.totalPrice)} added to your earnings.',
      confirmLabel: 'Finish',
    );
    if (!ok) return;
    Haptics.medium();
    await ref
        .read(bookingRepositoryProvider)
        .setStatus(booking, BookingStatus.completed);
    if (context.mounted) {
      showFlowToast(context,
          '${euro(booking.totalPrice)} added to your earnings 💶');
    }
  }

  /// Read-only details + Message rider (§3.8).
  void _openDetails(BuildContext context, WidgetRef ref) {
    final b = booking;
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
                Text(euro(b.totalPrice),
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
                icon: Icons.chat_bubble_outline_rounded,
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
}

class _ComingUpRow extends StatelessWidget {
  const _ComingUpRow({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final day = parseYmd(booking.date);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tones.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tones.line),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Text(day == null ? '--' : monthsShort[day.month - 1],
                    style: inter(9.5, 720,
                        color: tones.textFaint, spacing: .8)),
                Text(day == null ? '--' : '${day.day}',
                    style: interNum(16, 740,
                        color: context.scheme.onSurface)),
              ],
            ),
          ),
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
          Text(euro(booking.totalPrice),
              style: interNum(14, 720, color: tones.azureBrand)),
        ],
      ),
    );
  }
}

/// Earnings ledger — all-time + month-to-date + every completed session
/// (§3.8).
void showEarningsSheet(BuildContext context, WidgetRef ref) {
  showFlowSheet<void>(
    context,
    title: 'Earnings',
    builder: (sheetContext) => Consumer(
      builder: (sheetContext, sheetRef, _) {
        final total = sheetRef.watch(trainerRevenueProvider).value ?? 0;
        final month = sheetRef.watch(trainerMonthRevenueProvider).value ?? 0;
        final completed =
            sheetRef.watch(trainerCompletedProvider).value ?? const <Booking>[];
        final tones = sheetContext.tones;

        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: tones.heroGradient,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ALL TIME',
                            style: microLabel(
                                Colors.white.withValues(alpha: .7),
                                size: 10)),
                        const SizedBox(height: 6),
                        Text(euro(total),
                            style: sora(24, 780, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: tones.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: tones.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('THIS MONTH',
                            style:
                                microLabel(tones.textFaint, size: 10)),
                        const SizedBox(height: 6),
                        Text(euro(month),
                            style: sora(24, 780,
                                color: tones.azureBrand)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (completed.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Finished sessions land here with their payout.',
                  textAlign: TextAlign.center,
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                ),
              )
            else
              for (final b in completed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b.studentName,
                                style: Theme.of(sheetContext)
                                    .textTheme
                                    .titleSmall),
                            Text(
                                '${prettyYmd(b.date)} · ${b.hours}h',
                                style: inter(11.5, 500,
                                    color: tones.textFaint)),
                          ],
                        ),
                      ),
                      Text(euro(b.totalPrice),
                          style: interNum(14.5, 720,
                              color: tones.success)),
                    ],
                  ),
                ),
          ],
        );
      },
    ),
  );
}

/// The 4-step first-run tour (§3.8).
Future<void> showTrainerTour(BuildContext context) {
  var step = 0;
  const steps = [
    (
      Icons.space_dashboard_rounded,
      'Your Command Center',
      'Everything for the day in one place: requests, the manifest and your earnings.'
    ),
    (
      Icons.how_to_reg_rounded,
      'Approve or decline',
      'New requests appear under "Action required". Approve in one tap — undo is right there in the toast.'
    ),
    (
      Icons.qr_code_scanner_rounded,
      'Scan riders in',
      'Sessions only start when you scan the rider\'s QR ticket on the beach. Tap CHECK IN from anywhere.'
    ),
    (
      Icons.edit_calendar_rounded,
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
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: dialogContext.tones.azureBrand
                        .withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(icon,
                      color: dialogContext.tones.azureBrand, size: 34),
                ),
                const SizedBox(height: 18),
                Text(title,
                    style: Theme.of(dialogContext).textTheme.headlineSmall,
                    textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text(body,
                    textAlign: TextAlign.center,
                    style: Theme.of(dialogContext).textTheme.bodyMedium),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < steps.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == step ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == step
                              ? dialogContext.tones.azureBrand
                              : dialogContext.tones.line,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                ),
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
