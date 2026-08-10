import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/motion.dart';

/// Cross-fades the *pixels* of a theme switch instead of animating the theme.
///
/// `MaterialApp`'s built-in transition lerps the full `ThemeData` every frame
/// and rebuilds every `Theme.of` dependent. With the shell's `IndexedStack`
/// keeping all branches alive, that is a re-derive of ~25 sub-themes plus a
/// relayout of every mounted screen, ~24 times over 200ms — which is the
/// stutter it was trying to hide. Here the old frame is captured once as an
/// image, the theme snaps underneath in a single rebuild (the app sets
/// `themeAnimationStyle: AnimationStyle.noAnimation`), and the screenshot
/// fades out on the compositor, which can animate one texture's opacity at
/// full frame rate no matter how heavy the tree is.
///
/// Sits *above* `MaterialApp`, so the capture covers everything including
/// dialogs and sheets. If the capture fails for any reason the switch still
/// happens — instantly, with no shroud — so the fade is pure garnish and can
/// never wedge the toggle.
class ThemeSwap extends StatefulWidget {
  const ThemeSwap({super.key, required this.child});

  final Widget child;

  /// The nearest [ThemeSwapState]. Walks the element tree, so it works from
  /// inside `MaterialApp`'s routes; call it from the control that triggers
  /// the theme change.
  static ThemeSwapState of(BuildContext context) {
    final state = context.findAncestorStateOfType<ThemeSwapState>();
    assert(state != null, 'ThemeSwap.of() called outside a ThemeSwap');
    return state!;
  }

  @override
  State<ThemeSwap> createState() => ThemeSwapState();
}

class ThemeSwapState extends State<ThemeSwap>
    with SingleTickerProviderStateMixin {
  final _boundaryKey = GlobalKey();
  ui.Image? _shot;

  // Eager, not a lazy `late final` initializer: build() only touches the
  // controller while a shroud is up, so a lazy one would be *created inside
  // dispose()* on any run where the toggle was never used — and creating a
  // ticker does ancestor lookups that are illegal during teardown.
  late final AnimationController _fade;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(vsync: this, duration: FlowMotion.base)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            _shot?.dispose();
            _shot = null;
          });
        }
      });
  }

  /// Captures the current frame, runs [swap] (the actual theme change), and
  /// fades the captured frame out over the new theme.
  ///
  /// [swap] always runs, in the same synchronous block that installs the
  /// shroud — the frame that first paints the new theme is the same frame
  /// the old pixels appear on top of, so no naked half-themed frame slips
  /// through.
  Future<void> run(VoidCallback swap) async {
    ui.Image? shot;
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (boundary is RenderRepaintBoundary &&
        boundary.hasSize &&
        !boundary.size.isEmpty) {
      try {
        shot = await boundary.toImage(
            pixelRatio: View.of(context).devicePixelRatio);
      } catch (e) {
        shot = null; // Capture is garnish; the swap must happen regardless.
        assert(() {
          debugPrint('ThemeSwap: capture failed, swapping without fade: $e');
          return true;
        }());
      }
    }
    if (!mounted) {
      shot?.dispose();
      swap();
      return;
    }
    setState(() {
      _shot?.dispose(); // A re-toggle mid-fade replaces the shroud.
      _shot = shot;
    });
    swap();
    if (shot != null) _fade.forward(from: 0);
  }

  @override
  void dispose() {
    _fade.dispose();
    _shot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Alignment.topLeft, not the directional default: there is no
    // Directionality above MaterialApp to resolve it against.
    return Stack(
      alignment: Alignment.topLeft,
      textDirection: TextDirection.ltr,
      children: [
        RepaintBoundary(key: _boundaryKey, child: widget.child),
        if (_shot != null)
          Positioned.fill(
            // Taps fall through to the live app beneath the fading shroud.
            child: IgnorePointer(
              child: FadeTransition(
                opacity: _fade.drive(
                  Tween(begin: 1.0, end: 0.0)
                      .chain(CurveTween(curve: FlowMotion.curve)),
                ),
                child: RawImage(
                  image: _shot,
                  fit: BoxFit.fill,
                  // The capture is 1:1 with the surface — no resampling.
                  filterQuality: FilterQuality.none,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
