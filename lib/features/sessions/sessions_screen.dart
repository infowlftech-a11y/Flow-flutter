import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/radii.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/refs.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/misc.dart';
import '../../core/widgets/session_card.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/booking.dart';
import '../../data/repositories/booking_repository.dart';
import '../../providers/providers.dart';
import 'review_composer.dart';

/// Rider sessions — UPCOMING / ACTIVE / HISTORY (§3.7).
/// `?highlight=<bookingId>` selects the tab that actually contains that
/// booking, scrolls it into view and haloes it ~4s.
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
          // Drop the halo after ~4s.
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
          // Scrollable: three labels that each carry a count cannot be
          // promised to fit a third of a narrow phone. At 1.3x text they ran
          // out of their cells and HISTORY painted over ACTIVE — a
          // non-scrollable TabBar has nowhere to put the excess.
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(child: _tabLabel(buckets, 'UPCOMING', BookingBucket.upcoming)),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _tabLabel(buckets, 'ACTIVE', BookingBucket.active),
                  if (buckets.value?[BookingBucket.active]?.isNotEmpty ??
                      false) ...[
                    const SizedBox(width: 6),
                    const _LiveDot(),
                  ],
                ],
              ),
            ),
            Tab(child: _tabLabel(buckets, 'HISTORY', BookingBucket.history)),
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
              bucket: BookingBucket.upcoming,
              cardKeys: _cardKeys,
              highlight: _highlight,
              empty: const EmptyView.scrollable(
                icon: Symbols.event_available_rounded,
                title: 'Nothing booked yet',
                subtitle:
                    'Find a trainer in Explore and lock in your next session.',
              ),
              onRefresh: _refresh,
            ),
            _BookingList(
              bookings: data[BookingBucket.active]!,
              bucket: BookingBucket.active,
              cardKeys: _cardKeys,
              highlight: _highlight,
              empty: const EmptyView.scrollable(
                icon: Symbols.surfing_rounded,
                title: 'No live sessions',
                subtitle:
                    'When your trainer scans you in, your session shows here.',
              ),
              onRefresh: _refresh,
            ),
            _BookingList(
              bookings: data[BookingBucket.history]!,
              bucket: BookingBucket.history,
              cardKeys: _cardKeys,
              highlight: _highlight,
              empty: const EmptyView.scrollable(
                icon: Symbols.history_rounded,
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

  /// `UPCOMING 3` once loaded, bare `UPCOMING` while it isn't — a count of
  /// zero has to mean zero, so it can't be shown before data arrives.
  ///
  /// The count is a smaller, lighter span rather than `" (3)"` at full label
  /// size. At three tabs on a 360dp screen each label gets ~120dp, and
  /// `UPCOMING (2)` needed slightly more than that — so it wrapped to two
  /// lines while the other two stayed on one, leaving the tabs at mismatched
  /// heights with the indicator sitting low. It also reads better: the word is
  /// the label, the number is the qualifier.
  Widget _tabLabel(
      AsyncValue<BookingBuckets> buckets, String label, BookingBucket bucket) {
    final list = buckets.value?[bucket];
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: label),
        if (list != null)
          TextSpan(
            // Colour deliberately unset so it inherits the TabBar's
            // selected/unselected label colour along with the rest of the row.
            text: '  ${list.length}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
      ]),
      maxLines: 1,
    );
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

/// One tab: the session that matters, then the ones that don't yet.
///
/// The old list gave every booking the same card, so a session starting in
/// twenty minutes looked exactly like one three weeks out. Promoting the first
/// entry is the whole point of the redesign here — one card with a photo and a
/// clock, and thin rows underneath it.
class _BookingList extends StatelessWidget {
  const _BookingList({
    required this.bookings,
    required this.bucket,
    required this.cardKeys,
    required this.highlight,
    required this.empty,
    required this.onRefresh,
  });

