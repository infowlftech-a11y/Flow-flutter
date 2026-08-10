import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/motion.dart';
import '../theme/app_theme.dart';

/// Decodes at display size, not source size.
///
/// `Image.network` with no `cacheWidth`/`cacheHeight` decodes the full source
/// into memory: uploads are capped at 1600px on the long edge (§12.1), so a
/// 44px avatar was costing ~10MB of raw RGBA and a grid of them ran the raster
/// cache dry, which is where the scroll jank and the low-memory kills came
/// from. Decoding to the box costs the square of the ratio — a 44px avatar is
/// ~1300x cheaper.
///
/// Only one axis is ever passed to the decoder. Supplying both makes the codec
/// scale to exactly those numbers and quietly distorts the aspect ratio; one
/// axis lets the other follow proportionally.
int? _decodeHint(double? width, double? height, double dpr) {
  final w = (width != null && width.isFinite) ? width : null;
  final h = (height != null && height.isFinite) ? height : null;
  final longest = switch ((w, h)) {
    (null, null) => null,
    (final a?, null) => a,
    (null, final b?) => b,
    (final a?, final b?) => a > b ? a : b,
  };
  if (longest == null || longest <= 0) return null;
  return (longest * dpr).round();
}

/// Whether the hint above describes the width or the height of the box.
bool _hintIsWidth(double? width, double? height) {
  if (width == null || !width.isFinite) return false;
  if (height == null || !height.isFinite) return true;
  return width >= height;
}

/// Network image that can never look broken: while loading it shimmers a
/// brand-tinted surface, and a dead URL (several exist in the live DB) renders
/// a tinted placeholder icon — never the engine's broken-image glyph.
class FlowImage extends StatelessWidget {
  const FlowImage({
    super.key,
    this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
    this.placeholderIcon = Symbols.kitesurfing_rounded,
  });

  final String? url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final fallback = Container(
      width: width,
      height: height,
      color: tones.cardHigh,
      alignment: Alignment.center,
      child: Icon(placeholderIcon,
          size: 34, color: tones.azureBrand.withValues(alpha: .45)),
    );

    final u = url;
    if (u == null || u.isEmpty) return _rounded(fallback);

    // Most call sites size the image by its box rather than by an explicit
    // width/height, so the constraints are the only thing that knows how many
    // pixels will actually be shown. Unbounded axes fall through to null and
    // simply skip the hint on that axis.
    return _rounded(LayoutBuilder(
      builder: (context, constraints) {
        final boxW = width ??
            (constraints.hasBoundedWidth ? constraints.maxWidth : null);
        final boxH = height ??
            (constraints.hasBoundedHeight ? constraints.maxHeight : null);
        final hint = _decodeHint(boxW, boxH, MediaQuery.devicePixelRatioOf(context));
        final byWidth = _hintIsWidth(boxW, boxH);

        return Image.network(
          u,
          fit: fit,
          width: width,
          height: height,
          cacheWidth: byWidth ? hint : null,
          cacheHeight: byWidth ? null : hint,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => fallback,
          frameBuilder: (context, image, frame, wasSync) {
            if (wasSync) return image;
            // Cross-fade from the placeholder rather than popping in. The
            // previous version animated a constant opacity of 1, which is to
            // say it did not animate at all.
            return AnimatedSwitcher(
              duration: FlowMotion.base,
              switchInCurve: FlowMotion.curve,
              switchOutCurve: FlowMotion.curve,
              child: frame == null ? fallback : image,
            );
          },
        );
      },
    ));
  }

  Widget _rounded(Widget child) => borderRadius == null
      ? child
      : ClipRRect(borderRadius: borderRadius!, child: child);
}

/// Avatar with initial fallback — first initial of the name, `?` when empty.
class FlowAvatar extends StatelessWidget {
  const FlowAvatar({super.key, this.url, this.name, this.size = 44});

  final String? url;
  final String? name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final initial =
        (name ?? '').trim().isEmpty ? '?' : name!.trim()[0].toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      color: tones.azureBrand.withValues(alpha: .16),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: Theme.of(context).textTheme.titleLarge!.copyWith(
              color: tones.azureBrand,
              fontSize: size * .42,
            ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .32),
      child: (url == null || url!.isEmpty)
          ? fallback
          : Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              // Avatars are the worst offenders: 44px on screen, 1600px in
              // storage. The crop step already makes them square, so scaling
              // by width keeps the aspect.
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}
