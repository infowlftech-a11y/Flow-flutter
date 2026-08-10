import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/radii.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/misc.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/booking.dart';
import '../../data/models/schedule.dart';
import '../../data/repositories/booking_repository.dart';
import '../../providers/providers.dart';

/// Trainer calendar control (§3.9): day navigator, walk-in & time-off kept
/// above the timeline (time-critical beach tasks), tap-to-block hours.
class ScheduleTab extends ConsumerStatefulWidget {
  const ScheduleTab({super.key});

  @override
  ConsumerState<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends ConsumerState<ScheduleTab> {
  late String _date = todayYmd();

  DayKey get _key =>
      (instructorId: ref.read(sessionProvider).uid, date: _date);

  void _shiftDay(int delta) {
    final d = parseYmd(_date)!.add(Duration(days: delta));
    final today = DateTime.now();
    final min = DateTime(today.year, today.month, today.day);
    if (d.isBefore(min)) return;
    Haptics.select();
    setState(() => _date = ymd(d));
  }

  /// Rolls a stale selection forward when the day changes under the tab.
  ///
  /// `_date` is captured once, but this tab can outlive the day it was opened
  /// on — a trainer who leaves the app here overnight returns to `_date`
  /// pointing at yesterday. The header still claims TODAY, every hour reads
  /// as free (`pastSlots` only masks the *current* day), and a walk-in would
  /// be written into the past.
  void _rollOverIfStale() {
    if (_date.compareTo(todayYmd()) >= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _date.compareTo(todayYmd()) < 0) {
        setState(() => _date = todayYmd());
      }
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final min = DateTime(now.year, now.month, now.day);
    final current = parseYmd(_date);
    final picked = await showDatePicker(
      context: context,
      // Clamped: showDatePicker asserts initialDate is not before firstDate,
      // and a stale `_date` from before midnight is exactly that.
      initialDate:
          (current == null || current.isBefore(min)) ? min : current,
      firstDate: min,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = ymd(picked));
  }

  @override
  Widget build(BuildContext context) {
    _rollOverIfStale();
    final uid = ref.watch(sessionProvider.select((s) => s.uid));
    final key = (instructorId: uid, date: _date);
    final availability = ref.watch(dayAvailabilityProvider(key));
    final blocks = ref.watch(dayBlocksProvider(key));
    final dayBookings = ref.watch(dayAvailabilityProvider(key));
    final vacations = ref.watch(myVacationsProvider);
    final tones = context.tones;

    final vacationForDay = (vacations.value ?? const <Vacation>[])
        .where((v) => v.covers(_date))
        .firstOrNull;

    return RefreshIndicator(
      onRefresh: () async {
        // Resync blocks, bookings and vacations (§3.9).
        ref.invalidate(dayAvailabilityProvider(key));
        ref.invalidate(dayBlocksProvider(key));
        ref.invalidate(myVacationsProvider);
        await ref.read(dayAvailabilityProvider(key).future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 96),
        children: [
          // Day navigator.
          Row(
            children: [
              IconButton.outlined(
                onPressed: () => _shiftDay(-1),
                tooltip: 'Previous day',
                icon: const Icon(Symbols.chevron_left_rounded),
              ),
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Change date, currently ${longYmd(_date)}',
                  child: InkWell(
                    onTap: _pickDate,
                    borderRadius: FlowRadii.chip,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        children: [
                          Text(
                            _date == todayYmd() ? 'TODAY' : longYmd(_date),
                            style: _date == todayYmd()
                                ? microLabel(tones.azureBrand)
                                : Theme.of(context).textTheme.titleMedium,
                          ),
                          if (_date == todayYmd())
                            Text(longYmd(_date),
                                style:
                                    Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IconButton.outlined(
                onPressed: () => _shiftDay(1),
                tooltip: 'Next day',
                icon: const Icon(Symbols.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: MicroAction(
                  label: 'WALK-IN',
                  icon: Symbols.person_add_alt_rounded,
                  onPressed: () => _openWalkInSheet(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MicroAction(
                  label: 'TIME OFF',
                  icon: Symbols.beach_access_rounded,
                  filled: false,
                  onPressed: () => _openTimeOffSheet(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (vacationForDay != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: FlowNotice(
                icon: Symbols.beach_access_rounded,
                title: vacationForDay.label ?? 'Time off',
                body: 'You are away this whole day. '
                    'Riders see nothing bookable.',
              ),
            ),
          SectionHeader(
            'Day timeline',
            trailing: switch (availability) {
              // Counter hidden while loading — never a misleading 0 (§3.9).
              AsyncData(:final value) when value.blocked.isNotEmpty => Text(
                  '${value.blocked.length} blocked',
                  style: microLabel(tones.warning)),
              _ => null,
            },
          ),
          AsyncView<DayAvailability>(
            value: dayBookings,
            onRetry: () => ref.invalidate(dayAvailabilityProvider(key)),
            skeleton: Column(
              children: [
                for (var i = 0; i < 6; i++)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: SkeletonPulse(height: 56, radius: 14),
                  ),
              ],
            ),
            data: (day) => _Timeline(
              date: _date,
              day: day,
              blocks: blocks.value ?? const [],
              onToggle: (slot) => _toggleSlot(slot, day),
            ),
          ),
          const SizedBox(height: 24),
          _VacationList(vacations: vacations),
        ],
      ),
    );
  }

  Future<void> _toggleSlot(Slot slot, DayAvailability day) async {
    final schedule = ref.read(scheduleRepositoryProvider);
    final blocks = ref.read(dayBlocksProvider(_key)).value ?? const [];

    // A blocked hour → release it; a free hour → block it. Booked, past and
    // away hours are not tappable (enforced by the timeline).
    final existing = blocks
        .where((b) => b.blocksCalendar && b.expandBlock().contains(slot))
        .firstOrNull;
    Haptics.select();
    try {
      if (existing != null) {
        await schedule.releaseBlock(existing.id);
      } else {
        await schedule.blockHour(
          instructorId: ref.read(sessionProvider).uid,
          date: _date,
          start: slot,
        );
      }
    } catch (_) {
      if (mounted) {
        showFlowToast(context, "Couldn't update that hour. Try again.");
      }
    }
  }

  /// Add walk-in sheet (§3.9): only genuinely free hours are offered; price
  /// pre-filled with rate × 1, falls back to rate × hours if unparseable.
  void _openWalkInSheet(BuildContext context) {
    final day = ref.read(dayAvailabilityProvider(_key)).value;
    final freeSlots =
        [for (final s in BookingMath.slots()) if (day?.isFree(s) ?? false) s];

    if (freeSlots.isEmpty) {
      showFlowToast(context, 'No free hours left on ${prettyYmd(_date)}.');
      return;
    }

    final trainer = ref.read(currentUserProvider).value;
    final rate = trainer?.displayRate ?? FlowConst.defaultDisplayRate;
    final name = TextEditingController();
    final price = TextEditingController(text: '${rate.round()}');
    Slot? start;
    var duration = 1;
    var busy = false;
    var attempted = false;

    showFlowSheet<void>(
      context,
      title: 'Add walk-in',
      subtitle: 'Creates a confirmed booking on your calendar.',
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          bool slotRangeFree(Slot s, int hours) {
            // Closing time first: isFree() is vacuously true past 17:00, so
            // without this a 4h duration offers 17:00 and books to 21:00.
            if (!BookingMath.fitsInDay(s, hours)) return false;
            for (var i = 0; i < hours; i++) {
              final probe = s.plusHours(i);
              if (!(day?.isFree(probe) ?? false)) return false;
            }
            return true;
          }

          final offered =
              [for (final s in freeSlots) if (slotRangeFree(s, duration)) s];
          if (start != null && !offered.contains(start)) start = null;

          Future<void> submit() async {
            setSheet(() => attempted = true);
            if (name.text.trim().isEmpty || start == null) return;
            setSheet(() => busy = true);
            final total = double.tryParse(price.text.trim()) ??
                rate * duration;
            try {
              final session = ref.read(sessionProvider);
              await ref.read(bookingRepositoryProvider).createWalkIn(
                    instructorId: session.uid,
                    instructorName: session.displayName,
                    studentName: name.text.trim(),
                    date: _date,
                    start: start!,
                    durationHours: duration,
                    totalPrice: total,
                  );
              Haptics.medium();
              if (sheetContext.mounted) Navigator.pop(sheetContext);
              if (mounted) {
                showFlowToast(this.context, 'Walk-in added to your day');
              }
            } on SlotTakenFailure {
              if (sheetContext.mounted) {
                setSheet(() => busy = false);
                showFlowToast(sheetContext,
                    'That hour was just taken. Pick another start.');
              }
            } catch (_) {
              if (sheetContext.mounted) {
                setSheet(() => busy = false);
                showFlowToast(
                    sheetContext, "Couldn't add the walk-in. Try again.");
              }
            }
          }

          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            children: [
              TextField(
                controller: name,
                enabled: !busy,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Student name',
                  errorText: attempted && name.text.trim().isEmpty
                      ? 'Who is this session for?'
                      : null,
                ),
                onChanged: (_) => setSheet(() {}),
              ),
              const SizedBox(height: 18),
              Text('START TIME',
                  style: microLabel(sheetContext.tones.textFaint)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in offered)
                    FlowChoiceChip(
                      label: s.value,
                      selected: start == s,
                      onTap: () {
                        Haptics.select();
                        setSheet(() => start = s);
                      },
                    ),
                ],
              ),
              if (attempted && start == null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Pick a start time',
                      style: inter(12.5, 560,
                          color: sheetContext.tones.danger)),
                ),
              const SizedBox(height: 18),
              Text('DURATION',
                  style: microLabel(sheetContext.tones.textFaint)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final h in FlowConst.walkInDurations)
                    FlowChoiceChip(
                      label: '${h}h',
                      selected: duration == h,
                      onTap: () {
                        Haptics.select();
                        setSheet(() {
                          duration = h;
                          price.text = '${(rate * h).round()}';
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: price,
                enabled: !busy,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                    prefixText: '€ ', labelText: 'Total price'),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                  label: 'Add to my day', busy: busy, onPressed: submit),
            ],
          );
        },
      ),
      // Sheet-scoped controllers still need disposing — a trainer adding six
      // walk-ins in a session otherwise leaks twelve of them plus their
      // listener chains.
    ).whenComplete(() {
      name.dispose();
      price.dispose();
    });
  }

  /// Time-off sheet: the "to" picker can never precede "from" (§3.9).
  void _openTimeOffSheet(BuildContext context) {
    final reason = TextEditingController();
    var from = parseYmd(_date) ?? DateTime.now();
    var to = from;
    var busy = false;

    showFlowSheet<void>(
      context,
      title: 'Schedule time off',
      subtitle: 'Whole days where nothing is bookable.',
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          Future<void> pick(bool isFrom) async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: sheetContext,
              initialDate: isFrom ? from : to,
              firstDate: isFrom
                  ? DateTime(now.year, now.month, now.day)
                  : from, // "to" cannot precede "from"
              lastDate: now.add(const Duration(days: 365)),
            );
            if (picked == null) return;
            setSheet(() {
              if (isFrom) {
                from = picked;
                if (to.isBefore(from)) to = from;
              } else {
                to = picked;
              }
            });
          }

          Future<void> submit() async {
            setSheet(() => busy = true);
            try {
              await ref.read(scheduleRepositoryProvider).addVacation(
                    instructorId: ref.read(sessionProvider).uid,
                    startDate: ymd(from),
                    endDate: ymd(to),
                    label: reason.text.trim().isEmpty
                        ? 'Time off'
                        : reason.text.trim(),
                  );
              if (sheetContext.mounted) Navigator.pop(sheetContext);
              if (mounted) {
                showFlowToast(this.context, 'Time off scheduled');
              }
            } catch (_) {
              if (sheetContext.mounted) {
                setSheet(() => busy = false);
                showFlowToast(
                    sheetContext, "Couldn't schedule that. Try again.");
              }
            }
          }

          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            children: [
              TextField(
                controller: reason,
                enabled: !busy,
                decoration: const InputDecoration(
                    hintText: 'Reason (e.g. "Safari week")'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: InfoTile(
                        label: 'FROM',
                        value: prettyYmd(ymd(from)),
                        trailingIcon: Symbols.edit_calendar_rounded,
                        onTap: busy ? null : () => pick(true)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InfoTile(
                        label: 'TO',
                        value: prettyYmd(ymd(to)),
                        trailingIcon: Symbols.edit_calendar_rounded,
                        onTap: busy ? null : () => pick(false)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                  label: 'Schedule time off', busy: busy, onPressed: submit),
            ],
          );
        },
      ),
    ).whenComplete(reason.dispose);
  }
}

/// One row per bookable hour (§3.9).
class _Timeline extends ConsumerWidget {
  const _Timeline({
    required this.date,
    required this.day,
    required this.blocks,
    required this.onToggle,
  });

  final String date;
  final DayAvailability day;
  final List<Availability> blocks;
  final ValueChanged<Slot> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref
            .watch(trainerBookingsProvider)
            .value
            ?.where((b) => b.date == date && b.status.isLive)
            .toList() ??
        const <Booking>[];

    Booking? bookingAt(Slot slot) {
      for (final b in bookings) {
        if (b.occupiedSlots.contains(slot)) return b;
      }
      return null;
    }

    final tones = context.tones;
    return Column(
      children: [
        for (final slot in BookingMath.slots())
          Builder(builder: (context) {
            final booking = bookingAt(slot);
            final isPast = day.past.contains(slot);
            final isBlocked = day.blocked.contains(slot);
            final away = day.onVacation;

            final String state;
            final Color color;
            if (booking != null) {
              state = booking.studentName;
              color = tones.azureBrand;
            } else if (away) {
              state = 'Away';
              color = tones.warning;
            } else if (isPast) {
              state = 'Past';
              color = tones.textFaint;
            } else if (isBlocked) {
              state = 'Blocked';
              color = tones.warning;
            } else {
              state = 'Available';
              color = tones.success;
            }

            final tappable = booking == null && !isPast && !away;

            return Semantics(
              button: tappable,
              label:
                  '${slot.value}: $state${tappable ? isBlocked ? ', tap to release' : ', tap to block' : ''}',
              child: GestureDetector(
                onTap: tappable ? () => onToggle(slot) : null,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: booking != null
                        ? tones.azureBrand.withValues(alpha: .08)
                        : isBlocked
                            ? tones.warningTint
                            : tones.card,
                    borderRadius: FlowRadii.control,
                    border: Border.all(
                        color: booking != null
                            ? tones.azureBrand.withValues(alpha: .4)
                            : tones.line),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 52,
                        child: Text(slot.value,
                            style: interNum(14, 680,
                                color: isPast
                                    ? tones.textFaint
                                    : context.scheme.onSurface)),
                      ),
                      Container(
                        width: 8,
                        height: 8,
                        decoration:
                            BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(state,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: inter(
                                      13.5, booking != null ? 660 : 520,
                                      color: booking != null
                                          ? context.scheme.onSurface
                                          : color)),
                            ),
                            if (booking?.isManual ?? false) ...[
                              const SizedBox(width: 8),
                              const TagPill('WALK-IN'),
                            ],
                          ],
                        ),
                      ),
                      if (tappable)
                        Icon(
                          isBlocked
                              ? Symbols.lock_open_rounded
                              : Symbols.block_rounded,
                          size: 17,
                          color: tones.textFaint,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

/// Scheduled time off with per-entry delete + UNDO (§3.9, §10.4).
class _VacationList extends ConsumerWidget {
  const _VacationList({required this.vacations});

  final AsyncValue<List<Vacation>> vacations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = vacations.value ?? const <Vacation>[];
    if (list.isEmpty) return const SizedBox.shrink();
    final tones = context.tones;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Scheduled time off'),
        for (final v in list)
          FlowCard(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            // Control radius: a dense row of scheduled days, not a card.
            borderRadius: FlowRadii.control,
            child: Row(
              children: [
                Icon(Symbols.beach_access_rounded,
                    size: 19, color: tones.warning),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v.label ?? 'Time off',
                          style: Theme.of(context).textTheme.titleSmall),
                      Text(
                        v.startDate == v.endDate
                            ? prettyYmd(v.startDate)
                            : '${prettyYmd(v.startDate)} → ${prettyYmd(v.endDate)}',
                        style: inter(12.5, 500, color: tones.textFaint),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove time off',
                  onPressed: () async {
                    final schedule = ref.read(scheduleRepositoryProvider);
                    try {
                      await schedule.removeVacation(v.id);
                    } catch (_) {
                      // Unguarded, a rejected delete threw into the zone and
                      // the row stayed put with no toast — indistinguishable
                      // from nothing having been tapped.
                      if (context.mounted) {
                        showFlowToast(
                            context, "Couldn't remove that time off. Try again.");
                      }
                      return;
                    }
                    if (context.mounted) {
                      showFlowToast(
                        context,
                        'Time off removed',
                        undoLabel: 'UNDO',
                        onUndo: () => schedule.restoreVacation(v).ignore(),
                      );
                    }
                  },
                  icon: const Icon(Symbols.delete_outline_rounded, size: 20),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