  final List<Booking> bookings;
  final BookingBucket bucket;
  final Map<String, GlobalKey> cardKeys;
  final String? highlight;
  final Widget empty;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return RefreshIndicator(onRefresh: onRefresh, child: empty);
    }

    // History is a log: every entry is equally over, so nothing is promoted.
    // The other two tabs are sorted soonest-first by `_bucketize`, which is
    // what makes `first` the right one to lead with.
    final hero = bucket == BookingBucket.history ? null : bookings.first;
    final rest = hero == null ? bookings : bookings.sublist(1);

    final head = <Widget>[
      if (hero != null)
        _Halo(
          key: cardKeys.putIfAbsent(hero.id, GlobalKey.new),
          on: hero.id == highlight,
          child: _HeroSession(booking: hero),
        ),
      if (hero != null && rest.isNotEmpty) const SizedBox(height: 20),
      if (rest.isNotEmpty)
        SectionHeader(hero == null ? 'All sessions' : 'Also booked'),
    ];

    return RefreshIndicator(
      onRefresh: onRefresh,
      // Built lazily: history is unbounded, and a rider with three seasons
      // behind them would otherwise pay for every row on every rebuild.
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: head.length + rest.length,
        itemBuilder: (context, i) {
          if (i < head.length) return head[i];
          final b = rest[i - head.length];
          return Padding(
            padding: EdgeInsets.only(top: i == head.length ? 0 : 10),
            child: _Halo(
              key: cardKeys.putIfAbsent(b.id, GlobalKey.new),
              on: b.id == highlight,
              child: _SessionTile(booking: b),
            ),
          );
        },
      ),
    );
  }
}

/// The tint the `?highlight=` deep link paints for ~4s.
///
/// A halo *around* the entry rather than a recolour of it. [SessionRow] and
/// [LiveSessionCard] draw their own surfaces, and tinting those would mean two
/// shared components growing a `highlighted` flag apiece to serve one deep
/// link that only this screen has.
///
/// The padding is unconditional so the row does not shift by 4px when the
/// halo fades — the animation is the colour, not the geometry.
class _Halo extends StatelessWidget {
  const _Halo({super.key, required this.on, required this.child});

  final bool on;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final azure = context.tones.azureBrand;
    return AnimatedContainer(
      duration: FlowMotion.base,
      curve: FlowMotion.curve,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: on ? azure.withValues(alpha: .14) : Colors.transparent,
        borderRadius: FlowRadii.card,
      ),
      child: child,
    );
  }
}

