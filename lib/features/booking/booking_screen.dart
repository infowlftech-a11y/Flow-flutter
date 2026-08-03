import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/flow_image.dart';
import '../../core/widgets/misc.dart';
import '../../core/widgets/sheets.dart';
import '../../data/models/catalogue.dart';
import '../../data/models/schedule.dart';
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
        icon: Icons.link_off_rounded,
      );
    }
  }

  /// If a selected hour became unavailable while the screen is open, drop it
  /// on the next frame — but only once real data has arrived (§8.4).
  void _pruneSelection(DayAvailability day) {
    final stale = [for (final s in _selection) if (!day.isFree(s)) s];
    if (stale.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _selection.removeAll(stale));
      showFlowToast(context,
          'An hour you picked was just taken and has been removed.');
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
                    style: inter(12, 480, color: context.tones.textFaint),
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
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
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
                  borderRadius: BorderRadius.circular(16),
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
                            '${euro(target.rate)} × ${slots.length}h',
                            style: inter(14, 540,
                                color:
                                    sheetContext.scheme.onSurfaceVariant)),
                        Text(euro(_total),
                            style: sora(22, 760,
                                color: sheetContext.tones.azureBrand)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.storefront_outlined,
                            size: 15,
                            color: sheetContext.tones.textFaint),
                        const SizedBox(width: 6),
                        Text('Pay at the centre — nothing is charged in FLOW',
                            style: inter(12, 540,
                                color: sheetContext.tones.textFaint)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Your kite level is shared with the trainer so they can prep '
                'the right session.',
                style: inter(12, 480, color: sheetContext.tones.textFaint),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Confirm booking',
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
    } on SlotTakenFailure {
      if (sheetContext.mounted) Navigator.pop(sheetContext);
      if (mounted) {
        setState(() {
          _submitting = false;
          _selection.clear();
        });
        showFlowToast(context,
            'Those hours were just taken. Pick a different time.');
      }
    } catch (_) {
      if (sheetContext.mounted) {
        setSheet(() => _submitting = false);
        setState(() {});
        showFlowToast(
            sheetContext, "Couldn't send your request. Try again.");
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
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: dialogContext.tones.successTint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.send_rounded,
                      color: dialogContext.tones.success, size: 34),
                ),
                const SizedBox(height: 20),
                Text('Request sent!',
                    style: Theme.of(dialogContext).textTheme.headlineMedium),
                const SizedBox(height: 10),
                Text(
                  "Your trainer has been notified. You'll get a ping the "
                  'moment they approve.',
                  textAlign: TextAlign.center,
                  style: Theme.of(dialogContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 22),
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
                style: microLabel(context.tones.textFaint, size: 10.5)),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tones.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tones.line),
      ),
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
                      Icon(Icons.place_outlined,
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
              Text(euro(target.rate),
                  style: interNum(17, 760, color: tones.azureBrand)),
              Text('/ ${target.unit}',
                  style: inter(11, 540, color: tones.textFaint)),
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

    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: FlowConst.bookingDayStripLength,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final day = today.add(Duration(days: i));
          final date = ymd(day);
          final active = date == selected;
          final away = vacations.any((v) => v.covers(date));
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
                '${away ? ', trainer away' : over ? ', no hours left' : ''}',
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 62,
              decoration: BoxDecoration(
                color: active ? tones.azureBrand : tones.card,
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: active ? tones.azureBrand : tones.line),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
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
                              style: inter(9.5, 640, color: subFg, spacing: .6)),
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
      return _Notice(
        icon: Icons.beach_access_rounded,
        title: 'Away on this date',
        body: 'The trainer is off the water this day. Try another date.',
      );
    }
    if (day.fullyBooked) {
      // "Fully booked" is only true if hours were actually taken. Late in the
      // day the lead-time rule retires every slot, which is a clock problem,
      // not a demand one — saying otherwise misreads the trainer's day.
      final over = day.past.length >= BookingMath.slots().length;
      return _Notice(
        icon: over ? Icons.bedtime_rounded : Icons.event_busy_rounded,
        title: over ? "That's a wrap for today" : 'Fully booked',
        body: over
            ? 'Sessions need an hour of notice, so today is done. Pick a '
                'day from the strip above.'
            : 'Every hour is taken. Another day might be wide open.',
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.55,
      ),
      itemCount: BookingMath.slots().length,
      itemBuilder: (context, i) {
        final slot = BookingMath.slots()[i];
        final free = day.isFree(slot);
        final selected = selection.contains(slot);
        final reason = day.blockedReason(slot);
        return _SlotTile(
          slot: slot,
          state: selected
              ? _SlotState.selected
              : free
                  ? _SlotState.free
                  : _SlotState.blocked,
          reason: reason,
          onTap: free || selected ? () => onTap(slot) : null,
        );
      },
    );
  }
}

