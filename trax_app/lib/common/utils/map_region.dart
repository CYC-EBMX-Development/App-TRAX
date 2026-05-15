import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'coord_transform.dart';
import '../services/map_provider.dart';

/// Decides which map provider (Google vs. AMap) should be used for a given
/// piece of data. The rule is purely data-driven so that a Hong Kong user
/// opening a trail recorded in Beijing still sees the AMap variant — and a
/// Beijing user opening a trail recorded in Switzerland still sees Google.
class MapRegion {
  MapRegion._();

  /// True when the coordinate lies inside Chinese mainland (HK/MO/TW are
  /// treated as overseas to keep parity with the official map SDKs).
  static bool isMainlandCoord(double lat, double lng) =>
      CoordTransform.isInChinaMainland(lat, lng);

  static bool isMainlandLatLng(LatLng p) => isMainlandCoord(p.latitude, p.longitude);

  /// Provider chosen for a single coordinate (a trail / ride start point).
  static MapProvider providerForCoord(double lat, double lng) =>
      isMainlandCoord(lat, lng) ? MapProvider.amap : MapProvider.google;

  /// Provider chosen for a list of route points — uses the FIRST non-zero
  /// point as the canonical origin. Falls back to the current user-level
  /// provider (from [MapProviderService]) when the list is empty.
  static MapProvider providerForRoute(List<LatLng> points) {
    for (final p in points) {
      if (p.latitude == 0 && p.longitude == 0) continue;
      return providerForCoord(p.latitude, p.longitude);
    }
    return MapProviderService.current;
  }

  /// Provider chosen based on the user's current GPS-derived location.
  /// Used for *new* recordings (record / race / lap timer) where no data
  /// origin exists yet.
  static MapProvider providerForCurrentLocation() => MapProviderService.current;
}