/// The session the rider opened the app for: photo, clock, and its actions
/// inline rather than a tap away.
class _HeroSession extends ConsumerWidget {
  const _HeroSession({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = booking;
    // One listener, on the hero only. Riverpod caches the family by id, but a
    // history list of fifty rows each watching a profile is still fifty
    // widgets rebuilding on a document nobody is looking at.
    final profile = ref.watch(trainerProfileProvider(b.instructorId)).value;
    final live = b.status == BookingStatus.inProgress;
    final starts = b.startsAt;
    final until = starts?.difference(DateTime.now());

    // A countdown is only information while it is short. "504:12:07" for a
    // session three weeks out is a number nobody reads, so the clock appears
    // inside two days and the date carries it before that.
    final ticking =
        until != null && !until.isNegative && until < const Duration(hours: 48);
    final imminent =
        until != null && !until.isNegative && until < const Duration(hours: 2);

    final (countdownTo, countdownLabel) = live
        ? (b.endsAt, 'Time left')
        : ticking
            ? (starts, 'Until start')
            : (null, '');

    final actions = sessionActionsFor(b);

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: LiveSessionCard(
            title: dayAndTime(b, _whenLabel(b.date)),
            subtitle: '${b.title} with ${b.instructorName}',
            imageUrl: profile?.gallery.firstOrNull ?? profile?.photoUrl,
            badgeLabel: live
                ? 'LIVE NOW'
                : imminent
                    ? 'STARTS SOON'
                    : null,
            countdownTo: countdownTo,
            countdownLabel: countdownLabel,
            onTap: () => openSessionSheet(context, b),
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              for (final (i, a) in actions.indexed) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _ActionButton(booking: b, action: a)),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// A secondary session: thin, scannable, and tappable into its detail.
class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    return SessionRow(
      when: dayAndTime(b, prettyYmd(b.date)),
      who: b.instructorName,
      location: b.title,
      priceLabel: money(b.totalPrice),
      statusLabel: b.status.label.toUpperCase(),
      statusColor: statusColorFor(context, b.status),
      onTap: () => openSessionSheet(context, b),
    );
  }
}

/// `Sat 29 Aug · 10:00–11:00`, or just the day when the booking has no hours.
///
/// An expedition is sold by the day and carries no start time, and
/// `Booking.timeRange` reports that as a bare em dash — which rendered as
/// "Sat 29 Aug · —" on every safari in the app, a separator joining a date to
/// nothing. Three screens print this pair, so the rule lives once.
String dayAndTime(Booking b, String day) =>
    Slot.tryParse(b.startTime) == null ? day : '$day · ${b.timeRange}';

/// `Today` / `Tomorrow` / `Fri 14 Aug`.
///
/// Compared on calendar days, not elapsed hours: a session at 09:00 tomorrow
/// is "Tomorrow" whether it is now 23:00 or 08:00.
String _whenLabel(String date) {
  final d = parseYmd(date);
  if (d == null) return '--';
  final now = DateTime.now();
  final days = DateTime(d.year, d.month, d.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  return switch (days) {
    0 => 'Today',
    1 => 'Tomorrow',
    -1 => 'Yesterday',
    _ => prettyYmd(date),
  };
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

/// What a rider can do to one of their bookings.
enum SessionAction { checkIn, showTicket, rate, cancel }

/// The actions a booking offers, in the order they should be shown.
///
/// Public and pure so the rules are assertable without a widget tree. They are
/// easy to get subtly wrong — a safari has no beach counter to check in at, a
/// session already past cannot be checked into, and offering "Rate" on a
/// cancelled booking asks the rider to review something that never happened.
List<SessionAction> sessionActionsFor(Booking b) => switch (b.status) {
      BookingStatus.pending => const [SessionAction.cancel],
      BookingStatus.confirmed => [
          if (!b.isPast && !b.isSafari) SessionAction.checkIn,
          SessionAction.cancel,
        ],
      BookingStatus.inProgress => const [SessionAction.showTicket],
      BookingStatus.completed => const [SessionAction.rate],
      _ => const [],
    };

class _ActionButton extends ConsumerWidget {
  const _ActionButton({
    required this.booking,
    required this.action,
    this.onDone,
  });

  final Booking booking;
  final SessionAction action;

  /// Set only by the detail sheet, which has to get out of the way once the
  /// action it offered has been taken. The hero card passes nothing — it is
  /// already where the rider will look next.
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (action) {
      SessionAction.checkIn => MicroAction(
          label: 'CHECK IN',
          icon: Symbols.qr_code_2_rounded,
          onPressed: () => _handoff(context, (c) => showQrTicket(c, booking)),
        ),
      SessionAction.showTicket => MicroAction(
          label: 'SHOW TICKET',
          icon: Symbols.qr_code_2_rounded,
          onPressed: () => _handoff(context, (c) => showQrTicket(c, booking)),
        ),
      SessionAction.rate => MicroAction(
          label: 'RATE',
          icon: Symbols.star_outline_rounded,
          filled: false,
          onPressed: () => _handoff(context, _openRateSheet),
        ),
      SessionAction.cancel => MicroAction(
          label: 'CANCEL',
          filled: false,
          color: context.tones.danger,
          onPressed: () => _cancel(context, ref),
        ),
    };
  }

  /// Replaces the detail sheet with whatever the action opens.
  ///
  /// Stacking the QR dialog or the rate composer on top of the sheet leaves
  /// two dismissable layers describing one booking, and the back gesture takes
  /// the wrong one first. The root navigator's own context is captured before
  /// the pop because it outlives the sheet — the sheet's does not.
  void _handoff(BuildContext context, void Function(BuildContext) open) {
    final done = onDone;
    if (done == null) {
      open(context);
      return;
    }
    final root = Navigator.of(context, rootNavigator: true).context;
    done();
    open(root);
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    // Confirmation names the session and date; warns the trainer is
    // notified (§10.4).
    final ok = await confirmAction(
      context,
      title: 'Cancel this session?',
      body: '${booking.title} on ${longYmd(booking.date)} will be cancelled '
          'and your trainer will be notified.',
      confirmLabel: 'Cancel session',
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(bookingRepositoryProvider).cancelByRider(booking);
      if (!context.mounted) return;
      onDone?.call();
      showFlowToast(context, 'Session cancelled');
    } on StatusConflictFailure catch (e) {
      // The list is a live stream; this row moved on before the tap landed.
      // The specific reason ("already finished") matters more here than
      // anywhere: it is the difference between shrugging and not showing up.
      if (context.mounted) showFlowToast(context, e.message);
    } catch (e) {
      // The rider was told their trainer would be notified. If the write
      // failed they must not be left assuming it went through — they would
      // simply not turn up.
      if (context.mounted) showFlowToast(context, ErrorView.friendly(e));
    }
  }

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

// ---------------------------------------------------------------------------
// Detail sheet
// ---------------------------------------------------------------------------

/// A session's facts and everything the rider can do about it.
///
/// The rows in the list are thin on purpose — that is what makes them
/// scannable — so the buttons that used to sit on every card live here
/// instead, one tap from any of them.
void openSessionSheet(BuildContext context, Booking booking) {
  showFlowSheet<void>(
    context,
    title: booking.title,
    subtitle: '${booking.instructorName} · ${prettyYmd(booking.date)}',
    builder: (sheetContext) => _SessionSheet(booking: booking),
  );
}

class _SessionSheet extends ConsumerWidget {
  const _SessionSheet({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched live: a rider can be standing at the counter with this open when
    // the trainer scans them in, and the sheet flipping from "Approved" to
    // "In progress" under their thumb is the confirmation they came for.
    final b = ref.watch(bookingByIdProvider(booking.id)).value ?? booking;
    final actions = sessionActionsFor(b);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              StatusPill(status: b.status),
              // Only once the session is over. Before that "Unpaid" is
              // technically true and completely unhelpful — nobody pays for a
              // lesson they have not had.
              if (b.status == BookingStatus.completed) PaymentPill(b.payment),
            ],
          ),
          const SizedBox(height: 16),
          FlowCard(
            child: Column(
              children: [
                // The name to quote at support — the same reference the
                // beach ticket prints, and the one staff can search.
                _DetailRow(label: 'SESSION ID', value: sessionRef(b.id, b.date)),
                _DetailRow(label: 'WHEN', value: longYmd(b.date)),
                _DetailRow(label: 'TIME', value: b.timeRange),
                _DetailRow(label: 'TOTAL', value: money(b.totalPrice)),
                _DetailRow(label: 'STATUS', value: b.subLabel, last: true),
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (final (i, a) in actions.indexed) ...[
              if (i > 0) const SizedBox(height: 10),
              _ActionButton(
                booking: b,
                action: a,
                onDone: () => Navigator.pop(context),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        children: [
          Text(label, style: microLabel(context.tones.textFaint, size: 10)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// The colour a booking status wears, wherever it is drawn.
Color statusColorFor(BuildContext context, BookingStatus status) =>
    switch (status) {
      BookingStatus.pending => context.tones.warning,
      BookingStatus.confirmed => context.tones.success,
      BookingStatus.inProgress => context.tones.azureBrand,
      BookingStatus.completed => context.scheme.onSurfaceVariant,
      _ => context.tones.danger,
    };

/// A booking's status as a pill. The colour mapping is the only thing this
/// adds over [TagPill] — the drawing is shared, so a status pill and a tag can
/// no longer drift apart.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) => TagPill(
        status.label.toUpperCase(),
        color: statusColorFor(context, status),
        dense: true,
      );
}

/// The QR ticket (§3.7, §12.2): encodes `{"bookingId":…,"trainerId":…}`,
/// always on white so scanners work in dark mode, watches the booking live
/// and flips to "Session started" (with a haptic) the moment the trainer
/// scans.
///
/// Still here alongside the `/ticket` tab, and not redundant with it: that tab
/// is the carousel a rider swipes at a counter, this is *this* booking's code
/// with the live hand-off feedback attached.
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
              // Content arriving and leaving — the ticket giving way to the
              // "session started" confirmation. That is `slow` on the scale,
              // and 300ms was already exactly it, just written out.
              duration: FlowMotion.slow,
              switchInCurve: FlowMotion.curve,
              switchOutCurve: FlowMotion.curve,
              child: started
                  ? Column(
                      key: const ValueKey('started'),
                      children: [
                        FlowIconChip(
                          icon: Symbols.surfing_rounded,
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
                        const SizedBox(height: 3),
                        // The spoken fallback when the camera won't play —
                        // the same reference the full ticket screen prints.
                        Text(
                          sessionRef(widget.booking.id, widget.booking.date),
                          style: interNum(12, 560,
                              color: context.tones.textFaint, spacing: .5),
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
