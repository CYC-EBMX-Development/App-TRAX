import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../services/map_provider.dart';
import '../utils/map_region.dart';
import '../../models/ebike.dart';
import '../../models/race_live_data.dart';
import '../../models/ride_lap.dart';
import '../../models/trail.dart';
// Google-variant pages (existing, unchanged).
import '../../screens/trails/trail_detail_page.dart';
import '../../screens/trails/trail_record_page.dart';
import '../../screens/trails/trail_save_page.dart';
import '../../screens/ride/free_ride_page.dart';
import '../../screens/ride/lap_timer_page.dart';
import '../../screens/ride/race_tracking_page.dart';
import '../../screens/ride/ride_summary_page.dart';
import '../../screens/ride/ride_replay_page.dart';
import '../../screens/ride/trail_checkpoints_page.dart';
// AMap-variant pages (parallel CN code path).
import '../../screens/trails/amap/trail_detail_page_amap.dart';
import '../../screens/trails/amap/trail_record_page_amap.dart';
import '../../screens/trails/amap/trail_save_page_amap.dart';
import '../../screens/ride/amap/free_ride_page_amap.dart';
import '../../screens/ride/amap/lap_timer_page_amap.dart';
import '../../screens/ride/amap/lap_timer_setup_page_amap.dart';
import '../../screens/ride/amap/race_replay_page_amap.dart';
import '../../screens/ride/lap_timer_setup_page.dart';
import '../../screens/ride/race_replay_page.dart';
import '../../screens/ride/amap/race_tracking_page_amap.dart';
import '../../screens/ride/amap/ride_summary_page_amap.dart';
import '../../screens/ride/amap/ride_replay_page_amap.dart';
import '../../screens/ride/amap/trail_checkpoints_page_amap.dart';

/// Centralised entry point for opening any map-bearing page in the app.
///
/// Callers should NOT push the concrete Google / AMap page directly — they
/// should always go through [MapRouter] so the right variant is chosen based
/// on:
///   * **Existing data** (trail / ride / race already in the DB): look at
///     the data's origin coordinate(s).
///   * **New recording** (record / lap timer / race host / free ride): look
///     at the user's current location-derived provider
///     ([MapProviderService.current]).
///
/// This guarantees a Hong Kong user opening a Beijing trail still sees AMap,
/// and a Beijing user opening a London trail still sees Google.
class MapRouter {
  MapRouter._();

  // ───────── Trails ──────────────────────────────────────────────────

