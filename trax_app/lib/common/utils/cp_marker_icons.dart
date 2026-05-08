import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../theme/app_theme.dart';

/// Shared numbered checkpoint marker icon for Google Maps.
///
/// Renders a circular orange pin with a white border and the sequence
/// number centered. Results are cached per (devicePixelRatio, seq) so the
/// expensive picture rendering only happens once per app session.
class CpMarkerIcons {
  CpMarkerIcons._();

  static final Map<String, BitmapDescriptor> _cache = {};

  /// Returns a cached numbered marker bitmap, or null if not yet built.
  /// Use [warm] to pre-build before painting frames.
  static BitmapDescriptor? get(BuildContext context, int seq) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return _cache['${dpr}_$seq'];
  }

  /// Returns a numbered marker if cached, otherwise the default orange pin.
  static BitmapDescriptor getOrFallback(BuildContext context, int seq) {
    return get(context, seq) ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
  }

  /// Builds and caches numbered markers for all of [seqs]. Returns true
  /// when at least one new bitmap was added (caller should setState).
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

  /// Build the full Set<Marker> for a checkpoint positions map using the
  /// shared numbered-circle style. Triggers async warm() in the background
  /// and invokes [onWarmed] (typically `() => setState((){})`) once the
  /// numbered bitmaps are ready, so callers do not have to manage warming
  /// themselves. Use this for ALL maps that display ride/replay CP pins
  /// to keep the style globally consistent.
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
          markerId: MarkerId('${idPrefix}_${entry.key}'),
          position: entry.value,
          icon: getOrFallback(context, entry.key),
          // Keep CP pins below rider markers so riders always sit on top.
          zIndex: 0,
          infoWindow: InfoWindow(title: 'CP${entry.key}'),
        ),
    };
  }

  static Future<BitmapDescriptor> _build(int seq, double dpr) async {
    // Smaller CP pin so the rider markers visually dominate the map.
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
    return BitmapDescriptor.bytes(
      byteData!.buffer.asUint8List(),
      width: size / dpr,
      height: size / dpr,
    );
  }
}
