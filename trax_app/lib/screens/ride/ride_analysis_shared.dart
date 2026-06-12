import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../../common/utils/map_styles.dart';
import '../../theme/app_theme.dart';

class RideAnalysisSample {
  final LatLng position;
  final DateTime timestamp;
  final double speedKmh;
  final double altitudeM;

  const RideAnalysisSample({
    required this.position,
    required this.timestamp,
    required this.speedKmh,
    required this.altitudeM,
  });
}

enum RideAnalysisMetric { speed, altitude }

extension RideAnalysisMetricX on RideAnalysisMetric {
  String get label => this == RideAnalysisMetric.speed ? 'Speed' : 'Altitude';

  String get unit => this == RideAnalysisMetric.speed ? 'km/h' : 'm';

  Color get color =>
      this == RideAnalysisMetric.speed ? MapStyles.trailColor : const Color(0xFF2E7DF6);

  double valueOf(RideAnalysisSample s) =>
      this == RideAnalysisMetric.speed ? s.speedKmh : s.altitudeM;
}

/// Builds the analysis sample list straight from the recorded ride
/// points — one sample per real GPS fix, no time-grid resampling.
///
/// The analysis screen is a static scrubber/chart (not an animation),
/// so the 200ms interpolation that replay needs would only add
/// collinear filler points (5–25x the data) with zero analytical gain.
List<RideAnalysisSample> buildAnalysisSamples(
  List<Map<String, dynamic>> points,
) {
  if (points.isEmpty) return const [];

  final out = <RideAnalysisSample>[];
  for (final p in points) {
    final lat = (p['latitude'] as num?)?.toDouble();
    final lng = (p['longitude'] as num?)?.toDouble();
    final tStr = p['timestamp']?.toString();
    final t = tStr == null ? null : DateTime.tryParse(tStr);
    if (lat == null || lng == null || t == null) continue;
    out.add(RideAnalysisSample(
      position: LatLng(lat, lng),
      timestamp: t,
      speedKmh: (p['speed'] as num?)?.toDouble() ?? 0,
      altitudeM: (p['altitude'] as num?)?.toDouble() ?? 0,
    ));
  }

  return out;
}

List<double> buildCumulativeDistanceKm(List<RideAnalysisSample> samples) {
  if (samples.isEmpty) return const [];
  final out = List<double>.filled(samples.length, 0);
  for (int i = 1; i < samples.length; i++) {
    out[i] = out[i - 1] + _haversineKm(samples[i - 1].position, samples[i].position);
  }
  return out;
}

