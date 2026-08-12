// Measures assets/brand/icon.png, so the constants in
// make_icon_foreground.dart are derived rather than guessed.
//
// Run:  dart run tool/icon_probe.dart
//
// Re-run this if the artwork is ever replaced: every threshold in the
// generator depends on the separation it reports below.
import 'dart:io';
import 'package:image/image.dart';

double lum(Pixel p) => 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b;

void main() {
  final img = decodePng(File('assets/brand/icon.png').readAsBytesSync())!;
  stdout.writeln('size ${img.width}x${img.height}  hasAlpha=${img.hasAlpha}');

  stdout.writeln('\n--- luminance across the centre row ---');
  stdout.writeln('the border ring and the artwork must not overlap here');
  for (final (from, to, label) in [
    (0, 40, 'left edge'),
    (430, 511, 'right edge'),
  ]) {
    stdout.write('$label: ');
    for (var x = from; x <= to; x += 4) {
      stdout.write('${lum(img.getPixel(x, 256)).round()} ');
    }
    stdout.writeln();
  }

  // Mean of the dark field — the adaptive background colour.
  var r = 0.0, g = 0.0, b = 0.0, n = 0;
  for (var y = 80; y < img.height - 80; y++) {
    for (var x = 80; x < img.width - 80; x++) {
      final p = img.getPixel(x, y);
      if (lum(p) < 40) { r += p.r; g += p.g; b += p.b; n++; }
    }
  }
  String h(double v) => (v / n).round().toRadixString(16).padLeft(2, '0');
  stdout.writeln('\nmean background over $n px: #${h(r)}${h(g)}${h(b)}'
      '   <- adaptive_icon_background in pubspec.yaml');

  // How far the artwork reaches, which is why it cannot be used unmodified.
  int minX = img.width, maxX = 0;
  for (var y = 0; y < img.height; y++) {
    for (var x = 0; x < img.width; x++) {
      if (lum(img.getPixel(x, y)) > 110) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
      }
    }
  }
  stdout.writeln('artwork spans x=$minX..$maxX = '
      '${((maxX - minX) / img.width * 100).toStringAsFixed(0)}% of the width');
}
