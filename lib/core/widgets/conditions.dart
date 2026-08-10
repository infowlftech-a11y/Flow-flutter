import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/wind.dart';
import '../theme/app_theme.dart';
import '../theme/typography.dart';

/// Today's conditions at a spot: wind, air, water.
///
/// Three independent readings, not one block. Each disappears on its own when
/// its number is missing, because they come from different places and fail
/// separately — wind and air from the forecast endpoint, sea temperature from
/// the marine one, which returns nothing for a spot pinned slightly inland.
/// A strip that vanished entirely because the sea grid had a hole would be
/// hiding two numbers that arrived perfectly well.
///
/// Renders nothing at all when no metric is available. There is deliberately
/// no "—" placeholder: an empty slot where a number belongs reads as a
/// loading state that never resolves, and this is decoration on a booking
/// flow that has to work without it.
class ConditionsStrip extends StatelessWidget {
  const ConditionsStrip({super.key, required this.day});

  final WindDay? day;

  @override
  Widget build(BuildContext context) {
    final d = day;
    if (d == null) return const SizedBox.shrink();

    final air = d.displayAirC;
    final water = d.displayWaterC;

    return Row(
      children: [
        _Metric(
          icon: Symbols.air_rounded,
          label: 'WIND NOW',
          value: '${d.displayKnots}–${d.displayGustKnots} kt',
          // Wind is the one reading that decides whether the day happens at
          // all, so it carries the accent while the temperatures stay quiet.
          accent: true,
        ),
        if (air != null)
          _Metric(
            icon: Symbols.thermostat_rounded,
            label: 'AIR',
            value: '$air°C',
          ),
        if (water != null)
          _Metric(
            icon: Symbols.waves_rounded,
            label: 'WATER',
            value: '$water°C',
          ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final scheme = context.scheme;
    return Expanded(
      child: Semantics(
        // Read as one fact. Without this a screen reader announces "WIND NOW"
        // and "18–24 kt" as two unrelated fragments, and the label alone is
        // meaningless.
        label: '$label $value',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 18,
                color: accent ? tones.azureBrand : scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: microLabel(tones.textFaint, size: 9)),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: interNum(14, 700, color: scheme.onSurface),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
