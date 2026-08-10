import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'flow_image.dart';
import 'misc.dart';

/// Counts down to [target], to the second.
///
/// Scoped deliberately tight: it is its own widget so the ticking rebuilds a
/// single Text and nothing else. Hoisting the timer into the card would
/// re-run the photo, the gradient and the whole layout sixty times a minute
/// to change eight characters.
///
/// Stops itself at zero rather than counting into negatives, and holds no
/// timer once it has — a finished session must not keep a handset awake.
class CountdownText extends StatefulWidget {
  const CountdownText({
    super.key,
    required this.target,
    required this.style,
    this.expiredLabel = '00:00:00',
  });

  final DateTime target;
  final TextStyle style;
  final String expiredLabel;

  /// `HH:MM:SS`, clamped at zero.
  ///
  /// Public and static so it can be asserted directly. It was a static on the
  /// private state class, which put the one piece of pure logic in this file
  /// out of reach of a test that does not need a widget tree at all.
  static String format(Duration d) {
    if (d <= Duration.zero) return '00:00:00';
    String two(int n) => n.toString().padLeft(2, '0');
    // Hours deliberately not capped at 24: a multi-day safari counts down in
    // hours, and "03:12:44" for three days out would be a lie.
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  State<CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<CountdownText> {
  Timer? _timer;
  late Duration _left;

  @override
  void initState() {
    super.initState();
    _left = _remaining();
    if (!_left.isNegative && _left > Duration.zero) _start();
  }

  @override
  void didUpdateWidget(CountdownText old) {
    super.didUpdateWidget(old);
    // A rescheduled session changes the target under us; without this the
    // card would count down to the old time forever.
    if (old.target != widget.target) {
      _timer?.cancel();
      _left = _remaining();
      if (_left > Duration.zero) _start();
    }
  }

  Duration _remaining() => widget.target.difference(DateTime.now());

  void _start() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = _remaining();
      if (left <= Duration.zero) {
        t.cancel();
        if (mounted) setState(() => _left = Duration.zero);
        return;
      }
      if (mounted) setState(() => _left = left);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expired = _left <= Duration.zero;
    return Text(
      expired ? widget.expiredLabel : CountdownText.format(_left),
      style: widget.style,
    );
  }
}

/// The session happening now, or next — the one card that earns a photo.
///
/// Everything else in a session list is a row. This is a card because there
/// is only ever one of it and it is the thing the rider opened the app for.
class LiveSessionCard extends StatelessWidget {
  const LiveSessionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.imageUrl,
    this.badgeLabel,
    this.countdownTo,
    this.countdownLabel = 'Time left',
  });

  /// `Today, 13 May · 10:00 – 11:00`. Caller owns date formatting.
  final String title;

  /// `with Marco B. · El Gouna`.
  final String subtitle;

  final VoidCallback onTap;
  final String? imageUrl;

  /// `LIVE NOW`, `STARTS SOON`. Null hides the pill.
  final String? badgeLabel;

  /// Null hides the countdown — a session that has not been given an end time
  /// shows none rather than counting to an invented one.
  final DateTime? countdownTo;
  final String countdownLabel;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final hasPhoto = imageUrl != null && imageUrl!.isNotEmpty;

    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: Material(
        color: tones.card,
        borderRadius: FlowRadii.card,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              // No photo gets the brand gradient, not the placeholder. The
              // placeholder centres its glyph, and this card centres nothing —
              // the title lands straight on top of it, so a card with no image
              // read as a broken one rather than a plain one. That is not the
              // rare case either: it is every card until Storage is
              // provisioned. The gradient is dark navy in both themes, so the
              // white text below clears AA on it without the scrim.
              Positioned.fill(
                child: hasPhoto
                    ? FlowImage(url: imageUrl, fit: BoxFit.cover)
                    : DecoratedBox(
                        decoration: BoxDecoration(gradient: tones.heroGradient),
                      ),
              ),
              // The photo is behind text, so it needs a scrim rather than
              // trust. These are fixed dark values on purpose: the surface is
              // a photograph in both themes, so it is one of the documented
              // exceptions to reading colour from the scheme.
              if (hasPhoto)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [Color(0x66000000), Color(0xE604121F)],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (badgeLabel != null)
                      TagPill(badgeLabel!,
                          color: tones.danger,
                          icon: Symbols.circle,
                          iconFill: 1,
                          dense: true),
                    const SizedBox(height: 40),
                    Text(
                      title,
                      style: display(18, 740,
                          color: Colors.white, spacing: -.2, height: 1.25),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style:
                          inter(13, 500, color: Colors.white.withValues(alpha: .82)),
                    ),
                    if (countdownTo != null) ...[
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          CountdownText(
                            target: countdownTo!,
                            style: interNum(26, 780, color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          // The digits are the fact; the word beside them is
                          // the caption. If the row runs short it is the
                          // caption that gives way, never the clock.
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                countdownLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: inter(11.5, 560,
                                    color:
                                        Colors.white.withValues(alpha: .72)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A session in a list: thumbnail, when, with whom, money, state.
class SessionRow extends StatelessWidget {
  const SessionRow({
    super.key,
    required this.when,
    required this.who,
    required this.onTap,
    this.imageUrl,
    this.location,
    this.priceLabel,
    this.statusLabel,
    this.statusColor,
  });

  final String when;
  final String who;

  /// Null for a row with nothing behind it — a settled session in the ledger,
  /// say. The ripple and the button semantics go with it, so a screen reader
  /// is not told to tap something inert.
  final VoidCallback? onTap;

  final String? imageUrl;
  final String? location;
  final String? priceLabel;
  final String? statusLabel;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final scheme = context.scheme;

    return Material(
      color: tones.card,
      borderRadius: FlowRadii.inset,
      child: InkWell(
        borderRadius: FlowRadii.inset,
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: FlowRadii.inset,
            border: Border.all(color: tones.line),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: FlowRadii.chip,
                  child: FlowImage(
                      url: imageUrl, width: 52, height: 52, fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(when,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: inter(13.5, 700,
                                    color: scheme.onSurface)),
                          ),
                          if (statusLabel != null) ...[
                            const SizedBox(width: 6),
                            TagPill(statusLabel!,
                                color: statusColor, dense: true),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        location == null ? who : '$who · $location',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            inter(12.5, 500, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (priceLabel != null) ...[
                  const SizedBox(width: 10),
                  Text(priceLabel!,
                      style: interNum(15, 760, color: scheme.onSurface)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