  /// Open Trail Detail. Provider chosen by the trail's start coordinate.
  static Future<bool?> openTrailDetail(BuildContext context, Trail trail) {
    final lat = trail.startLatitude;
    final lng = trail.startLongitude;
    final provider = (lat != null && lng != null)
        ? MapRegion.providerForCoord(lat, lng)
        : MapProviderService.current;
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => provider == MapProvider.amap
            ? TrailDetailPageAmap(trail: trail)
            : TrailDetailPage(trail: trail),
      ),
    );
  }

  /// Open Trail Record. New recording → current-location provider.
  static Future<bool?> openTrailRecord(BuildContext context) async {
    await MapProviderService.ensureResolved();
    if (!context.mounted) return null;
    final provider = MapRegion.providerForCurrentLocation();
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => provider == MapProvider.amap
            ? const TrailRecordPageAmap()
            : const TrailRecordPage(),
      ),
    );
  }

  /// Open Trail Save preview after recording. Provider chosen by the
  /// just-recorded route's origin.
  static Future<bool?> openTrailSave(
    BuildContext context, {
    required List<Map<String, dynamic>> points,
    required List<LatLng> route,
  }) {
    final provider = MapRegion.providerForRoute(route);
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => provider == MapProvider.amap
            ? TrailSavePageAmap(points: points, route: route)
            : TrailSavePage(points: points, route: route),
      ),
    );
  }

  // ───────── Rides / Races ───────────────────────────────────────────

  /// Open Lap Timer. Provider chosen by the trail's start coordinate. Set
  /// [replace] to use `pushReplacement` (typical when arriving from a
  /// setup/preparation screen).
  static Future<dynamic> openLapTimer(
    BuildContext context, {
    required EBike selectedBike,
    required Trail trail,
    required int targetLaps,
    LatLng? startLocation,
    bool autoStart = false,
    bool replace = false,
  }) {
    final lat = trail.startLatitude;
    final lng = trail.startLongitude;
    final provider = (lat != null && lng != null)
        ? MapRegion.providerForCoord(lat, lng)
        : MapProviderService.current;
    final route = MaterialPageRoute(
      builder: (_) => provider == MapProvider.amap
          ? LapTimerPageAmap(
              selectedBike: selectedBike,
              trail: trail,
              targetLaps: targetLaps,
              startLocation: startLocation,
              autoStart: autoStart,
            )
          : LapTimerPage(
              selectedBike: selectedBike,
              trail: trail,
              targetLaps: targetLaps,
              startLocation: startLocation,
              autoStart: autoStart,
            ),
    );
    final nav = Navigator.of(context);
    return replace ? nav.pushReplacement(route) : nav.push(route);
  }

  /// Open Race Tracking. Race region is not yet known at navigation time;
  /// fall back to the user-level provider. Set [replace] to use
  /// `pushReplacement` (used when transitioning from a race-detail / waiting
  /// screen into the live tracking screen).
  /// TODO(phase3): preload race meta and branch on its start point.
  static Future<dynamic> openRaceTracking(
    BuildContext context, {
    required int raceId,
    bool replace = false,
  }) {
    final provider = MapProviderService.current;
    final route = MaterialPageRoute(
      builder: (_) => provider == MapProvider.amap
          ? RaceTrackingPageAmap(raceId: raceId)
          : RaceTrackingPage(raceId: raceId),
    );
    final nav = Navigator.of(context);
    return replace ? nav.pushReplacement(route) : nav.push(route);
  }

  /// Open Ride Summary. The ride's start coordinate is not on the
  /// `RideRecord` model (would require an extra /points fetch); fall back to
  /// the user-level provider. Set [replace] to use `pushReplacement`
  /// (typical when arriving from a just-finished recording flow).
  /// TODO(phase3): preload the first point and branch on it.
  static Future<dynamic> openRideSummary(
    BuildContext context, {
    required int rideId,
    bool replace = false,
  }) {
    final provider = MapProviderService.current;
    final route = MaterialPageRoute(
      builder: (_) => provider == MapProvider.amap
          ? RideSummaryPageAmap(rideId: rideId)
          : RideSummaryPage(rideId: rideId),
    );
    final nav = Navigator.of(context);
    return replace ? nav.pushReplacement(route) : nav.push(route);
  }

  /// Open Ride Replay. Provider chosen by the first point's region.
  static Future<dynamic> openRideReplay(
    BuildContext context, {
    required List<Map<String, dynamic>> points,
    required String rideName,
    List<RideLap> laps = const [],
  }) {
    final origin = _firstCoord(points);
    final provider = origin != null
        ? MapRegion.providerForCoord(origin.latitude, origin.longitude)
        : MapProviderService.current;
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => provider == MapProvider.amap
            ? RideReplayPageAmap(points: points, rideName: rideName, laps: laps)
            : RideReplayPage(points: points, rideName: rideName, laps: laps),
      ),
    );
  }

  /// Open Race Replay. Routes through provider chosen by current location
  /// since the riders' rides are arbitrary GPS routes.
  static Future<dynamic> openRaceReplay(
    BuildContext context, {
    required String raceName,
    required int targetLaps,
    required List<RiderLiveInfo> riders,
    bool isLaps = false,
    int? trailId,
  }) async {
    await MapProviderService.ensureResolved();
    if (!context.mounted) return null;
    final provider = MapRegion.providerForCurrentLocation();
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => provider == MapProvider.amap
            ? RaceReplayPageAmap(
                raceName: raceName,
                targetLaps: targetLaps,
                riders: riders,
                isLaps: isLaps,
                trailId: trailId,
              )
            : RaceReplayPage(
                raceName: raceName,
                targetLaps: targetLaps,
                riders: riders,
                isLaps: isLaps,
                trailId: trailId,
              ),
      ),
    );
  }

  /// Open Lap Timer Setup. Provider chosen by current location since the
  /// trail is selected inside the page.
  static Future<dynamic> openLapTimerSetup(
    BuildContext context, {
    required EBike selectedBike,
  }) async {
    await MapProviderService.ensureResolved();
    if (!context.mounted) return null;
    final provider = MapRegion.providerForCurrentLocation();
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => provider == MapProvider.amap
            ? LapTimerSetupPageAmap(selectedBike: selectedBike)
            : LapTimerSetupPage(selectedBike: selectedBike),
      ),
    );
  }

  /// Open Free Ride. New recording → current-location provider.
  static Future<dynamic> openFreeRide(
    BuildContext context, {
    required EBike selectedBike,
  }) async {
    await MapProviderService.ensureResolved();
    if (!context.mounted) return null;
    final provider = MapRegion.providerForCurrentLocation();
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => provider == MapProvider.amap
            ? FreeRidePageAmap(selectedBike: selectedBike)
            : FreeRidePage(selectedBike: selectedBike),
      ),
    );
  }

  /// Open Trail Checkpoints (per-user picker, up to 4 CPs). Provider is
  /// chosen by the trail's start coordinate so the picker always renders
  /// on the right basemap.
  static Future<dynamic> openTrailCheckpoints(
    BuildContext context, {
    required int trailId,
    String? trailName,
    double? trailStartLat,
    double? trailStartLng,
  }) {
    final provider = (trailStartLat != null && trailStartLng != null)
        ? MapRegion.providerForCoord(trailStartLat, trailStartLng)
        : MapProviderService.current;
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => provider == MapProvider.amap
            ? TrailCheckpointsPageAmap(
                trailId: trailId, trailName: trailName)
            : TrailCheckpointsPage(trailId: trailId, trailName: trailName),
      ),
    );
  }

  static LatLng? _firstCoord(List<Map<String, dynamic>> points) {
    for (final p in points) {
      final lat = p['latitude'];
      final lng = p['longitude'];
      if (lat is num && lng is num && (lat != 0 || lng != 0)) {
        return LatLng(lat.toDouble(), lng.toDouble());
      }
    }
    return null;
  }
}
