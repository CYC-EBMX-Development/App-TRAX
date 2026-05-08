import 'package:flutter/material.dart';
import '../models/ride_lap.dart';
import '../theme/app_theme.dart';

/// Excel-style lap × checkpoint splits table.
///
/// Rows: laps (newest first or as provided). When [targetLaps] is supplied
/// the grid always renders that many rows, padding with empty cells so the
/// skeleton is visible from the start of a session.
/// Columns: CP1, CP2, …, CPn, Finish (Total).
/// Cells: cumulative time at the checkpoint (mode = cumulative)
///        OR interval time from previous checkpoint (mode = interval).
///
/// To support a live ticker on the in-progress lap, callers may pass
/// [currentLapNumber] together with [currentLapPasses] (a list of
/// (sequenceIndex, secondsFromLapStart) tuples) and [currentLapElapsed]
/// — these are used to fill the current-lap row as checkpoints are hit.
enum LapSplitMode { cumulative, interval }

class LapSplitsGrid extends StatefulWidget {
  final List<RideLap> laps;
  final Color? accentColor;
  final String title;
  final bool reverse; // when true, newest lap first; default false (Lap 1 at top)
  final LapSplitMode initialMode;

  /// When > 0, force the grid to render this many rows (lap 1..targetLaps).
  /// Rows with no completed-lap data and no live data are shown empty.
  final int targetLaps;

  /// When > 0, force the grid to render this many checkpoint columns
  /// (CP1 | … | CPn | Finish). Useful before any lap is completed.
  final int checkpointCount;

  /// Live ticker for the currently-running lap. Pass the lap number (1-based)
  /// and any checkpoint passes recorded so far for that lap.
  final int? currentLapNumber;
  final List<({int sequenceIndex, int secondsFromLapStart})>? currentLapPasses;
  final int? currentLapElapsed;

  const LapSplitsGrid({
    super.key,
    required this.laps,
    this.accentColor,
    this.title = 'Lap splits',
    this.reverse = false,
    this.initialMode = LapSplitMode.cumulative,
    this.targetLaps = 0,
    this.checkpointCount = 0,
    this.currentLapNumber,
    this.currentLapPasses,
    this.currentLapElapsed,
  });

  @override
  State<LapSplitsGrid> createState() => _LapSplitsGridState();
}

class _LapSplitsGridState extends State<LapSplitsGrid> {
  late LapSplitMode _mode = widget.initialMode;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? AppColors.primary;
    final laps = widget.laps;

    // Determine columns: max checkpoints across (provided floor, completed
    // laps, live current-lap passes).
    int maxCp = widget.checkpointCount;
    for (final l in laps) {
      if (l.checkpointPasses.length > maxCp) {
        maxCp = l.checkpointPasses.length;
      }
    }
    if (widget.currentLapPasses != null) {
      for (final p in widget.currentLapPasses!) {
        if (p.sequenceIndex > maxCp) maxCp = p.sequenceIndex;
      }
    }

    // Determine rows: at minimum the target laps; otherwise fall back to
    // completed-lap count (legacy callers).
    final totalRows =
        widget.targetLaps > 0 ? widget.targetLaps : laps.length;
    if (totalRows == 0) return const SizedBox.shrink();

    // Index completed laps by lapNumber for fast lookup.
    final lapByNumber = {for (final l in laps) l.lapNumber: l};

    // Best-lap highlight (only among completed laps).
    int? bestLapNumber;
    int bestSec = 1 << 30;
    for (final l in laps) {
      if (l.durationSeconds < bestSec) {
        bestSec = l.durationSeconds;
        bestLapNumber = l.lapNumber;
      }
    }

    // Build row order.
    final lapOrder = <int>[for (int i = 1; i <= totalRows; i++) i];
    if (widget.reverse) {
      lapOrder.sort((a, b) => b.compareTo(a));
    }

    // Headers.
    final headers = <String>[];
    for (int i = 1; i <= maxCp; i++) {
      headers.add('CP$i');
    }
    headers.add('Finish');

    // Build per-row cell data.
    final rowsData = <_RowData>[];
    for (final lapNum in lapOrder) {
      final lap = lapByNumber[lapNum];
      final isCurrent = widget.currentLapNumber == lapNum;
      rowsData.add(_buildRow(
        lapNumber: lapNum,
        lap: lap,
        isCurrent: isCurrent,
        maxCp: maxCp,
        bestLapNumber: bestLapNumber,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(accent),
        const SizedBox(height: 6),
        _buildTable(headers, rowsData, accent),
      ],
    );
  }

  _RowData _buildRow({
    required int lapNumber,
    required RideLap? lap,
    required bool isCurrent,
    required int maxCp,
    required int? bestLapNumber,
  }) {
    final cells = <String>[];
    final isBest = bestLapNumber != null && lapNumber == bestLapNumber;

    if (lap != null) {
      // Completed lap.
      final passes = [...lap.checkpointPasses]
        ..sort((a, b) => a.sequenceIndex.compareTo(b.sequenceIndex));
      final byIdx = {
        for (final p in passes) p.sequenceIndex: p.secondsFromLapStart
      };
      final cum = <int>[];
      for (int i = 1; i <= maxCp; i++) {
        cum.add(byIdx[i] ?? -1);
      }
      cum.add(lap.durationSeconds);
      _formatCells(cum, cells);
    } else if (isCurrent) {
      // In-progress lap: live ticker.
      final passes = widget.currentLapPasses ?? const [];
      final byIdx = {
        for (final p in passes) p.sequenceIndex: p.secondsFromLapStart
      };
      final cum = <int>[];
      for (int i = 1; i <= maxCp; i++) {
        cum.add(byIdx[i] ?? -1);
      }
      cum.add(widget.currentLapElapsed ?? -1);
      _formatCells(cum, cells);
    } else {
      // Future lap: all empty.
      for (int i = 1; i <= maxCp; i++) {
        cells.add('—');
      }
      cells.add('—');
    }

    return _RowData(
      label: 'Lap $lapNumber',
      cells: cells,
      isBest: isBest,
      isCurrent: isCurrent,
    );
  }

