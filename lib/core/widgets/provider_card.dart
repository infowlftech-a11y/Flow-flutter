import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'flow_image.dart';

/// A provider in a browsable list: photo left, identity right, price trailing.
///
/// Horizontal rather than a grid tile, which is the shape the redesign asks
/// for and the better one for this content: a grid forces the name to wrap or
/// ellipse at two words, and the four facts a rider actually compares —
/// rating, spot, price, and whether they like the face — read faster stacked
/// against a fixed-width photo than tiled.
///
/// The price is the only right-aligned element on purpose. It is the field
/// people scan down the list for, and a ragged left edge would defeat that.
class ProviderCard extends StatelessWidget {
  const ProviderCard({
    super.key,
    required this.name,
    required this.photoUrl,
    required this.onTap,
    this.rating,
    this.reviewCount,
    this.location,
    this.priceLabel,
    this.priceUnit = 'hour',
    this.badge,
    this.trailing,
  });

  final String name;
  final String? photoUrl;
  final VoidCallback onTap;

  /// Null hides the rating row entirely rather than showing zero stars — a
  /// provider with no reviews yet has no rating, and painting an empty row of
  /// outlines reads as "rated badly".
  final double? rating;
  final int? reviewCount;

  final String? location;

  /// Pre-formatted, because the caller owns the currency (§3.7).
  final String? priceLabel;

  /// What the price buys. `hour` for a lesson, `day` for a safari — it was
  /// hardcoded to `hour`, which quietly mislabelled every multi-day trip in
  /// the catalogue by a factor of about eight.
  final String priceUnit;

  /// Small marker over the photo — the verified tick, a "Station" pill.
  final Widget? badge;

  /// Replaces the price column. Used where the card sits in a picker rather
  /// than a catalogue and money is not the point.
  final Widget? trailing;

  static const _photo = 96.0;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final scheme = context.scheme;

    return Material(
      color: tones.card,
      borderRadius: FlowRadii.card,
      child: InkWell(
        borderRadius: FlowRadii.card,
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: FlowRadii.card,
            border: Border.all(color: tones.line),
          ),
          child: ConstrainedBox(
            // The photo sets the height, and it is comfortably over the 48
            // minimum, so the row needs no separate tap-target padding.
            constraints: const BoxConstraints(minHeight: _photo),
            child: Row(
              // Centre, not stretch. A stretched child cannot report an
              // intrinsic height, so the row threw outright the moment it was
              // laid out anywhere height-unbounded — a list, which is the only
              // place this card is ever used. The photo is a fixed square and
              // the card clips it, which gets the same bleeding edge without
              // asking the row to measure something it cannot.
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _Photo(url: photoUrl, badge: badge),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: display(17, 700,
                              color: scheme.onSurface, spacing: -.2),
                        ),
                        if (rating != null) ...[
                          const SizedBox(height: 6),
                          _Rating(value: rating!, count: reviewCount),
                        ],
                        if (location != null || priceLabel != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (location != null)
                                // Three fifths of the row to the price, two to
                                // the place. An even loose flex — which is what
                                // `spaceBetween` gave both sides — splits the
                                // row in half however little either needs, and
                                // half a 360px card is narrower than `EGP 95 /
                                // hour`, so the default phone read `EGP 95 /
                                // h…`. Price is the number the choice turns on;
                                // a shortened place name still reads.
                                Expanded(
                                  flex: 2,
                                  child: Row(
                                    children: [
                                      Icon(Symbols.place_rounded,
                                          size: 13, color: tones.textFaint),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          location!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: inter(13, 500,
                                              color: scheme.onSurfaceVariant),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                const Spacer(flex: 2),
                              if (priceLabel != null) ...[
                                const SizedBox(width: 10),
                                // Scaled down rather than ellipsized. A fixed
                                // pixel cap cannot work here — 160px is wider
                                // than the whole row on a 320px card at 1.3x,
                                // so the price simply overflowed it. Shrinking
                                // the type keeps the figure and the unit; an
                                // ellipsis would drop whichever mattered.
                                Expanded(
                                  flex: 3,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Text.rich(
                                      TextSpan(children: [
                                        TextSpan(
                                          text: priceLabel,
                                          style: interNum(16, 760,
                                              color: scheme.onSurface),
                                        ),
                                        TextSpan(
                                          text: ' / $priceUnit',
                                          style: inter(11.5, 500,
                                              color: tones.textFaint),
                                        ),
                                      ]),
                                      textAlign: TextAlign.right,
                                      maxLines: 1,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (trailing != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Center(child: trailing),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.url, this.badge});

  final String? url;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    // A fixed square. Only the leading corners are rounded: the photo butts
    // against the card's content, so rounding its trailing edge would cut a
    // notch out of the row.
    const radius = BorderRadius.only(
      topLeft: Radius.circular(FlowRadius.card),
      bottomLeft: Radius.circular(FlowRadius.card),
    );
    return SizedBox(
      width: ProviderCard._photo,
      height: ProviderCard._photo,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: radius,
              child: FlowImage(
                url: url,
                width: ProviderCard._photo,
                height: ProviderCard._photo,
                fit: BoxFit.cover,
              ),
            ),
          ),
          if (badge != null)
            Positioned(right: 6, bottom: 6, child: badge!),
        ],
      ),
    );
  }
}

class _Rating extends StatelessWidget {
  const _Rating({required this.value, this.count});

  final double value;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Semantics(
      label: count == null
          ? 'Rated ${value.toStringAsFixed(1)} out of 5'
          : 'Rated ${value.toStringAsFixed(1)} out of 5, $count reviews',
      excludeSemantics: true,
      child: Row(
        children: [
          Icon(Symbols.star_rounded, size: 15, fill: 1, color: tones.azureBrand),
          const SizedBox(width: 4),
          Text(value.toStringAsFixed(1),
              style: interNum(13.5, 700, color: tones.azureBrand)),
          if (count != null) ...[
            const SizedBox(width: 4),
            // The review count is the one part of this row that may be
            // dropped: the rating itself is the fact, the count is the
            // qualifier. Without this the row is entirely rigid and pushes
            // past a narrow card rather than shortening.
            Flexible(
              child: Text(
                '($count)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: inter(12.5, 500, color: tones.textFaint),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
