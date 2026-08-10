import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'misc.dart';

/// A session on the trainer's day, as one line.
///
/// The live session is marked by a leading accent edge *and* a labelled pill,
/// not by colour alone — a trainer glancing at this in direct sun on a beach
/// is the worst-case reader, and one tinted row among five is not enough.
class AgendaRow extends StatelessWidget {
  const AgendaRow({
    super.key,
    required this.time,
    required this.name,
    required this.onTap,
    this.statusLabel,
    this.live = false,
  });

  final String time;
  final String name;
  final VoidCallback onTap;

  /// `Upcoming`, `Completed`. Null shows nothing.
  final String? statusLabel;

  final bool live;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final scheme = context.scheme;

    return Material(
      color: live ? scheme.primary.withValues(alpha: .10) : tones.card,
      borderRadius: FlowRadii.inset,
      child: InkWell(
        borderRadius: FlowRadii.inset,
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: FlowRadii.inset,
            border: Border.all(
                color: live ? scheme.primary.withValues(alpha: .55) : tones.line),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Text(time,
                      style: interNum(13, 700,
                          color: live ? scheme.primary : scheme.onSurface)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: inter(13.5, 560, color: scheme.onSurface),
                    ),
                  ),
                  if (live)
                    TagPill('LIVE',
                        color: scheme.primary,
                        icon: Symbols.circle,
                        iconFill: 1,
                        dense: true)
                  else if (statusLabel != null)
                    Text(statusLabel!,
                        style: inter(12, 560, color: tones.textFaint)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pending booking request with its two answers.
///
/// Approve and decline are the same size and weight on purpose. Making the
/// approving action louder is a nudge, and the trainer is the one carrying
/// the consequence of a session they did not want.
class RequestRow extends StatelessWidget {
  const RequestRow({
    super.key,
    required this.when,
    required this.name,
    required this.onApprove,
    required this.onDecline,
    this.location,
    this.busy = false,
  });

  final String when;
  final String name;
  final VoidCallback onApprove;
  final VoidCallback onDecline;
  final String? location;

  /// Locks both answers while one is in flight, so a double tap cannot
  /// approve and decline the same request.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final scheme = context.scheme;

    return Container(
      decoration: BoxDecoration(
        color: tones.card,
        borderRadius: FlowRadii.inset,
        border: Border.all(color: tones.line),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(when,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: inter(12.5, 560, color: tones.textFaint)),
                const SizedBox(height: 3),
                Text(
                  location == null ? name : '$name · $location',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: inter(14, 640, color: scheme.onSurface),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Answer(
            icon: Symbols.check_rounded,
            label: 'Approve $name',
            color: tones.success,
            onTap: busy ? null : onApprove,
          ),
          const SizedBox(width: 6),
          _Answer(
            icon: Symbols.close_rounded,
            label: 'Decline $name',
            color: tones.danger,
            onTap: busy ? null : onDecline,
          ),
        ],
      ),
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    // The visual puck is 36; the hit box is 48. Growing the art to meet the
    // target would put two heavy circles in a row that is mostly text.
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: SizedBox(
        width: 48,
        height: 48,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: onTap == null ? .08 : .16),
              ),
              child: Icon(icon,
                  size: 19,
                  color: onTap == null
                      ? tones.textFaint
                      : tones.onTint(color)),
            ),
          ),
        ),
      ),
    );
  }
}
