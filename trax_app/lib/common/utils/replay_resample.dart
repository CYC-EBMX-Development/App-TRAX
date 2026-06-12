import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

/// A track resampled onto a fixed playback grid.
class ReplayTrack {
  final List<LatLng> route;
  final List<DateTime>? times;
  final List<double> speeds;
  const ReplayTrack({
    required this.route,
    required this.times,
    required this.speeds,
  });
}

/// Resamples a recorded track onto a fixed [stepMs] grid (default 200 ms) so
/// replay advances one point every [stepMs].
///
/// Requirements:
///   1. Replay plays one point every 200 ms.
///   2. A sparse gap (e.g. the 1 s module cadence) is split along the straight
///      line between the two raw fixes into `round(gapMs / stepMs)` equal
///      sub-segments (1 s -> 5 sub-points of 200 ms each), linearly
///      interpolating position and speed.
///
/// When [times] is null or its length does not match [route], a uniform
/// [assumedIntervalMs] (default 1 s) is assumed between consecutive raw points,
/// so every raw segment is split into `assumedIntervalMs / stepMs` (= 5)
/// sub-segments.
ReplayTrack resampleReplayTrack({
  required List<LatLng> route,
  required List<DateTime>? times,
  required List<double> speeds,
  int stepMs = 200,
  int assumedIntervalMs = 1000,
}) {
  // Fewer than 2 points: nothing to interpolate, pass through unchanged.
  if (route.length < 2) {
    return ReplayTrack(
      route: List<LatLng>.from(route),
      times: times == null ? null : List<DateTime>.from(times),
      speeds: List<double>.from(speeds),
    );
  }

  final hasTimes = times != null && times.length == route.length;

  final outRoute = <LatLng>[];
  final outTimes = <DateTime>[];
  final outSpeeds = <double>[];

  // Seed with the first raw sample.
  outRoute.add(route.first);
  if (hasTimes) outTimes.add(times!.first);
  outSpeeds.add(speeds.isNotEmpty ? speeds.first : 0.0);

  for (int i = 0; i < route.length - 1; i++) {
    final a = route[i];
    final b = route[i + 1];
    final sa = i < speeds.length ? speeds[i] : 0.0;
    final sb = (i + 1) < speeds.length ? speeds[i + 1] : sa;

    int gapMs;
    DateTime? ta;
    if (hasTimes) {
      ta = times![i];
      gapMs = times[i + 1].difference(ta).inMilliseconds;
    } else {
      gapMs = assumedIntervalMs;
    }

    // Equal sub-segments for this gap (1 s / 200 ms = 5). Guard against
    // zero/negative gaps from duplicate timestamps.
    int segments = gapMs <= 0 ? 1 : (gapMs / stepMs).round();
    if (segments < 1) segments = 1;

    for (int j = 1; j <= segments; j++) {
      final t = j / segments;
      outRoute.add(LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      ));
      outSpeeds.add(sa + (sb - sa) * t);
      if (hasTimes) {
        outTimes.add(ta!.add(Duration(milliseconds: (gapMs * t).round())));
      }
    }
  }

  return ReplayTrack(
    route: outRoute,
    times: hasTimes ? outTimes : null,
    speeds: outSpeeds,
  );
}
