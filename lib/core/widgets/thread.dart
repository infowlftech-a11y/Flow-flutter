import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'surfaces.dart';

/// The tucked corner on a bubble that continues a run from the same sender.
/// Not a scale step — it is a notch in one component, not a surface radius.
const _tuck = Radius.circular(6);

/// One message in a thread.
///
/// Three implementations existed — rider↔trainer chat, support tickets and
/// suspension appeals — and they agreed on the idea and on nothing else:
/// bubbles were capped at 74%, 78% and a flat 280 px; corners were 18, 16 and
/// 14; body text was 14.5, 14 and 13.5. None of that variation meant anything.
///
/// The width cap is now measured against the **incoming constraints** rather
/// than `MediaQuery.sizeOf(context).width`. Two of the three measured the whole
/// screen while sitting inside a padded list, so the real cap drifted with the
/// padding; the appeal thread sidestepped that with a hardcoded 280 px, which
/// then stayed 280 px on a tablet.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.text,
    required this.mine,
    this.firstOfRun = true,
    this.lastOfRun = true,
    this.header,
    this.footer,
    this.maxWidthFactor = .78,
    this.onLongPress,
    this.mineColor,
    this.theirsColor,
    this.mineTextColor,
    this.theirsTextColor,
    this.borderColor,
    this.bordered = true,
  });

  final String text;

  /// Right-aligned and brand-filled when true.
  final bool mine;

  /// Corner shaping for consecutive messages from one sender. Both default to
  /// true, which is a standalone bubble with four equal corners.
  final bool firstOfRun;
  final bool lastOfRun;

  /// Sits above the text inside the bubble — the FLOW SUPPORT label.
  final Widget? header;

  /// Sits below the bubble, outside it — a timestamp or sender name.
  final Widget? footer;

  /// Share of the available width the bubble may occupy.
  final double maxWidthFactor;

  final VoidCallback? onLongPress;

  /// Palette overrides for threads that do not sit on the themed background —
  /// the appeal thread renders on the ink gate surface in both themes.
  final Color? mineColor;
  final Color? theirsColor;
  final Color? mineTextColor;
  final Color? theirsTextColor;
  final Color? borderColor;

  /// Outlines an incoming bubble so it separates from the surface behind it.
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final scheme = context.scheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    // `primary`/`onPrimary` rather than the brand azure with hardcoded white.
    // In dark, `azureBrand` is the vivid logo azure and white text on it
    // measures 2.4:1 — the worst contrast anywhere in the app, on the surface
    // a chat screen is mostly made of. The scheme already answers "what reads
    // on a primary fill" per brightness: ink on bright azure in dark, white on
    // deep azure in light. Both clear AA.
    final fill = mine
        ? (mineColor ?? scheme.primary)
        : (theirsColor ??
            (dark ? scheme.surfaceContainerHigh : Colors.white));
    final ink = mine
        ? (mineTextColor ?? scheme.onPrimary)
        : (theirsTextColor ?? scheme.onSurface);

    const full = Radius.circular(FlowRadius.inset);
    final radius = BorderRadius.only(
      topLeft: mine || firstOfRun ? full : _tuck,
      topRight: !mine || firstOfRun ? full : _tuck,
      bottomLeft: mine || lastOfRun ? full : _tuck,
      bottomRight: !mine || lastOfRun ? full : _tuck,
    );

    return Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            onLongPress: onLongPress,
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * maxWidthFactor),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: radius,
                border: mine || !bordered
                    ? null
                    : Border.all(color: borderColor ?? tones.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (header != null) ...[
                    header!,
                    const SizedBox(height: 4),
                  ],
                  Text(text,
                      style: inter(14, 460, color: ink, height: 1.45)),
                ],
              ),
            ),
          ),
        ),
        if (footer != null) ...[const SizedBox(height: 3), footer!],
      ],
    );
  }
}

/// The text field and send button of a thread composer.
///
/// Separate from [MessageComposer] because the appeal thread's composer lives
/// inside a card on the gate screen rather than in a bar pinned to the bottom.
///
/// The 48 px send button is the point: the appeal thread used a bare
/// `IconButton.filled`, which is 40 px — under the minimum tap target, on the
/// one screen where a user is already having a bad day.
class ComposerField extends StatelessWidget {
  const ComposerField({
    super.key,
    required this.controller,
    required this.onSend,
    this.canSend = true,
    this.busy = false,
    this.hintText = 'Message…',
    this.maxLines = 5,
    this.sendIcon = Icons.arrow_upward_rounded,
    this.textStyle,
    this.isDense = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend;

  /// Fades the send button and swallows submits when false.
  final bool canSend;

  /// Disables the field and swaps the send glyph for a spinner.
  final bool busy;
  final String hintText;
  final int maxLines;
  final IconData sendIcon;

  /// For a composer on a non-themed surface.
  final TextStyle? textStyle;
  final bool isDense;

  @override
  Widget build(BuildContext context) {
    final enabled = canSend && !busy;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !busy,
            minLines: 1,
            maxLines: maxLines,
            style: textStyle,
            textCapitalization: TextCapitalization.sentences,
            decoration:
                InputDecoration(hintText: hintText, isDense: isDense),
            onSubmitted: (_) => enabled ? onSend() : null,
          ),
        ),
        const SizedBox(width: 10),
        AnimatedOpacity(
          curve: FlowMotion.curve,
          duration: FlowMotion.fast,
          opacity: enabled ? 1 : .45,
          child: SizedBox(
            width: 48,
            height: 48,
            child: IconButton.filled(
              onPressed: enabled ? onSend : null,
              tooltip: 'Send',
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(sendIcon, size: 22),
            ),
          ),
        ),
      ],
    );
  }
}

/// A [ComposerField] in the bar that sits under a thread — surface tint, a
/// hairline along the top and safe-area padding underneath.
class MessageComposer extends StatelessWidget {
  const MessageComposer({
    super.key,
    required this.controller,
    required this.onSend,
    this.canSend = true,
    this.busy = false,
    this.hintText = 'Message…',
    this.maxLines = 5,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool canSend;
  final bool busy;
  final String hintText;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return StickyBar(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: ComposerField(
        controller: controller,
        onSend: onSend,
        canSend: canSend,
        busy: busy,
        hintText: hintText,
        maxLines: maxLines,
      ),
    );
  }
}
