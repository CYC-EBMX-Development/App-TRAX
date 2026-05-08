import 'package:flutter/material.dart';
import '../../models/ride_lap.dart';
import '../../theme/app_theme.dart';

/// Shared expandable row for a single lap; when checkpointPasses are present,
/// expands to show CP splits (Start→CP1, CP1→CP2, …, CPn→Finish, Total).
class ExpandableLapRow extends StatefulWidget {
  final RideLap lap;
  final bool initiallyExpanded;
  final Color? accentColor;
  final String? trailingFastestBadge;

  const ExpandableLapRow({
    super.key,
    required this.lap,
    this.initiallyExpanded = false,
    this.accentColor,
    this.trailingFastestBadge,
  });

  @override
  State<ExpandableLapRow> createState() => _ExpandableLapRowState();
}

class _ExpandableLapRowState extends State<ExpandableLapRow> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final lap = widget.lap;
    final accent = widget.accentColor ?? AppColors.primary;
    final hasPasses = lap.checkpointPasses.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: hasPasses ? () => setState(() => _expanded = !_expanded) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 26, height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${lap.lapNumber}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Lap ${lap.lapNumber}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                        ),
                        Text(
                          '${lap.distanceKm.toStringAsFixed(2)} km'
                          '${lap.overlapPercent != null ? " · ${lap.overlapPercent!.toStringAsFixed(0)}% overlap" : ""}',
                          style: const TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (widget.trailingFastestBadge != null)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.trailingFastestBadge!,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                  Text(
                    lap.formatted,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: accent,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (hasPasses) ...[
                    const SizedBox(width: 6),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (hasPasses && _expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: _buildSplitsTable(lap, accent),
            ),
        ],
      ),
    );
  }

  Widget _buildSplitsTable(RideLap lap, Color accent) {
    final passes = [...lap.checkpointPasses]
      ..sort((a, b) => a.sequenceIndex.compareTo(b.sequenceIndex));

    // Build segment list: Start→CP1, CP1→CP2, …, CPn→Finish.
    final rows = <_SplitRow>[];
    int prevSec = 0;
    int? prevSeq;
    for (final p in passes) {
      final label = prevSeq == null
          ? 'Start → CP${p.sequenceIndex}'
          : 'CP$prevSeq → CP${p.sequenceIndex}';
      rows.add(_SplitRow(
        label: label,
        seconds: p.secondsFromLapStart - prevSec,
        cumulative: p.secondsFromLapStart,
      ));
      prevSec = p.secondsFromLapStart;
      prevSeq = p.sequenceIndex;
    }
    // Final segment to Finish
    rows.add(_SplitRow(
      label: prevSeq == null ? 'Start → Finish' : 'CP$prevSeq → Finish',
      seconds: lap.durationSeconds - prevSec,
      cumulative: lap.durationSeconds,
    ));

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in rows) _splitLine(r, accent, false),
          const Divider(height: 10, color: AppColors.divider),
          _splitLine(
              _SplitRow(
                  label: 'Total', seconds: lap.durationSeconds, cumulative: lap.durationSeconds),
              accent,
              true),
        ],
      ),
    );
  }

  Widget _splitLine(_SplitRow r, Color accent, bool isTotal) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              r.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
                color: isTotal
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
          if (!isTotal) ...[
            Text(
              'cum ${formatLapDuration(r.cumulative)}',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            formatLapDuration(r.seconds),
            style: TextStyle(
              fontSize: 12,
              fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
              color: isTotal ? accent : AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _SplitRow {
  final String label;
  final int seconds;
  final int cumulative;
  const _SplitRow({
    required this.label,
    required this.seconds,
    required this.cumulative,
  });
}
