import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../utils/coord_transform.dart';
import '../utils/dev_proxy.dart';
import 'map_provider.dart';

/// One driving-route option returned by [MapService.directionsAlternatives].
/// `points` is the densified polyline in WGS-84; `distanceMeters` and
/// `durationSeconds` come straight from the provider when available.
class RouteCandidate {
  final String label; // e.g. "Recommended", "Shortest", "No highways"
  final List<LatLng> points;
  final double? distanceMeters;
  final double? durationSeconds;
  const RouteCandidate({
    required this.label,
    required this.points,
    this.distanceMeters,
    this.durationSeconds,
  });
}

/// A single place / address search hit. [location] is WGS-84.
class PlaceResult {
  final String name;
  final String address;
  final LatLng location;
  const PlaceResult({
    required this.name,
    required this.address,
    required this.location,
  });
}

/// Unified façade for map REST APIs. Internally dispatches to either Google
/// Maps Web Services or AMap Web Services depending on
/// [MapProviderService.current]. All [LatLng] inputs are assumed to be in
/// WGS-84; any GCJ-02 conversion (required for AMap) is done internally.
class MapService {
  MapService._();

  // ---------------------------------------------------------------------------
  // API keys.
  //
  // Google Static Maps / Geocoding / Directions key (browser-key style, must
  // be enabled for the three services in the GCP console).
  static const String googleApiKey =
      'AIzaSyDmzdgVvZu4f5Q7zCKytQ5Syz0RLQzUxng';

  // AMap Web Service key. Apply at https://lbs.amap.com/dev/ and replace.
  // Once obtained, also remember to whitelist the calling host/IP in the
  // AMap console. This is the REST key (Web服务), NOT the Android/iOS SDK key.
  //
  // Inject at build time:
  //   flutter build apk --dart-define=AMAP_KEY=xxxxxxxx
  // (Already wired into scripts/run_android.sh and scripts/build_apk.sh.)
  static const String amapApiKey = String.fromEnvironment(
    'AMAP_KEY',
    defaultValue: 'PLACEHOLDER_AMAP_KEY',
  );

  // AMap native SDK keys. These are different from [amapApiKey] (which is
  // the Web service key) — Android uses a key bound to packageName+SHA1,
  // iOS to bundle id. Both are read at build time via --dart-define.
  //
  // Android key is also injected into AndroidManifest.xml via
  // manifestPlaceholders["AMAP_ANDROID_SDK_KEY"] (see app/build.gradle.kts);
  // the dart-defined value here is what we hand to AMapWidget.apiKey, where
  // the SDK uses it as a runtime cross-check.
  //
  // iOS key is read by AppDelegate.swift from Info.plist (injected via
  // ios/Flutter/AmapKey.xcconfig).
  static const String amapAndroidSdkKey = String.fromEnvironment(
    'AMAP_ANDROID_SDK_KEY',
    defaultValue: '',
  );
  static const String amapIosSdkKey = String.fromEnvironment(
    'AMAP_IOS_SDK_KEY',
    defaultValue: '',
  );

  // ---------------------------------------------------------------------------
  // Public API.

  /// Reverse-geocode a WGS-84 coordinate to a human-readable place string.
  /// Returns null on failure.
  static Future<String?> reverseGeocode(double lat, double lng) async {
    final dio = _dio();
    try {
      if (MapProviderService.useAmap) {
        final c = CoordTransform.wgs84ToGcj02(lat, lng);
        final resp = await dio.get(
          'https://restapi.amap.com/v3/geocode/regeo',
          queryParameters: {
            'key': amapApiKey,
            'location': '${c.lng},${c.lat}', // amap = lng,lat
            'extensions': 'base',
            'output': 'json',
          },
        );
        final json = resp.data as Map<String, dynamic>?;
        if (json == null || json['status'] != '1') return null;
        final regeo = json['regeocode'] as Map<String, dynamic>?;
        return regeo?['formatted_address'] as String?;
      } else {
        final resp = await dio.get(
          'https://maps.googleapis.com/maps/api/geocode/json',
          queryParameters: {
            'latlng': '$lat,$lng',
            'key': googleApiKey,
            'result_type': 'neighborhood|locality|sublocality|route',
            'language': 'en',
          },
        );
        final json = resp.data;
        if (json == null) return null;
        if (json['status'] != 'OK') return null;
        final results = json['results'] as List?;
        if (results == null || results.isEmpty) return null;
        return results[0]['formatted_address'] as String?;
      }
    } catch (_) {
      return null;
    }
  }

