import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Canonical real-time GNSS satellite-count badge.
///
/// Shows how many satellites the bike module is currently locked onto, as
/// reported live over the module telemetry WebSocket (`ModuleTelemetry.satellites`).
/// Used on every activity-prep map (free ride / lap timer setup / race tracking),
/// the trail-record map, and the module-detail GPS tab, so the rider always sees
/// the live fix quality.
///
/// States (a 3D GPS fix needs >= 4 satellites):
/// * `count == null`  -> "Searching…" (no frame / no value yet) — grey.
/// * `count <= 3`     -> weak fix — amber.
/// * `count >= 4`     -> good fix — green.
class SatelliteBadge extends StatelessWidget {
  /// Live satellite count, or `null` when no module frame has arrived yet.
  final int? count;

  const SatelliteBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final c = count;
    final Color accent;
    final String label;
    if (c == null) {
      accent = AppColors.textSecondary;
      label = 'Searching…';
    } else if (c <= 3) {
      accent = Colors.amber.shade700;
      label = '$c sat${c == 1 ? '' : 's'}';
    } else {
      accent = AppColors.success;
      label = '$c sats';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.satellite_alt, size: 16, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
