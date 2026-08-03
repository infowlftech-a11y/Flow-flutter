import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/constants.dart';
import '../core/widgets/sheets.dart';

/// Picks images already downscaled for upload: max 1600px on the long edge,
/// JPEG quality 82 (§12.1) — the picker applies both natively.
class ImageService {
  ImageService._();
  static final _picker = ImagePicker();

  /// Shows the camera/gallery sheet, then picks. Null when dismissed.
  static Future<XFile?> pickWithSheet(BuildContext context) async {
    final source = await showImageSourceSheet(context);
    if (source == null) return null;
    return pick(source);
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
}
