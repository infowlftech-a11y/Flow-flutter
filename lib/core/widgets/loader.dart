import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// The branded wait state: two wind arcs circling, the outer one breathing.
///
/// Every prominent "something is coming" moment renders this instead of a
/// stock [CircularProgressIndicator] — the splash, [AsyncView]'s fallback,
/// the busy overlay, and the in-sheet thread loads. Inline button spinners
/// deliberately keep the stock indicator: at 18–22px the arcs read as a
/// smudge, and a control's busy state is feedback, not a loading screen.
///
/// Holds still when the OS reports reduce-motion, the same deal
/// [SkeletonPulse] makes.
class FlowLoader extends StatefulWidget {
  const FlowLoader({super.key, this.size = 36, this.color});

  final double size;

  /// Defaults to the scheme's primary. Override only on surfaces that are
  /// dark by subject (the cropper, image viewers), where the theme's colour
  /// is not the one being painted over.
  final Color? color;

  @override
  State<FlowLoader> createState() => _FlowLoaderState();
}

class _FlowLoaderState extends State<FlowLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: FlowMotion.pulse);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
      _c.value = .35;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      label: 'Loading',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) =>
              CustomPaint(painter: _WindPainter(t: _c.value, color: color)),
        ),
      ),
    );
  }
}

class _WindPainter extends CustomPainter {
  const _WindPainter({required this.t, required this.color});

  /// Animation phase, 0..1 — one full revolution per cycle.
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final stroke = size.width * .1;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;

    final angle = t * 2 * math.pi;
    // The outer gust breathes between 100° and 150° as it circles; the sine
    // keeps the growth and the shrink continuous across the loop seam.
    final breathe = (math.sin(angle) + 1) / 2;
    final outer = (size.width - stroke) / 2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outer),
      angle,
      _rad(100 + 50 * breathe),
      false,
      paint,
    );

    // The inner gust: shorter, lighter, half a turn behind, breathing in
    // counterphase — two layers of wind rather than a rim and its echo.
    paint
      ..color = color.withValues(alpha: .45)
      ..strokeWidth = stroke * .8;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outer * .58),
      angle + math.pi,
      _rad(70 + 30 * (1 - breathe)),
      false,
      paint,
    );
  }

  static double _rad(double deg) => deg * math.pi / 180;

  @override
  bool shouldRepaint(_WindPainter old) => old.t != t || old.color != color;
}
