import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Shared start/finish marker icons for Google Maps.
///
/// Renders a circular flag-style badge with a single letter (`S` for start,
/// `F` for finish) on a coloured fill (green / red) with a white border.
/// This shape — a flat circular badge — is visually distinct from the
/// default Google Maps teardrop pin used for generic "location" markers.
///
/// Bitmaps are cached and pre-built at app startup via [warm].
class StartEndMarkerIcons {
  StartEndMarkerIcons._();

  static const _greenFill = Color(0xFF1FA85B);
  static const _redFill = Color(0xFFE8413A);
  static BitmapDescriptor? _start;
  static BitmapDescriptor? _finish;

  /// Start (green "S"). Falls back to the default green pin if [warm] has
  /// not completed yet.
  static BitmapDescriptor get start =>
      _start ??
      BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);

  /// Finish/End (red "F"). Falls back to the default red pin if [warm] has
  /// not completed yet.
  static BitmapDescriptor get finish =>
      _finish ??
      BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);

  /// Pre-build both bitmaps once. Safe to call multiple times. Should be
  /// invoked at app startup (e.g. from main()).
  static Future<void> warm() async {
    if (_start != null && _finish != null) return;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final dpr = views.isNotEmpty ? views.first.devicePixelRatio : 3.0;
    _start ??= await _build('S', _greenFill, dpr);
    _finish ??= await _build('F', _redFill, dpr);
  }

  static Future<BitmapDescriptor> _build(
      String text, Color fill, double dpr) async {
    // Reduced size to match the smaller pin style requested.
    // Was 18 / 3 / fontSize 20.
    final r = 11.0 * dpr;
    final borderW = 2.0 * dpr;
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
