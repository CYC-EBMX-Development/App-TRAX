import 'dart:async';

import 'package:amap_flutter_location/amap_flutter_location.dart';
import 'package:amap_flutter_location/amap_location_option.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../utils/coord_transform.dart';
import 'map_service.dart';

/// Unified, dual-source geolocation.
///
/// Two independent providers are queried **concurrently** and the first one
/// to return a usable fix wins:
///
///  * **Geolocator** (CoreLocation on iOS, Google Play Services on Android) —
///    works worldwide, including indoors via Apple/Google Wi-Fi positioning.
///    In mainland China the GMS network-location server is unreachable, so on
///    Android-in-China it only succeeds outdoors (satellite lock).
///  * **AMap location SDK** — has its own Wi-Fi/cell positioning database that
///    works indoors in mainland China without Google, but has no data abroad.
///
/// Racing the two means: indoors-in-China → AMap wins; abroad → Geolocator
/// wins; outdoors anywhere → whichever locks first. The caller therefore gets
/// a fix in far more situations than either source alone.
///
/// All fixes are normalised to **WGS-84** (the app's in-memory datum). AMap
/// returns GCJ-02, which is converted back via [CoordTransform.gcj02ToWgs84].
class LocationService {
  LocationService._();

  static bool _amapInited = false;

  /// One-time AMap SDK setup: privacy compliance + api keys. Safe to call
  /// repeatedly; only the first call does work. Must run before the first
  /// AMap location request.
  static void _ensureAmapInit() {
    if (_amapInited) return;
    _amapInited = true;
    try {
      // Required by Chinese regulations — without consent the SDK refuses
      // to locate. The map widget already declares the same consent.
      AMapFlutterLocation.updatePrivacyShow(true, true);
      AMapFlutterLocation.updatePrivacyAgree(true);
      AMapFlutterLocation.setApiKey(
        MapService.amapAndroidSdkKey,
        MapService.amapIosSdkKey,
      );
    } catch (_) {
      // Plugin/native not available — AMap branch will simply yield nothing.
    }
  }

  /// Ensure location permission is granted, prompting if needed.
  /// Returns false when denied (or denied-forever).
  static Future<bool> ensurePermission() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      return perm != LocationPermission.denied &&
          perm != LocationPermission.deniedForever;
    } catch (_) {
      return false;
    }
  }

  /// Race both providers and return the first usable WGS-84 fix, or null when
  /// neither produces one within [timeout].
  ///
  /// When [allowLastKnown] is true (default) the Geolocator branch first
  /// returns the OS cached fix instantly when present — cheap and good enough
  /// for region/provider resolution. Pass false to force a fresh fix.
  static Future<LatLng?> getFix({
    Duration timeout = const Duration(seconds: 8),
    bool allowLastKnown = true,
  }) async {
    if (!await ensurePermission()) return null;

    final completer = Completer<LatLng?>();
    var pending = 2;
    void settle(LatLng? fix) {
      if (completer.isCompleted) return;
      if (fix != null) {
        completer.complete(fix);
        return;
      }
      pending -= 1;
      if (pending == 0) completer.complete(null);
    }

    unawaited(_geolocatorFix(timeout, allowLastKnown)
        .then(settle, onError: (_) => settle(null)));
    unawaited(_amapFix(timeout).then(settle, onError: (_) => settle(null)));

    return completer.future
        .timeout(timeout + const Duration(seconds: 2), onTimeout: () => null);
  }

  /// Geolocator branch — already WGS-84, no datum conversion.
  static Future<LatLng?> _geolocatorFix(
      Duration timeout, bool allowLastKnown) async {
    Position? pos;
    if (allowLastKnown) {
      try {
        pos = await Geolocator.getLastKnownPosition();
      } catch (_) {}
    }
    if (pos == null) {
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            // Medium maps to BALANCED on Android, which permits a
            // network/Wi-Fi fix (HIGH forces satellites, which fail indoors).
            accuracy: LocationAccuracy.medium,
            timeLimit: timeout,
          ),
        );
      } catch (_) {}
    }
    if (pos == null) return null;
    return LatLng(pos.latitude, pos.longitude);
  }

  /// AMap branch — returns GCJ-02, converted to WGS-84 for app use.
  static Future<LatLng?> _amapFix(Duration timeout) async {
    _ensureAmapInit();
    AMapFlutterLocation? loc;
    StreamSubscription<Map<String, Object>>? sub;
    final completer = Completer<LatLng?>();
    try {
      loc = AMapFlutterLocation();
      sub = loc.onLocationChanged().listen((result) {
        if (completer.isCompleted) return;
        final code = (result['errorCode'] as num?)?.toInt();
        final lat = (result['latitude'] as num?)?.toDouble();
        final lng = (result['longitude'] as num?)?.toDouble();
        if ((code == null || code == 0) &&
            lat != null &&
            lng != null &&
            (lat != 0 || lng != 0)) {
          final wgs = CoordTransform.gcj02ToWgs84(lat, lng);
          completer.complete(LatLng(wgs.lat, wgs.lng));
        } else {
          completer.complete(null);
        }
      });
      loc.setLocationOption(AMapLocationOption(
        onceLocation: true,
        needAddress: false,
        locationMode: AMapLocationMode.Hight_Accuracy,
      ));
      loc.startLocation();
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      try {
        await sub?.cancel();
      } catch (_) {}
      try {
        loc?.stopLocation();
        loc?.destroy();
      } catch (_) {}
    }
  }
}
