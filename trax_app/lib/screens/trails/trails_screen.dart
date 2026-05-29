import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:amap_flutter_base/amap_flutter_base.dart' as amap;
import 'package:amap_flutter_map/amap_flutter_map.dart' as amap_map;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:shared_preferences/shared_preferences.dart';

import '../../common/network/trax_api.dart';
import '../../common/network/app_response.dart';
import '../../common/services/map_service.dart';
import '../../common/services/map_provider.dart';
import '../../common/utils/amap_adapter.dart';
import '../../common/utils/coord_transform.dart';
import '../../common/utils/trail_thumbnail.dart';
import '../../common/utils/trax_storage_util.dart';
import '../../common/widgets/map_router.dart';
import '../../common/widgets/page_code_badge.dart';
import '../../models/ebike.dart';
import '../../models/trail.dart';
import '../../theme/app_theme.dart';
import '../ride/host_laps_page.dart';
import '../ride/host_race_page.dart';
import '../ride/lap_timer_setup_page.dart';
import 'trail_record_mode.dart';
import 'widgets/trail_detail_inline_sheet.dart';

class TrailsScreen extends StatefulWidget {
  const TrailsScreen({super.key});

  @override
  State<TrailsScreen> createState() => TrailsScreenState();
}

enum _MapLayer { normal, satellite }

