import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_theme.dart';

/// Standard FLOW modal sheet: drag handle, title row, safe-area padding and
/// keyboard avoidance. All of §4.5's sheet inventory goes through this.
Future<T?> showFlowSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext) builder,
  bool isDismissible = true,
  bool enableDrag = true,
  String? subtitle,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: sheetContext.tones.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(sheetContext).textTheme.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: Theme.of(sheetContext).textTheme.bodyMedium),
                ],
              ],
            ),
          ),
          Flexible(child: builder(sheetContext)),
        ],
      ),
    ),
  );
}

/// Destructive/irreversible confirmation dialog (§10.4).
///
/// The two choices are twins: same height, same width, same shape — an
/// outline against a fill. This used to be a bare `TextButton` beside a
/// `FilledButton`, which put the two answers to the same question in two
/// different visual languages, one of them barely reading as a button at
/// all. Labels scale down rather than wrap: these are verb phrases
/// ('Leave open', 'Close ticket'), and half a verb is worse than a small
/// one.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Keep',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;

      Widget label(String text) => FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(text, maxLines: 1),
          );

      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48)),
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: label(cancelLabel),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: destructive
                      ? FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          backgroundColor: scheme.error,
                          foregroundColor: scheme.onError)
                      : FilledButton.styleFrom(
                          minimumSize: const Size(0, 48)),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: label(confirmLabel),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Camera vs gallery chooser used by every image picker in the app.
Future<ImageSource?> showImageSourceSheet(BuildContext context) {
  return showFlowSheet<ImageSource>(
    context,
    title: 'Add a photo',
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Symbols.photo_camera_rounded),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Symbols.photo_library_rounded),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
}
