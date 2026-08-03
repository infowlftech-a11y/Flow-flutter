import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
    this.placeholderIcon = Icons.kitesurfing_rounded,
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
    Widget fallback = Container(
      width: width,
      height: height,
      color: tones.cardHigh,
      alignment: Alignment.center,
      child: Icon(placeholderIcon,
          size: 34, color: tones.azureBrand.withValues(alpha: .45)),
    );

    Widget child;
    final u = url;
    if (u == null || u.isEmpty) {
      child = fallback;
    } else {
      child = Image.network(
        u,
        fit: fit,
        width: width,
        height: height,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => fallback,
        frameBuilder: (context, image, frame, wasSync) {
          if (wasSync || frame != null) {
            return AnimatedOpacity(
              opacity: 1,
              duration: const Duration(milliseconds: 200),
              child: image,
            );
          }
          return fallback;
        },
      );
    }

    if (borderRadius != null) {
      child = ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return child;
  }
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
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}