  /// Build a static-map image URL framing [route]. Returns null if route is
  /// empty. Inputs are WGS-84; for AMap the points are converted internally.
  static String? staticMapUrl(
    List<LatLng> route, {
    int width = 240,
    int height = 240,
    int scale = 2,
  }) {
    if (route.isEmpty) return null;
    // AMap REST static-map caps the `paths` parameter length (~1024 chars
    // per path, ~2KB total URL). Downsample more aggressively + truncate
    // coordinate precision when using AMap.
    final maxPts = MapProviderService.useAmap ? 40 : 120;
    final pts = _downsample(route, maxPts);
    return MapProviderService.useAmap
        ? _amapStaticUrl(pts, width: width, height: height, scale: scale)
        : _googleStaticUrl(pts, width: width, height: height, scale: scale);
  }

  /// Driving-route polyline through `origin → waypoints → origin` (closed
  /// loop). Returns the densified polyline as WGS-84 points, or null on
  /// failure / empty result.
  static Future<List<LatLng>?> directionsRoundTrip({
    required LatLng origin,
    required List<LatLng> waypoints,
    Duration connectTimeout = const Duration(seconds: 5),
    Duration receiveTimeout = const Duration(seconds: 8),
  }) async {
    if (waypoints.isEmpty) return null;
    final dio = _dio();
    final opts = Options(
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: connectTimeout,
    );
    try {
      if (MapProviderService.useAmap) {
        return await _amapDirections(dio, origin, waypoints, opts);
      } else {
        return await _googleDirections(dio, origin, waypoints, opts);
      }
    } catch (_) {
      return null;
    }
  }

  /// Driving polyline strictly from [a] → [b] (no waypoints, no return
  /// trip). Returned points are densified WGS-84. The first and last
  /// points are the actual road-snapped endpoints chosen by the routing
  /// provider, which is exactly what we want for "snap-to-road" UX —
  /// the caller can use them to replace the user's tap location.
  /// Returns null on failure / empty result.
  static Future<List<LatLng>?> directionsBetween({
    required LatLng a,
    required LatLng b,
    Duration connectTimeout = const Duration(seconds: 5),
    Duration receiveTimeout = const Duration(seconds: 8),
  }) async {
    final dio = _dio();
    final opts = Options(
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: connectTimeout,
    );
    try {
      if (MapProviderService.useAmap) {
        return await _amapLeg(dio, a, b, opts);
      } else {
        return await _googleLeg(dio, a, b, opts);
      }
    } catch (_) {
      return null;
    }
  }

  /// Like [directionsRoundTrip] but returns up to ~3 alternative routes the
  /// user can pick from. AMap is queried with three different routing
  /// strategies (default / shortest / avoid highways) in parallel; Google
  /// is queried once with `alternatives=true`. Empty list means no usable
  /// route was found.
  static Future<List<RouteCandidate>> directionsAlternatives({
    required LatLng origin,
    required List<LatLng> waypoints,
    Duration connectTimeout = const Duration(seconds: 6),
    Duration receiveTimeout = const Duration(seconds: 12),
  }) async {
    if (waypoints.isEmpty) return const [];
    final dio = _dio();
    final opts = Options(
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: connectTimeout,
    );
    try {
      if (MapProviderService.useAmap) {
        return await _amapAlternatives(dio, origin, waypoints, opts);
      } else {
        return await _googleAlternatives(dio, origin, waypoints, opts);
      }
    } catch (_) {
      return const [];
    }
  }

