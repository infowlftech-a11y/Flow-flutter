import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/palette.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'brand.dart';

/// The rider's check-in credential, as a card.
///
/// **Light in both themes, deliberately.** This is one of the documented
/// exceptions to reading colour from the scheme (alongside image viewers and
/// the scanner): the surface is read by a camera, not a person, and a dark QR
/// inverts to something many scanners refuse. Everything on this card is
/// therefore a fixed value, and the surrounding page is what changes with the
/// theme.
///
/// The payload is not this widget's business — it takes the encoded string
/// and draws it. The `{bookingId, trainerId}` contract (§12.2) belongs to the
/// screen that builds it and to the scanner that reads it.
class TicketCard extends StatelessWidget {
  const TicketCard({
    super.key,
    required this.payload,
    required this.rows,
    this.ticketId,
    this.qrSize = 196,
  });

  /// The encoded QR contents.
  final String payload;

  /// Label/value pairs under the code — session, instructor, spot. Ordered by
  /// the caller, because what matters most differs by ticket type.
  final List<(String, String)> rows;

  /// Human-readable reference, shown last and monospaced-ish. Null hides it.
  final String? ticketId;

  final double qrSize;

  /// The ink used on the ticket. Fixed, for the reason in the class doc.
  static const _ink = FlowColors.ink;
  static const _sub = Color(0xFF5A6B85);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FlowColors.white,
        borderRadius: FlowRadii.dialog,
      ),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // `light: false` — the wordmark sits on white here regardless of
          // the app's brightness.
          //
          // Scaled rather than given a size parameter: the wordmark exists at
          // one size for the gates, and adding a `height` to a shared widget
          // so that one caller can shrink it puts a knob on the component
          // library that every future caller then has to have an opinion
          // about. A ticket header is the only place it needs to be small.
          // The SizedBox has to be the *parent*: inside a FittedBox it just
          // clamps the wordmark to 46px and lets it overflow, rather than
          // giving the FittedBox a box to scale into.
          const SizedBox(
            height: 46,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: FlowWordmark(light: false),
            ),
          ),
          const SizedBox(height: 20),
          QrImageView(
            data: payload,
            version: QrVersions.auto,
            size: qrSize,
            backgroundColor: FlowColors.white,
            eyeStyle:
                const QrEyeStyle(eyeShape: QrEyeShape.square, color: _ink),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: _ink,
            ),
          ),
          const SizedBox(height: 20),
          for (final (label, value) in rows) ...[
            _Row(label: label, value: value),
            const SizedBox(height: 14),
          ],
          if (ticketId != null)
            _Row(label: 'TICKET ID', value: ticketId!, mono: true),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: microLabel(TicketCard._sub, size: 9.5)),
          // 3, the one deliberate off-grid step: the hairline between a label
          // and the value it names.
          const SizedBox(height: 3),
          Text(
            value,
            style: mono
                ? interNum(14, 700, color: TicketCard._ink)
                : inter(15, 640, color: TicketCard._ink),
          ),
        ],
      ),
    );
  }
}

/// A swipeable stack of tickets with a dot indicator.
///
/// A rider with three sessions booked this week has three credentials, and
/// making them dig back into a list for each one is the kind of friction that
/// gets noticed at a beach counter with a queue behind them.
///
/// Falls through to a plain card for a single ticket — one dot is not an
/// indicator, it is a smudge.
class TicketCarousel extends StatefulWidget {
  const TicketCarousel({super.key, required this.tickets});

  final List<Widget> tickets;

  @override
  State<TicketCarousel> createState() => _TicketCarouselState();
}

class _TicketCarouselState extends State<TicketCarousel> {
  late final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tickets.length == 1) return widget.tickets.single;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // A PageView needs a bounded height and the tickets vary with how
        // many rows they carry, so the tallest one sets it for all. Measuring
        // per-page would make the whole carousel jump as it settles.
        Flexible(
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.tickets.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: widget.tickets[i],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _Dots(count: widget.tickets.length, active: _page),
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Semantics(
      label: 'Ticket ${active + 1} of $count',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: AnimatedContainer(
                duration: FlowMotion.base,
                curve: FlowMotion.curve,
                width: i == active ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  // Below 8 and proportional — not a surface, so the literal
                  // stays.
                  borderRadius: BorderRadius.circular(3),
                  color: i == active
                      ? context.scheme.primary
                      : tones.textFaint.withValues(alpha: .45),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