class TrailsScreenState extends State<TrailsScreen>
    with SingleTickerProviderStateMixin {
  Future<void> refresh() => _bootstrap();

  final PageController _cardCtrl = PageController(viewportFraction: 0.88);

  MapProvider _provider = MapProvider.google;
  _MapLayer _layer = _MapLayer.normal;

  gmap.GoogleMapController? _gController;
  amap_map.AMapController? _aController;

  gmap.LatLng? _userPos;
  bool _isLoading = true;
  bool _showLayerChoices = false;
  bool _showRecordChoices = false;

  List<Trail> _trails = [];
  int _selectedIdx = 0;
  gmap.LatLng? _nearbyAnchor;
  gmap.LatLng? _cameraCenterCandidate;

  // ───── Trail-detail inline sheet state ───────────────────────────
  // 0.0 = collapsed (trail-card carousel shown), 1.0 = fully expanded
  // (sheet with detail strips shown, cards hidden, map reframed).
  // The same controller drives BOTH the sheet's slide-up animation and
  // the card carousel's slide-down/fade-out animation, so the two are
  // always visually in sync during a tap-flip OR a finger-drag.
  late final AnimationController _detailAnim;
  // Card carousel sits ~170 px tall; the bottom panel's collapsed
  // footprint reserves room for it. The expanded height is computed
  // each frame from `_detailContentKey`'s measured size (or a sensible
  // default until the first measurement lands).
  static const double _kCardArea = 170;
  final GlobalKey _detailContentKey = GlobalKey();
  double? _measuredDetailH; // set after first post-frame measurement.
  // When the detail sheet is fully expanded we tell GoogleMap to reserve
  // this many logical pixels at the bottom for the sheet, so subsequent
  // `newLatLngBounds` fits the route into the *visible* upper area
  // (AMap has no equivalent — we shift its camera via `scrollBy`
  // instead, see `_focusRoute`).
  double _mapBottomInset = 0;

  // Suppress reactive-refresh loops when WE are the ones moving things.
  bool _suppressCameraIdle = false;
  bool _suppressPageChange = false;
  Timer? _suppressCameraIdleTimer;

  final Map<String, List<gmap.LatLng>> _routeCache = {};
  final Map<int, Uint8List?> _thumbCache = {};
  final Set<int> _thumbLoading = <int>{};
  List<gmap.LatLng> _selectedRoute = const [];
  // For AMap: marker auto-IDs are generated at construction time, so we
  // record `marker.id -> trail index` and look up taps through this map.
  final Map<String, int> _amapTrailMarkerIdx = {};

  @override
  void initState() {
    super.initState();
    _detailAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      lowerBound: 0,
      upperBound: 1,
    );
    MapProviderService.providerNotifier.addListener(_onProviderChanged);
    _bootstrap();
  }

  void _onProviderChanged() {
    final next = MapProviderService.current;
    if (!mounted || next == _provider) return;
    setState(() => _provider = next);
  }

  @override
  void dispose() {
    MapProviderService.providerNotifier.removeListener(_onProviderChanged);
    _suppressCameraIdleTimer?.cancel();
    _detailAnim.dispose();
    _cardCtrl.dispose();
    _gController?.dispose();
    // _aController is disposed automatically by AMapWidget.dispose().
    super.dispose();
  }

  /// Wrap a programmatic camera move so the resulting `onCameraIdle` /
  /// `onCameraMoveEnd` callback does NOT trigger a nearby re-sort. Without
  /// this guard, `_focusRoute` would feedback-loop with `_refreshNearbyByAnchor`.
  void _markProgrammaticCameraMove() {
    _suppressCameraIdle = true;
    _suppressCameraIdleTimer?.cancel();
    _suppressCameraIdleTimer = Timer(
      const Duration(milliseconds: 700),
      () => _suppressCameraIdle = false,
    );
  }

  Future<void> _bootstrap() async {
    setState(() => _isLoading = true);
    // Get the user's GPS fix FIRST. On a cold start the OS permission dialog
    // is shown inside `_fetchUserLocation`, so the background resolver in
    // `MapProviderService` would otherwise time out before the user grants
    // permission and `current` would stay at the default Google provider —
    // which is wrong in mainland China.
    await _fetchUserLocation();
    if (_userPos != null) {
      await MapProviderService.applyForCoordinate(
        _userPos!.latitude,
        _userPos!.longitude,
      );
    } else {
      // No GPS yet (web / permission denied). Wait briefly for the
      // background GPS resolver to settle before snapshotting.
      await MapProviderService.ensureResolved();
    }
    _provider = MapProviderService.current;
    if (!mounted) return;
    // Dismiss the full-screen spinner as soon as the correct basemap is
    // chosen — testers were seeing the spinner persist for ~10s after the
    // Google→AMap switch on cold start in CN, because we used to await
    // the trail-list network call before clearing it. Trails fetch in
    // the background and the carousel simply appears when ready.
    setState(() => _isLoading = false);
    unawaited(_loadTrails());
  }

  Future<void> _fetchUserLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      // Try the cached last-known fix FIRST — returns instantly when the
      // OS has any prior reading, which is the common case (the user has
      // used other GPS apps, or just opened the system map). This lets us
      // pick the right basemap (Google vs AMap) without waiting for a
      // fresh satellite lock.
      Position? pos;
      try {
        pos = await Geolocator.getLastKnownPosition();
      } catch (_) {}
      // Upgrade to a fresh fix only when there's nothing cached, and cap
      // it so we never block the spinner for more than a few seconds.
      pos ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
      if (!mounted) return;
      setState(() {
        _userPos = gmap.LatLng(pos!.latitude, pos.longitude);
      });
    } catch (_) {}
  }

  Future<void> _loadTrails() async {
    final anchor = _nearbyAnchor ?? _userPos;
    // Prefer the nearby endpoint when we know where to look. Fall back to
    // the full visible list (e.g. first launch on web with no GPS, OR when
    // the user has no trails within the 20km radius — without this we'd
    // show an empty map for anyone whose recorded trails sit in another
    // city).
    AppResponse resp;
    if (anchor != null) {
      resp = await TraxApi.getNearbyTrails(
        lat: anchor.latitude,
        lng: anchor.longitude,
      );
      final empty = resp.isSuccess() &&
          resp.data is List &&
          (resp.data as List).isEmpty;
      if (!resp.isSuccess() || empty) {
        resp = await TraxApi.getTrails();
      }
    } else {
      resp = await TraxApi.getTrails();
    }
    if (!mounted) return;

    if (resp.isSuccess() && resp.data is List) {
      final list = (resp.data as List)
          .map((e) => Trail.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _trails = _sortByDistance(list, anchor: anchor);
        if (_selectedIdx >= _trails.length) _selectedIdx = 0;
      });
      if (_trails.isNotEmpty) {
        await _selectTrail(_selectedIdx, animateCamera: true);
      }
    } else {
      setState(() => _trails = []);
    }
  }

  List<Trail> _sortByDistance(List<Trail> list, {gmap.LatLng? anchor}) {
    final center = anchor ?? _userPos;
    if (center == null) return list;
    final copy = List<Trail>.from(list);
    copy.sort((a, b) {
      final da = _distanceMeters(a, anchor: center);
      final db = _distanceMeters(b, anchor: center);
      return da.compareTo(db);
    });
    return copy;
  }

  double _distanceMeters(Trail t, {gmap.LatLng? anchor}) {
    final center = anchor ?? _nearbyAnchor ?? _userPos;
    if (center == null || t.startLatitude == null || t.startLongitude == null) {
      return double.infinity;
    }
    return Geolocator.distanceBetween(
      center.latitude,
      center.longitude,
      t.startLatitude!,
      t.startLongitude!,
    );
  }

  Future<void> _refreshNearbyByAnchor(gmap.LatLng anchor) async {
    final old = _nearbyAnchor;
    _nearbyAnchor = anchor;
    if (old != null) {
      final moved = Geolocator.distanceBetween(
        old.latitude,
        old.longitude,
        anchor.latitude,
        anchor.longitude,
      );
      if (moved < 120) return;
    }

    // Pull fresh trails for the new area. Keep the currently-selected trail
    // pinned even if it isn't returned (so the user doesn't lose their card).
    final selectedId = _trails.isEmpty ? null : _trails[_selectedIdx].id;
    final selectedTrail = _trails.isEmpty ? null : _trails[_selectedIdx];

    final resp = await TraxApi.getNearbyTrails(
      lat: anchor.latitude,
      lng: anchor.longitude,
    );
    if (!mounted) return;

    var list = <Trail>[];
    if (resp.isSuccess() && resp.data is List) {
      list = (resp.data as List)
          .map((e) => Trail.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    // If the nearby query came back empty (anchor is far from any of the
    // user's trails), fall back to the full visible list so the map never
    // ends up blank after a pan.
    if (list.isEmpty) {
      final all = await TraxApi.getTrails();
      if (!mounted) return;
      if (all.isSuccess() && all.data is List) {
        list = (all.data as List)
            .map((e) => Trail.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
    // Keep the previously selected trail in the list if the server dropped it.
    if (selectedTrail != null && selectedId != null &&
        list.indexWhere((t) => t.id == selectedId) < 0) {
      list.add(selectedTrail);
    }

    final sorted = _sortByDistance(list, anchor: anchor);
    var nextIdx = 0;
    if (selectedId != null) {
      final idx = sorted.indexWhere((t) => t.id == selectedId);
      if (idx >= 0) nextIdx = idx;
    }
    if (!mounted) return;
    setState(() {
      _trails = sorted;
      _selectedIdx = sorted.isEmpty ? 0 : nextIdx;
    });
    if (_cardCtrl.hasClients && _trails.isNotEmpty) {
      final current = _cardCtrl.page?.round() ?? 0;
      if (current != _selectedIdx) {
        _suppressPageChange = true;
        _cardCtrl.jumpToPage(_selectedIdx);
      }
    }
  }

  Future<void> _selectTrail(int index, {required bool animateCamera}) async {
    if (index < 0 || index >= _trails.length) return;
    final trail = _trails[index];
    setState(() {
      _selectedIdx = index;
    });
    final route = await _loadTrailRoute(trail);
    if (!mounted) return;
    setState(() => _selectedRoute = route);
    if (animateCamera) {
      await _focusRoute(route, trail);
    }
  }

  /// Handle a tap on one of the per-trail map pins: select the trail,
  /// slide the bottom card carousel to it, and focus the camera.
  void _onTrailMarkerTapped(int index) {
    if (index < 0 || index >= _trails.length) return;
    if (_cardCtrl.hasClients) {
      final current = _cardCtrl.page?.round() ?? _selectedIdx;
      if (current != index) {
        _suppressPageChange = true;
        _cardCtrl.animateToPage(
          index,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    }
    _selectTrail(index, animateCamera: true);
  }

  Future<List<gmap.LatLng>> _loadTrailRoute(Trail trail) async {
    final id = trail.id;
    if (id == null || id.isEmpty) return const [];
    final cached = _routeCache[id];
    if (cached != null) return cached;

    final trailId = int.tryParse(id);
    if (trailId == null) return const [];

    final resp = await TraxApi.getTrailPoints(trailId);
    if (!(resp.isSuccess() && resp.data is List)) return const [];

    final pts = <gmap.LatLng>[];
    for (final raw in resp.data as List) {
      if (raw is! Map<String, dynamic>) continue;
      final lat = raw['latitude'];
      final lng = raw['longitude'];
      if (lat is num && lng is num) {
        pts.add(gmap.LatLng(lat.toDouble(), lng.toDouble()));
      }
    }
    _routeCache[id] = pts;
    return pts;
  }

  Future<void> _focusRoute(List<gmap.LatLng> route, Trail trail) async {
    if (_provider == MapProvider.google && _gController == null) return;
    if (_provider == MapProvider.amap && _aController == null) return;

    _markProgrammaticCameraMove();

    if (route.length <= 1) {
      final lat = trail.startLatitude;
      final lng = trail.startLongitude;
      if (lat == null || lng == null) return;
      final center = gmap.LatLng(lat, lng);
      if (_provider == MapProvider.google) {
        await _gController!.animateCamera(
          gmap.CameraUpdate.newLatLngZoom(center, 15),
        );
      } else {
        await _aController!.moveCamera(
          amap_map.CameraUpdate.newLatLngZoom(AmapAdapter.toAmap(center), 15),
        );
      }
      return;
    }

    if (_provider == MapProvider.google) {
      double minLat = route.first.latitude;
      double maxLat = route.first.latitude;
      double minLng = route.first.longitude;
      double maxLng = route.first.longitude;
      for (final p in route) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      final bounds = gmap.LatLngBounds(
        southwest: gmap.LatLng(minLat, minLng),
        northeast: gmap.LatLng(maxLat, maxLng),
      );
      // GoogleMap honours the widget's `padding` property when fitting
      // bounds, so a bottom padding equal to the sheet height
      // automatically frames the route into the still-visible upper
      // area. See `_mapBottomInset` setter in `_expandDetail`.
      await _gController!.animateCamera(
        gmap.CameraUpdate.newLatLngBounds(bounds, 48),
      );
      return;
    }

    final amapPts = AmapAdapter.toAmapList(route);
    double minLat = amapPts.first.latitude;
    double maxLat = amapPts.first.latitude;
    double minLng = amapPts.first.longitude;
    double maxLng = amapPts.first.longitude;
    for (final p in amapPts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    // AMap has no widget-level `padding` and chaining `newLatLngBounds`
    // with a follow-up `scrollBy` is racy (the second moveCamera
    // cancels the first's animation mid-flight). Instead, when the
    // detail sheet is open we expand the SOUTH side of the bounding
    // box in a single fit operation so:
    //   1. Latitude becomes the limiting dimension (forces zoom-out
    //      enough to fit the inflated lat-span vertically, so the
    //      *original* route ends up vertically smaller and thus fully
    //      visible above the sheet), AND
    //   2. The original route occupies the upper (1 - f) of the
    //      inflated bounds, naturally sitting above the sheet.
    if (_mapBottomInset > 4) {
      final mq = MediaQuery.of(context);
      // Map widget fills the Stack background — its rendered size is
      // approximately the screen minus the system top inset (status
      // bar). We deliberately don't subtract the bottom nav because
      // the map extends behind it.
      final mapW = mq.size.width;
      final mapH = mq.size.height - mq.padding.top;
      if (mapW > 0 && mapH > 0) {
        final f = (_mapBottomInset / mapH).clamp(0.05, 0.7);
        final visibleAspect = mapW / (mapH * (1 - f)); // px : px
        final latSpanOrig = (maxLat - minLat).abs();
        final lngSpanOrig = (maxLng - minLng).abs();
        final centerLat = (maxLat + minLat) / 2;
        final cosLat = math.cos(centerLat * math.pi / 180).abs();
        // Lat-span (in degrees) needed for latitude to be the limiting
        // dimension at the inflated zoom. Mercator: 1° lat is wider in
        // pixels than 1° lng by 1/cosLat at the given latitude.
        final latSpanForLimiting =
            (lngSpanOrig * cosLat) / visibleAspect;
        // Lat-span needed so the original route sits in the upper
        // (1 - f) portion of the inflated bounds.
        final latSpanForShift = latSpanOrig / (1 - f);
        final latSpanTarget =
            math.max(latSpanForLimiting, latSpanForShift);
        final extra = (latSpanTarget - latSpanOrig).clamp(0.0, 180.0);
        minLat -= extra; // inflate southward
      }
    }
    await _aController!.moveCamera(
      amap_map.CameraUpdate.newLatLngBounds(
        amap.LatLngBounds(
          southwest: amap.LatLng(minLat, minLng),
          northeast: amap.LatLng(maxLat, maxLng),
        ),
        48,
      ),
      animated: true,
      duration: 280,
    );
  }

  Future<void> _centerOnUser() async {
    if (_userPos == null) {
      await _fetchUserLocation();
    }
    if (_userPos == null) return;
    final p = _userPos!;
    _nearbyAnchor = p;
    _markProgrammaticCameraMove();
    if (_provider == MapProvider.google && _gController != null) {
      await _gController!.animateCamera(gmap.CameraUpdate.newLatLngZoom(p, 16));
      return;
    }
    if (_provider == MapProvider.amap && _aController != null) {
      await _aController!
          .moveCamera(amap_map.CameraUpdate.newLatLngZoom(AmapAdapter.toAmap(p), 16));
    }
  }

  Future<void> _openSearch() async {
    final place = await showSearch<PlaceResult?>(
      context: context,
      delegate: _PlaceSearchDelegate(
        near: _nearbyAnchor ?? _userPos,
      ),
    );
    if (!mounted || place == null) return;
    final target = place.location;
    // NOTE: we deliberately do NOT pre-set `_nearbyAnchor` here.
    // `_refreshNearbyByAnchor` early-exits when the new anchor is within
    // 120 m of the previous one, and it uses `_nearbyAnchor` as the
    // "previous". Pre-setting it would self-cancel the refresh and the
    // trail cards would never re-sort against the searched location.
    _markProgrammaticCameraMove();
    if (_provider == MapProvider.google && _gController != null) {
      await _gController!
          .animateCamera(gmap.CameraUpdate.newLatLngZoom(target, 15));
    } else if (_provider == MapProvider.amap && _aController != null) {
      await _aController!.moveCamera(
        amap_map.CameraUpdate.newLatLngZoom(AmapAdapter.toAmap(target), 15),
      );
    }
    await _refreshNearbyByAnchor(target);
  }

  Future<void> _ensureThumb(Trail trail) async {
    final id = int.tryParse(trail.id ?? '');
    if (id == null) return;
    if (_thumbCache.containsKey(id) || _thumbLoading.contains(id)) return;
    _thumbLoading.add(id);
    final result = await loadTrailThumbnail(id, serverImageUrl: trail.imageUrl);
    _thumbLoading.remove(id);
    if (!mounted) return;
    setState(() => _thumbCache[id] = result.bytes);
  }

  double _trailBearingDeg(Trail trail) {
    final route = _selectedRoute;
    if (route.length >= 2) {
      return _bearing(route.first, route.last);
    }
    if (trail.startLatitude != null &&
        trail.startLongitude != null &&
        trail.endLatitude != null &&
        trail.endLongitude != null) {
      return _bearing(
        gmap.LatLng(trail.startLatitude!, trail.startLongitude!),
        gmap.LatLng(trail.endLatitude!, trail.endLongitude!),
      );
    }
    return 0;
  }

  /// Tangent direction (deg, 0=north, clockwise) at three equally-spaced
  /// points along the trail polyline (1/4, 1/2, 3/4). Used by the detail
  /// page's directional indicator so each `>` reflects the local heading
  /// rather than the global start→end bearing.
  List<double> _trailSegmentBearingsDeg(Trail trail) {
    final route = _selectedRoute;
    if (route.length < 2) {
      final b = _trailBearingDeg(trail);
      return [b, b, b];
    }
    final n = route.length;
    double sampleAt(double t) {
      final centerIdx = (t * (n - 1)).clamp(0, n - 1).toDouble();
      final lo = centerIdx.floor().clamp(0, n - 2);
      final hi = (lo + 1).clamp(1, n - 1);
      return _bearing(route[lo], route[hi]);
    }
    return [sampleAt(0.25), sampleAt(0.5), sampleAt(0.75)];
  }

  double _bearing(gmap.LatLng from, gmap.LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final brng = math.atan2(y, x) * 180 / math.pi;
    return (brng + 360) % 360;
  }

  Future<void> _openRecordModePicker() async {
    final mode = await showModalBottomSheet<TrailRecordLaunchMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.alt_route),
              title: const Text('Trail Record'),
              onTap: () => Navigator.of(ctx).pop(TrailRecordLaunchMode.trailRecord),
            ),
            ListTile(
              leading: const Icon(Icons.loop),
              title: const Text('Lap'),
              onTap: () => Navigator.of(ctx).pop(TrailRecordLaunchMode.lap),
            ),
            ListTile(
              leading: const Icon(Icons.add_road),
              title: const Text('Pick Point'),
              onTap: () => Navigator.of(ctx).pop(TrailRecordLaunchMode.pickPoint),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.close, color: AppColors.textSecondary),
              title: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
    if (!mounted || mode == null) return;
    final saved = await MapRouter.openTrailRecordWithMode(context, mode: mode);
    if (saved == true) {
      await _loadTrails();
    }
  }

  Future<EBike?> _resolvePreferredBike() async {
    final resp = await TraxApi.getUserBikes();
    if (!(resp.isSuccess() && resp.data is List)) return null;
    final bikes = (resp.data as List)
        .whereType<Map<String, dynamic>>()
        .map(EBike.fromJson)
        .toList();
    if (bikes.isEmpty) return null;

    final saved = TraxStorageUtil.getSelectedBikeId();
    if (saved.isNotEmpty) {
      for (final b in bikes) {
        if (b.id == saved) return b;
      }
    }
    final first = bikes.first;
    await TraxStorageUtil.saveSelectedBikeId(first.id);
    return first;
  }

  Future<void> _openLapTimerForTrail(Trail trail) async {
    final bike = await _resolvePreferredBike();
    if (!mounted) return;
    if (bike == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a bike before starting lap timer.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LapTimerSetupPage(selectedBike: bike, initialTrail: trail),
      ),
    );
    if (!mounted) return;
    await _loadTrails();
  }

  Future<void> _openHostLapsForTrail(Trail trail) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HostLapsPage(initialTrail: trail)),
    );
    if (!mounted) return;
    await _loadTrails();
  }

  Future<void> _openHostRaceForTrail(Trail trail) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HostRacePage(initialTrail: trail)),
    );
    if (!mounted) return;
    await _loadTrails();
  }

  @override
  Widget build(BuildContext context) {
    return PageCodeBadge(code: '600', child: _buildScaffold(context));
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(child: _buildMap()),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 14,
            right: 14,
            child: _buildTopBar(),
          ),
          Positioned(
            right: 14,
            top: MediaQuery.of(context).padding.top + 86,
            child: _buildRightControls(),
          ),
          if (_isLoading)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ),
            ),
          if (_trails.isNotEmpty) _buildTrailBottomLayer(context),
        ],
      ),
    );
  }

  /// Bottom layer: the trail-card carousel + the draggable detail sheet.
  ///
  /// Both visuals are stacked on top of each other and cross-fade driven
  /// by the same [_detailAnim]:
  ///   * value == 0  → only cards visible.
  ///   * value == 1  → only the detail sheet visible.
  ///   * 0 < v < 1   → mid-drag; cards slide down + fade, sheet slides up.
  ///
  /// Tap on a card OR drag-up anywhere on the carousel expands the sheet.
  /// Drag the sheet's top handle down to collapse.
  Widget _buildTrailBottomLayer(BuildContext context) {
    return AnimatedBuilder(
      animation: _detailAnim,
      builder: (ctx, _) {
        final v = _detailAnim.value;
        final detailH = _expandedSheetHeight(context);
        final bottomInset = MediaQuery.of(context).padding.bottom;

        // Card carousel: slide down + fade out as v → 1.
        final cardSlide = (_kCardArea + 24) * v;
        final cards = Positioned(
          left: 0,
          right: 0,
          bottom: 16,
          height: 154,
          child: IgnorePointer(
            ignoring: v > 0.5,
            child: Opacity(
              opacity: (1 - v).clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, cardSlide),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragUpdate: _onCarouselDragUpdate,
                  onVerticalDragEnd: _onCarouselDragEnd,
                  child: PageView.builder(
                    controller: _cardCtrl,
                    itemCount: _trails.length,
                    onPageChanged: (idx) {
                      if (_suppressPageChange) {
                        _suppressPageChange = false;
                        return;
                      }
                      _selectTrail(idx, animateCamera: true);
                    },
                    itemBuilder: (_, idx) {
                      final trail = _trails[idx];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: _trailCard(trail),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );

        // Detail sheet: slide up from below the screen as v → 1.
        final sheetOffsetY = detailH * (1 - v);
        final sheet = Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: detailH + bottomInset,
          child: IgnorePointer(
            ignoring: v < 0.05,
            child: Transform.translate(
              offset: Offset(0, sheetOffsetY),
              child: _buildDetailSheet(context, detailH, bottomInset),
            ),
          ),
        );

        return Stack(children: [cards, sheet]);
      },
    );
  }

  /// Computes the sheet's expanded height. After the first build, we use
  /// the measured intrinsic content height (so the panel exactly hugs
  /// the detail strips and never leaves whitespace below). Until that
  /// measurement lands we use a sensible default cap.
  double _expandedSheetHeight(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final maxH = screenH * 0.62;
    final measured = _measuredDetailH;
    if (measured == null || measured <= 0) {
      // Default before first paint: 56% of the screen — enough for
      // header + stats + location + checkpoints on common phones, but
      // never tall enough to cover the map entirely.
      return (screenH * 0.56).clamp(360, maxH);
    }
    return measured.clamp(220, maxH);
  }

  Widget _buildDetailSheet(
      BuildContext context, double height, double bottomInset) {
    final trail = _trails[_selectedIdx];
    // The entire sheet (handle + content) is draggable. Inner scroll is
    // disabled because the sheet auto-sizes to the measured content
    // height (capped at 62% screen), so scrolling isn't needed and
    // would otherwise steal the vertical-drag gesture from the sheet.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: _onSheetDragUpdate,
      onVerticalDragEnd: _onSheetDragEnd,
      child: Material(
        color: Colors.white,
        elevation: 12,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: _onSheetDragUpdate,
              onVerticalDragEnd: _onSheetDragEnd,
              onTap: _collapseDetail,
              child: SizedBox(
                height: 28,
                child: Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textSecondary.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(bottom: bottomInset + 12),
                physics: const NeverScrollableScrollPhysics(),
                child: _DetailMeasureWrapper(
                  contentKey: _detailContentKey,
                  onMeasured: _onDetailMeasured,
                  child: TrailDetailInlineSheet(
                    trail: trail,
                    onChanged: () {
                      if (mounted) _loadTrails();
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onDetailMeasured(double h) {
    // We add the 28 px handle row, NOT the bottom safe-area inset (that
    // is applied separately by the Positioned wrapper). +20 leaves a
    // small breathing-room margin so the last strip isn't flush against
    // the safe-area boundary on phones with a home indicator.
    final total = h + 28 + 20;
    if (_measuredDetailH != null &&
        (total - _measuredDetailH!).abs() < 1) {
      return;
    }
    setState(() => _measuredDetailH = total);
    // If we're already expanded, re-frame the map for the new sheet
    // size so the route stays visible above the (possibly larger or
    // smaller) sheet.
    if (_detailAnim.value > 0.9 &&
        _trails.isNotEmpty &&
        _selectedRoute.isNotEmpty) {
      _focusRoute(_selectedRoute, _trails[_selectedIdx]);
    }
  }

  // ───── Drag handlers ─────────────────────────────────────────────

  void _onCarouselDragUpdate(DragUpdateDetails d) {
    // Dragging UP on the carousel (negative dy) reveals the sheet.
    // Map 1:1 against the sheet's expanded height so the sheet appears
    // to follow the finger exactly.
    final detailH = _expandedSheetHeight(context);
    final delta = -d.primaryDelta! / detailH;
    _detailAnim.value =
        (_detailAnim.value + delta).clamp(0.0, 1.0);
  }

  void _onCarouselDragEnd(DragEndDetails d) {
    final vy = d.primaryVelocity ?? 0;
    if (vy < -300 || _detailAnim.value > 0.25) {
      _expandDetail();
    } else {
      _collapseDetail();
    }
  }

  void _onSheetDragUpdate(DragUpdateDetails d) {
    // Dragging DOWN on the sheet (positive dy) collapses it. 1:1 with
    // finger movement so it feels physically attached to the touch.
    final detailH = _expandedSheetHeight(context);
    final delta = -d.primaryDelta! / detailH;
    _detailAnim.value =
        (_detailAnim.value + delta).clamp(0.0, 1.0);
  }

  void _onSheetDragEnd(DragEndDetails d) {
    final vy = d.primaryVelocity ?? 0;
    if (vy > 300 || _detailAnim.value < 0.75) {
      _collapseDetail();
    } else {
      _expandDetail();
    }
  }

  Future<void> _expandDetail() async {
    if (_trails.isEmpty) return;
    // Tell GoogleMap to reserve the sheet's footprint at the bottom
    // BEFORE animating, so that when we re-fit the route the new
    // visible area is already known. Use the measured content height
    // when available, else the default-cap fallback.
    final screenH = MediaQuery.of(context).size.height;
    final sheetH = _measuredDetailH ?? _expandedSheetHeight(context);
    final newInset = sheetH.clamp(0, screenH * 0.7).toDouble();
    if (_mapBottomInset != newInset) {
      setState(() => _mapBottomInset = newInset);
    }
    // Kick off the camera reframe and the sheet animation in PARALLEL
    // so the map's bounds-fit visibly slides at the same time the
    // sheet slides up — instead of the previous "sheet first, then
    // camera jumps" experience. We schedule the camera reframe in a
    // post-frame callback so the GoogleMap's just-set `padding` is
    // already flushed to the native layer when `animateCamera` issues
    // its `newLatLngBounds`.
    final sheetFuture =
        _detailAnim.animateTo(1.0, curve: Curves.easeOutCubic);
    if (_selectedRoute.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_focusRoute(_selectedRoute, _trails[_selectedIdx]));
      });
    }
    await sheetFuture;
  }

  Future<void> _collapseDetail() async {
    // Same simultaneous-animation rationale as `_expandDetail`: drop
    // the GoogleMap padding immediately, kick off the camera fit on
    // the next frame, and animate the sheet down concurrently.
    if (_mapBottomInset != 0) {
      setState(() => _mapBottomInset = 0);
    }
    final sheetFuture =
        _detailAnim.animateTo(0.0, curve: Curves.easeInCubic);
    if (_trails.isNotEmpty && _selectedRoute.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_focusRoute(_selectedRoute, _trails[_selectedIdx]));
      });
    }
    await sheetFuture;
  }

  Widget _buildMap() {
    if (_provider == MapProvider.amap) {
      return _buildAmap();
    }
    return _buildGoogleMap();
  }

  Widget _buildGoogleMap() {
    final markers = <gmap.Marker>{};
    // NOTE: do NOT add a separate marker for the user position — Google
    // Maps already renders the native blue "my-location" dot when
    // `myLocationEnabled: true`. Adding our own marker on top produced
    // a duplicate pin that looked like a second "current location".
    //
    // We also only render the START pin for the currently SELECTED
    // trail (drawn below via `_selectedRoute`). Non-selected nearby
    // trails used to each get a blue drop-pin, which testers mistook
    // for "my location". Discovery of other trails happens through the
    // bottom card carousel + their polylines (when rendered).
    if (_selectedRoute.isNotEmpty) {
      markers.add(gmap.Marker(
        markerId: const gmap.MarkerId('start'),
        position: _selectedRoute.first,
        icon: gmap.BitmapDescriptor.defaultMarkerWithHue(gmap.BitmapDescriptor.hueGreen),
      ));
      if (_selectedRoute.length > 1) {
        markers.add(gmap.Marker(
          markerId: const gmap.MarkerId('finish'),
          position: _selectedRoute.last,
          icon: gmap.BitmapDescriptor.defaultMarkerWithHue(gmap.BitmapDescriptor.hueRed),
        ));
      }
    }

    return gmap.GoogleMap(
      initialCameraPosition: gmap.CameraPosition(
        target: _userPos ?? const gmap.LatLng(22.5431, 114.0579),
        zoom: 14,
      ),
      mapType:
          _layer == _MapLayer.satellite ? gmap.MapType.satellite : gmap.MapType.normal,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      compassEnabled: false,
      buildingsEnabled: _layer == _MapLayer.satellite,
      tiltGesturesEnabled: false,
      rotateGesturesEnabled: true,
      padding: EdgeInsets.only(bottom: _mapBottomInset),
      polylines: {
        if (_selectedRoute.length >= 2)
          gmap.Polyline(
            polylineId: const gmap.PolylineId('trail_route'),
            points: _selectedRoute,
            color: AppColors.primary,
            width: 5,
          ),
      },
      markers: markers,
      onMapCreated: (c) {
        _gController = c;
        if (_trails.isNotEmpty) {
          _focusRoute(_selectedRoute, _trails[_selectedIdx]);
        } else {
          _centerOnUser();
        }
      },
      onCameraMove: (pos) {
        _cameraCenterCandidate = pos.target;
      },
      onCameraIdle: () async {
        if (_suppressCameraIdle) return;
        final center = _cameraCenterCandidate;
        if (center == null) return;
        await _refreshNearbyByAnchor(center);
      },
    );
  }

  Widget _buildAmap() {
    final markers = <amap_map.Marker>{};
    _amapTrailMarkerIdx.clear();
    // See _buildGoogleMap for rationale: skip a duplicate user-position
    // pin (AMap draws its own when location is enabled) and skip start
    // pins for non-selected trails (only the selected trail's S/F
    // markers are drawn below).
    if (_selectedRoute.isNotEmpty) {
      markers.addAll(AmapAdapter.startFinishMarkers(_selectedRoute));
    }

    return amap_map.AMapWidget(
      privacyStatement: AmapAdapter.privacy(),
      apiKey: AmapAdapter.apiKey(),
      initialCameraPosition: AmapAdapter.initialCamera(
        _selectedRoute,
        zoom: 14,
      ),
      // Enable the native AMap blue-dot for the user position. Without
      // these options AMap does NOT draw it (unlike Google Maps which
      // turns it on via `myLocationEnabled`).
      myLocationStyleOptions: amap_map.MyLocationStyleOptions(
        true,
        circleFillColor: AppColors.primary.withValues(alpha: 0.15),
        circleStrokeColor: AppColors.primary,
        circleStrokeWidth: 1,
      ),
      mapType: _layer == _MapLayer.satellite
          ? amap_map.MapType.satellite
          : amap_map.MapType.normal,
      buildingsEnabled: _layer == _MapLayer.satellite,
      compassEnabled: false,
      tiltGesturesEnabled: false,
      rotateGesturesEnabled: true,
      polylines: {
        if (_selectedRoute.length >= 2)
          AmapAdapter.routePolyline(_selectedRoute, color: AppColors.primary),
      },
      markers: markers,
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
      },
      onMapCreated: (c) {
        _aController = c;
        if (_trails.isNotEmpty) {
          _focusRoute(_selectedRoute, _trails[_selectedIdx]);
        } else {
          _centerOnUser();
        }
      },
      onCameraMoveEnd: (pos) {
        if (_suppressCameraIdle) return;
        final wgs = CoordTransform.gcj02ToWgs84(
          pos.target.latitude,
          pos.target.longitude,
        );
        _refreshNearbyByAnchor(gmap.LatLng(wgs.lat, wgs.lng));
      },
    );
  }

  Widget _buildTopBar() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _openSearch,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.search, color: AppColors.textSecondary, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Search places',
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.keyboard_arrow_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRightControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _layersRow(),
        const SizedBox(height: 8),
        _roundControlBtn(
          icon: Icons.my_location,
          tip: 'My Location',
          onTap: _centerOnUser,
        ),
        const SizedBox(height: 8),
        _recordRow(),
      ],
    );
  }

  /// Layers trigger + a left-expanding pill that reveals normal/satellite
  /// choices. The pill grows from the right (anchored to the circular
  /// trigger), giving the visual effect of the round button "splitting"
  /// horizontally and pulling its content out to the left.
  Widget _layersRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LeftExpandPill(
          open: _showLayerChoices,
          children: [
            _pillIconBtn(
              icon: Icons.map,
              active: _layer == _MapLayer.normal,
              onTap: () => setState(() {
                _layer = _MapLayer.normal;
                _showLayerChoices = false;
              }),
            ),
            _pillIconBtn(
              icon: Icons.satellite_alt,
              active: _layer == _MapLayer.satellite,
              onTap: () => setState(() {
                _layer = _MapLayer.satellite;
                _showLayerChoices = false;
              }),
            ),
          ],
        ),
        _roundControlBtn(
          icon: Icons.layers_outlined,
          tip: 'Layers',
          active: _showLayerChoices,
          onTap: () => setState(() {
            _showLayerChoices = !_showLayerChoices;
            if (_showLayerChoices) _showRecordChoices = false;
          }),
        ),
      ],
    );
  }

  /// Record trigger + a left-expanding pill that reveals the three
  /// record-launch modes. Same animation grammar as [_layersRow].
  Widget _recordRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LeftExpandPill(
          open: _showRecordChoices,
          children: [
            _pillIconBtn(
              icon: Icons.route,
              onTap: () => _launchRecordMode(TrailRecordLaunchMode.trailRecord),
            ),
            _pillIconBtn(
              icon: Icons.loop,
              onTap: () => _launchRecordMode(TrailRecordLaunchMode.lap),
            ),
            _pillIconBtn(
              icon: Icons.add_location_alt_outlined,
              onTap: () => _launchRecordMode(TrailRecordLaunchMode.pickPoint),
            ),
          ],
        ),
        _roundControlBtn(
          icon: Icons.fiber_manual_record,
          tip: 'Record',
          iconColor: Colors.red,
          active: _showRecordChoices,
          onTap: () => setState(() {
            _showRecordChoices = !_showRecordChoices;
            if (_showRecordChoices) _showLayerChoices = false;
          }),
        ),
      ],
    );
  }

  Future<void> _launchRecordMode(TrailRecordLaunchMode mode) async {
    setState(() => _showRecordChoices = false);
    if (!mounted) return;
    final saved = await MapRouter.openTrailRecordWithMode(context, mode: mode);
    if (saved == true && mounted) {
      await _loadTrails();
    }
  }

  Widget _pillIconBtn({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(
          icon,
          size: 22,
          color: active ? AppColors.primary : AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _roundControlBtn({
    required IconData icon,
    required String tip,
    required VoidCallback onTap,
    bool active = false,
    Color? iconColor,
  }) {
    return Tooltip(
      message: tip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              color: iconColor ??
                  (active ? AppColors.primary : AppColors.textPrimary),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _trailCard(Trail trail) {
    // Kick off thumbnail load lazily; cached + deduped inside
    // `_ensureThumb`, will trigger a rebuild via setState when it lands.
    unawaited(_ensureThumb(trail));
    final thumbId = int.tryParse(trail.id ?? '');
    final thumbBytes = thumbId == null ? null : _thumbCache[thumbId];

    final distanceM = _distanceMeters(trail, anchor: _nearbyAnchor ?? _userPos);
    final distanceText = distanceM.isFinite
        ? distanceM >= 1000
            ? '${(distanceM / 1000).toStringAsFixed(1)} km away'
            : '${distanceM.toStringAsFixed(0)} m away'
        : 'Distance unknown';

    return GestureDetector(
      onTap: () => _expandDetail(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _trailCardThumb(thumbBytes),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            trail.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: trail.isPublic
                                ? AppColors.primary.withValues(alpha: 0.12)
                                : AppColors.textSecondary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            trail.isPublic ? 'Public' : 'Personal',
                            style: TextStyle(
                              fontSize: 11,
                              color: trail.isPublic ? AppColors.primary : AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      distanceText,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _miniStat(Icons.straighten, '${(trail.distance ?? 0).toStringAsFixed(2)} km'),
                        const SizedBox(width: 10),
                        _miniStat(Icons.trending_up, '${(trail.elevation ?? 0).toStringAsFixed(0)} m'),
                        const SizedBox(width: 10),
                        _miniStat(Icons.loop, trail.type == 'lap' ? 'Lap' : 'Free'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trailCardThumb(Uint8List? bytes) {
    final placeholder = Container(
      color: AppColors.textSecondary.withValues(alpha: 0.10),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        size: 28,
        color: AppColors.textSecondary.withValues(alpha: 0.6),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 104,
        height: 104,
        child: bytes == null
            ? placeholder
            : Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => placeholder,
              ),
      ),
    );
  }

  Widget _miniStat(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// Wraps the inline trail-detail body and reports its laid-out height
/// back to the host screen so the bottom sheet can size itself exactly
/// to the content (no whitespace below).
class _DetailMeasureWrapper extends StatefulWidget {
  const _DetailMeasureWrapper({
    required this.contentKey,
    required this.onMeasured,
    required this.child,
  });

  final GlobalKey contentKey;
  final ValueChanged<double> onMeasured;
  final Widget child;

  @override
  State<_DetailMeasureWrapper> createState() => _DetailMeasureWrapperState();
}

class _DetailMeasureWrapperState extends State<_DetailMeasureWrapper> {
  double _lastReported = -1;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = widget.contentKey.currentContext;
      final box = ctx?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final h = box.size.height;
      if ((h - _lastReported).abs() > 0.5) {
        _lastReported = h;
        widget.onMeasured(h);
      }
    });
    return KeyedSubtree(key: widget.contentKey, child: widget.child);
  }
}

/// Pill container that animates from zero-width to its content's natural
/// width, anchored on the right so the reveal grows out to the LEFT —
/// giving the visual effect of a round button "splitting" and pulling a
/// horizontal capsule out alongside it.
class _LeftExpandPill extends StatelessWidget {
  const _LeftExpandPill({required this.open, required this.children});

  final bool open;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ClipRect(
        child: AnimatedAlign(
          alignment: Alignment.centerRight,
          heightFactor: 1.0,
          widthFactor: open ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: IgnorePointer(
            ignoring: !open,
            child: Material(
              color: Colors.white,
              elevation: 3,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-page trail detail. Pushed as a real route so iOS edge-swipe back
/// and Android system back work without extra wiring.
class _TrailDetailFullPage extends StatelessWidget {
  const _TrailDetailFullPage({
    required this.trail,
    required this.thumbBytes,
    required this.bearingsDeg,
    required this.onLapTimer,
    required this.onHostLaps,
    required this.onHostRace,
    required this.onOpenLegacyDetail,
  });

  final Trail trail;
  final Uint8List? thumbBytes;
  final List<double> bearingsDeg;
  final VoidCallback onLapTimer;
  final VoidCallback onHostLaps;
  final VoidCallback onHostRace;
  final VoidCallback onOpenLegacyDetail;

  @override
  Widget build(BuildContext context) {
    final isLap = trail.type == 'lap';
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Material(
                    color: const Color(0xFFF1F3F5),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).maybePop(),
                      child: const SizedBox(
                        width: 34,
                        height: 34,
                        child: Icon(Icons.arrow_back),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trail.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          height: 156,
                          width: double.infinity,
                          child: thumbBytes != null
                              ? Image.memory(
                                  thumbBytes!,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                )
                              : trail.imageUrl != null && trail.imageUrl!.isNotEmpty
                                  ? Image.network(
                                      trail.imageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => _thumbPlaceholder(),
                                    )
                                  : _thumbPlaceholder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F6F8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: List.generate(3, (i) {
                            // `>` glyph natively points east. Subtract 90°
                            // so a north-heading (bearing 0) arrow points up.
                            final angle = (bearingsDeg[i] - 90) * math.pi / 180;
                            return Transform.rotate(
                              angle: angle,
                              child: const Text(
                                '>',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _detailChip(trail.isPublic ? 'Public Trail' : 'Personal Trail'),
                          _detailChip(trail.type == 'lap' ? 'Lap Trail' : 'Free Ride Trail'),
                          _detailChip('${(trail.distance ?? 0).toStringAsFixed(2)} km'),
                          _detailChip('${(trail.elevation ?? 0).toStringAsFixed(0)} m gain'),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if ((trail.location ?? '').isNotEmpty)
                        Text(
                          trail.location!,
                          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                        ),
                      if ((trail.description ?? '').isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          trail.description!,
                          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (isLap) ...[
                const Text(
                  'Quick Ride Actions',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _primaryActionBtn(text: 'Lap Timer', onTap: onLapTimer)),
                    const SizedBox(width: 8),
                    Expanded(child: _secondaryActionBtn(text: 'Host Laps', onTap: onHostLaps)),
                    const SizedBox(width: 8),
                    Expanded(child: _secondaryActionBtn(text: 'Host Race', onTap: onHostRace)),
                  ],
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: _primaryActionBtn(
                    text: 'Open Trail Detail',
                    onTap: onOpenLegacyDetail,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbPlaceholder() {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.08),
      alignment: Alignment.center,
      child: const Icon(Icons.terrain, color: AppColors.primary, size: 36),
    );
  }

  Widget _detailChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _primaryActionBtn({required String text, required VoidCallback onTap}) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(text, textAlign: TextAlign.center),
    );
  }

  Widget _secondaryActionBtn({required String text, required VoidCallback onTap}) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: BorderSide(color: AppColors.divider.withValues(alpha: 0.9)),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(text, textAlign: TextAlign.center),
    );
  }
}

class _PlaceSearchDelegate extends SearchDelegate<PlaceResult?> {
  _PlaceSearchDelegate({this.near});

  final gmap.LatLng? near;
  // Notifier the body listens to — avoids the removed `notifyListeners()`
  // on SearchDelegate.
  final ValueNotifier<_SearchBodyState> _state =
      ValueNotifier(const _SearchBodyState());
  // Recent searches loaded from SharedPreferences on first build.
  final ValueNotifier<List<PlaceResult>> _recents = ValueNotifier(const []);
  bool _recentsLoaded = false;
  // Monotonic request id, used to drop stale responses when the user keeps typing.
  int _requestSeq = 0;
  String _lastQuery = '';
  Timer? _debounce;
  bool _closed = false;

  static const _kRecentsKey = 'trax_recent_place_search_v1';
  static const _kMaxRecents = 8;

  @override
  String? get searchFieldLabel => 'Search places';

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: const TextStyle(
            color: AppColors.textPrimary, fontSize: 16),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: AppColors.textSecondary),
        border: InputBorder.none,
      ),
      textTheme: base.textTheme.copyWith(
        titleLarge: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w500),
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          onPressed: () {
            query = '';
            _lastQuery = '';
            _debounce?.cancel();
            _state.value = const _SearchBodyState();
            showSuggestions(context);
          },
          icon: const Icon(Icons.clear),
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      onPressed: () {
        _closed = true;
        _debounce?.cancel();
        close(context, null);
      },
      icon: const Icon(Icons.arrow_back),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    _scheduleSearch(immediate: true);
    return _buildBody(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (!_recentsLoaded) {
      _recentsLoaded = true;
      _loadRecents();
    }
    _scheduleSearch();
    return _buildBody(context);
  }

  void _scheduleSearch({bool immediate = false}) {
    final q = query.trim();
    if (q == _lastQuery) return;
    _lastQuery = q;
    _debounce?.cancel();
    if (q.length < 2) {
      _state.value = const _SearchBodyState();
      return;
    }
    _debounce = Timer(
      Duration(milliseconds: immediate ? 0 : 300),
      _runSearch,
    );
  }

  Future<void> _runSearch() async {
    if (_closed) return;
    final q = query.trim();
    if (q.length < 2) return;
    final reqId = ++_requestSeq;
    _state.value = _SearchBodyState(
        loading: true, results: _state.value.results);
    final results = await MapService.searchPlaces(q, near: near);
    if (_closed || reqId != _requestSeq) return;
    _state.value = _SearchBodyState(results: results);
  }

  @override
  void close(BuildContext context, PlaceResult? result) {
    _closed = true;
    _debounce?.cancel();
    if (result != null) {
      // Fire-and-forget: persist to recents before navigating away.
      _pushRecent(result);
    }
    super.close(context, result);
  }

  // ───── Recent searches persistence ───────────────────────────────

  Future<void> _loadRecents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kRecentsKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List)
          .map((e) => _placeFromJson(e as Map<String, dynamic>))
          .whereType<PlaceResult>()
          .toList();
      if (!_closed) _recents.value = list;
    } catch (_) {
      // Ignore corrupt cache — recents are non-critical.
    }
  }

  Future<void> _pushRecent(PlaceResult place) async {
    try {
      final current = List<PlaceResult>.from(_recents.value);
      current.removeWhere((p) =>
          p.name == place.name && p.address == place.address);
      current.insert(0, place);
      while (current.length > _kMaxRecents) {
        current.removeLast();
      }
      _recents.value = current;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRecentsKey,
          jsonEncode(current.map(_placeToJson).toList()));
    } catch (_) {}
  }

  Future<void> _clearRecents() async {
    _recents.value = const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kRecentsKey);
    } catch (_) {}
  }

  Map<String, dynamic> _placeToJson(PlaceResult p) => {
        'name': p.name,
        'address': p.address,
        'lat': p.location.latitude,
        'lng': p.location.longitude,
      };

  PlaceResult? _placeFromJson(Map<String, dynamic> j) {
    final lat = (j['lat'] as num?)?.toDouble();
    final lng = (j['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return PlaceResult(
      name: (j['name'] as String?) ?? '',
      address: (j['address'] as String?) ?? '',
      location: gmap.LatLng(lat, lng),
    );
  }

  // ───── Body ──────────────────────────────────────────────────────

  Widget _buildBody(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F6F8),
      child: ValueListenableBuilder<_SearchBodyState>(
        valueListenable: _state,
        builder: (ctx, state, _) {
          final qLen = query.trim().length;
          // Empty query → recent searches (Amap/Google pattern).
          if (qLen < 2) {
            return ValueListenableBuilder<List<PlaceResult>>(
              valueListenable: _recents,
              builder: (rctx, recents, __) =>
                  _buildIdleBody(rctx, recents),
            );
          }
          return Column(
            children: [
              SizedBox(
                height: 2,
                child: state.loading
                    ? const LinearProgressIndicator(
                        minHeight: 2,
                        color: AppColors.primary,
                        backgroundColor: Color(0x11000000),
                      )
                    : const SizedBox.shrink(),
              ),
              Expanded(
                child: _buildResultsBody(context, state),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildIdleBody(BuildContext context, List<PlaceResult> recents) {
    if (recents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.search,
                  size: 48, color: AppColors.textSecondary),
              SizedBox(height: 12),
              Text(
                'Search for a place, address or POI',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Row(
            children: [
              const Text(
                'Recent',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary),
              ),
              const Spacer(),
              TextButton(
                onPressed: _clearRecents,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (int i = 0; i < recents.length; i++) ...[
                _buildPlaceTile(
                  context,
                  recents[i],
                  leadingIcon: Icons.history,
                  leadingTint: AppColors.textSecondary,
                ),
                if (i != recents.length - 1)
                  const Divider(height: 1, indent: 56, endIndent: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultsBody(BuildContext context, _SearchBodyState state) {
    if (state.results.isEmpty) {
      if (state.loading) {
        return const SizedBox.shrink();
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.search_off,
                  size: 48, color: AppColors.textSecondary),
              SizedBox(height: 12),
              Text(
                'No places found',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      color: Colors.white,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: state.results.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 56, endIndent: 12),
        itemBuilder: (itemCtx, i) {
          final item = state.results[i];
          return _buildPlaceTile(
            itemCtx,
            item,
            leadingIcon: Icons.place_outlined,
            leadingTint: AppColors.primary,
            showPushToQuery: true,
          );
        },
      ),
    );
  }

  Widget _buildPlaceTile(
    BuildContext context,
    PlaceResult item, {
    required IconData leadingIcon,
    required Color leadingTint,
    bool showPushToQuery = false,
  }) {
    final dist = _distanceLabel(item.location);
    return InkWell(
      onTap: () => close(context, item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: leadingTint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(leadingIcon, size: 18, color: leadingTint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name.isEmpty ? item.address : item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (item.address.isNotEmpty &&
                      item.address != item.name) ...[
                    const SizedBox(height: 2),
                    Text(
                      dist == null
                          ? item.address
                          : '$dist  ·  ${item.address}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ] else if (dist != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      dist,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showPushToQuery)
              IconButton(
                tooltip: 'Use this name',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  query = item.name.isEmpty ? item.address : item.name;
                  showResults(context);
                },
                icon: const Icon(Icons.north_west,
                    size: 18, color: AppColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }

  String? _distanceLabel(gmap.LatLng dest) {
    final origin = near;
    if (origin == null) return null;
    final meters = _haversine(origin, dest);
    if (meters < 1000) {
      return '${meters.round()} m';
    }
    final km = meters / 1000;
    if (km < 10) {
      return '${km.toStringAsFixed(1)} km';
    }
    return '${km.round()} km';
  }

  double _haversine(gmap.LatLng a, gmap.LatLng b) {
    const r = 6371000.0; // meters
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLng = _deg2rad(b.longitude - a.longitude);
    final lat1 = _deg2rad(a.latitude);
    final lat2 = _deg2rad(b.latitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLng / 2) * math.sin(dLng / 2) *
            math.cos(lat1) * math.cos(lat2);
    return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
  }

  double _deg2rad(double d) => d * math.pi / 180.0;
}

class _SearchBodyState {
  const _SearchBodyState({this.loading = false, this.results = const []});
  final bool loading;
  final List<PlaceResult> results;
}
