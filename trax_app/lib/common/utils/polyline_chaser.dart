import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Slides a short "chaser" segment along a polyline route so the trail
/// reads as a flowing line in the travel direction — mirroring the
/// indeterminate blue stripe used elsewhere in the app's UI. Pure compute
/// only; the caller drives the animation phase via [sliceAt].
class PolylineChaser {
  PolylineChaser(this.route, {this.spanFraction = 0.08})
      : _cum = _cumDistances(route) {
    _total = _cum.isEmpty ? 0 : _cum.last;
  }

  final List<LatLng> route;

  /// Length of the highlighted head segment, expressed as a fraction of
  /// the total route length.
  final double spanFraction;

  final List<double> _cum;
  late final double _total;

  bool get canRender => route.length >= 3 && _total > 0;

  /// Position of the head dot at animation phase [t] (`t` wraps into [0,1)).
  LatLng headAt(double t) {
    if (!canRender) return route.isNotEmpty ? route.first : const LatLng(0, 0);
    final phase = t - t.floorToDouble();
    return _pointAtDist(_total * phase);
  }

  /// Returns a contiguous slice of [route] covering the chaser head at
  /// animation phase [t] (`t` is wrapped into `[0, 1)`).
  List<LatLng> sliceAt(double t) {
    if (!canRender) return const [];
    final span = (_total * spanFraction).clamp(1.0, _total);
    final phase = t - t.floorToDouble();
    final headDist = _total * phase;
    final tailDist = headDist - span;

    final headIdx = _ceilIdx(headDist);
    final startDist = tailDist < 0 ? 0.0 : tailDist;
    final tailIdx = _ceilIdx(startDist);

    final out = <LatLng>[];
    out.add(_pointAtDist(startDist));
    for (int i = tailIdx; i < headIdx; i++) {
      out.add(route[i]);
    }
    out.add(_pointAtDist(headDist));
    return out;
  }

  int _ceilIdx(double d) {
    int lo = 0, hi = _cum.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_cum[mid] < d) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  LatLng _pointAtDist(double d) {
    if (d <= 0) return route.first;
    if (d >= _total) return route.last;
    final i = _ceilIdx(d);
    final prev = _cum[i - 1];
    final segLen = _cum[i] - prev;
    final f = segLen <= 0 ? 0.0 : (d - prev) / segLen;
    final a = route[i - 1];
    final b = route[i];
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * f,
      a.longitude + (b.longitude - a.longitude) * f,
    );
  }

  static List<double> _cumDistances(List<LatLng> pts) {
    if (pts.length < 2) return const [];
    final out = List<double>.filled(pts.length, 0);
    for (int i = 1; i < pts.length; i++) {
      out[i] = out[i - 1] + _meters(pts[i - 1], pts[i]);
    }
    return out;
  }

  static double _meters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
  }
}