  /// Forward place / address search. Returns up to ~10 ranked results,
  /// each with a display name, an address line and a WGS-84 location.
  /// Empty list on no match or failure.
  static Future<List<PlaceResult>> searchPlaces(
    String query, {
    LatLng? near,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final dio = _dio();
    final opts = Options(
      connectTimeout: timeout,
      receiveTimeout: timeout,
      sendTimeout: timeout,
    );
    try {
      if (MapProviderService.useAmap) {
        return await _amapSearchPlaces(dio, q, near, opts);
      } else {
        return await _googleSearchPlaces(dio, q, near, opts);
      }
    } catch (_) {
      return const [];
    }
  }

  static Future<List<PlaceResult>> _amapSearchPlaces(
    Dio dio,
    String q,
    LatLng? near,
    Options opts,
  ) async {
    // AMap text-search ("place/text"). When [near] is supplied we add a
    // city hint by reverse-geocoding-free fallback: just bias by location
    // via the `location` parameter (sort_rule=weight already considers it).
    final params = <String, dynamic>{
      'key': amapApiKey,
      'keywords': q,
      'offset': '15',
      'page': '1',
      'extensions': 'base',
      'output': 'json',
    };
    if (near != null) {
      final c = CoordTransform.wgs84ToGcj02(near.latitude, near.longitude);
      params['location'] = '${c.lng},${c.lat}';
    }
    final resp = await dio.get(
      'https://restapi.amap.com/v3/place/text',
      queryParameters: params,
      options: opts,
    );
    final json = resp.data as Map<String, dynamic>?;
    if (json == null || json['status'] != '1') return const [];
    final pois = json['pois'] as List?;
    if (pois == null || pois.isEmpty) return const [];
    final out = <PlaceResult>[];
    for (final raw in pois) {
      if (raw is! Map) continue;
      final loc = (raw['location'] as String?) ?? '';
      final parts = loc.split(',');
      if (parts.length != 2) continue;
      final lng = double.tryParse(parts[0]);
      final lat = double.tryParse(parts[1]);
      if (lat == null || lng == null) continue;
      final wgs = CoordTransform.gcj02ToWgs84(lat, lng);
      final name = (raw['name'] as String?) ?? q;
      final addr = [
        raw['pname'],
        raw['cityname'],
        raw['adname'],
        raw['address'],
      ]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join(' · ');
      out.add(PlaceResult(
        name: name,
        address: addr,
        location: LatLng(wgs.lat, wgs.lng),
      ));
    }
    return out;
  }

  static Future<List<PlaceResult>> _googleSearchPlaces(
    Dio dio,
    String q,
    LatLng? near,
    Options opts,
  ) async {
    // Use Geocoding for address queries — no Places API billing required
    // and it returns a `formatted_address` + viewport per result.
    final params = <String, dynamic>{
      'address': q,
      'key': googleApiKey,
      'language': 'en',
    };
    if (near != null) {
      // 50 km bias circle around the user.
      params['bounds'] =
          '${near.latitude - 0.45},${near.longitude - 0.45}|'
          '${near.latitude + 0.45},${near.longitude + 0.45}';
    }
    final resp = await dio.get(
      'https://maps.googleapis.com/maps/api/geocode/json',
      queryParameters: params,
      options: opts,
    );
    final json = resp.data;
    if (json == null || json['status'] != 'OK') return const [];
    final results = json['results'] as List?;
    if (results == null || results.isEmpty) return const [];
    final out = <PlaceResult>[];
    for (final raw in results) {
      if (raw is! Map) continue;
      final geom = raw['geometry'] as Map?;
      final loc = geom?['location'] as Map?;
      final lat = (loc?['lat'] as num?)?.toDouble();
      final lng = (loc?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final addr = (raw['formatted_address'] as String?) ?? q;
      out.add(PlaceResult(
        name: addr.split(',').first.trim(),
        address: addr,
        location: LatLng(lat, lng),
      ));
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Google implementations.

  static String _googleStaticUrl(
    List<LatLng> pts, {
    required int width,
    required int height,
    required int scale,
  }) {
    final encoded = _encodePolyline(pts);
    final markers = <String>[
      'color:green|label:S|${pts.first.latitude},${pts.first.longitude}',
      if (pts.length > 1)
        'color:red|label:E|${pts.last.latitude},${pts.last.longitude}',
    ];
    final params = <String, String>{
      'size': '${width}x$height',
      'scale': '$scale',
      'maptype': 'roadmap',
      'path': 'color:0xFF6A00FF|weight:4|enc:$encoded',
      'key': googleApiKey,
    };
    final qs = StringBuffer();
    params.forEach((k, v) {
      if (qs.isNotEmpty) qs.write('&');
      qs
        ..write(Uri.encodeQueryComponent(k))
        ..write('=')
        ..write(Uri.encodeQueryComponent(v));
    });
    for (final m in markers) {
      qs
        ..write('&markers=')
        ..write(Uri.encodeQueryComponent(m));
    }
    return 'https://maps.googleapis.com/maps/api/staticmap?$qs';
  }

  static Future<List<LatLng>?> _googleDirections(
    Dio dio,
    LatLng origin,
    List<LatLng> waypoints,
    Options opts,
  ) async {
    final originStr = '${origin.latitude},${origin.longitude}';
    final wps =
        waypoints.map((w) => '${w.latitude},${w.longitude}').join('|');
    final resp = await dio.get(
      'https://maps.googleapis.com/maps/api/directions/json',
      queryParameters: {
        'origin': originStr,
        'destination': originStr,
        'waypoints': wps,
        'mode': 'driving',
        'key': googleApiKey,
      },
      options: opts,
    );
    final json = resp.data as Map<String, dynamic>?;
    if (json == null || json['status'] != 'OK') return null;
    final routes = json['routes'] as List?;
    if (routes == null || routes.isEmpty) return null;
    final overview = routes[0]['overview_polyline']?['points'] as String?;
    if (overview == null || overview.isEmpty) return null;
    return _decodePolyline(overview);
  }

  // ---------------------------------------------------------------------------
  // AMap implementations.

  static String _amapStaticUrl(
    List<LatLng> pts, {
    required int width,
    required int height,
    required int scale,
  }) {
    // Convert all points to GCJ-02 and pretty-print as lng,lat;lng,lat;…
    // AMap requires 6-decimal precision max for static map paths.
    String fmt(double v) => v.toStringAsFixed(6);
    final gcj = pts
        .map((p) => CoordTransform.wgs84ToGcj02(p.latitude, p.longitude))
        .toList();
    final polyline = gcj.map((c) => '${fmt(c.lng)},${fmt(c.lat)}').join(';');
    // AMap static map: paths=weight,color,opacity,fillcolor,fillopacity:points
    // Weight 4, color 0x6A00FF (primary, no alpha), full opacity.
    final paths = '4,0x6A00FF,1,,:$polyline';
    final start = gcj.first;
    final end = gcj.last;
    final markers = pts.length > 1
        ? 'mid,0x00C853,A:${fmt(start.lng)},${fmt(start.lat)}|mid,0xD32F2F,B:${fmt(end.lng)},${fmt(end.lat)}'
        : 'mid,0x00C853,A:${fmt(start.lng)},${fmt(start.lat)}';
    final params = <String, String>{
      'key': amapApiKey,
      'size': '$width*$height',
      'scale': scale.toString(),
      'paths': paths,
      'markers': markers,
    };
    // NOTE: AMap requires literal `,` `:` `;` separators inside the values of
    // `paths` and `markers`. `Uri.encodeQueryComponent` percent-encodes those
    // which produces `infocode 20003` UNKNOWN_ERROR. We only encode the key
    // and only encode spaces inside the value (which is the only character
    // that needs escaping in well-formed AMap path/marker strings).
    final qs = StringBuffer();
    params.forEach((k, v) {
      if (qs.isNotEmpty) qs.write('&');
      qs
        ..write(Uri.encodeQueryComponent(k))
        ..write('=')
        ..write(v.replaceAll(' ', '%20'));
    });
    return 'https://restapi.amap.com/v3/staticmap?$qs';
  }

  static Future<List<LatLng>?> _amapDirections(
    Dio dio,
    LatLng origin,
    List<LatLng> waypoints,
    Options opts,
  ) async {
    final originGcj =
        CoordTransform.wgs84ToGcj02(origin.latitude, origin.longitude);
    final wpsGcj = waypoints
        .map((w) => CoordTransform.wgs84ToGcj02(w.latitude, w.longitude))
        .toList();

    final originStr = '${originGcj.lng},${originGcj.lat}';
    final waypointsStr =
        wpsGcj.map((c) => '${c.lng},${c.lat}').join(';');

    final resp = await dio.get(
      'https://restapi.amap.com/v3/direction/driving',
      queryParameters: {
        'key': amapApiKey,
        'origin': originStr,
        'destination': originStr,
        'waypoints': waypointsStr,
        // strategy 2 = "distance-shortest" (ignores live traffic and tolls).
        // The user-picked waypoints are already passed in order, and AMap
        // preserves that order; this only controls how the legs between
        // adjacent waypoints are computed (we want the shortest leg, not
        // the fastest by current traffic).
        'strategy': '2',
        'extensions': 'base',
        'output': 'json',
      },
      options: opts,
    );
    final json = resp.data as Map<String, dynamic>?;
    if (json == null || json['status'] != '1') return null;
    final route = json['route'] as Map<String, dynamic>?;
    final paths = route?['paths'] as List?;
    if (paths == null || paths.isEmpty) return null;
    final steps = (paths.first as Map<String, dynamic>)['steps'] as List?;
    if (steps == null) return null;
    final out = <LatLng>[];
    for (final step in steps) {
      final polyline = (step as Map<String, dynamic>)['polyline'] as String?;
      if (polyline == null || polyline.isEmpty) continue;
      for (final pair in polyline.split(';')) {
        final lnglat = pair.split(',');
        if (lnglat.length != 2) continue;
        final lng = double.tryParse(lnglat[0]);
        final lat = double.tryParse(lnglat[1]);
        if (lng == null || lat == null) continue;
        // AMap returns GCJ-02; convert back to WGS-84 so the rest of the
        // app (which stores WGS-84) sees consistent coordinates.
        final wgs = CoordTransform.gcj02ToWgs84(lat, lng);
        out.add(LatLng(wgs.lat, wgs.lng));
      }
    }
    return out.isEmpty ? null : out;
  }

  /// Single-leg driving polyline for AMap (a → b).
  static Future<List<LatLng>?> _amapLeg(
    Dio dio,
    LatLng a,
    LatLng b,
    Options opts,
  ) async {
    final aGcj = CoordTransform.wgs84ToGcj02(a.latitude, a.longitude);
    final bGcj = CoordTransform.wgs84ToGcj02(b.latitude, b.longitude);
    final resp = await dio.get(
      'https://restapi.amap.com/v3/direction/driving',
      queryParameters: {
        'key': amapApiKey,
        'origin': '${aGcj.lng},${aGcj.lat}',
        'destination': '${bGcj.lng},${bGcj.lat}',
        // strategy 2 = distance-shortest (matches Pick-Points UX intent).
        'strategy': '2',
        'extensions': 'base',
        'output': 'json',
      },
      options: opts,
    );
    final json = resp.data as Map<String, dynamic>?;
    if (json == null || json['status'] != '1') return null;
    final paths = (json['route'] as Map<String, dynamic>?)?['paths'] as List?;
    if (paths == null || paths.isEmpty) return null;
    final parsed = _amapPathToCandidate(paths.first as Map<String, dynamic>);
    return parsed?.$1;
  }

  /// Single-leg driving polyline for Google (a → b).
  static Future<List<LatLng>?> _googleLeg(
    Dio dio,
    LatLng a,
    LatLng b,
    Options opts,
  ) async {
    final resp = await dio.get(
      'https://maps.googleapis.com/maps/api/directions/json',
      queryParameters: {
        'origin': '${a.latitude},${a.longitude}',
        'destination': '${b.latitude},${b.longitude}',
        'mode': 'driving',
        'key': googleApiKey,
      },
      options: opts,
    );
    final json = resp.data as Map<String, dynamic>?;
    if (json == null || json['status'] != 'OK') return null;
    final routes = json['routes'] as List?;
    if (routes == null || routes.isEmpty) return null;
    final overview = routes[0]['overview_polyline']?['points'] as String?;
    if (overview == null || overview.isEmpty) return null;
    final pts = _decodePolyline(overview);
    return pts.isEmpty ? null : pts;
  }

  /// Parse one AMap driving "path" object into a (closed) WGS-84 polyline
  /// plus distance/duration fields. Returns null if the path is empty.
  static (List<LatLng>, double?, double?)? _amapPathToCandidate(
      Map<String, dynamic> path) {
    final steps = path['steps'] as List?;
    if (steps == null) return null;
    final pts = <LatLng>[];
    for (final step in steps) {
      final polyline = (step as Map<String, dynamic>)['polyline'] as String?;
      if (polyline == null || polyline.isEmpty) continue;
      for (final pair in polyline.split(';')) {
        final lnglat = pair.split(',');
        if (lnglat.length != 2) continue;
        final lng = double.tryParse(lnglat[0]);
        final lat = double.tryParse(lnglat[1]);
        if (lng == null || lat == null) continue;
        final wgs = CoordTransform.gcj02ToWgs84(lat, lng);
        pts.add(LatLng(wgs.lat, wgs.lng));
      }
    }
    if (pts.isEmpty) return null;
    final dist = double.tryParse('${path['distance']}');
    final dur = double.tryParse('${path['duration']}');
    return (pts, dist, dur);
  }

  static Future<List<RouteCandidate>> _amapAlternatives(
    Dio dio,
    LatLng origin,
    List<LatLng> waypoints,
    Options opts,
  ) async {
    final originGcj =
        CoordTransform.wgs84ToGcj02(origin.latitude, origin.longitude);
    final wpsGcj = waypoints
        .map((w) => CoordTransform.wgs84ToGcj02(w.latitude, w.longitude))
        .toList();
    final originStr = '${originGcj.lng},${originGcj.lat}';
    final waypointsStr = wpsGcj.map((c) => '${c.lng},${c.lat}').join(';');

    // Three classic AMap driving strategies. 0 = recommended (fastest by
    // current traffic), 2 = distance-shortest, 6 = avoid highways/tolls.
    // Each call returns a single best path under that strategy.
    const strategies = <(int, String)>[
      (0, 'Recommended'),
      (2, 'Shortest'),
      (6, 'Scenic'),
    ];
    Future<RouteCandidate?> fetch((int, String) s) async {
      try {
        final resp = await dio.get(
          'https://restapi.amap.com/v3/direction/driving',
          queryParameters: {
            'key': amapApiKey,
            'origin': originStr,
            'destination': originStr,
            'waypoints': waypointsStr,
            'strategy': '${s.$1}',
            'extensions': 'base',
            'output': 'json',
          },
          options: opts,
        );
        final json = resp.data as Map<String, dynamic>?;
        if (json == null || json['status'] != '1') return null;
        final paths = (json['route'] as Map<String, dynamic>?)?['paths'] as List?;
        if (paths == null || paths.isEmpty) return null;
        final parsed =
            _amapPathToCandidate(paths.first as Map<String, dynamic>);
        if (parsed == null) return null;
        return RouteCandidate(
          label: s.$2,
          points: parsed.$1,
          distanceMeters: parsed.$2,
          durationSeconds: parsed.$3,
        );
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait(strategies.map(fetch));
    final out = <RouteCandidate>[];
    final seenKeys = <String>{};
    for (final c in results) {
      if (c == null || c.points.length < 2) continue;
      // Dedupe by total distance rounded to 10 m — different strategies
      // sometimes return the same path.
      final k = c.distanceMeters == null
          ? '${c.points.length}'
          : (c.distanceMeters! / 10).round().toString();
      if (seenKeys.add(k)) out.add(c);
    }
    return out;
  }

  static Future<List<RouteCandidate>> _googleAlternatives(
    Dio dio,
    LatLng origin,
    List<LatLng> waypoints,
    Options opts,
  ) async {
    final originStr = '${origin.latitude},${origin.longitude}';
    final wps =
        waypoints.map((w) => '${w.latitude},${w.longitude}').join('|');
    final resp = await dio.get(
      'https://maps.googleapis.com/maps/api/directions/json',
      queryParameters: {
        'origin': originStr,
        'destination': originStr,
        'waypoints': wps,
        'mode': 'driving',
        'alternatives': 'true',
        'key': googleApiKey,
      },
      options: opts,
    );
    final json = resp.data as Map<String, dynamic>?;
    if (json == null || json['status'] != 'OK') return const [];
    final routes = json['routes'] as List?;
    if (routes == null || routes.isEmpty) return const [];
    final out = <RouteCandidate>[];
    for (var i = 0; i < routes.length; i++) {
      final r = routes[i] as Map<String, dynamic>;
      final overview = r['overview_polyline']?['points'] as String?;
      if (overview == null || overview.isEmpty) continue;
      final pts = _decodePolyline(overview);
      if (pts.length < 2) continue;
      // Sum leg distances/durations.
      double dist = 0, dur = 0;
      for (final leg in (r['legs'] as List? ?? const [])) {
        final l = leg as Map<String, dynamic>;
        dist += (l['distance']?['value'] as num?)?.toDouble() ?? 0;
        dur += (l['duration']?['value'] as num?)?.toDouble() ?? 0;
      }
      out.add(RouteCandidate(
        label: i == 0 ? 'Recommended' : 'Alternative ${i + 1}',
        points: pts,
        distanceMeters: dist == 0 ? null : dist,
        durationSeconds: dur == 0 ? null : dur,
      ));
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Shared helpers.

  static Dio _dio() {
    final d = Dio();
    applyDevProxy(d.httpClientAdapter as IOHttpClientAdapter);
    return d;
  }

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

  static List<LatLng> _decodePolyline(String encoded) {
    final out = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;
    while (index < encoded.length) {
      int b;
      var shift = 0;
      var result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dLat;
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dLng;
      out.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return out;
  }
}

// Silences unused-import lint if dio's io.dart isn't otherwise used.
// ignore: unused_element
typedef _Keep = HttpClient;
