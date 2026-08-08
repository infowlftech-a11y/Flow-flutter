// Images must be decoded at display size, not at source size.
//
// Uploads are capped at 1600px on the long edge, so an undecorated
// `Image.network` put ~10MB of raw RGBA behind every 44px avatar. That is the
// difference between a list that scrolls and one that thrashes the raster
// cache, so it is worth a test rather than a comment.
//
// `cacheWidth`/`cacheHeight` surface as a ResizeImage wrapper around the
// underlying provider, which is what these assertions read.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/theme/app_theme.dart';
import 'package:flow/core/widgets/flow_image.dart';

const _url = 'https://example.test/photo.jpg';

Future<ResizeImage> _resizeImageOf(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    theme: FlowTheme.dark(),
    home: Scaffold(body: Center(child: child)),
  ));
  final image = tester.widget<Image>(find.byType(Image));
  expect(image.image, isA<ResizeImage>(),
      reason: 'the decoder was handed the full-size source');
  return image.image as ResizeImage;
}

void main() {
  testWidgets('avatars decode at their on-screen size', (tester) async {
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final resized =
        await _resizeImageOf(tester, const FlowAvatar(url: _url, size: 44));

    expect(resized.width, 132); // 44 logical x 3
    // Only one axis, or the codec scales to both numbers and distorts.
    expect(resized.height, isNull);
  });

  testWidgets('a landscape box constrains the decode by width', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final resized = await _resizeImageOf(
      tester,
      const SizedBox(width: 200, height: 100, child: FlowImage(url: _url)),
    );

    expect(resized.width, 400);
    expect(resized.height, isNull);
  });

  testWidgets('a portrait box constrains the decode by height', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final resized = await _resizeImageOf(
      tester,
      const SizedBox(width: 100, height: 200, child: FlowImage(url: _url)),
    );

    expect(resized.height, 400);
    expect(resized.width, isNull);
  });

  testWidgets('an unbounded box still renders rather than guessing',
      (tester) async {
    addTearDown(tester.view.reset);

    // A Row gives its children unbounded width; the hint has to fall back to
    // the bounded axis instead of throwing or decoding at infinity.
    await tester.pumpWidget(MaterialApp(
      theme: FlowTheme.dark(),
      home: Scaffold(
        body: Row(
          children: const [
            SizedBox(height: 60, child: FlowImage(url: _url)),
          ],
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
  });
}
