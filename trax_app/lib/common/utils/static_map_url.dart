import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Build a Google Static Maps URL that auto-fits the given polyline route.
///
/// The Static Maps API automatically frames the map to contain the entire
/// `path` parameter when no center/zoom are supplied, so the returned image
/// always shows the full trail at an appropriate scale.
class StaticMapUrl {
  static const String _apiKey = 'AIzaSyDmzdgVvZu4f5Q7zCKytQ5Syz0RLQzUxng';
  static const String _base = 'https://maps.googleapis.com/maps/api/staticmap';

  /// Returns a URL rendering [route] as a colored polyline at [width]x[height]
  /// (logical pixels, multiplied by [scale] for retina). Returns null if the
  /// route is empty.
  static String? forRoute(
    List<LatLng> route, {
    int width = 240,
    int height = 240,
    int scale = 2,
    String pathColor = '0xFF6A00FF', // matches AppColors.primary
    int pathWeight = 4,
    String mapType = 'roadmap',
  }) {
    if (route.isEmpty) return null;

    // Down-sample very long routes so the URL stays under the ~8 KB limit.
    final pts = _downsample(route, 120);
    final encoded = _encodePolyline(pts);
    final markers = <String>[
      'color:green|label:S|${route.first.latitude},${route.first.longitude}',
      if (route.length > 1)
        'color:red|label:E|${route.last.latitude},${route.last.longitude}',
    ];

    final params = <String, String>{
      'size': '${width}x$height',
      'scale': '$scale',
      'maptype': mapType,
      'path': 'color:$pathColor|weight:$pathWeight|enc:$encoded',
      'key': _apiKey,
    };
    final qs = StringBuffer();
    params.forEach((k, v) {
      if (qs.isNotEmpty) qs.write('&');
      qs..write(Uri.encodeQueryComponent(k))..write('=')..write(Uri.encodeQueryComponent(v));
    });
    for (final m in markers) {
      qs..write('&markers=')..write(Uri.encodeQueryComponent(m));
    }
    return '$_base?$qs';
  }

  /// Reduce point count to at most [maxPoints] by uniform stride sampling
  /// (always preserving the first and last points).
  static List<LatLng> _downsample(List<LatLng> pts, int maxPoints) {
    if (pts.length <= maxPoints) return pts;
    final step = pts.length / maxPoints;
    final out = <LatLng>[];
    for (var i = 0; i < maxPoints; i++) {
      out.add(pts[(i * step).floor()]);
    }
    if (out.last != pts.last) out.add(pts.last);
    return out;
  }

  /// Google encoded polyline algorithm format.
  static String _encodePolyline(List<LatLng> points) {
    final sb = StringBuffer();
    int lastLat = 0, lastLng = 0;
    for (final p in points) {
      final lat = (p.latitude * 1e5).round();
      final lng = (p.longitude * 1e5).round();
      _encodeValue(lat - lastLat, sb);
      _encodeValue(lng - lastLng, sb);
      lastLat = lat;
      lastLng = lng;
    }
    return sb.toString();
  }

  static void _encodeValue(int v, StringBuffer sb) {
    var value = v < 0 ? ~(v << 1) : (v << 1);
    while (value >= 0x20) {
      sb.writeCharCode((0x20 | (value & 0x1f)) + 63);
      value >>= 5;
    }
    sb.writeCharCode(value + 63);
  }
}