  void _formatCells(List<int> cum, List<String> out) {
    if (_mode == LapSplitMode.cumulative) {
      for (int i = 0; i < cum.length; i++) {
        final v = cum[i];
        out.add(v < 0 ? '—' : formatLapDuration(v));
      }
    } else {
      // Interval mode: first cell is interval from lap start (0) to first CP.
      int prev = 0;
      for (int i = 0; i < cum.length; i++) {
        final v = cum[i];
        if (v < 0) {
          out.add('—');
          // Do not advance prev when CP is missing; keep last known anchor.
        } else {
          out.add(formatLapDuration(v - prev));
          prev = v;
        }
      }
    }
  }

  Widget _buildHeader(Color accent) {
    return Row(
      children: [
        Text(
          widget.title,
          style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() {
            _mode = _mode == LapSplitMode.cumulative
                ? LapSplitMode.interval
                : LapSplitMode.cumulative;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _mode == LapSplitMode.cumulative
                      ? Icons.timeline
                      : Icons.compare_arrows,
                  size: 12,
                  color: accent,
                ),
                const SizedBox(width: 4),
                Text(
                  _mode == LapSplitMode.cumulative
                      ? 'Cumulative'
                      : 'Interval',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTable(
      List<String> headers, List<_RowData> rows, Color accent) {
    const double lapColWidth = 56;
    const double minCellWidth = 64;
    const double headerHeight = 28;
    const double rowHeight = 28;

    final dataColCount = headers.length; // CP1..CPn + Finish

    return LayoutBuilder(builder: (context, constraints) {
      // Decide column width.
      // - If we have a bounded parent width, distribute the available room
      //   between the data columns (CP1..CPn + Finish), using minCellWidth
      //   as a floor. When even the floor exceeds available width, fall
      //   back to scrollable.
      // - We subtract 2px for the outer Container border (1px each side)
      //   so the table never spills past the parent.
      double cellWidth = minCellWidth;
      bool needScroll = true;
      if (constraints.hasBoundedWidth && dataColCount > 0) {
        const double borderInset = 2.0;
        final available = constraints.maxWidth - borderInset;
        final naturalDataWidth = minCellWidth * dataColCount;
        final availableForData = available - lapColWidth;
        if (availableForData >= naturalDataWidth) {
          cellWidth = availableForData / dataColCount;
          needScroll = false;
        }
      }

      final table = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              _cell('Lap',
                  width: lapColWidth,
                  height: headerHeight,
                  isHeader: true,
                  accent: accent),
              for (final h in headers)
                _cell(h,
                    width: cellWidth,
                    height: headerHeight,
                    isHeader: true,
                    accent: accent),
            ],
          ),
          // Data rows
          for (final row in rows)
            Row(
              children: [
                _cell(
                  row.label,
                  width: lapColWidth,
                  height: rowHeight,
                  isLapLabel: true,
                  accent: accent,
                  highlight: row.isBest,
                  isCurrent: row.isCurrent,
                ),
                for (int c = 0; c < row.cells.length; c++)
                  _cell(
                    row.cells[c],
                    width: cellWidth,
                    height: rowHeight,
                    accent: accent,
                    isTotal: c == row.cells.length - 1,
                    highlight: row.isBest && c == row.cells.length - 1,
                    isCurrent: row.isCurrent,
                  ),
              ],
            ),
        ],
      );

      return Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: needScroll
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: table,
              )
            : table,
      );
    });
  }

  Widget _cell(
    String text, {
    required double width,
    required double height,
    bool isHeader = false,
    bool isLapLabel = false,
    bool isTotal = false,
    bool highlight = false,
    bool isCurrent = false,
    required Color accent,
  }) {
    Color bg;
    if (isHeader) {
      bg = AppColors.background;
    } else if (highlight) {
      bg = accent.withValues(alpha: 0.10);
    } else if (isCurrent) {
      bg = accent.withValues(alpha: 0.04);
    } else {
      bg = Colors.transparent;
    }
    final color = isHeader
        ? AppColors.textSecondary
        : (highlight || isTotal
            ? accent
            : (text == '—'
                ? AppColors.textSecondary.withValues(alpha: 0.5)
                : AppColors.textPrimary));
    final weight = isHeader
        ? FontWeight.w700
        : (isLapLabel || isTotal ? FontWeight.w700 : FontWeight.w500);
    final showThumbsUp = isTotal && highlight && text != '—';
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          right: BorderSide(color: AppColors.divider, width: 0.5),
          bottom: BorderSide(color: AppColors.divider, width: 0.5),
        ),
      ),
      child: showThumbsUp
          ? Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isHeader ? 10.5 : 11,
                      fontWeight: weight,
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                const Text('👍', style: TextStyle(fontSize: 11)),
              ],
            )
          : Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isHeader ? 10.5 : 11,
                fontWeight: weight,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
    );
  }
}

class _RowData {
  final String label;
  final List<String> cells;
  final bool isBest;
  final bool isCurrent;
  const _RowData({
    required this.label,
    required this.cells,
    required this.isBest,
    required this.isCurrent,
  });
}
