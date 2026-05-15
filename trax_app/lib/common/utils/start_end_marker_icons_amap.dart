import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:amap_flutter_map/amap_flutter_map.dart';

/// AMap counterpart of [StartEndMarkerIcons]. Renders flat circular badges
/// (`S` green / `F` red) so the trail's start point is visually distinct
/// from the default red teardrop pin used for user checkpoints.
class StartEndMarkerIconsAmap {
  StartEndMarkerIconsAmap._();

  static const _greenFill = Color(0xFF1FA85B);
  static const _redFill = Color(0xFFE8413A);
  static const _violetFill = Color(0xFF6A00FF);
  static BitmapDescriptor? _start;
  static BitmapDescriptor? _finish;
  static final Map<int, BitmapDescriptor> _numbered = {};

  static BitmapDescriptor get start => _start ?? BitmapDescriptor.defaultMarker;
  static BitmapDescriptor get finish =>
      _finish ?? BitmapDescriptor.defaultMarker;

  /// Synchronous accessor for a numbered waypoint badge. Falls back to the
  /// default marker until [ensureNumbered] has prepared the bitmap.
  static BitmapDescriptor numbered(int n) =>
      _numbered[n] ?? BitmapDescriptor.defaultMarker;

  /// Lazily build (and cache) a numbered waypoint badge in violet.
  static Future<BitmapDescriptor> ensureNumbered(int n) async {
    final cached = _numbered[n];
    if (cached != null) return cached;
    final icon = await _build('$n', _violetFill);
    _numbered[n] = icon;
    return icon;
  }

  static Future<void> warm() async {
    if (_start != null && _finish != null) return;
    // AMap's BitmapDescriptor.fromBytes has no physical-size hint, so the
    // bitmap is rendered at its native pixel size. Keep dimensions modest
    // (Google variant uses width/height hint = size/dpr to get the same
    // visual result with a higher-res bitmap).
    _start ??= await _build('S', _greenFill);
    _finish ??= await _build('F', _redFill);
  }

  static Future<BitmapDescriptor> _build(String text, Color fill) async {
    // Matches the Google variant: r=11, border=2, fontSize=13 (logical px).
    // Render at 3x for crispness on hi-DPI phones; AMap displays it 1:1 in
    // device pixels, so the on-screen size will be ~28 logical px on a 3x
    // device — same as Google Maps after its width/height hint.
    const double scale = 3.0;
    final r = 11.0 * scale;
    final borderW = 2.0 * scale;
    final size = (r + borderW) * 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
    final cx = size / 2;
    final cy = size / 2;
    canvas.drawCircle(
        Offset(cx, cy), r + borderW / 2, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = fill);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: 13 * scale,
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
