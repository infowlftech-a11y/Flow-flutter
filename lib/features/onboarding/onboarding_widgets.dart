import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../services/image_service.dart';

/// Circular avatar picker: shows the picked file, an existing URL, or a
/// placeholder — tap anywhere to (re)pick.
class AvatarPicker extends StatelessWidget {
  const AvatarPicker({
    super.key,
    required this.file,
    required this.onPicked,
    this.existingUrl,
    this.size = 104,
    this.enabled = true,
  });

  final XFile? file;
  final ValueChanged<XFile> onPicked;
  final String? existingUrl;
  final double size;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    Widget content;
    if (file != null) {
      content = Image.file(File(file!.path),
          width: size, height: size, fit: BoxFit.cover);
    } else if (existingUrl != null && existingUrl!.isNotEmpty) {
      content = Image.network(existingUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _placeholder(tones));
    } else {
      content = _placeholder(tones);
    }

    return Semantics(
      button: true,
      label: 'Profile photo, tap to change',
      child: GestureDetector(
        onTap: enabled
            ? () async {
                final picked = await ImageService.pickWithSheet(context);
                if (picked != null) onPicked(picked);
              }
            : null,
        child: Stack(
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: tones.azureBrand.withValues(alpha: .5), width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: content,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: tones.azureBrand,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 2),
                ),
                child: const Icon(Icons.photo_camera_rounded,
                    size: 15, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(dynamic tones) => Container(
        width: size,
        height: size,
        color: (tones.azureBrand as Color).withValues(alpha: .12),
        child: Icon(Icons.add_a_photo_outlined,
            color: tones.azureBrand as Color, size: size * .3),
      );
}


/// Labeled form group with an optional "required" marker + inline error.
class FormGroup extends StatelessWidget {
  const FormGroup({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
    this.errorText,
  });

  final String label;
  final Widget child;
  final bool required;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label.toUpperCase(), style: microLabel(tones.textFaint)),
            if (required)
              Text(' *', style: microLabel(tones.azureBrand)),
          ],
        ),
        const SizedBox(height: 8),
        child,
        AnimatedSize(
          duration: FlowMotion.base,
          alignment: Alignment.topLeft,
          child: errorText == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(errorText!,
                      style: inter(12.5, 560, color: tones.danger)),
                ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
