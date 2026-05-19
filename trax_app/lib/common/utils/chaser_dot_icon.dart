import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;

import '../../theme/app_theme.dart';

/// Renders the small blue "chaser" dot used to indicate trail direction
/// of travel. A solid blue disc with a white halo so it stays visible on
/// both satellite and road tiles. Sized in logical pixels (caller passes
/// the device pixel ratio).
class ChaserDotIcon {
  ChaserDotIcon._();

  static gmap.BitmapDescriptor? _cached;
  static double? _cachedDpr;

  /// Raw PNG bytes — convenient for AMap which uses
  /// `BitmapDescriptor.fromBytes`.
  static Uint8List? _cachedBytes;

  static Future<gmap.BitmapDescriptor> bitmap(double dpr) async {
    if (_cached != null && _cachedDpr == dpr) return _cached!;
    final bytes = await _png(dpr);
    final bd = gmap.BitmapDescriptor.bytes(
      bytes,
      width: 14,
      height: 14,
    );
    _cached = bd;
    _cachedDpr = dpr;
    return bd;
  }

  /// PNG bytes of the dot, cached per dpr. Used by callers (AMap) that
  /// need raw bytes rather than a `BitmapDescriptor`.
  static Future<Uint8List> bytes(double dpr) async {
    if (_cachedBytes != null && _cachedDpr == dpr) return _cachedBytes!;
    _cachedBytes = await _png(dpr);
    _cachedDpr = dpr;
    return _cachedBytes!;
  }

  static Future<Uint8List> _png(double dpr) async {
    // 14 logical px diameter dot — meaningfully larger than the 2px route
    // line so it reads as a moving "head" instead of a thickening of the
    // line itself.
    final size = 14.0 * dpr;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    final c = Offset(size / 2, size / 2);
    final haloR = size / 2;
    final dotR = haloR - 2.0 * dpr;

    canvas.drawCircle(c, haloR, Paint()..color = Colors.white);
    canvas.drawCircle(c, dotR, Paint()..color = AppColors.primary);

    final pic = recorder.endRecording();
    final img = await pic.toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }
}
