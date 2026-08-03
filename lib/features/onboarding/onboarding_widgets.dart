import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/misc.dart';
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

/// Multi-select chips over the suggested list, plus "add your own".
class LanguagePicker extends StatefulWidget {
  const LanguagePicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.errorText,
  });

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final String? errorText;

  @override
  State<LanguagePicker> createState() => _LanguagePickerState();
}

class _LanguagePickerState extends State<LanguagePicker> {
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _toggle(String lang) {
    Haptics.select();
    final next = [...widget.selected];
    next.contains(lang) ? next.remove(lang) : next.add(lang);
    widget.onChanged(next);
  }

  void _addCustom() {
    final lang = _custom.text.trim();
    if (lang.isEmpty) return;
    if (!widget.selected.contains(lang)) {
      widget.onChanged([...widget.selected, lang]);
    }
    _custom.clear();
  }

  @override
  Widget build(BuildContext context) {
    final custom = [
      for (final l in widget.selected)
        if (!FlowConst.languages.contains(l)) l,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final lang in [...FlowConst.languages, ...custom])
              FlowChoiceChip(
                label: lang,
                selected: widget.selected.contains(lang),
                onTap: () => _toggle(lang),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _custom,
                decoration:
                    const InputDecoration(hintText: 'Add another language…'),
                textCapitalization: TextCapitalization.words,
                onSubmitted: (_) => _addCustom(),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.outlined(
              onPressed: _addCustom,
              tooltip: 'Add language',
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        // Inline error under the chips (§9.2).
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: widget.errorText == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(widget.errorText!,
                      style: inter(12.5, 560, color: context.tones.danger)),
                ),
        ),
      ],
    );
  }
}

/// Single-select chips for the closed spot / level lists.
class ChipSelect extends StatelessWidget {
  const ChipSelect({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          FlowChoiceChip(
            label: o,
            selected: value == o,
            onTap: () {
              Haptics.select();
              onChanged(value == o ? null : o);
            },
          ),
      ],
    );
  }
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
        const SizedBox(height: 9),
        child,
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topLeft,
          child: errorText == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(errorText!,
                      style: inter(12.5, 560, color: tones.danger)),
                ),
        ),
        const SizedBox(height: 22),
      ],
    );
  }
}
