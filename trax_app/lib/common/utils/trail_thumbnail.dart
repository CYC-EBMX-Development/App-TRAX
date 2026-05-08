import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../network/trax_api.dart';
import 'static_map_url.dart';

/// Process-lifetime cache of trail-id → static-map PNG bytes.
final Map<int, Uint8List> trailThumbCache = {};

/// Outcome of attempting to load a trail thumbnail.
class TrailThumbnailResult {
  final Uint8List? bytes;
  final bool failed;
  const TrailThumbnailResult({this.bytes, this.failed = false});
}

/// Fetch a Google Static Map PNG of [trailId]'s recorded route.
///
/// Returns a cached result instantly when available, otherwise downloads via
/// Dio (with the local debug PROXY 127.0.0.1:7897 in `kDebugMode`).
Future<TrailThumbnailResult> loadTrailThumbnail(int trailId) async {
  final cached = trailThumbCache[trailId];
  if (cached != null) {
    return TrailThumbnailResult(bytes: cached);
  }

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
  final url = StaticMapUrl.forRoute(pts);
  if (url == null) return const TrailThumbnailResult(failed: true);

  try {
    final dio = Dio();
    // In debug mode, route the Google Static Maps request through the local
    // dev proxy — required on networks where direct access to
    // maps.googleapis.com is blocked. Mirrors the pattern used in
    // trail_detail_page / trail_save_page / trail_record_page.
    if (kDebugMode) {
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.findProxy = (uri) => 'PROXY 127.0.0.1:7897';
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      };
    }
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
      trailThumbCache[trailId] = bytes;
      return TrailThumbnailResult(bytes: bytes);
    }
    return const TrailThumbnailResult(failed: true);
  } catch (_) {
    return const TrailThumbnailResult(failed: true);
  }
}