enum _SlotState { free, selected, blocked }

class _SlotTile extends StatelessWidget {
  const _SlotTile({
    required this.slot,
    required this.state,
    required this.reason,
    required this.onTap,
  });

  final Slot slot;
  final _SlotState state;
  final String? reason;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final scheme = context.scheme;

    final (bg, border, fg) = switch (state) {
      _SlotState.selected => (
          tones.azureBrand,
          tones.azureBrand,
          Colors.white
        ),
      _SlotState.free => (tones.card, tones.line, scheme.onSurface),
      _SlotState.blocked => (
          Colors.transparent,
          tones.line.withValues(alpha: .5),
          tones.textFaint.withValues(alpha: .8)
        ),
    };

    final label = switch (state) {
      _SlotState.selected => 'Selected',
      _SlotState.free => 'Free',
      _SlotState.blocked => reason ?? 'Unavailable',
    };

    return Semantics(
      button: onTap != null,
      label:
          '${slot.value} to ${slot.plusHours(1).value}, $label',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: border),
        ),
        // Ripple on top of the fill: a tapped hour should acknowledge the
        // touch on contact, not only once setState lands.
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${slot.value}–${slot.plusHours(1).value}',
                    style: interNum(13, 680, color: fg)),
                const SizedBox(height: 2),
                Text(label,
                    style: inter(10.5, 580,
                        color: state == _SlotState.selected
                            ? Colors.white.withValues(alpha: .85)
                            : state == _SlotState.free
                                ? tones.success
                                : fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tones.warningTint,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: tones.warning, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(body, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotGridSkeleton extends StatelessWidget {
  const _SlotGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.55,
      ),
      itemCount: 10,
      itemBuilder: (_, _) =>
          const SkeletonPulse(height: 999, radius: 13),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tones.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tones.line),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, color: tones.azureBrand, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${start.value}–${end.value}',
                    style: interNum(16, 720,
                        color: context.scheme.onSurface)),
                Text(
                    '${slots.length} hour${slots.length == 1 ? '' : 's'} · ${prettyYmd(date)}',
                    style: inter(12.5, 500, color: tones.textFaint)),
              ],
            ),
          ),
          Text(euro(total), style: sora(20, 760, color: tones.azureBrand)),
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
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 12 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: context.scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: tones.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    hours == 0
                        ? 'No hours selected'
                        : '$hours hour${hours == 1 ? '' : 's'}',
                    style: inter(12, 580, color: tones.textFaint)),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  transitionBuilder: (child, anim) => SlideTransition(
                    position: Tween(
                            begin: const Offset(0, .5), end: Offset.zero)
                        .animate(anim),
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: Text(
                    total == null ? '—' : euro(total),
                    key: ValueKey(total),
                    style: sora(22, 780, color: context.scheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
          PrimaryButton(
            label: 'Review & confirm',
            expand: false,
            onPressed: onReview,
          ),
        ],
      ),
    );
  }
}
