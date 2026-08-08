import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/radii.dart';
import '../theme/app_theme.dart';
import '../theme/typography.dart';
import '../utils/haptics.dart';
import 'sheets.dart';

/// A tap-to-open field backed by [showFlowPicker].
///
/// Replaces the wrap-of-chips pattern the forms used to lay out inline. A
/// chip wall works for four rider levels and falls apart everywhere else: it
/// cannot show ~190 nationalities, it grows the form past what fits on a
/// phone, and it offers no way to search. This reads as one field regardless
/// of how long the underlying list is.
class FlowPickerField extends StatelessWidget {
  const FlowPickerField({
    super.key,
    required this.values,
    required this.onChanged,
    required this.options,
    required this.sheetTitle,
    this.hintText = 'Select',
    this.multiSelect = false,
    this.allowCustom = false,
    this.sheetSubtitle,
    this.enabled = true,
    this.hasError = false,
  });

  /// Current selection. Single-select fields simply hold 0 or 1 entries.
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final List<String> options;
  final String sheetTitle;
  final String? sheetSubtitle;
  final String hintText;
  final bool multiSelect;

  /// Whether a value outside [options] can be typed in and added.
  final bool allowCustom;
  final bool enabled;
  final bool hasError;

  Future<void> _open(BuildContext context) async {
    Haptics.select();
    final picked = await showFlowPicker(
      context,
      title: sheetTitle,
      subtitle: sheetSubtitle,
      options: options,
      selected: values,
      multiSelect: multiSelect,
      allowCustom: allowCustom,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final empty = values.isEmpty;
    final borderColor = hasError
        ? tones.danger
        : (empty ? tones.line : tones.azureBrand.withValues(alpha: .55));

    return Semantics(
      button: true,
      label: '$sheetTitle. ${empty ? 'None selected' : values.join(', ')}',
      child: InkWell(
        onTap: enabled ? () => _open(context) : null,
        borderRadius: FlowRadii.control,
        child: AnimatedContainer(
          curve: FlowMotion.curve,
          duration: FlowMotion.fast,
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            borderRadius: FlowRadii.control,
            border: Border.all(color: borderColor, width: 1.2),
            color: tones.card,
          ),
          child: Row(
            children: [
              Expanded(
                child: empty
                    ? Text(hintText,
                        style: inter(15, 460, color: tones.textFaint))
                    : (multiSelect
                        ? _Tags(values: values, onRemove: enabled ? _remove : null)
                        : Text(values.first,
                            style: inter(15, 560,
                                color:
                                    Theme.of(context).colorScheme.onSurface))),
              ),
              Icon(
                multiSelect ? Icons.add_rounded : Icons.expand_more_rounded,
                size: 20,
                color: enabled ? tones.textFaint : tones.line,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _remove(String value) =>
      onChanged([for (final v in values) if (v != value) v]);
}

/// Selected values as removable tags — the whole point of multi-select being
/// a field rather than a chip wall is that only the *chosen* items take space.
class _Tags extends StatelessWidget {
  const _Tags({required this.values, required this.onRemove});

  final List<String> values;
  final ValueChanged<String>? onRemove;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final v in values)
          Container(
            padding: const EdgeInsets.fromLTRB(11, 6, 5, 6),
            decoration: BoxDecoration(
              color: tones.azureBrand.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(v, style: inter(14, 600, color: tones.azureBrand)),
                const SizedBox(width: 3),
                InkWell(
                  onTap: onRemove == null ? null : () {
                    Haptics.select();
                    onRemove!(v);
                  },
                  borderRadius: FlowRadii.card,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close_rounded,
                        size: 14, color: tones.azureBrand),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Searchable single- or multi-select sheet. Returns null when dismissed —
/// distinct from an empty list, which means "cleared on purpose".
Future<List<String>?> showFlowPicker(
  BuildContext context, {
  required String title,
  required List<String> options,
  required List<String> selected,
  String? subtitle,
  bool multiSelect = false,
  bool allowCustom = false,
}) {
  return showFlowSheet<List<String>>(
    context,
    title: title,
    subtitle: subtitle,
    builder: (sheetContext) => _PickerBody(
      options: options,
      initial: selected,
      multiSelect: multiSelect,
      allowCustom: allowCustom,
    ),
  );
}

class _PickerBody extends StatefulWidget {
  const _PickerBody({
    required this.options,
    required this.initial,
    required this.multiSelect,
    required this.allowCustom,
  });

  final List<String> options;
  final List<String> initial;
  final bool multiSelect;
  final bool allowCustom;

  @override
  State<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends State<_PickerBody> {
  late final _search = TextEditingController();
  late List<String> _selected = [...widget.initial];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _query => _search.text.trim();

  /// Previously-added custom values are kept visible alongside the suggested
  /// ones, so a user can untick their own entry instead of only ever adding.
  List<String> get _all => [
        ...widget.options,
        for (final s in _selected)
          if (!widget.options.contains(s)) s,
      ];

  List<String> get _visible {
    if (_query.isEmpty) return _all;
    final q = _query.toLowerCase();
    final matches = [
      for (final o in _all)
        if (o.toLowerCase().contains(q)) o,
    ];
    // Prefix matches first: typing "ge" should surface German before Nigerien.
    matches.sort((a, b) {
      final ap = a.toLowerCase().startsWith(q) ? 0 : 1;
      final bp = b.toLowerCase().startsWith(q) ? 0 : 1;
      return ap != bp ? ap - bp : a.compareTo(b);
    });
    return matches;
  }

  /// Offered only when the typed text is not already an option — otherwise
  /// people end up with "german" sitting next to "German".
  bool get _canAddCustom =>
      widget.allowCustom &&
      _query.isNotEmpty &&
      !_all.any((o) => o.toLowerCase() == _query.toLowerCase());

  void _toggle(String value) {
    Haptics.select();
    if (!widget.multiSelect) {
      Navigator.pop(context, [value]);
      return;
    }
    setState(() {
      _selected.contains(value)
          ? _selected.remove(value)
          : _selected = [..._selected, value];
    });
  }

  void _addCustom() {
    final value = _query;
    if (value.isEmpty) return;
    Haptics.select();
    if (!widget.multiSelect) {
      Navigator.pop(context, [value]);
      return;
    }
    setState(() {
      _selected = [..._selected, value];
      _search.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final visible = _visible;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: TextField(
            controller: _search,
            autofocus: false,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _canAddCustom ? _addCustom() : null,
            decoration: InputDecoration(
              hintText: widget.allowCustom ? 'Search or add…' : 'Search…',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 17),
                      onPressed: () => setState(_search.clear),
                    ),
            ),
          ),
        ),
        Flexible(
          child: visible.isEmpty && !_canAddCustom
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                  child: Text('Nothing matches “$_query”.',
                      style: inter(14, 460, color: tones.textFaint)),
                )
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    if (_canAddCustom)
                      ListTile(
                        leading: Icon(Icons.add_circle_outline_rounded,
                            color: tones.azureBrand),
                        title: Text('Add “$_query”',
                            style:
                                inter(15, 620, color: tones.azureBrand)),
                        onTap: _addCustom,
                      ),
                    for (final o in visible)
                      _Row(
                        label: o,
                        selected: _selected.contains(o),
                        multiSelect: widget.multiSelect,
                        onTap: () => _toggle(o),
                      ),
                  ],
                ),
        ),
        // Single-select commits on tap, so a Done button would only ever be a
        // second way to do nothing.
        if (widget.multiSelect)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _selected),
                child: Text(_selected.isEmpty
                    ? 'Done'
                    : 'Done · ${_selected.length} selected'),
              ),
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.selected,
    required this.multiSelect,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool multiSelect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return ListTile(
      onTap: onTap,
      dense: true,
      title: Text(
        label,
        style: inter(15, selected ? 620 : 460,
            color: selected
                ? tones.azureBrand
                : Theme.of(context).colorScheme.onSurface),
      ),
      trailing: selected
          ? Icon(
              multiSelect
                  ? Icons.check_box_rounded
                  : Icons.check_circle_rounded,
              color: tones.azureBrand,
              size: 21,
            )
          : (multiSelect
              ? Icon(Icons.check_box_outline_blank_rounded,
                  color: tones.line, size: 22)
              : null),
    );
  }
}
