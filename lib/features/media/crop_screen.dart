import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../core/constants.dart';
import '../../core/theme/palette.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/feedback.dart';

/// Crop shapes the app asks for.
enum CropShape {
  /// Avatars — masked to a circle, always 1:1.
  circle,

  /// Gallery and certificate shots — 4:3 landscape.
  rect,
}

/// A self-contained cropper.
///
/// Written rather than pulled in as a package so the crop step looks like the
/// rest of FLOW (ink navy, azure rim, Space Grotesk labels) instead of dropping the
/// user into a third-party activity mid-onboarding — and so the Android build
/// needs no extra native activity registered.
///
/// The gesture model is "move the photo under a fixed hole": the mask never
/// moves, which keeps the output aspect exact and means there are no crop
/// handles to fight on a phone.
class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.source, required this.shape});

  final XFile source;
  final CropShape shape;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  ui.Image? _image;
  Object? _loadError;
  bool _saving = false;

  /// Scale and translation of the image relative to the crop window, in
  /// crop-window pixels.
  double _scale = 1;
  Offset _offset = Offset.zero;

  double _startScale = 1;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  /// Size of the crop hole, set during layout.
  Size _window = Size.zero;

  double get _aspect => widget.shape == CropShape.circle ? 1 : 4 / 3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.source.path).readAsBytes();
      final decoded = await decodeImageFromList(bytes);
      if (!mounted) {
        decoded.dispose();
        return;
      }
      setState(() => _image = decoded);
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  /// The smallest scale that still covers the crop window — panning can never
  /// expose a transparent gap, so the output is always fully populated.
  double get _minScale {
    final image = _image;
    if (image == null || _window.isEmpty) return 1;
    return math.max(
      _window.width / image.width,
      _window.height / image.height,
    );
  }

  /// Clamps translation so the image edges stay outside the window.
  Offset _clamp(Offset offset, double scale) {
    final image = _image;
    if (image == null || _window.isEmpty) return offset;
    final w = image.width * scale;
    final h = image.height * scale;
    final maxX = math.max(0.0, (w - _window.width) / 2);
    final maxY = math.max(0.0, (h - _window.height) / 2);
    return Offset(
      offset.dx.clamp(-maxX, maxX),
      offset.dy.clamp(-maxY, maxY),
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    _startScale = _scale;
    _startOffset = _offset;
    _startFocal = details.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final next = (_startScale * details.scale).clamp(_minScale, _minScale * 8);
    // Pan is tracked from the gesture's own start point so a pinch that also
    // drifts keeps the photo under the fingers.
    final panned = _startOffset + (details.focalPoint - _startFocal);
    // Keep the pinch focal point anchored while zooming.
    final zoomAdjusted = panned * (next / _startScale);
    setState(() {
      _scale = next;
      _offset = _clamp(zoomAdjusted, next);
    });
  }

  /// Renders the visible window at full source resolution (capped), so the
  /// export is not limited by how large the preview happened to be.
  Future<void> _save() async {
    final image = _image;
    if (image == null || _saving) return;
    setState(() => _saving = true);
    try {
      // Output resolution: what the user actually framed, capped to the same
      // long-edge limit the uploader uses so a crop cannot smuggle a larger
      // file past §12.1.
      final srcW = _window.width / _scale;
      final srcH = _window.height / _scale;
      final cap = FlowConst.uploadMaxDimension.toDouble();
      final outLong = math.min(math.max(srcW, srcH), cap);
      final outW = srcW >= srcH ? outLong : outLong * (srcW / srcH);
      final outH = srcH > srcW ? outLong : outLong * (srcH / srcW);

      // Source rect currently under the window.
      final centreX = image.width / 2 - _offset.dx / _scale;
      final centreY = image.height / 2 - _offset.dy / _scale;
      final src = Rect.fromLTWH(
        centreX - srcW / 2,
        centreY - srcH / 2,
        srcW,
        srcH,
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final dst = Rect.fromLTWH(0, 0, outW, outH);
      // Opaque backing: JPEG has no alpha, and a circular mask would
      // otherwise composite against black fringing at the rim.
      canvas.drawRect(dst, Paint()..color = Colors.white);
      canvas.drawImageRect(
          image, src, dst, Paint()..filterQuality = FilterQuality.high);
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(outW.round(), outH.round());
      picture.dispose();

      final data =
          await rendered.toByteData(format: ui.ImageByteFormat.png);
      rendered.dispose();
      if (data == null) throw StateError('Could not encode the crop.');

      // Written beside the picker's own temp file — that directory is already
      // app-owned and writable, which avoids taking a path_provider
      // dependency just to find a scratch folder.
      final dir = File(widget.source.path).parent.path;
      final out = File(
          '$dir/flow_crop_${DateTime.now().millisecondsSinceEpoch}.png');
      await out.writeAsBytes(data.buffer.asUint8List(), flush: true);

      if (mounted) {
        Haptics.medium();
        Navigator.pop(context, XFile(out.path));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text("Couldn't crop that image. Try another.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: context.scheme.onSurface,
        title: Text('Crop photo',
            style: display(17, 700, color: context.scheme.onSurface)),
        leading: IconButton(
          icon: const Icon(Symbols.close_rounded),
          tooltip: 'Cancel',
          onPressed: _saving ? null : () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _image == null || _saving ? null : _save,
            child: Text(
              _saving ? 'Saving…' : 'Done',
              style: inter(15, 700,
                  color: _image == null || _saving
                      ? context.scheme.onSurfaceVariant
                      : context.scheme.primary),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loadError != null
          // No longer `onScrim`: that variant paints light-on-dark for a
          // camera or photo backdrop, and this screen's chrome now follows
          // the theme like the rest of the app.
          ? const EmptyView(
              icon: Symbols.broken_image_rounded,
              title: 'Could not open that image',
              subtitle: 'Pick a different photo and try again.',
            )
          : _image == null
              ? Center(
                  child:
                      CircularProgressIndicator(color: context.scheme.primary))
              : _buildEditor(),
    );
  }

  Widget _buildEditor() {
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Fit the crop window inside the available area with a margin,
              // honouring the requested aspect.
              const margin = 24.0;
              final availW = constraints.maxWidth - margin * 2;
              final availH = constraints.maxHeight - margin * 2;
              var w = availW;
              var h = w / _aspect;
              if (h > availH) {
                h = availH;
                w = h * _aspect;
              }
              final window = Size(w, h);
              if (window != _window) {
                final first = _window.isEmpty;
                _window = window;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    // First layout starts at _minScale — the whole photo, as
                    // far out as the crop allows.
                    //
                    // This was `math.max(_scale, _minScale)` with `_scale`
                    // still at its initial 1, and 1 means *one image pixel per
                    // logical pixel*: a 3000px photo opened at roughly 8x in a
                    // 350px window, so every user landed on a close-up of the
                    // middle of their picture and had to pinch their way back
                    // out. The `max` was reading as "no smaller than the
                    // minimum" when what it needed to say was "exactly the
                    // minimum".
                    _scale = first ? _minScale : math.max(_scale, _minScale);
                    _offset = _clamp(_offset, _scale);
                  });
                });
              }

              return Center(
                child: GestureDetector(
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: ClipRect(
                      child: CustomPaint(
                        painter: _CropPainter(
                          image: _image!,
                          scale: _scale,
                          offset: _offset,
                          shape: widget.shape,
                        ),
                        size: window,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 26),
          child: Text(
            'Pinch to zoom · drag to reposition',
            textAlign: TextAlign.center,
            style: inter(14, 500, color: context.scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.image,
    required this.scale,
    required this.offset,
    required this.shape,
  });

  final ui.Image image;
  final double scale;
  final Offset offset;
  final CropShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final w = image.width * scale;
    final h = image.height * scale;
    final dst = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2) + offset,
      width: w,
      height: h,
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );

    // Rule-of-thirds guides, drawn over the photo so the framing is legible
    // against a busy beach shot.
    //
    // The 2px azure rim that used to sit on the crop boundary is gone. It
    // read as part of the result rather than as chrome — a blue edge around
    // the photo you had just cropped — and on the circle it traced exactly
    // the line the output is masked to, so the eye could not tell whether the
    // colour was in the picture or on top of it. A white hairline at low
    // opacity says "this is the edge of the frame" without claiming to be
    // part of the image.
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: .7);
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .6
      ..color = Colors.white.withValues(alpha: .35);

    final bounds = Offset.zero & size;
    if (shape == CropShape.circle) {
      final radius = math.min(size.width, size.height) / 2;
      final centre = Offset(size.width / 2, size.height / 2);
      // Dim everything outside the circle.
      canvas.drawPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(bounds),
          Path()..addOval(Rect.fromCircle(center: centre, radius: radius)),
        ),
        Paint()..color = FlowColors.ink.withValues(alpha: .66),
      );
      canvas.drawCircle(centre, radius, rim);
    } else {
      canvas.drawRect(bounds.deflate(1), rim);
      for (var i = 1; i < 3; i++) {
        final dx = size.width * i / 3;
        final dy = size.height * i / 3;
        canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), guide);
        canvas.drawLine(Offset(0, dy), Offset(size.width, dy), guide);
      }
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image ||
      old.scale != scale ||
      old.offset != offset ||
      old.shape != shape;
}

