// Builds the adaptive-icon foreground layer from assets/brand/icon.png.
//
// Run:  dart run tool/make_icon_foreground.dart
//
// The source is a finished *legacy* icon: its own rounded square, its own
// border ring, artwork running to 97% of the canvas width. An adaptive icon
// is two layers the launcher masks itself, and only the centre 66 of 108dp
// is guaranteed visible — so the square, the ring and the edge-to-edge scale
// all have to go, or the launcher clips the swoosh and stamps a sticker edge
// around it.
//
// Measured from the source (tool/icon_probe2.dart):
//   background field   lum ~10
//   border ring        lum 58-61, within 8px of the edge
//   artwork            lum 115+
//
// Two things remove the ring. The luminance ramp handles its straight runs,
// and a rounded-rect mask handles its corner arcs, which no square inset can
// reach because the ring turns diagonally there.
//
// Dropping the background by luminance is safe here for one specific reason:
// the adaptive background layer is the same navy, so every pixel this makes
// transparent reveals an identical colour behind it. Alpha is ramped rather
// than thresholded so antialiasing survives.
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart';

const lumLow = 68.0; // below: background. Ring at 58-61 falls here.
const lumHigh = 104.0; // above: artwork. Swoosh measures 115+.

/// The source's own rounded-square geometry, in source pixels.
const maskInset = 22.0;
const maskRadius = 104.0;

/// Adaptive icons are 108dp; the launcher guarantees only the centre 66dp.
const canvas = 432; // 108dp at xxxhdpi

/// flutter_launcher_icons wraps the foreground in `android:inset="16%"`, so
/// the drawable ends up occupying the middle 68% of the layer. Filling that
/// much of *this* canvas therefore lands the artwork at 0.9 x 0.68 = 61% of
/// 108dp — exactly the 66dp the launcher guarantees.
///
/// Sizing for the inset rather than removing it from the generated XML is
/// deliberate: the XML is regenerated every run, so an edit there would be
/// silently undone the next time anyone touches the icon.
const insetSurvives = 0.68;
const safeFraction = (66 / 108) / insetSurvives;

/// Signed test for a point inside a rounded rectangle.
bool insideRoundedRect(double x, double y, double w, double h, double r) {
  final cx = math.max(math.max(0.0, x - (w - r)), r - x);
  final cy = math.max(math.max(0.0, y - (h - r)), r - y);
  if (cx <= 0 || cy <= 0) return x >= 0 && y >= 0 && x <= w && y <= h;
  return cx * cx + cy * cy <= r * r;
}

void main() {
  final src = decodePng(File('assets/brand/icon.png').readAsBytesSync())!;
  final w = src.width.toDouble(), h = src.height.toDouble();

  final cut = Image(width: src.width, height: src.height, numChannels: 4);
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final inner = insideRoundedRect(x - maskInset, y - maskInset,
          w - maskInset * 2, h - maskInset * 2, maskRadius);
      if (!inner) continue; // outside the ring's path — drop it entirely

      final p = src.getPixel(x, y);
      final lum = 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b;
      final t = ((lum - lumLow) / (lumHigh - lumLow)).clamp(0.0, 1.0);
      cut.setPixelRgba(
          x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), (t * 255).round());
    }
  }

  // Bounding box of what survived, so the artwork is centred on its own ink
  // rather than on the source canvas.
  int minX = cut.width, minY = cut.height, maxX = 0, maxY = 0;
  for (var y = 0; y < cut.height; y++) {
    for (var x = 0; x < cut.width; x++) {
      if (cut.getPixel(x, y).a > 128) {
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
      }
    }
  }
  final bw = maxX - minX + 1, bh = maxY - minY + 1;
  stdout.writeln('artwork after cut: ${bw}x$bh at ($minX,$minY)');

  final art = copyCrop(cut, x: minX, y: minY, width: bw, height: bh);

  // Scale the longest side into the safe zone and centre it.
  final target = (canvas * safeFraction).round();
  final scale = target / math.max(bw, bh);
  final sw = (bw * scale).round(), sh = (bh * scale).round();
  final scaled = copyResize(art,
      width: sw, height: sh, interpolation: Interpolation.cubic);

  final out = Image(width: canvas, height: canvas, numChannels: 4);
  compositeImage(out, scaled,
      dstX: ((canvas - sw) / 2).round(), dstY: ((canvas - sh) / 2).round());

  File('assets/brand/icon_foreground.png').writeAsBytesSync(encodePng(out));
  stdout.writeln('wrote assets/brand/icon_foreground.png '
      '($canvas x $canvas, artwork ${sw}x$sh = '
      '${(math.max(sw, sh) / canvas * 100).toStringAsFixed(0)}% of canvas)');

  writeLegacy(src);
}

/// The legacy mipmap: the design as drawn, but with the corners outside its
/// rounded square made transparent.
///
/// The source is opaque #000000 out there, which Android 8+ never shows —
/// the adaptive layers replace it — but older launchers and some notification
/// surfaces use this file directly, and hard black corners around a
/// blue-bordered square read as a mistake.
///
/// The corners are pure black and the design's own field is navy (#010d29,
/// channel sum 55), so the two separate cleanly on channel sum alone. The
/// ramp keeps the rounded edge antialiased instead of stair-stepping it.
void writeLegacy(Image src) {
  const sumLow = 6.0, sumHigh = 30.0;
  final out = Image(width: src.width, height: src.height, numChannels: 4);
  var cleared = 0;
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      final sum = p.r + p.g + p.b;
      final t = ((sum - sumLow) / (sumHigh - sumLow)).clamp(0.0, 1.0);
      if (t < 1) cleared++;
      out.setPixelRgba(
          x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), (t * 255).round());
    }
  }
  File('assets/brand/icon_legacy.png').writeAsBytesSync(encodePng(out));
  stdout.writeln('wrote assets/brand/icon_legacy.png '
      '($cleared corner px made transparent)');
}
