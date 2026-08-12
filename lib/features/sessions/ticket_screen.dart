import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_x.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/ticket.dart';
import '../../data/models/booking.dart';
import '../../providers/providers.dart';
import 'sessions_screen.dart' show dayAndTime;

/// The rider's check-in credentials, as a top-level destination.
///
/// It was a dialog reached from a session card, which is two taps and a
/// remembered path at the exact moment a rider is standing at a counter with
/// a queue behind them. Promoting it to a tab is the redesign's one real
/// information-architecture change on the rider side.
///
/// Shows every booking that *has* a credential — confirmed or already
/// started. A pending request has nothing to scan, and a completed one has
/// nothing left to prove.
class TicketScreen extends ConsumerWidget {
  const TicketScreen({super.key});

  /// §12.2 — the payload the scanner expects. Unchanged: this screen is a new
  /// place to show the credential, not a new credential.
  static String payloadFor(Booking b) =>
      jsonEncode({'bookingId': b.id, 'trainerId': b.instructorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buckets = ref.watch(riderBucketsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your ticket'),
        centerTitle: true,
      ),
      body: AsyncView<BookingBuckets>(
        value: buckets,
        onRetry: () => ref.invalidate(riderBookingsProvider),
        data: (data) {
          final tickets = [
            ...?data[BookingBucket.active],
            ...?data[BookingBucket.upcoming],
          ].where((b) =>
                  b.status == BookingStatus.confirmed ||
                  b.status == BookingStatus.inProgress).toList();

          if (tickets.isEmpty) {
            return const EmptyView.scrollable(
              icon: Symbols.confirmation_number_rounded,
              title: 'No tickets yet',
              subtitle:
                  'Once a trainer approves your booking, your check-in code '
                  'appears here.',
            );
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                children: [
                  Expanded(
                    child: TicketCarousel(
                      tickets: [
                        for (final b in tickets)
                          SingleChildScrollView(
                            // Centred, not top-aligned. A ticket is shorter
                            // than the space it gets, and pinning it to the
                            // top left ~180dp of gap between the card and the
                            // page dots, which read as orphaned. `Center`
                            // inside a scroll view still scrolls once the card
                            // outgrows the viewport at large text scales.
                            child: Center(
                              child: TicketCard(
                                payload: payloadFor(b),
                                ticketId: _reference(b),
                                rows: [
                                  ('SESSION',
                                      dayAndTime(b, prettyYmd(b.date))),
                                  ('INSTRUCTOR', b.instructorName),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Arrive 10 minutes early',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// A short human-readable reference, derived rather than stored — it exists
  /// so a rider and a trainer can say the same thing out loud when a camera
  /// will not cooperate, not as an identifier anything looks up.
  static String _reference(Booking b) {
    final id = b.id.replaceAll(RegExp('[^A-Za-z0-9]'), '').toUpperCase();
    final tail = id.length <= 4 ? id : id.substring(id.length - 4);
    return 'FLW-${b.date.replaceAll('-', '').substring(4)}-$tail';
  }
}
