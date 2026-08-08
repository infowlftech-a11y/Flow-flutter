import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'buttons.dart';
import 'flow_image.dart';

/// The paged-content indicator, in one place.
///
/// Two copies existed — the trainer profile's photo strip and the command
/// centre's tour dialog — agreeing on every metric (200ms, 6 px tall, 18 px
/// when active, 3 px apart) and differing only in colour, because one sits on
/// photography and the other on a themed surface. That is what [activeColor]
/// and [inactiveColor] are for; the motion is not a per-screen decision.
class PageDots extends StatelessWidget {
  const PageDots({
    super.key,
    required this.count,
    required this.index,
    this.activeColor,
    this.inactiveColor,
  });

  final int count;
  final int index;

  /// Defaults to the brand azure. Pass white when the dots sit on an image.
  final Color? activeColor;
  final Color? inactiveColor;

  @override
  Widget build(BuildContext context) {
    final on = activeColor ?? context.tones.azureBrand;
    final off = inactiveColor ?? context.tones.line;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            curve: FlowMotion.curve,
            duration: FlowMotion.base,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index ? on : off,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

/// A picked photo with a remove affordance, and optionally a NEW badge.
///
/// Three copies: the profile editor's gallery (which had the badge and the
/// screen-reader label), the trainer-onboarding gallery and the appeal sheet's
/// evidence row (which had neither, and used a 4 px tap-target inset against
/// the other two's 5 px). The [Semantics] wrapper is now unconditional — a
/// remove button that only announces itself on one of three screens is a bug,
/// not a variant.
class ThumbTile extends StatelessWidget {
  const ThumbTile({
    super.key,
    required this.child,
    required this.onRemove,
    this.isNew = false,
  });

  /// A locally-picked file, clipped and squared — the shape three of the four
  /// call sites were spelling out by hand.
  ThumbTile.file(
    String path, {
    super.key,
    required this.onRemove,
    this.isNew = false,
    double size = 84,
  }) : child = ClipRRect(
          borderRadius: FlowRadii.chip,
          child: Image.file(
            File(path),
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );

  final Widget child;

  /// Null disables the button — used while an upload is in flight.
  final VoidCallback? onRemove;

  /// Marks a pick that has not been uploaded yet.
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isNew)
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: context.tones.azureBrand,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('NEW',
                  style: inter(10, 800, color: Colors.white, spacing: .8)),
            ),
          ),
        Positioned(
          right: 0,
          top: 0,
          child: Semantics(
            button: true,
            label: 'Remove photo',
            // The visible puck stays small — it sits on a photo and a bigger
            // one would cover the thing being judged. What grows is the hit
            // box: this was a 24x24 target, which is half the 48 the platform
            // asks for. The refactor gave this button its screen-reader label
            // and left it unhittable, which is the sort of thing measuring
            // catches and reading does not.
            child: SizedBox(
              width: 48,
              height: 48,
              child: GestureDetector(
                onTap: onRemove,
                // Transparent, not null: an empty area of a GestureDetector
                // is not hit-testable otherwise, so the padding around the
                // puck would swallow nothing and the target would still be 24.
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                          color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pinch-to-zoom image viewer, pushed on the root navigator.
///
/// Stateful purely to own the [PageController]. Built in `build()` it leaked
/// one controller (with its ScrollPosition and ticker) per open, and worse:
/// any rebuild of the route — rotation, a keyboard or inset change, a theme
/// switch — constructed a *second* controller for the PageView to attach to,
/// silently abandoning the first mid-gesture and losing the current page.
///
/// The admin console's certificate viewer was a separate single-image copy
/// that used a tonal [IconButton] where this one uses a [ScrimIconButton], so
/// the same "close this photo" gesture looked different depending on which
/// photo you had opened.
class FullScreenImageViewer extends StatefulWidget {
  const FullScreenImageViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
    this.maxScale = 5,
  });

  final List<String?> images;
  final int initialIndex;
  final double maxScale;

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  late final _page = PageController(initialPage: widget.initialIndex);

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _page,
            itemCount: widget.images.length,
            itemBuilder: (_, i) => InteractiveViewer(
              maxScale: widget.maxScale,
              child: Center(
                child: FlowImage(url: widget.images[i], fit: BoxFit.contain),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ScrimIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Close',
                onTap: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens [FullScreenImageViewer] over the current screen.
///
/// `opaque: false` with a black barrier so the photo fades in over the page
/// rather than replacing it.
void showFullScreenImages(
  BuildContext context,
  List<String?> images, {
  int initialIndex = 0,
  double maxScale = 5,
}) {
  if (images.isEmpty) return;
  Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black,
    pageBuilder: (_, _, _) => FullScreenImageViewer(
      images: images,
      initialIndex: initialIndex,
      maxScale: maxScale,
    ),
  ));
}
