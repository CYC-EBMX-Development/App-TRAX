import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';

/// AMap counterpart of [AvatarMarkerIcons]. Returns an AMap
/// [BitmapDescriptor] painted from the rider's avatar PNG bytes (or an
/// initial fallback) so AMap-flavoured screens can show riders the same
/// way the Google variants do.
class AvatarMarkerIconsAmap {
  AvatarMarkerIconsAmap._();

  static final Map<String, BitmapDescriptor> _cache = {};
  static final Map<String, Uint8List> _bytesCache = {};

  static String _key(
      String? url, String name, Color color, bool isMe, bool withLabel) {
    return '${url ?? ''}|$name|${color.toARGB32()}|$isMe|$withLabel';
  }

  static Future<BitmapDescriptor> build(
    BuildContext context, {
    required String? avatarUrl,
    required String name,
    required Color color,
    bool isMe = false,
    bool withLabel = true,
  }) async {
    final key = _key(avatarUrl, name, color, isMe, withLabel);
    final cached = _cache[key];
    if (cached != null) return cached;
    final bytes = await _fetchBytes(avatarUrl);
    final icon =
        await _draw(context, name, color, isMe, bytes, withLabel: withLabel);
    _cache[key] = icon;
    return icon;
  }

  static Future<Uint8List?> _fetchBytes(String? url) async {
    if (url == null || url.isEmpty) return null;
    final cached = _bytesCache[url];
    if (cached != null) return cached;
    try {
      final resp = await Dio().get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (resp.data == null) return null;
      final bytes = Uint8List.fromList(resp.data!);
      _bytesCache[url] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<BitmapDescriptor> _draw(
    BuildContext context,
    String name,
    Color color,
    bool isMe,
    Uint8List? avatarBytes, {
    required bool withLabel,
  }) async {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final displayName = isMe ? 'You' : name.split(' ').first;
    final nameTp = TextPainter(
      text: TextSpan(
        text: displayName,
        style: TextStyle(
          color: Colors.black87,
          fontSize: 11 * dpr,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final circleR = 20 * dpr;
    final borderW = 3 * dpr;
    final gap = 4 * dpr;
    final nameH = nameTp.height;
    final nameBgPad = 4 * dpr;
    final labelW = withLabel ? (nameTp.width + nameBgPad * 2) : 0.0;
    final w = labelW.clamp(circleR * 2 + borderW * 2, 200 * dpr);
    final labelBlock =
        withLabel ? (gap + nameH + nameBgPad * 2 + 2 * dpr) : 0.0;
    final totalH = borderW + circleR * 2 + borderW + labelBlock;
    final cx = w / 2;
    final cy = borderW + circleR;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, totalH));
    canvas.drawCircle(
      Offset(cx, cy),
      circleR + borderW / 2,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(Offset(cx, cy), circleR, Paint()..color = color);
    if (avatarBytes != null) {
      try {
        final codec = await ui.instantiateImageCodec(
          avatarBytes,
          targetWidth: (circleR * 2).toInt(),
          targetHeight: (circleR * 2).toInt(),
        );
        final frame = await codec.getNextFrame();
        final img = frame.image;
        canvas.save();
        final clipPath = Path()
          ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: circleR));
        canvas.clipPath(clipPath);
        final dst = Rect.fromCircle(center: Offset(cx, cy), radius: circleR);
        paintImage(canvas: canvas, rect: dst, image: img, fit: BoxFit.cover);
        canvas.restore();
        img.dispose();
      } catch (_) {
        _drawInitial(canvas, displayName, cx, cy, dpr);
      }
    } else {
      _drawInitial(canvas, displayName, cx, cy, dpr);
    }
    if (withLabel) {
      final nameY = cy + circleR + borderW + gap;
      final nameRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, nameY + nameH / 2 + nameBgPad),
          width: nameTp.width + nameBgPad * 2,
          height: nameH + nameBgPad,
        ),
        Radius.circular(4 * dpr),
      );
      canvas.drawRRect(nameRect, Paint()..color = Colors.white);
      canvas.drawRRect(
        nameRect,
        Paint()
          ..color = color.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 * dpr,
      );
      nameTp.paint(
          canvas, Offset(cx - nameTp.width / 2, nameY + nameBgPad / 2));
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(w.toInt(), totalH.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }

  static void _drawInitial(
      Canvas canvas, String displayName, double cx, double cy, double dpr) {
    final initialTp = TextPainter(
      text: TextSpan(
        text: displayName.isEmpty ? '?' : displayName[0].toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontSize: 18 * dpr,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    initialTp.paint(
        canvas, Offset(cx - initialTp.width / 2, cy - initialTp.height / 2));
  }
}
