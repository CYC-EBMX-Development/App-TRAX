import 'dart:math' as math;

import 'package:amap_flutter_base/amap_flutter_base.dart' as amap;
import 'package:amap_flutter_map/amap_flutter_map.dart' as amap_map;
import 'package:flutter/material.dart' show Color, Offset;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;

import 'coord_transform.dart';
import 'start_end_marker_icons_amap.dart';
import '../services/map_service.dart';
import '../../theme/app_theme.dart';

/// Helpers that bridge the rest of the app — which standardises on
/// `google_maps_flutter.LatLng` (WGS-84) as the in-memory coord type — to
/// the AMap SDK, which uses its own `amap_flutter_base.LatLng` and expects
/// GCJ-02 coordinates inside Chinese mainland.
///
/// All conversions go through [CoordTransform.wgs84ToGcj02] which is a
/// no-op outside the mainland (so an overseas point handed to AMap by
/// mistake still renders correctly).
class AmapAdapter {
  AmapAdapter._();

  /// Build the AMap api-key container from the dart-define key pair.
  static amap.AMapApiKey apiKey() => amap.AMapApiKey(
        androidKey: MapService.amapAndroidSdkKey,
        iosKey: MapService.amapIosSdkKey,
      );

  /// AMap SDK compliance declaration. Passed to every [AMapWidget] so the
  /// native SDK knows the user has been informed and has consented to the
  /// privacy policy (required by Chinese regulations).
  static amap.AMapPrivacyStatement privacy() =>
      const amap.AMapPrivacyStatement(
        hasContains: true,
        hasShow: true,
        hasAgree: true,
      );

  /// Convert a WGS-84 google [LatLng] to a GCJ-02 AMap [LatLng].
  static amap.LatLng toAmap(gmap.LatLng p) {
    final c = CoordTransform.wgs84ToGcj02(p.latitude, p.longitude);
    return amap.LatLng(c.lat, c.lng);
  }

  /// Convert a list of WGS-84 google points to a list of GCJ-02 AMap points.
  static List<amap.LatLng> toAmapList(List<gmap.LatLng> points) =>
      points.map(toAmap).toList(growable: false);

  /// Convert a GCJ-02 AMap [LatLng] back to a WGS-84 google [LatLng]. Used
  /// to handle map taps where the SDK hands us GCJ-02 coordinates but the
  /// rest of the app expects WGS-84.
  static gmap.LatLng fromAmap(amap.LatLng p) {
    final c = CoordTransform.gcj02ToWgs84(p.latitude, p.longitude);
    return gmap.LatLng(c.lat, c.lng);
  }

  /// Build a polyline overlay from a WGS-84 route.
  ///
  /// Default width is `8` (doubled from the previous default of `4`) to
  /// match the bumped trail-line styling used app-wide.
  static amap_map.Polyline routePolyline(List<gmap.LatLng> points,
      {double width = 8, Color? color}) {
    return amap_map.Polyline(
      points: toAmapList(points),
      color: color ?? AppColors.primary,
      width: width,
    );
  }

  /// Start + finish marker pair. Uses the flat circular green-S / red-F
  /// badges (see [StartEndMarkerIconsAmap]) so the trail start point is
  /// visually distinct from user checkpoints, which render as the default
  /// AMap red teardrop pins.
  ///
  /// For closed loops (start within ~10 m of finish — lap trails) we only
  /// emit the S marker, otherwise F would be drawn on top and the user
  /// would never see S.
  static Set<amap_map.Marker> startFinishMarkers(List<gmap.LatLng> points) {
    if (points.isEmpty) return const {};
    final start = points.first;
    final end = points.last;
    final isLoop = points.length < 2 ||
        _approxMeters(start, end) < 10;
    final set = <amap_map.Marker>{
      amap_map.Marker(
        position: toAmap(start),
        icon: StartEndMarkerIconsAmap.start,
        anchor: const Offset(0.5, 0.5),
        zIndex: 10,
        infoWindow: const amap_map.InfoWindow(title: 'Start'),
      ),
    };
    if (!isLoop) {
      set.add(amap_map.Marker(
        position: toAmap(end),
        icon: StartEndMarkerIconsAmap.finish,
        anchor: const Offset(0.5, 0.5),
        zIndex: 10,
        infoWindow: const amap_map.InfoWindow(title: 'Finish'),
      ));
    }
    return set;
  }

  /// Cheap equirectangular distance estimate in metres — good enough at
  /// the 10 m threshold we use for loop detection.
  static double _approxMeters(gmap.LatLng a, gmap.LatLng b) {
    const earthR = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLng = (b.longitude - a.longitude) * math.pi / 180.0;
    final meanLat = (a.latitude + b.latitude) / 2 * math.pi / 180.0;
    final x = dLng * math.cos(meanLat);
    return earthR * math.sqrt(x * x + dLat * dLat);
  }

  /// Initial camera position centred on the route's midpoint.
  static amap_map.CameraPosition initialCamera(List<gmap.LatLng> points,
      {double zoom = 14}) {
    if (points.isEmpty) {
      return const amap_map.CameraPosition(
        target: amap.LatLng(39.909187, 116.397451), // Beijing fallback
        zoom: 10,
      );
    }
    return amap_map.CameraPosition(
      target: toAmap(points[points.length ~/ 2]),
      zoom: zoom,
    );
  }
}
