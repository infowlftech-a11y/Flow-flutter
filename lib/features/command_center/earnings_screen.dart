import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/misc.dart';
import '../../core/widgets/session_card.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/booking.dart';
import '../../data/repositories/booking_repository.dart';
import '../../providers/providers.dart';
import '../sessions/sessions_screen.dart' show dayAndTime;

/// What the trainer has earned, as a destination rather than a sheet.
///
/// The ledger was reachable only by tapping a stat tile on the dashboard,
/// which made the app's answer to "how am I doing" a thing you had to already
/// know how to find.
class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(trainerEarningsWeekProvider);
    final completed = ref.watch(trainerCompletedProvider);
    final allTime = ref.watch(trainerRevenueProvider);
    final outstanding = ref.watch(trainerOutstandingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: AsyncView<List<Booking>>(
        value: completed,
        onRetry: () => ref.invalidate(trainerBookingsProvider),
        onRefresh: () async => ref.invalidate(trainerBookingsProvider),
        data: (sessions) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            FlowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader('This week'),
                  _Headline(
                    amount: week.value?.total ?? 0,
                    delta: week.value?.deltaVsPrevious,
                  ),
                  const SizedBox(height: 20),
                  WeekBars(
                    bars: [
                      for (var i = 0; i < _weekdays.length; i++)
                        WeekBar(
                          label: _weekdays[i],
                          value: week.value?.byWeekday[i] ?? 0,
                          semanticValue:
                              euro(week.value?.byWeekday[i] ?? 0),
                          highlighted: week.value?.todayIndex == i,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'ALL TIME',
                    value: euro(allTime.value ?? 0),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Stat(
                    label: 'STILL TO COLLECT',
                    value: euro(outstanding.value ?? 0),
                    tone: (outstanding.value ?? 0) > 0
                        ? context.tones.warning
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const SectionHeader('Completed sessions'),
            if (sessions.isEmpty)
              const EmptyView(
                icon: Symbols.receipt_long_rounded,
                title: 'Nothing settled yet',
                subtitle:
                    'Sessions you finish appear here with what they earned.',
              )
            else
              for (final b in sessions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SessionRow(
                    when: dayAndTime(b, prettyYmd(b.date)),
                    who: b.studentName,
                    priceLabel: euro(b.amountDue),
                    statusLabel: b.payment.isOutstanding ? 'UNPAID' : null,
                    statusColor: context.tones.warning,
                    // Settled rows do nothing, and say so by not rippling.
                    // The unpaid ones are the only reason a trainer opens this
                    // list twice.
                    onTap: b.payment.isOutstanding
                        ? () => _settle(context, ref, b)
                        : null,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Settle a session that was finished without payment.
///
/// Confirms first: this is the one action in the ledger that changes money,
/// and it is a single tap away from a scrolling list. It moved here with the
/// ledger itself — it used to sit behind a sheet on the dashboard.
Future<void> _settle(
    BuildContext context, WidgetRef ref, Booking booking) async {
  final ok = await confirmAction(
    context,
    title: 'Mark as paid?',
    body: 'Records that ${booking.studentName} paid '
        '${euro(booking.amountDue)} for ${prettyYmd(booking.date)}.',
    confirmLabel: 'Mark paid',
  );
  if (!ok) return;
  Haptics.medium();
  try {
    await ref.read(bookingRepositoryProvider).markPaid(
          booking.id,
          trainerId: booking.instructorId,
        );
    if (context.mounted) {
      showFlowToast(context, '${euro(booking.amountDue)} collected 💶');
    }
  } on PaymentFailure catch (e) {
    if (context.mounted) showFlowToast(context, e.message);
  } catch (e) {
    if (context.mounted) {
      showFlowToast(context, "Couldn't save that. ${ErrorView.friendly(e)}");
    }
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.amount, this.delta});

  final double amount;
  final double? delta;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final d = delta;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(euro(amount),
            style: interNum(30, 780, color: context.scheme.onSurface)),
        const SizedBox(width: 10),
        // Nothing at all when there is no previous week to compare with —
        // see `deltaVsPrevious`. An invented "+100%" would read as a result.
        if (d != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  d >= 0
                      ? Symbols.trending_up_rounded
                      : Symbols.trending_down_rounded,
                  size: 15,
                  color: d >= 0 ? tones.success : tones.danger,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '${d >= 0 ? '+' : ''}${(d * 100).round()}% vs last week',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: inter(11.5, 600,
                        color: d >= 0 ? tones.success : tones.danger),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return FlowCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: microLabel(context.tones.textFaint, size: 9.5)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: interNum(19, 760,
                    color: tone ?? context.scheme.onSurface)),
          ),
        ],
      ),
    );
  }
}
