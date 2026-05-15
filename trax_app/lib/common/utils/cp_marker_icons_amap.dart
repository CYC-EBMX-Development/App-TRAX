import 'dart:ui' as ui;
import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../../theme/app_theme.dart';
import 'amap_adapter.dart';

/// AMap counterpart of [CpMarkerIcons]. Same orange numbered-circle look
/// so the visual style stays consistent across providers. Bitmaps are
/// cached per (DPR, sequence index) to amortize rendering cost.
class CpMarkerIconsAmap {
  CpMarkerIconsAmap._();

  static final Map<String, BitmapDescriptor> _cache = {};

  static BitmapDescriptor? get(BuildContext context, int seq) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return _cache['${dpr}_$seq'];
  }

  static BitmapDescriptor getOrFallback(BuildContext context, int seq) {
    return get(context, seq) ?? BitmapDescriptor.defaultMarker;
  }

  static Future<bool> warm(BuildContext context, Iterable<int> seqs) async {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    var changed = false;
    for (final s in seqs) {
      final key = '${dpr}_$s';
      if (_cache.containsKey(key)) continue;
      _cache[key] = await _build(s, dpr);
      changed = true;
    }
    return changed;
  }

  /// Build the full Set<Marker> for a checkpoint positions map. Input
  /// positions are in WGS-84; they are converted to GCJ-02 internally.
  static Set<Marker> buildMarkers(
    BuildContext context,
    Map<int, LatLng> positions, {
    VoidCallback? onWarmed,
    String idPrefix = 'cp',
  }) {
    if (positions.isNotEmpty) {
      // ignore: discarded_futures
      warm(context, positions.keys).then((changed) {
        if (changed && onWarmed != null) onWarmed();
      });
    }
    return {
      for (final entry in positions.entries)
        Marker(
          position: AmapAdapter.toAmap(entry.value),
          icon: getOrFallback(context, entry.key),
          zIndex: 0,
          infoWindow: InfoWindow(title: 'CP${entry.key}'),
        ),
    };
  }

  static Future<BitmapDescriptor> _build(int seq, double dpr) async {
    final r = 11.0 * dpr;
    final borderW = 2.0 * dpr;
    final size = (r + borderW) * 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
    final cx = size / 2;
    final cy = size / 2;
    canvas.drawCircle(
        Offset(cx, cy), r + borderW / 2, Paint()..color = Colors.white);
    canvas.drawCircle(
        Offset(cx, cy), r, Paint()..color = AppColors.primary);
    final tp = TextPainter(
      text: TextSpan(
        text: '$seq',
        style: TextStyle(
          color: Colors.white,
          fontSize: 13 * dpr,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }
}
