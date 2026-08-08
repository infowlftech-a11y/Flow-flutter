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
  const FlowWordmark({super.key, this.light});

  /// Force the treatment. Left null it follows the theme, which is what the
  /// backdrop behind it now does too — the wordmark used to be hardcoded
  /// white, so in light mode it sat white-on-white.
  final bool? light;

  @override
  Widget build(BuildContext context) {
    final onDark = light ?? Theme.of(context).brightness == Brightness.dark;
    final color = onDark ? FlowColors.white : FlowColors.ink;
    return Column(
      children: [
        Text('FLOW',
            style: sora(32, 800, color: color, spacing: 6)),
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
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    // The backdrop used to be ink in both themes, which made every screen it
    // carries — splash, the four auth routes, the four gates — a dark island
    // in an otherwise white app. The swells need a little more alpha on a
    // light ground to read at all.
    final base = dark ? FlowColors.ink : theme.colorScheme.surface;
    final swells = dark ? const [.10, .14] : const [.13, .18];
    final glow = dark ? .22 : .16;

    return DecoratedBox(
      decoration: BoxDecoration(color: base),
      // The swells are placed at fractions of the painted box, and `Scaffold`
      // shrinks its body when the keyboard opens — so the fractions get
      // recomputed against a much shorter box and the waves climb up over the
      // form. On sign-in they landed across the CTA and the footer. Adding
      // the hidden height back makes the painter see the pre-keyboard box, so
      // the swells stay where they were: at the bottom, behind the keyboard.
      //
      // Two things here are load-bearing, and both are about the `Scaffold`
      // between us and the keyboard:
      //
      //  - The inset must come from `View`, not `MediaQuery`. A `Scaffold`
      //    that resizes for the keyboard reports `viewInsets.bottom` to its
      //    body as 0, having already spent it on the shrink.
      //  - `LayoutBuilder` is what makes this rebuild. Nothing down here
      //    depends on a `MediaQuery` that changes, so the body being given a
      //    new height is the only signal that reaches this far.
      //
      // With no keyboard the inset is 0 and this paints exactly as before.
      child: LayoutBuilder(
        builder: (context, _) {
          final view = View.of(context);
          return CustomPaint(
            painter: _WavePainter(
              view.viewInsets.bottom / view.devicePixelRatio,
              swell1: swells[0],
              swell2: swells[1],
              glow: glow,
            ),
            child: child,
          );
        },
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter(
    this.bottomInset, {
    required this.swell1,
    required this.swell2,
    required this.glow,
  });

  /// Height currently hidden by the keyboard.
  final double bottomInset;

  /// Alphas, which differ per brightness — the same values that read as a
  /// gentle swell on ink are invisible on a near-white surface.
  final double swell1;
  final double swell2;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height + bottomInset;

    // Soft azure glow top-right.
    canvas.drawCircle(
      Offset(w * .9, h * .08),
      w * .55,
      Paint()
        ..shader = RadialGradient(colors: [
          FlowColors.azure.withValues(alpha: glow),
          FlowColors.azure.withValues(alpha: 0),
        ]).createShader(
            Rect.fromCircle(center: Offset(w * .9, h * .08), radius: w * .55)),
    );

    // Two crossing swells near the bottom.
    final path1 = Path()
      ..moveTo(0, h * .78)
      ..cubicTo(w * .25, h * .72, w * .45, h * .86, w * .7, h * .8)
      ..cubicTo(w * .85, h * .76, w * .95, h * .8, w, h * .77)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
        path1, Paint()..color = FlowColors.azure.withValues(alpha: swell1));

    final path2 = Path()
      ..moveTo(0, h * .87)
      ..cubicTo(w * .3, h * .93, w * .55, h * .82, w * .8, h * .9)
      ..cubicTo(w * .9, h * .93, w * .97, h * .9, w, h * .91)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
        path2, Paint()..color = FlowColors.azure.withValues(alpha: swell2));
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.bottomInset != bottomInset ||
      oldDelegate.swell1 != swell1 ||
      oldDelegate.swell2 != swell2 ||
      oldDelegate.glow != glow;
}