String formatElapsed(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) {
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

class RideAnalysisChart extends StatefulWidget {
  final List<RideAnalysisSample> samples;
  final RideAnalysisMetric metric;
  final int cursor;
  final int windowStart;
  final int windowEnd;
  final ValueChanged<int> onCursorChanged;
  final void Function(int start, int end) onWindowChanged;

  const RideAnalysisChart({
    super.key,
    required this.samples,
    required this.metric,
    required this.cursor,
    required this.windowStart,
    required this.windowEnd,
    required this.onCursorChanged,
    required this.onWindowChanged,
  });

  @override
  State<RideAnalysisChart> createState() => _RideAnalysisChartState();
}

class _RideAnalysisChartState extends State<RideAnalysisChart> {
  static const double _padL = 10;
  static const double _padR = 10;
  static const double _padT = 14;
  static const double _padB = 22;

  int _scaleStartSpan = 0;
  double _scaleStartFocusFrac = 0.5;
  double _scaleStartFocusIndex = 0;

  int get _total => widget.samples.length;

  int get _minWindowPoints => _total < 10 ? _total : 10;

  bool get _canZoomIn => _total > 10;

  void _setCursorFromDx(double dx, double width) {
    final x0 = _padL;
    final x1 = width - _padR;
    if (x1 <= x0) return;
    final frac = ((dx - x0) / (x1 - x0)).clamp(0.0, 1.0);
    final span = widget.windowEnd - widget.windowStart;
    final idx = widget.windowStart + (span * frac).round();
    widget.onCursorChanged(idx.clamp(0, _total - 1));
  }

  void _zoomAround({required int nextSpan, required double focusFrac, required double focusIndex}) {
    int span = nextSpan.clamp(_minWindowPoints, _total);
    if (!_canZoomIn) span = _total;

    int start = (focusIndex - focusFrac * (span - 1)).round();
    final maxStart = _total - span;
    if (start < 0) start = 0;
    if (start > maxStart) start = maxStart;
    final end = start + span - 1;
    widget.onWindowChanged(start, end);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _setCursorFromDx(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) => _setCursorFromDx(d.localPosition.dx, width),
          onScaleStart: (d) {
            final span = widget.windowEnd - widget.windowStart + 1;
            _scaleStartSpan = span;
            final x0 = _padL;
            final x1 = width - _padR;
            final frac = (x1 <= x0)
                ? 0.5
                : ((d.localFocalPoint.dx - x0) / (x1 - x0)).clamp(0.0, 1.0);
            _scaleStartFocusFrac = frac;
            _scaleStartFocusIndex =
                widget.windowStart + frac * (span - 1).toDouble();
          },
          onScaleUpdate: (d) {
            if (d.pointerCount < 2 || !_canZoomIn || _scaleStartSpan <= 0) return;
            final nextSpan = (_scaleStartSpan / d.scale).round();
            _zoomAround(
              nextSpan: nextSpan,
              focusFrac: _scaleStartFocusFrac,
              focusIndex: _scaleStartFocusIndex,
            );
          },
          child: CustomPaint(
            painter: _RideAnalysisChartPainter(
              samples: widget.samples,
              metric: widget.metric,
              cursor: widget.cursor,
              windowStart: widget.windowStart,
              windowEnd: widget.windowEnd,
              padL: _padL,
              padR: _padR,
              padT: _padT,
              padB: _padB,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

class _RideAnalysisChartPainter extends CustomPainter {
  final List<RideAnalysisSample> samples;
  final RideAnalysisMetric metric;
  final int cursor;
  final int windowStart;
  final int windowEnd;
  final double padL;
  final double padR;
  final double padT;
  final double padB;

  _RideAnalysisChartPainter({
    required this.samples,
    required this.metric,
    required this.cursor,
    required this.windowStart,
    required this.windowEnd,
    required this.padL,
    required this.padR,
    required this.padT,
    required this.padB,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final x0 = padL;
    final x1 = size.width - padR;
    final y0 = padT;
    final y1 = size.height - padB;
    if (x1 <= x0 || y1 <= y0) return;

    final start = windowStart.clamp(0, samples.length - 1);
    final end = windowEnd.clamp(start, samples.length - 1);
    final span = (end - start).toDouble();

    double minV = double.infinity;
    double maxV = -double.infinity;
    for (int i = start; i <= end; i++) {
      final v = metric.valueOf(samples[i]);
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    if (!minV.isFinite || !maxV.isFinite) return;
    if ((maxV - minV).abs() < 0.001) {
      maxV += 1;
      minV -= 1;
    } else {
      final pad = (maxV - minV) * 0.12;
      maxV += pad;
      minV -= pad;
    }

    double xFor(int idx) {
      if (span <= 0) return x0;
      return x0 + (idx - start) / span * (x1 - x0);
    }

    double yFor(double v) => y1 - (v - minV) / (maxV - minV) * (y1 - y0);

    final grid = Paint()
      ..color = AppColors.divider
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = y0 + (y1 - y0) * i / 4;
      canvas.drawLine(Offset(x0, y), Offset(x1, y), grid);
    }

    final path = Path();
    for (int i = start; i <= end; i++) {
      final p = Offset(xFor(i), yFor(metric.valueOf(samples[i])));
      if (i == start) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }

    final linePaint = Paint()
      ..color = metric.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    final c = cursor.clamp(start, end);
    final cx = xFor(c);
    final cv = metric.valueOf(samples[c]);
    final cy = yFor(cv);

    final vLine = Paint()
      ..color = AppColors.textPrimary.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const dash = 6.0;
    const gap = 5.0;
    double yy = y0;
    while (yy < y1) {
      final yTo = math.min(y1, yy + dash);
      canvas.drawLine(Offset(cx, yy), Offset(cx, yTo), vLine);
      yy += dash + gap;
    }

    final dotPaint = Paint()..color = metric.color;
    canvas.drawCircle(Offset(cx, cy), 6, dotPaint);
    canvas.drawCircle(Offset(cx, cy), 2.4, Paint()..color = Colors.white);

    final valueText = '${cv.toStringAsFixed(1)} ${metric.unit}';
    final valueTp = TextPainter(
      text: TextSpan(
        text: valueText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final bubbleW = valueTp.width + 14;
    const bubbleH = 28.0;
    double bx = cx - bubbleW / 2;
    if (bx < x0) bx = x0;
    if (bx + bubbleW > x1) bx = x1 - bubbleW;
    double by = cy - bubbleH - 14;
    if (by < y0) by = y0 + 2;

    final bubbleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(bx, by, bubbleW, bubbleH),
      const Radius.circular(8),
    );
    canvas.drawRRect(bubbleRect, Paint()..color = metric.color);
    valueTp.paint(canvas, Offset(bx + 7, by + 6));

    final tip = Path()
      ..moveTo(cx, by + bubbleH + 6)
      ..lineTo(cx - 5, by + bubbleH)
      ..lineTo(cx + 5, by + bubbleH)
      ..close();
    canvas.drawPath(tip, Paint()..color = metric.color);

    _paintTimeLabel(canvas, samples[start].timestamp, Offset(x0, y1 + 4), alignRight: false);
    _paintTimeLabel(canvas, samples[end].timestamp, Offset(x1, y1 + 4), alignRight: true);
    _paintTimeLabel(canvas, samples[c].timestamp, Offset(cx, y1 + 4), center: true);
  }

  void _paintTimeLabel(
    Canvas canvas,
    DateTime t,
    Offset origin, {
    bool alignRight = false,
    bool center = false,
  }) {
    final text = formatElapsed(t.difference(samples.first.timestamp));
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    double dx = origin.dx;
    if (alignRight) dx -= tp.width;
    if (center) dx -= tp.width / 2;
    canvas.drawRect(
      Rect.fromLTWH(dx - 4, origin.dy - 1, tp.width + 8, tp.height + 2),
      Paint()..color = AppColors.surface.withValues(alpha: 0.85),
    );
    tp.paint(canvas, Offset(dx, origin.dy));
  }

  @override
  bool shouldRepaint(covariant _RideAnalysisChartPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.metric != metric ||
        oldDelegate.cursor != cursor ||
        oldDelegate.windowStart != windowStart ||
        oldDelegate.windowEnd != windowEnd;
  }
}

double _haversineKm(LatLng a, LatLng b) {
  const earthR = 6371.0;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final la1 = a.latitude * math.pi / 180;
  final la2 = b.latitude * math.pi / 180;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(la1) * math.cos(la2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * earthR * math.asin(math.sqrt(h));
}
