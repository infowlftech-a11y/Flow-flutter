// Renders what the launcher will actually show, so the icon is checked
// rather than assumed: background colour + foreground inset 16%, then the
// two masks Android applies (full circle is the harshest common one).
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart';

const size = 300;

bool insideRoundedRect(double x, double y, double w, double h, double r) {
  final cx = math.max(math.max(0.0, x - (w - r)), r - x);
  final cy = math.max(math.max(0.0, y - (h - r)), r - y);
  if (cx <= 0 || cy <= 0) return x >= 0 && y >= 0 && x <= w && y <= h;
  return cx * cx + cy * cy <= r * r;
}

Image composeAdaptive() {
  final fg = decodePng(
      File('android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png')
          .readAsBytesSync())!;
  final layer = Image(width: size, height: size, numChannels: 4);
  fill(layer, color: ColorRgba8(0x00, 0x0C, 0x25, 255));
  // android:inset="16%" -> the drawable occupies the middle 68%.
  final d = (size * 0.68).round();
  final scaled = copyResize(fg, width: d, height: d,
      interpolation: Interpolation.cubic);
  compositeImage(layer, scaled,
      dstX: ((size - d) / 2).round(), dstY: ((size - d) / 2).round());
  return layer;
}

Image mask(Image src, bool Function(int, int) keep) {
  final out = Image(width: size, height: size, numChannels: 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      if (!keep(x, y)) continue;
      final p = src.getPixel(x, y);
      out.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), 255);
    }
  }
  return out;
}

void main() {
  final adaptive = composeAdaptive();
  final c = size / 2.0, r = size / 2.0;

  final circle = mask(adaptive, (x, y) {
    final dx = x - c + 0.5, dy = y - c + 0.5;
    return dx * dx + dy * dy <= r * r;
  });
  final squircle = mask(adaptive,
      (x, y) => insideRoundedRect(x.toDouble(), y.toDouble(),
          size.toDouble(), size.toDouble(), size * 0.28));

  final legacy = copyResize(
      decodePng(File('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png')
          .readAsBytesSync())!,
      width: size, height: size, interpolation: Interpolation.cubic);

  // Strip: circle | squircle | legacy, on a mid grey so edges are visible.
  final sheet = Image(width: size * 3 + 40, height: size + 20, numChannels: 4);
  fill(sheet, color: ColorRgba8(0x9a, 0x9a, 0x9a, 255));
  compositeImage(sheet, circle, dstX: 5, dstY: 10);
  compositeImage(sheet, squircle, dstX: size + 20, dstY: 10);
  compositeImage(sheet, legacy, dstX: size * 2 + 35, dstY: 10);
  File('tool/icon_preview.png').writeAsBytesSync(encodePng(sheet));
  stdout.writeln('wrote tool/icon_preview.png — circle | squircle | legacy');
}
