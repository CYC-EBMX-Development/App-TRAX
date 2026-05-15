import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../network/trax_api.dart';
import '../services/map_service.dart';
import 'dev_proxy.dart';

/// Process-lifetime cache of trail-id → static-map PNG bytes.
final Map<int, Uint8List> trailThumbCache = {};

/// Disk-cache directory (lazily resolved). Survives across app launches
/// so the Trails page can render instantly on cold start.
Directory? _diskCacheDir;
Future<Directory> _ensureDiskCacheDir() async {
  final cached = _diskCacheDir;
  if (cached != null) return cached;
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/trail_thumbs');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  _diskCacheDir = dir;
  return dir;
}

Future<Uint8List?> _readFromDisk(int trailId) async {
  try {
    final dir = await _ensureDiskCacheDir();
    final f = File('${dir.path}/$trailId.bin');
    if (await f.exists()) {
      final bytes = await f.readAsBytes();
      if (_looksLikeImage(bytes)) return bytes;
    }
  } catch (_) {
    // Disk failures are non-fatal — fall through to network.
  }
  return null;
}

Future<void> _writeToDisk(int trailId, Uint8List bytes) async {
  try {
    final dir = await _ensureDiskCacheDir();
    final f = File('${dir.path}/$trailId.bin');
    await f.writeAsBytes(bytes, flush: false);
  } catch (_) {
    // ignore disk write failures
  }
}

/// Wipe the on-disk cached thumbnail for [trailId]. Call after a trail
/// is re-recorded / re-saved so the next render fetches the new image.
Future<void> invalidateTrailThumb(int trailId) async {
  trailThumbCache.remove(trailId);
  try {
    final dir = await _ensureDiskCacheDir();
    final f = File('${dir.path}/$trailId.bin');
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

/// Outcome of attempting to load a trail thumbnail.
class TrailThumbnailResult {
  final Uint8List? bytes;
  final bool failed;
  const TrailThumbnailResult({this.bytes, this.failed = false});
}

/// Fetch a static-map PNG of [trailId]'s recorded route.
///
/// Resolution order:
///   1. In-memory process cache.
///   2. Server-baked thumbnail via [serverImageUrl] (set by the backend at
///      trail creation, e.g. "/images/trails/42.png"). Preferred when
///      available because it avoids hitting Google directly — important
///      for iOS users in restricted networks.
///   3. Dynamic Google Static Maps fetch as a fallback for legacy trails
///      created before backend pre-baking existed.
Future<TrailThumbnailResult> loadTrailThumbnail(
  int trailId, {
  String? serverImageUrl,
}) async {
  final cached = trailThumbCache[trailId];
  if (cached != null) {
    return TrailThumbnailResult(bytes: cached);
  }

  // 0) Disk cache survives cold starts — instant on subsequent launches.
  final disk = await _readFromDisk(trailId);
  if (disk != null) {
    trailThumbCache[trailId] = disk;
    return TrailThumbnailResult(bytes: disk);
  }

  // 1) Try the server-baked PNG when the trail carries an imageUrl.
  if (serverImageUrl != null && serverImageUrl.isNotEmpty) {
    final fullUrl = _resolveServerImageUrl(serverImageUrl);
    try {
      final dio = Dio();
      final resp = await dio.get<List<int>>(
        fullUrl,
        options: Options(
          responseType: ResponseType.bytes,
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      if (resp.statusCode == 200 && resp.data != null) {
        final bytes = Uint8List.fromList(resp.data!);
        if (_looksLikeImage(bytes)) {
          trailThumbCache[trailId] = bytes;
          unawaited(_writeToDisk(trailId, bytes));
          return TrailThumbnailResult(bytes: bytes);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[trail_thumbnail] server thumb fetch failed for trail $trailId: $e');
      }
      // fall through to dynamic Google fetch
    }
  }

  // 2) Fallback: dynamic Google Static Maps fetch from raw points.
  final resp = await TraxApi.getTrailPoints(trailId);
  if (!resp.isSuccess() || resp.data is! List) {
    return const TrailThumbnailResult(failed: true);
  }
  final pts = (resp.data as List)
      .map((p) {
        final m = p as Map<String, dynamic>;
        return LatLng(
          (m['latitude'] as num).toDouble(),
          (m['longitude'] as num).toDouble(),
        );
      })
      .toList();
  final url = MapService.staticMapUrl(pts);
  if (url == null) return const TrailThumbnailResult(failed: true);
  if (kDebugMode) {
    // ignore: avoid_print
    print('[trail_thumbnail] GET trail=$trailId url=$url');
  }

  try {
    final dio = Dio();
    // In Mac/simulator debug with USE_DEV_PROXY=true, route through
    // local Clash proxy. On real devices (or when the flag is unset) we
    // talk directly to Google.
    applyDevProxy(dio.httpClientAdapter as IOHttpClientAdapter);
    final imgResp = await dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    if (imgResp.statusCode == 200 && imgResp.data != null) {
      final bytes = Uint8List.fromList(imgResp.data!);
      // Sanity check: AMap / Google static maps can hand back a JSON or
      // HTML error body with status 200 (INVALID_USER_KEY, quota
      // exceeded, key not whitelisted for static-map, …). Trying to
      // hand that to `Image.memory` blows up the engine decoder, so
      // detect non-image payloads here and surface a failed result
      // instead.
      if (!_looksLikeImage(bytes)) {
        if (kDebugMode) {
          final preview = String.fromCharCodes(
              bytes.take(160).map((b) => b >= 32 && b < 127 ? b : 0x2e));
          // ignore: avoid_print
          print(
              '[trail_thumbnail] non-image body for trail $trailId (len=${bytes.length}): $preview');
        }
        return const TrailThumbnailResult(failed: true);
      }
      trailThumbCache[trailId] = bytes;
      unawaited(_writeToDisk(trailId, bytes));
      return TrailThumbnailResult(bytes: bytes);
    }
    return const TrailThumbnailResult(failed: true);
  } catch (_) {
    return const TrailThumbnailResult(failed: true);
  }
}

/// Resolve a server-relative thumbnail path to an absolute URL.
/// Strips the trailing "/api" segment from the configured API base so
/// that "/images/trails/42.png" hits the static-resource handler.
String _resolveServerImageUrl(String pathOrUrl) {
  if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
    return pathOrUrl;
  }
  final apiBase = TraxUrl.baseUrlRelease;
  final origin = apiBase.endsWith('/api')
      ? apiBase.substring(0, apiBase.length - 4)
      : apiBase;
  if (pathOrUrl.startsWith('/')) return '$origin$pathOrUrl';
  return '$origin/$pathOrUrl';
}

bool _looksLikeImage(Uint8List b) {
  if (b.length < 8) return false;
  // PNG signature.
  if (b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47 &&
      b[4] == 0x0D &&
      b[5] == 0x0A &&
      b[6] == 0x1A &&
      b[7] == 0x0A) {
    return true;
  }
  // JPEG SOI.
  if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return true;
  // WebP (RIFF....WEBP).
  if (b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return true;
  }
  return false;
}
