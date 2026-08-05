import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/constants.dart';
import '../core/widgets/sheets.dart';
import '../features/media/crop_screen.dart';

/// Picks images already downscaled for upload: max 1600px on the long edge,
/// JPEG quality 82 (§12.1) — the picker applies both natively.
class ImageService {
  ImageService._();
  static final _picker = ImagePicker();

  /// Shows the camera/gallery sheet, picks, then hands the result to the
  /// cropper. Null when the user backs out of *either* step.
  ///
  /// Cropping sits here rather than in each caller so no screen can forget
  /// it: before this, whatever the gallery returned went straight to Storage,
  /// and a portrait photo was centre-cropped by `BoxFit.cover` at display
  /// time — the user never got to choose which part of it survived.
  /// [shape] of `null` skips the cropper entirely — used for evidence
  /// attachments (reports, appeals), where trimming the image is exactly what
  /// a moderator does not want.
  static Future<XFile?> pickWithSheet(
    BuildContext context, {
    CropShape? shape = CropShape.circle,
  }) async {
    final source = await showImageSourceSheet(context);
    if (source == null) return null;
    final picked = await pick(source);
    if (picked == null || shape == null || !context.mounted) return picked;
    return crop(context, picked, shape: shape);
  }

  /// Pushes the cropper. Returns null if the user cancels, so callers can
  /// treat "cancelled the crop" the same as "picked nothing".
  static Future<XFile?> crop(
    BuildContext context,
    XFile file, {
    CropShape shape = CropShape.circle,
  }) {
    return Navigator.of(context, rootNavigator: true).push<XFile>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CropScreen(source: file, shape: shape),
      ),
    );
  }

  static Future<XFile?> pick(ImageSource source) => _picker.pickImage(
        source: source,
        maxWidth: FlowConst.uploadMaxDimension.toDouble(),
        maxHeight: FlowConst.uploadMaxDimension.toDouble(),
        imageQuality: FlowConst.uploadJpegQuality,
      );

  static Future<List<XFile>> pickMulti() => _picker.pickMultiImage(
        maxWidth: FlowConst.uploadMaxDimension.toDouble(),
        maxHeight: FlowConst.uploadMaxDimension.toDouble(),
        imageQuality: FlowConst.uploadJpegQuality,
      );

  /// Multi-pick followed by a crop pass over each shot, in order.
  ///
  /// Skipping the crop on one image drops just that image rather than
  /// abandoning the whole batch — a long-press multi-select is easy to
  /// overshoot, and cancelling is the natural way to undo one.
  static Future<List<XFile>> pickMultiCropped(
    BuildContext context, {
    CropShape shape = CropShape.rect,
  }) async {
    final picked = await pickMulti();
    final out = <XFile>[];
    for (final file in picked) {
      if (!context.mounted) break;
      final cropped = await crop(context, file, shape: shape);
      if (cropped != null) out.add(cropped);
    }
    return out;
  }
}
