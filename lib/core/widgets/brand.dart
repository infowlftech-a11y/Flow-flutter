import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/typography.dart';

/// The FLOW logomark (bundled from assets/brand/logo.png).
class FlowLogo extends StatelessWidget {
  const FlowLogo({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .24),
      child: Image.asset(
        'assets/brand/logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        semanticLabel: 'FLOW',
      ),
    );
  }
}

/// Wordmark + tagline, used on gates and the auth screen.
class FlowWordmark extends StatelessWidget {
  const FlowWordmark({super.key, this.light = true});
  final bool light;

  @override
  Widget build(BuildContext context) {
    final color = light ? FlowColors.white : FlowColors.ink;
    return Column(
      children: [
        Text('FLOW',
            style: sora(34, 800, color: color, spacing: 6)),
        const SizedBox(height: 4),
        Text('OWN THE WIND',
            style: inter(11.5, 700, color: FlowColors.azure, spacing: 4.5)),
      ],
    );
  }
}

/// The auth backdrop wave, drawn with a CustomPainter — the predecessor's
/// `new-wave.png` is corrupt at source and never rendered anywhere (§14.1).
class WaveBackdrop extends StatelessWidget {
  const WaveBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: FlowColors.ink),
      child: CustomPaint(
        painter: _WavePainter(),
        child: child,
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Soft azure glow top-right.
    canvas.drawCircle(
      Offset(w * .9, h * .08),
      w * .55,
      Paint()
        ..shader = RadialGradient(colors: [
          FlowColors.azure.withValues(alpha: .22),
          FlowColors.azure.withValues(alpha: 0),
        ]).createShader(
            Rect.fromCircle(center: Offset(w * .9, h * .08), radius: w * .55)),
    );

    // Two crossing swells near the bottom.
    final swell1 = Path()
      ..moveTo(0, h * .78)
      ..cubicTo(w * .25, h * .72, w * .45, h * .86, w * .7, h * .8)
      ..cubicTo(w * .85, h * .76, w * .95, h * .8, w, h * .77)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
        swell1, Paint()..color = FlowColors.azure.withValues(alpha: .10));

    final swell2 = Path()
      ..moveTo(0, h * .87)
      ..cubicTo(w * .3, h * .93, w * .55, h * .82, w * .8, h * .9)
      ..cubicTo(w * .9, h * .93, w * .97, h * .9, w, h * .91)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
        swell2, Paint()..color = FlowColors.azure.withValues(alpha: .14));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
