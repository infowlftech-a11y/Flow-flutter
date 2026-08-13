import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/radii.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/booking_grid.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/flow_image.dart';
import '../../core/widgets/misc.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/surfaces.dart';
import '../../core/theme/palette.dart';
import '../../data/models/cancellation.dart';
import '../../data/models/catalogue.dart';
import '../../data/models/schedule.dart';
import '../../data/models/wind.dart';
import '../../data/repositories/booking_repository.dart';
import '../../providers/providers.dart';

/// The booking flow — who / pick a day / available hours / summary on one
/// scroll (§3.6). Availability is streamed, so a slot vanishing mid-booking
/// disappears from the grid (and the selection) live.
class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key, required this.target});

  final BookingTarget target;

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  late String _date = todayYmd();
  final Set<Slot> _selection = {};
  final _message = TextEditingController();
  bool _gearNeeded = false;
  bool _submitting = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  List<Slot> get _sortedSelection =>
      [..._selection]..sort((a, b) => a.minutesOfDay - b.minutesOfDay);

  double get _total => widget.target.rate * _selection.length;

  void _changeDay(String date) {
    if (date == _date) return;
    Haptics.select();
    setState(() {
      _date = date;
      _selection.clear(); // selection never survives a day change (§8.4)
    });
  }

  /// Contiguous hour selection (§8.4).
  void _tapSlot(Slot slot, DayAvailability day) {
    Haptics.select();
    var collapsed = false;
    setState(() {
      if (_selection.contains(slot)) {
        _selection.clear();
        return;
      }
      if (_selection.isEmpty) {
        _selection.add(slot);
        return;
      }
      final anchor = _sortedSelection.first;
      final from = anchor.minutesOfDay <= slot.minutesOfDay ? anchor : slot;
      final to = anchor.minutesOfDay <= slot.minutesOfDay ? slot : anchor;
      final range = [
        for (var h = from.hour; h <= to.hour; h++) Slot.fromHour(h),
      ];
      if (range.every(day.isFree)) {
        _selection
          ..clear()
          ..addAll(range);
      } else {
        // A taken hour sits between the two picks, so the range can't span
        // it. Restarting from the new hour is right — but silently dropping
        // the earlier pick looks like a bug unless we say why.
        collapsed = range.length > 1;
        _selection
          ..clear()
          ..add(slot);
      }
    });
    if (collapsed) {
      showFlowToast(
        context,
        "Those hours aren't back-to-back — starting again from "
        '${slot.value}.',
        icon: Symbols.link_off_rounded,
      );
    }
  }

  /// If a selected hour became unavailable while the screen is open, drop it
  /// on the next frame — but only once real data has arrived (§8.4).
  void _pruneSelection(DayAvailability day) {
    if ([for (final s in _selection) if (!day.isFree(s)) s].isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Re-check against the live selection: several builds can schedule this
      // before the first callback runs, and that one may already have pruned.
      // Without this the rider gets the same toast two or three times.
      final stale = [for (final s in _selection) if (!day.isFree(s)) s];
      if (stale.isEmpty) return;

      var split = false;
      setState(() {
        _selection.removeAll(stale);
        // Dropping a *middle* hour leaves a gap, and the write derives
        // endTime from first→last of the span (§8.6) — so a gapped selection
        // would book straight across an hour someone else now holds, and the
        // trainer would see one unbroken block. Selection has to stay
        // contiguous (§8.4): keep only the run the earliest survivor starts.
        final remaining = _sortedSelection;
        final run = BookingMath.leadingRun(remaining);
        split = run.length != remaining.length;
        _selection
          ..clear()
          ..addAll(run);
      });

      showFlowToast(
        context,
        split
            ? 'An hour you picked was just taken, so the hours after the gap '
                'were dropped — sessions run back-to-back.'
            : 'An hour you picked was just taken and has been removed.',
        icon: split ? Symbols.link_off_rounded : null,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final availability = ref.watch(dayAvailabilityProvider(
        (instructorId: target.providerId, date: _date)));

    if (availability case AsyncData(:final value)) {
      _pruneSelection(value);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Book your session')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                _ProviderCard(target: target),
                const SizedBox(height: 24),
                const SectionHeader('Pick a day'),
                _DayStrip(
                  instructorId: target.providerId,
                  selected: _date,
                  onChanged: _changeDay,
                ),
                _WindSummary(
                  instructorId: target.providerId,
                  date: _date,
                ),
                const SizedBox(height: 24),
                SectionHeader(
                  'Available hours',
                  trailing: _selection.isEmpty
                      ? null
                      : TextButton(
                          onPressed: () =>
                              setState(() => _selection.clear()),
                          child: const Text('CLEAR'),
                        ),
                ),
                // The contiguous-hours rule is invisible until it bites, so
                // state it up front rather than letting a far-apart second
                // tap silently collapse the selection.
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Tap a start hour, then an end hour — sessions run '
                    'back-to-back.',
                    style: inter(12.5, 480, color: context.tones.textFaint),
                  ),
                ),
                AsyncView<DayAvailability>(
                  value: availability,
                  onRetry: () => ref.invalidate(dayAvailabilityProvider(
                      (instructorId: target.providerId, date: _date))),
                  // The grid must not default to "free" before data arrives —
                  // loading never lies (§10.2).
                  skeleton: const _SlotGridSkeleton(),
                  data: (day) => _SlotArea(
                    day: day,
                    selection: _selection,
                    onTap: (slot) => _tapSlot(slot, day),
                  ),
                ),
                AnimatedSize(
                  duration: FlowMotion.base,
                  curve: FlowMotion.curve,
                  alignment: Alignment.topCenter,
                  child: _selection.isEmpty
                      ? const SizedBox.shrink()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 24),
                            const SectionHeader('Your session'),
                            _SummaryCard(
                              target: target,
                              date: _date,
                              slots: _sortedSelection,
                              total: _total,
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _message,
                              maxLines: 3,
                              minLines: 2,
                              decoration: const InputDecoration(
                                  hintText:
                                      'Message to your trainer (optional)'),
                            ),
                            const SizedBox(height: 10),
                            SwitchListTile(
                              value: _gearNeeded,
                              onChanged: (v) {
                                Haptics.select();
                                setState(() => _gearNeeded = v);
                              },
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 6),
                              title: const Text('I need gear'),
                              subtitle: const Text(
                                  'Kite, board and harness provided at the centre'),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          _StickyBar(
            hours: _selection.length,
            total: _selection.isEmpty ? null : _total,
            onReview: _selection.isEmpty ? null : _openReviewSheet,
          ),
        ],
      ),
    );
  }

  /// Review sheet → Confirm → success dialog (§3.6).
  void _openReviewSheet() {
    final target = widget.target;
    showFlowSheet<void>(
      context,
      title: 'Review & confirm',
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final slots = _sortedSelection;
          final start = slots.first;
          final end = start.plusHours(slots.length);
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
            children: [
              _ReviewRow('Service',
                  target.subTarget ?? '${target.title} · kitesurf lesson'),
              _ReviewRow('Date', longYmd(_date)),
              _ReviewRow('Time', '${start.value}–${end.value}'),
              _ReviewRow('Duration',
                  '${slots.length} hour${slots.length == 1 ? '' : 's'}'),
              _ReviewRow('Gear', _gearNeeded ? 'Provided by centre' : 'Own gear'),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: sheetContext.tones.azureBrand.withValues(alpha: .08),
                  borderRadius: FlowRadii.inset,
                  border: Border.all(
                      color:
                          sheetContext.tones.azureBrand.withValues(alpha: .3)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                            '${money(target.rate)} × ${slots.length}h',
                            style: inter(14, 540,
                                color:
                                    sheetContext.scheme.onSurfaceVariant)),
                        Text(money(_total),
                            style: display(22, 760,
                                color: sheetContext.tones.azureBrand)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Symbols.account_balance_wallet_rounded,
                            size: 15,
                            color: sheetContext.tones.textFaint),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                              'You pay FLOW now — your trainer is paid '
                              'after the session',
                              style: inter(12.5, 540,
                                  color: sheetContext.tones.textFaint)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // The policy, before the money leaves — a fee nobody was
              // warned about is a complaint, not a policy. Wording follows
              // the booking.com pattern: name the deadline when there is
              // one, say plainly when there is not.
              _PolicyLine(date: _date, start: _sortedSelection.first),
              const SizedBox(height: 6),
              Text(
                'Your kite level is shared with the trainer so they can prep '
                'the right session.',
                style: inter(12.5, 480, color: sheetContext.tones.textFaint),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Confirm & pay ${money(_total)}',
                busy: _submitting,
                onPressed: () => _confirm(sheetContext, setSheet),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirm(
      BuildContext sheetContext, StateSetter setSheet) async {
    if (_submitting) return;
    setSheet(() => _submitting = true);
    setState(() {});
    try {
      final session = ref.read(sessionProvider);
      final rider = ref.read(currentUserProvider).value;
      await ref.read(bookingRepositoryProvider).createBooking(
            target: widget.target,
            riderUid: session.uid,
            riderName: session.displayName,
            riderLevel: rider?.level ?? 'Rider',
            date: _date,
            slots: _sortedSelection,
            gearNeeded: _gearNeeded,
            message: _message.text.trim(),
            bufferMinutes: rider?.bufferMinutes ?? FlowConst.defaultBufferMinutes,
          );
      Haptics.medium();
      if (sheetContext.mounted) Navigator.pop(sheetContext);
      if (mounted) _showSuccess();
    } on SlotTakenFailure catch (e) {
      if (sheetContext.mounted) Navigator.pop(sheetContext);
      if (mounted) {
        setState(() {
          _submitting = false;
          _selection.clear();
        });
        // The failure carries its own wording — "just taken" and "too close
        // to now" need different advice, and both land here.
        showFlowToast(context, e.message);
      }
    } catch (e) {
      if (sheetContext.mounted) {
        setSheet(() => _submitting = false);
        setState(() {});
        showFlowToast(sheetContext,
            "Couldn't send your request. ${ErrorView.friendly(e)}");
      }
    }
  }

  /// Not dismissible by tapping outside; the single Done button closes the
  /// dialog and pops the booking screen (§3.6).
  void _showSuccess() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Dialog(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FlowIconChip(
                  icon: Symbols.send_rounded,
                  color: dialogContext.tones.success,
                  size: 76,
                  borderRadius: const BorderRadius.all(Radius.circular(38)),
                ),
                const SizedBox(height: 20),
                Text('Request sent!',
                    style: Theme.of(dialogContext).textTheme.headlineMedium),
                const SizedBox(height: 10),
                Text(
                  '${money(_total)} is held by FLOW — refunded in full if '
                  "the trainer declines. You'll get a ping the moment they "
                  'approve.',
                  textAlign: TextAlign.center,
                  style: Theme.of(dialogContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Done',
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    if (mounted) context.pop();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The cancellation terms, stated before the money leaves.
///
/// booking.com's pattern: name the free-cancellation deadline when there is
/// one, and say plainly when there is not — a session booked inside the
/// window has no free exit, and the rider should know that with their thumb
/// still off the pay button.
class _PolicyLine extends StatelessWidget {
  const _PolicyLine({required this.date, required this.start});

  /// Local `YYYY-MM-DD` + the first selected hour — the session's start.
  final String date;
  final Slot start;

  static String _fmt(DateTime t) {
    final ymd = '${t.year.toString().padLeft(4, '0')}-'
        '${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${prettyYmd(ymd)}, $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final day = parseYmd(date);
    final deadline = day
        ?.add(Duration(minutes: start.minutesOfDay))
        .subtract(CancellationPolicy.freeCancelWindow);
    final free = deadline != null && DateTime.now().isBefore(deadline);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          free ? Symbols.event_available_rounded : Symbols.schedule_rounded,
          size: 15,
          color: free ? tones.success : tones.warning,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            free
                ? 'Free cancellation until ${_fmt(deadline)}. After that '
                    "you're charged in full. Declined or unanswered requests "
                    'are always refunded.'
                : 'Starts within 24 hours — cancelling after you pay is '
                    'charged in full. Declined or unanswered requests are '
                    'always refunded.',
            style: inter(12.5, 520, color: tones.textFaint, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label.toUpperCase(),
                style: microLabel(context.tones.textFaint, size: 10)),
          ),
          Expanded(
            child: Text(value,
                style: Theme.of(context).textTheme.titleSmall),
          ),
        ],
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.target});
  final BookingTarget target;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return FlowCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          FlowAvatar(url: target.imageUrl, name: target.title, size: 54),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target.subTarget == null
                      ? target.title
                      : '${target.title} — ${target.subTarget}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (target.subtitle != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Symbols.place_rounded,
                          size: 13, color: tones.textFaint),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(target.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                inter(12.5, 500, color: tones.textFaint)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(money(target.rate),
                  style: interNum(17, 760, color: tones.azureBrand)),
              Text('/ ${target.unit}',
                  style: inter(11.5, 540, color: tones.textFaint)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Horizontal strip of the next 21 days starting today (§3.6).
///
/// Days the trainer is away are dimmed and struck through, so a rider
/// scanning for a free date sees it in the strip instead of discovering it
/// one blind tap at a time. They stay tappable — the grid's "Away on this
/// date" notice remains the explanation, this is only the signpost.
class _DayStrip extends ConsumerWidget {
  const _DayStrip({
    required this.instructorId,
    required this.selected,
    required this.onChanged,
  });

  final String instructorId;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final tones = context.tones;
    // Absent/erroring vacation data simply means no day is flagged — the
    // strip degrades to its old behaviour rather than lying about a day.
    final vacations =
        ref.watch(instructorVacationsProvider(instructorId)).value ?? const [];
    // Same contract as vacations: no forecast simply means no wind row. The
    // strip must never wait on the network to become usable.
    final wind = ref.watch(providerWindProvider(instructorId)).value;

    // A fixed height keeps the tiles from jittering as the strip scrolls,
    // but every row inside one is text — weekday, date, month, wind — so the
    // whole box has to scale with the text rather than a share of it. Flat at
    // 104 it overflowed at 1.3x; the extra 8px at 1.0x is slack so the column
    // is not sitting flush against its own border.
    final height = MediaQuery.textScalerOf(context).scale(112);

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: FlowConst.bookingDayStripLength,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final day = today.add(Duration(days: i));
          final date = ymd(day);
          final active = date == selected;
          final away = vacations.any((v) => v.covers(date));
          // Null past the forecast horizon (16 days) and whenever the fetch
          // failed — both render as an empty slot, never as a guess.
          final gust = wind?.forDate(date);
          // Today stops being bookable once the lead-time rule has eaten
          // every remaining hour — flag it like an away day rather than
          // letting it read as open.
          final over = i == 0 &&
              BookingMath.pastSlots(date, now: today).length >=
                  BookingMath.slots().length;
          final muted = (away || over) && !active;

          final fg = active ? Colors.white : context.scheme.onSurface;
          final subFg = active
              ? Colors.white.withValues(alpha: .85)
              : tones.textFaint;

          return Semantics(
            button: true,
            selected: active,
            label: '${weekdaysLong[day.weekday - 1]} ${day.day} '
                '${monthsLong[day.month - 1]}'
                '${i == 0 ? ', today' : ''}'
                '${away ? ', trainer away' : over ? ', no hours left' : ''}'
                // Spoken in full: "18 knots, Good" reads, "18kt" does not.
                '${gust == null ? '' : ', ${gust.displayKnots} knots, '
                    '${gust.rating.label}'}',
            child: AnimatedContainer(
              duration: FlowMotion.fast,
              curve: FlowMotion.curve,
              width: 62,
              decoration: BoxDecoration(
                color: active ? tones.azureBrand : tones.card,
                borderRadius: FlowRadii.inset,
                border:
                    Border.all(color: active ? tones.azureBrand : tones.line),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: FlowRadii.inset,
                  onTap: () => onChanged(date),
                  child: Opacity(
                    opacity: muted ? .45 : 1,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            i == 0 ? 'TODAY' : weekdaysShort[day.weekday - 1],
                            style: inter(10, 720, color: subFg, spacing: .8),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${day.day}',
                            // A line through the date reads as "not this one"
                            // at a glance, without needing a legend.
                            style: interNum(20, 740, color: fg).copyWith(
                              decoration: muted
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                              decorationColor: tones.textFaint,
                              decorationThickness: 2,
                            ),
                          ),
                          Text(monthsShort[day.month - 1],
                              style: inter(10, 640, color: subFg, spacing: .6)),
                          // Fixed-height row whether or not there is a
                          // forecast, so tiles inside and beyond the horizon
                          // stay the same size and the strip does not jitter
                          // as you scroll past day 16.
                          SizedBox(
                            height: 16,
                            child: gust == null
                                ? null
                                : Center(
                                    child: Text(
                                      '${gust.displayKnots}kt',
                                      style: interNum(11.5, 760,
                                          color: active
                                              ? Colors.white
                                              : windColor(gust.rating)),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One colour per band, shared by the strip and the summary so a day cannot
/// read as "good" in one place and "strong" in the other.
///
/// Deliberately not a gradient: the bands are decisions ("can I ride this"),
/// and a continuous ramp would imply a precision the forecast does not have.
Color windColor(WindRating rating) => switch (rating) {
      WindRating.calm => FlowColors.slate,
      WindRating.light => FlowColors.amber,
      WindRating.good => FlowColors.emerald,
      WindRating.strong => FlowColors.amber,
      WindRating.extreme => FlowColors.coral,
    };

/// The forecast for the day the rider is actually looking at.
///
/// The strip answers "which day", this answers "what am I getting" — the
/// numbers a rider would otherwise leave the app to find. It is advisory and
/// says so: the trainer decides on the morning, not this row.
class _WindSummary extends ConsumerWidget {
  const _WindSummary({required this.instructorId, required this.date});

  final String instructorId;
  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final day = ref.watch(providerWindProvider(instructorId)).value?.forDate(date);

    // No forecast, or a date past the horizon — collapse entirely rather than
    // leave an empty band where information used to be.
    return AnimatedSize(
      duration: FlowMotion.base,
      curve: FlowMotion.curve,
      alignment: Alignment.topCenter,
      child: day == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: windColor(day.rating).withValues(alpha: .10),
                borderRadius: FlowRadii.chip,
                border: Border.all(
                    color: windColor(day.rating).withValues(alpha: .35)),
              ),
              child: Row(
                children: [
                  Icon(Symbols.air_rounded,
                      size: 18, color: windColor(day.rating)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${day.rating.label} · ${day.displayKnots}kt '
                          '${day.compass}'
                          '${day.hasUsefulGust ? ' · gusts '
                              '${day.displayGustKnots}' : ''}',
                          style: inter(14, 700,
                              color: windColor(day.rating), height: 1.25),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          day.rating.detail,
                          style: inter(11.5, 480, color: tones.textFaint),
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

class _SlotArea extends StatelessWidget {
  const _SlotArea({
    required this.day,
    required this.selection,
    required this.onTap,
  });

  final DayAvailability day;
  final Set<Slot> selection;
  final ValueChanged<Slot> onTap;

  @override
  Widget build(BuildContext context) {
    // Whole-day time off → a single notice instead of the grid (§3.6).
    if (day.onVacation) {
      return const FlowNotice(
        icon: Symbols.beach_access_rounded,
        title: 'Away on this date',
        body: 'The trainer is off the water this day. Try another date.',
      );
    }
    if (day.fullyBooked) {
      // "Fully booked" is only true if hours were actually taken. Late in the
      // day the lead-time rule retires every slot, which is a clock problem,
      // not a demand one — saying otherwise misreads the trainer's day.
      final over = day.past.length >= BookingMath.slots().length;
      return FlowNotice(
        icon: over ? Symbols.bedtime_rounded : Symbols.event_busy_rounded,
        title: over ? "That's a wrap for today" : 'Fully booked',
        body: over
            ? 'Sessions need an hour of notice, so today is done. Pick a '
                'day from the strip above.'
            : 'Every hour is taken. Another day might be wide open.',
      );
    }
    final slots = BookingMath.slots();
    final states = [
      for (final s in slots)
        selection.contains(s)
            ? SlotState.selected
            : slotStateForReason(day.blockedReason(s)),
    ];

    return Column(
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            // A fixed height, not an aspect ratio. The ratio made the tile as
            // tall as the phone was wide divided by three — on a small handset
            // that resolved to 64px, and the 48px tap target inside it was
            // silently clamped to 46 by the padding and the border.
            mainAxisExtent: 68,
          ),
          itemCount: slots.length,
          itemBuilder: (context, i) => SlotTile(
            range: '${slots[i].value}–${slots[i].plusHours(1).value}',
            state: states[i],
            onTap: () => onTap(slots[i]),
          ),
        ),
        const SizedBox(height: 14),
        // Only the states this day actually contains. A fixed five-item key
        // under a day where everything is free is five facts to read and four
        // of them irrelevant.
        Align(
          alignment: Alignment.centerLeft,
          child: SlotLegend(
            states: [
              for (final s in SlotState.values)
                if (states.contains(s)) s,
            ],
          ),
        ),
      ],
    );
  }
}

class _SlotGridSkeleton extends StatelessWidget {
  const _SlotGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonGrid(
      shrinkWrap: true,
      count: 10,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        // Must track the real grid's delegate exactly, or the hours jump the
        // moment they arrive.
        mainAxisExtent: 68,
      ),
      tile: SkeletonPulse(height: 999, radius: FlowRadius.chip),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.target,
    required this.date,
    required this.slots,
    required this.total,
  });

  final BookingTarget target;
  final String date;
  final List<Slot> slots;
  final double total;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final start = slots.first;
    final end = start.plusHours(slots.length);
    return FlowCard(
      child: Row(
        children: [
          Icon(Symbols.schedule_rounded, color: tones.azureBrand, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${start.value}–${end.value}',
                    style: interNum(17, 720,
                        color: context.scheme.onSurface)),
                Text(
                    '${slots.length} hour${slots.length == 1 ? '' : 's'} · ${prettyYmd(date)}',
                    style: inter(12.5, 500, color: tones.textFaint)),
              ],
            ),
          ),
          Text(money(total), style: display(20, 760, color: tones.azureBrand)),
        ],
      ),
    );
  }
}

/// Sticky bottom bar: hour count + live total (a dash before selection) and
/// Review & confirm (§3.6). The total slides on change (§10.9).
class _StickyBar extends StatelessWidget {
  const _StickyBar({
    required this.hours,
    required this.total,
    required this.onReview,
  });

  final int hours;
  final double? total;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return StickyBar(
      child: Row(
        // Both sides flex, but not evenly. Half the bar each looks right at
        // 1.0x and starves the button everywhere else: `Review & confirm`
        // needed ~188px of the 154 a half share gives it on a 360px phone and
        // came out as `Review & co…`. The label is now short enough to fit
        // regardless, and the 2:3 split keeps it that way at 1.3x.
        children: [
          Flexible(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    hours == 0
                        ? 'No hours selected'
                        : '$hours hour${hours == 1 ? '' : 's'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: inter(12.5, 580, color: tones.textFaint)),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: FlowMotion.fast,
                  switchInCurve: FlowMotion.curve,
                  switchOutCurve: FlowMotion.curve,
                  transitionBuilder: (child, anim) => SlideTransition(
                    position: Tween(
                            begin: const Offset(0, .5), end: Offset.zero)
                        .animate(anim),
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: Text(
                    total == null ? '—' : money(total),
                    key: ValueKey(total),
                    style: display(22, 780, color: context.scheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 3,
            child: PrimaryButton(
              // Not "Review": this app also has star reviews, and a lone
              // Review button next to a price reads as "rate your trainer".
              // The sheet it opens is still titled "Review & confirm".
              label: 'Continue',
              expand: true,
              onPressed: onReview,
            ),
          ),
        ],
      ),
    );
  }
}
