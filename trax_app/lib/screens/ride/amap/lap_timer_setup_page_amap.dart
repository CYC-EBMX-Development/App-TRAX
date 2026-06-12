import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:amap_flutter_base/amap_flutter_base.dart' as amap;
import 'package:amap_flutter_map/amap_flutter_map.dart' as amap_map;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../../../common/utils/amap_adapter.dart';
import '../../../common/utils/location_signal_gate.dart';
import '../../../common/utils/start_end_marker_icons_amap.dart';
import '../../../common/utils/trail_thumbnail.dart';
import '../../../common/network/trax_api.dart';
import '../../../common/widgets/page_code_badge.dart';
import '../../../common/widgets/map_router.dart';
import '../../../common/widgets/my_location_fab.dart';
import '../../../common/widgets/satellite_badge.dart';
import '../../../models/ebike.dart';
import '../../../models/trail.dart';
import '../../../models/user_checkpoint.dart';
import '../../../services/active_ride_service.dart';
import '../../../common/utils/map_styles.dart';
import '../../../theme/app_theme.dart';

/// AMap mirror of [LapTimerSetupPage]. The Google `GoogleMap` widgets in
/// the main view and the checkpoint-pick view are swapped for
/// `AMapWidget`. Two SDK gaps are bridged here:
///
/// 1. AMap has no `getLatLng(ScreenCoordinate)` — the start-location
///    picker reads `_cameraCenter` (captured from `onCameraMove*`) and
///    converts it back to WGS-84 via [AmapAdapter.fromAmap].
/// 2. `BitmapDescriptor.bytes(width:, height:)` does not exist on AMap;
///    bitmaps are emitted via `BitmapDescriptor.fromBytes(...)` at native
///    DPR pixel size.
class LapTimerSetupPageAmap extends StatefulWidget {
  final EBike selectedBike;
  const LapTimerSetupPageAmap({super.key, required this.selectedBike});

  @override
  State<LapTimerSetupPageAmap> createState() =>
      _LapTimerSetupPageAmapState();
}

class _LapTimerSetupPageAmapState extends State<LapTimerSetupPageAmap> {
  final _svc = ActiveRideService.instance;
  bool get _hasModule =>
      (widget.selectedBike.traxSerialNumber ?? '').isNotEmpty;

  // Bottom sheet controller — lets us drag/tap the pinned handle.
  final DraggableScrollableController _sheetCtl =
      DraggableScrollableController();
  double _sheetMinSize = 0.10;
  double _sheetMaxSize = 0.60;
  // Live sheet height in logical px; drives map fit-bounds south buffer.
  double _sheetSizePx = 0;
  // Sheet extent when the most recent finger-down started; used to bias
  // the manual snap so a small downward drag anywhere on the body
  // collapses the sheet.
  double _dragStartExtent = 0;

  // Data
  List<Trail> _trails = [];
  bool _isLoadingTrails = true;
  Trail? _selectedTrail;
  int _targetLaps = 3;

  // Trail route preview (WGS-84).
  List<LatLng> _trailRoute = [];
  bool _isLoadingRoute = false;
  int _trailPointCount = 0;

  // Map
  amap_map.AMapController? _mapController;
  bool _mapReady = false;
  LatLng? _userLocation;

  // Checkpoints
  List<UserCheckpoint> _checkpoints = [];
  bool _isPickingCheckpoint = false;
  bool _addingCheckpoint = false;

  // Slider-along-trail
  List<double> _cumDistM = const [];
  double _trailLengthM = 0;
  double _sliderT = 0.5;
  List<double> _checkpointTicks = const [];

  // Numbered checkpoint marker bitmap cache.
  final Map<int, amap_map.BitmapDescriptor> _cpMarkerCache = {};
  amap_map.BitmapDescriptor? _draftCpIcon;

  bool _autoSelectorShown = false;

  @override
  void initState() {
    super.initState();
    // Keep the map fit synced with the sheet height so the trail stays
    // framed in the visible area above the sheet.
    _sheetCtl.addListener(_onSheetSizeChanged);
    _bootstrap();
    _warmDraftIcon();
    // Pre-Start preview — see lap_timer_setup_page for rationale.
    if (_hasModule) {
      _svc.previewModule(widget.selectedBike);
    }
  }

  void _onSheetSizeChanged() {
    if (!mounted || !_sheetCtl.isAttached) return;
    final screenH = MediaQuery.of(context).size.height;
    final px = _sheetCtl.size * screenH;
    if ((px - _sheetSizePx).abs() < 6) return;
    setState(() => _sheetSizePx = px);
  }

  /// Re-fit the trail (or recentre on user location) so it sits in the
  /// visible area above the sheet. Called after a snap settles.
  void _refitMapToSheet() {
    if (!mounted || _mapController == null) return;
    if (_trailRoute.isNotEmpty) {
      _fitTrailBounds(_trailRoute);
    } else if (_userLocation != null) {
      _mapController!.moveCamera(
        amap_map.CameraUpdate.newLatLngZoom(
            AmapAdapter.toAmap(_userLocation!), 15),
      );
    }
  }

  /// Manual snap-on-release with a downward-drag bias — lets the user
  /// collapse the sheet by dragging anywhere on the body.
  void _snapAfterDrag() {
    if (!_sheetCtl.isAttached) return;
    final cur = _sheetCtl.size;
    final range = (_sheetMaxSize - _sheetMinSize).clamp(0.0001, 1.0);
    final delta = cur - _dragStartExtent;
    const threshold = 0.04;
    double target;
    if (delta < -threshold) {
      target = _sheetMinSize;
    } else if (delta > threshold) {
      target = _sheetMaxSize;
    } else {
      target = ((cur - _sheetMinSize) / range) >= 0.5
          ? _sheetMaxSize
          : _sheetMinSize;
    }
    if ((cur - target).abs() < 0.005) return;
    _sheetCtl.animateTo(target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut);
    Future.delayed(const Duration(milliseconds: 240), _refitMapToSheet);
  }

  @override
  void dispose() {
    _sheetCtl.removeListener(_onSheetSizeChanged);
    _sheetCtl.dispose();
    _mapController = null;
    // Tear down the pre-Start preview subscription. No-op if active.
    _svc.stopPreview();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadTrails(), _fetchUserLocation()]);
    if (!mounted) return;
    if (!_autoSelectorShown && _selectedTrail == null && _trails.isNotEmpty) {
      _autoSelectorShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openTrailSelector(initial: true);
      });
    }
  }

  Future<void> _loadTrails() async {
    final resp = await TraxApi.getTrails();
    if (!mounted) return;
    if (resp.isSuccess() && resp.data is List) {
      _trails = (resp.data as List)
          .map((e) => Trail.fromJson(e as Map<String, dynamic>))
          .where((t) => t.type == 'lap')
          .toList();
    }
    setState(() => _isLoadingTrails = false);
  }

  Future<void> _fetchUserLocation() async {
    // With a module bike, never auto-pan to phone GPS — match the Google
    // variant's behaviour.
    if (_hasModule) return;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      _userLocation = LatLng(pos.latitude, pos.longitude);
      if (_mapReady && _selectedTrail == null) {
        _mapController?.moveCamera(
          amap_map.CameraUpdate.newLatLngZoom(
              AmapAdapter.toAmap(_userLocation!), 15),
        );
      }
    } catch (_) {}
  }

  Future<void> _openTrailSelector({required bool initial}) async {
    final picked = await showModalBottomSheet<Trail>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: !initial,
      enableDrag: !initial,
      builder: (sheetCtx) => _TrailPickerSheet(
        trails: _trails,
        initialSelectedId: _selectedTrail?.id,
        showCancel: !initial,
      ),
    );
    if (!mounted) return;
    if (picked != null && picked.id != _selectedTrail?.id) {
      await _applySelectedTrail(picked);
    }
  }

  Future<void> _applySelectedTrail(Trail trail) async {
    setState(() {
      _selectedTrail = trail;
      _trailRoute = [];
      _trailPointCount = 0;
      _isLoadingRoute = true;
      _isPickingCheckpoint = false;
      _checkpoints = [];
      _cpMarkerCache.clear();
    });

    final id = int.tryParse(trail.id ?? '');
    if (id == null) {
      setState(() => _isLoadingRoute = false);
      return;
    }

    _loadCheckpoints(id);

    final resp = await TraxApi.getTrailPoints(id);
    if (!mounted) return;

    if (resp.isSuccess() && resp.data is List) {
      final pts = (resp.data as List).map((p) {
        final m = p as Map<String, dynamic>;
        return LatLng(
          (m['latitude'] as num).toDouble(),
          (m['longitude'] as num).toDouble(),
        );
      }).toList();
      setState(() {
        _trailRoute = pts;
        _trailPointCount = pts.length;
        _isLoadingRoute = false;
        _recomputeArcLengths();
        _recomputeCheckpointTicks();
      });
      if (pts.isNotEmpty && _mapReady) _fitTrailBounds(pts);
    } else {
      setState(() => _isLoadingRoute = false);
    }
  }

  // ── Polyline arc-length helpers ──────────────────────────
  void _recomputeArcLengths() {
    if (_trailRoute.length < 2) {
      _cumDistM = const [];
      _trailLengthM = 0;
      return;
    }
    final cum = <double>[0];
    double total = 0;
    for (var i = 1; i < _trailRoute.length; i++) {
      total += _haversineM(_trailRoute[i - 1], _trailRoute[i]);
      cum.add(total);
    }
    _cumDistM = cum;
    _trailLengthM = total;
  }

  void _recomputeCheckpointTicks() {
    if (_trailRoute.length < 2 || _trailLengthM <= 0) {
      _checkpointTicks = const [];
      return;
    }
    _checkpointTicks = _checkpoints
        .map((cp) => _fractionOf(LatLng(cp.latitude, cp.longitude)))
        .toList();
  }

  LatLng _positionAtFraction(double t) {
    if (_trailRoute.isEmpty) return const LatLng(0, 0);
    if (_trailRoute.length == 1) return _trailRoute.first;
    final target = (t.clamp(0.0, 1.0)) * _trailLengthM;
    var lo = 0, hi = _cumDistM.length - 1;
    while (lo < hi - 1) {
      final mid = (lo + hi) >> 1;
      if (_cumDistM[mid] <= target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final segStart = _cumDistM[lo];
    final segEnd = _cumDistM[hi];
    final segLen = (segEnd - segStart).abs();
    final f = segLen > 0 ? (target - segStart) / segLen : 0.0;
    final a = _trailRoute[lo];
    final b = _trailRoute[hi];
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * f,
      a.longitude + (b.longitude - a.longitude) * f,
    );
  }

  double _fractionOf(LatLng p) {
    if (_trailRoute.length < 2 || _trailLengthM <= 0) return 0;
    var bestDist = double.infinity;
    double bestArc = 0;
    for (var i = 0; i < _trailRoute.length - 1; i++) {
      final a = _trailRoute[i];
      final b = _trailRoute[i + 1];
      final segLen = _haversineM(a, b);
      if (segLen <= 0) continue;
      final cosLat = math.cos(a.latitude * math.pi / 180);
      final bx = (b.longitude - a.longitude) * cosLat;
      final by = b.latitude - a.latitude;
      final px = (p.longitude - a.longitude) * cosLat;
      final py = p.latitude - a.latitude;
      final l2 = bx * bx + by * by;
      var u = l2 > 0 ? (px * bx + py * by) / l2 : 0.0;
      u = u.clamp(0.0, 1.0);
      final cx = u * bx;
      final cy = u * by;
      final dx = px - cx;
      final dy = py - cy;
      final approxM = math.sqrt(dx * dx + dy * dy) * 111320.0;
      if (approxM < bestDist) {
        bestDist = approxM;
        bestArc = _cumDistM[i] + segLen * u;
      }
    }
    return (bestArc / _trailLengthM).clamp(0.0, 1.0);
  }

  static double _haversineM(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final s1 = math.sin(dLat / 2);
    final s2 = math.sin(dLng / 2);
    final h = s1 * s1 +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            s2 *
            s2;
    return 2 * r * math.asin(math.sqrt(h));
  }

  void _fitTrailBounds(List<LatLng> pts) {
    if (pts.isEmpty || _mapController == null) return;
    if (pts.length == 1) {
      _mapController!.moveCamera(
        amap_map.CameraUpdate.newLatLngZoom(AmapAdapter.toAmap(pts.first), 15),
      );
      return;
    }
    final amapPts = AmapAdapter.toAmapList(pts);
    double minLat = amapPts.first.latitude, maxLat = amapPts.first.latitude;
    double minLng = amapPts.first.longitude, maxLng = amapPts.first.longitude;
    for (final p in amapPts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    // AMap CameraUpdate.newLatLngBounds has no per-edge padding. To keep
    // the trail centred in the visible area above the bottom sheet, we
    // expand the bounds southward by the sheet's screen-ratio so the
    // "phantom" extra area sits behind the sheet.
    final screenH = MediaQuery.of(context).size.height;
    final sheetPx = _sheetSizePx > 0 ? _sheetSizePx : 0;
    final visiblePx = (screenH - sheetPx).clamp(1.0, screenH);
    final latSpan = (maxLat - minLat).abs();
    final southBuf = latSpan * (sheetPx / visiblePx);
    _mapController!.moveCamera(
      amap_map.CameraUpdate.newLatLngBounds(
        amap.LatLngBounds(
          southwest: amap.LatLng(minLat - southBuf, minLng),
          northeast: amap.LatLng(maxLat, maxLng),
        ),
        50,
      ),
    );
  }

  // ── Checkpoints ───────────────────────────────────────────
  Future<void> _loadCheckpoints(int trailId) async {
    final resp = await TraxApi.getTrailCheckpoints(trailId);
    if (!mounted) return;
    if (resp.isSuccess() && resp.data is List) {
      setState(() {
        _checkpoints = (resp.data as List)
            .map((e) => UserCheckpoint.fromJson(e as Map<String, dynamic>))
            .toList();
        _recomputeCheckpointTicks();
      });
      _warmCpMarkers();
    }
  }

  Future<void> _warmCpMarkers() async {
    var changed = false;
    for (final cp in _checkpoints) {
      if (!_cpMarkerCache.containsKey(cp.sequenceIndex)) {
        _cpMarkerCache[cp.sequenceIndex] =
            await _buildNumberedMarker(cp.sequenceIndex, AppColors.primary);
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
  }

  Future<void> _warmDraftIcon() async {
    if (_draftCpIcon != null) return;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final dpr = views.isNotEmpty ? views.first.devicePixelRatio : 3.0;
    _draftCpIcon = await _buildNumberedMarker(
        _checkpoints.length + 1, const Color(0xFF8E24AA),
        dpr: dpr);
    if (mounted) setState(() {});
  }

  Future<amap_map.BitmapDescriptor> _buildNumberedMarker(int seq, Color fill,
      {double? dpr}) async {
    final d = dpr ?? MediaQuery.of(context).devicePixelRatio;
    final r = 11.0 * d;
    final borderW = 2.0 * d;
    final size = (r + borderW) * 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
    final cx = size / 2;
    final cy = size / 2;
    canvas.drawCircle(
        Offset(cx, cy), r + borderW / 2, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = fill);
    final tp = TextPainter(
      text: TextSpan(
        text: '$seq',
        style: TextStyle(
          color: Colors.white,
          fontSize: 13 * d,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return amap_map.BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }

  amap_map.BitmapDescriptor _cpIcon(int seq) {
    return _cpMarkerCache[seq] ?? amap_map.BitmapDescriptor.defaultMarker;
  }

  void _enterCheckpointPickMode() {
    if (_selectedTrail == null) return;
    if (_checkpoints.length >= 4) {
      _toast('Max 4 checkpoints');
      return;
    }
    setState(() => _isPickingCheckpoint = true);
    _warmDraftIcon();
    if (_trailRoute.isNotEmpty && _mapReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitTrailBounds(_trailRoute);
      });
    }
  }

  void _exitCheckpointPickMode() {
    setState(() => _isPickingCheckpoint = false);
    if (_trailRoute.isNotEmpty && _mapReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitTrailBounds(_trailRoute);
      });
    }
  }

  Future<void> _confirmCheckpointAtCenter() async {
    if (_selectedTrail == null) return;
    final id = int.tryParse(_selectedTrail!.id ?? '');
    if (id == null) return;
    if (_trailRoute.length < 2) {
      _toast('Trail has no path', isError: true);
      return;
    }
    setState(() => _addingCheckpoint = true);
    try {
      final cpPos = _positionAtFraction(_sliderT);
      final resp = await TraxApi.addTrailCheckpoint(
          id, cpPos.latitude, cpPos.longitude);
      if (!mounted) return;
      if (resp.isSuccess() && resp.data is List) {
        setState(() {
          _checkpoints = (resp.data as List)
              .map((e) => UserCheckpoint.fromJson(e as Map<String, dynamic>))
              .toList();
          _recomputeCheckpointTicks();
        });
        _warmCpMarkers();
        _draftCpIcon = null;
        _warmDraftIcon();
      } else {
        _toast(
            resp.message.isNotEmpty
                ? resp.message
                : 'Failed to add checkpoint',
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _addingCheckpoint = false);
    }
  }

  Future<void> _deleteCheckpoint(UserCheckpoint cp) async {
    final resp = await TraxApi.deleteTrailCheckpoint(cp.id);
    if (!mounted) return;
    if (resp.isSuccess() && resp.data is List) {
      setState(() {
        _checkpoints = (resp.data as List)
            .map((e) => UserCheckpoint.fromJson(e as Map<String, dynamic>))
            .toList();
        _recomputeCheckpointTicks();
      });
      _warmCpMarkers();
      _draftCpIcon = null;
      _warmDraftIcon();
    } else {
      _toast(resp.message.isNotEmpty ? resp.message : 'Failed to delete',
          isError: true);
    }
  }

  // ── My Location ───────────────────────────────────────────
  /// Re-centers the map on the rider's current location.
  ///
  /// Mirrors the Free Ride behavior: for module bikes we require live
  /// module telemetry — there is NO silent fallback to phone GPS,
  /// because the rider needs to know the bike module has no signal
  /// before starting the session. Phone-only bikes use phone GPS and
  /// the native AMap blue dot.
  Future<void> _onMyLocationTap() async {
    if (_hasModule) {
      if (_svc.telemetry == null) {
        if (!mounted) return;
        _toast('Unable to get bike module signal', isError: true);
        return;
      }
      if (_mapController != null) {
        await _mapController!.moveCamera(
          amap_map.CameraUpdate.newLatLngZoom(
              AmapAdapter.toAmap(_svc.currentPos), 16),
        );
      }
      return;
    }

    // Phone-only path: actively re-query the OS.
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        _toast('Unable to get phone GPS signal', isError: true);
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      final target = LatLng(p.latitude, p.longitude);
      setState(() => _userLocation = target);
      if (_mapController != null) {
        await _mapController!.moveCamera(
          amap_map.CameraUpdate.newLatLngZoom(
              AmapAdapter.toAmap(target), 16),
        );
      }
    } catch (_) {
      if (!mounted) return;
      _toast('Unable to get phone GPS signal', isError: true);
    }
  }

  Future<void> _onStartSession() async {
    if (_selectedTrail == null) return;
    final ok = await LocationSignalGate.ensureSignalOrConfirm(
      context: context,
      bike: widget.selectedBike,
    );
    if (!ok || !mounted) return;
    MapRouter.openLapTimer(
      context,
      selectedBike: widget.selectedBike,
      trail: _selectedTrail!,
      targetLaps: _targetLaps,
      autoStart: true,
      replace: true,
    );
  }

  /// Top-of-screen banner matching the Free Ride / Trails snackbar
  /// style — renders just below the topbar via the root overlay so
  /// every page surfaces errors in the same spot.
  void _toast(String msg, {bool isError = false}) {
    showTraxSnackBar(context, msg, isError: isError);
  }

  Set<Factory<OneSequenceGestureRecognizer>> get _gestures =>
      <Factory<OneSequenceGestureRecognizer>>{
        Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
      };

  @override
  Widget build(BuildContext context) =>
      PageCodeBadge(code: '404A', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isPickingCheckpoint
          ? _buildCheckpointPickView()
          : _buildMainView(),
    );
  }

  // ── Main view ────────────────────────────────────────────
  Widget _buildMainView() {
    final safeTop = MediaQuery.of(context).padding.top;
    final screenH = MediaQuery.of(context).size.height;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final collapsedPx = 100.0 + safeBottom;
    final minSize = (collapsedPx / screenH).clamp(0.10, 0.30);
    final expandedPx = _estimatedExpandedPx(safeBottom);
    final maxSize = (expandedPx / screenH).clamp(minSize + 0.05, 0.92);
    final mapBottomPx = _sheetSizePx > 0 ? _sheetSizePx : expandedPx;

    LatLng mapCenter;
    if (_trailRoute.isNotEmpty) {
      mapCenter = _trailRoute[_trailRoute.length ~/ 2];
    } else if (_userLocation != null) {
      mapCenter = _userLocation!;
    } else {
      mapCenter = const LatLng(22.8956, 113.8739);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        amap_map.AMapWidget(
          privacyStatement: AmapAdapter.privacy(),
          apiKey: AmapAdapter.apiKey(),
          initialCameraPosition: amap_map.CameraPosition(
            target: AmapAdapter.toAmap(mapCenter),
            zoom: 15,
          ),
          // Native AMap blue-dot is phone GPS — hide it on module bikes
          // so the map only ever shows the bike's location.
          myLocationStyleOptions: amap_map.MyLocationStyleOptions(
            !_hasModule,
            circleFillColor: AppColors.primary.withValues(alpha: 0.15),
            circleStrokeColor: AppColors.primary,
            circleStrokeWidth: 1,
          ),
          scrollGesturesEnabled: true,
          zoomGesturesEnabled: true,
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          gestureRecognizers: _gestures,
          polylines: {
            if (_trailRoute.length >= 2) ...[
              AmapAdapter.routePolyline(_trailRoute,
                  color: MapStyles.trailHaloColor,
                  width: MapStyles.trailHaloWidth),
              AmapAdapter.routePolyline(_trailRoute,
                  color: MapStyles.trailColor,
                  width: MapStyles.trailWidth),
            ],
          },
          markers: {
            if (_trailRoute.isNotEmpty)
              amap_map.Marker(
                position: AmapAdapter.toAmap(_trailRoute.first),
                icon: StartEndMarkerIconsAmap.start,
                anchor: const Offset(0.5, 0.5),
                infoWindow: const amap_map.InfoWindow(
                    title: 'Start / Finish'),
              ),
            // Module bike → native AMap blue dot suppressed; draw our
            // own once the module reports a fix.
            if (_hasModule && _svc.telemetry != null)
              amap_map.Marker(
                position: AmapAdapter.toAmap(_svc.currentPos),
                icon: amap_map.BitmapDescriptor.defaultMarker,
                anchor: const Offset(0.5, 0.5),
                infoWindow: const amap_map.InfoWindow(
                    title: 'My bike location'),
              ),
            for (final cp in _checkpoints)
              amap_map.Marker(
                position: AmapAdapter.toAmap(
                    LatLng(cp.latitude, cp.longitude)),
                icon: _cpIcon(cp.sequenceIndex),
                anchor: const Offset(0.5, 0.5),
                infoWindow: amap_map.InfoWindow(
                    title: 'Checkpoint ${cp.sequenceIndex}'),
              ),
          },
          onMapCreated: (c) {
            _mapController = c;
            _mapReady = true;
            if (_trailRoute.isNotEmpty) {
              _fitTrailBounds(_trailRoute);
            } else if (_userLocation != null) {
              c.moveCamera(amap_map.CameraUpdate.newLatLngZoom(
                  AmapAdapter.toAmap(_userLocation!), 15));
            }
          },
        ),

        if (_isLoadingRoute)
          Positioned(
            top: safeTop + 56, left: 0, right: 0,
            child: const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              ),
            ),
          ),

        // Top bar
        Positioned(
          top: safeTop + 8, left: 12, right: 12,
          child: Row(
            children: [
              _circleBtn(Icons.arrow_back,
                  () => Navigator.of(context).pop()),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 6),
                    ],
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.timer, size: 18, color: AppColors.primary),
                      SizedBox(width: 6),
                      Text('Lap Timer Setup',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // My-location FAB
        Positioned(
          right: 14,
          bottom: mapBottomPx + 12,
          child: MyLocationFab(onTap: _onMyLocationTap),
        ),

        // Live satellite count (module bikes only)
        if (_hasModule)
          Positioned(
            top: safeTop + 56,
            right: 12,
            child: SatelliteBadge(count: _svc.telemetry?.satellites),
          ),

        // Bottom draggable sheet — manual snap so a small downward drag
        // anywhere on the body collapses it. Start button is pinned
        // BELOW as a Positioned widget so its Y stays constant across
        // snap states.
        DraggableScrollableSheet(
          controller: _sheetCtl,
          initialChildSize: maxSize,
          minChildSize: minSize,
          maxChildSize: maxSize,
          snap: false,
          builder: (ctx, scrollController) {
            _sheetMinSize = minSize;
            _sheetMaxSize = maxSize;
            return Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                if (_sheetCtl.isAttached) {
                  _dragStartExtent = _sheetCtl.size;
                }
              },
              onPointerUp: (_) => _snapAfterDrag(),
              onPointerCancel: (_) => _snapAfterDrag(),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 8, offset: Offset(0, -2)),
                  ],
                ),
                child: _buildSheetBody(scrollController),
              ),
            );
          },
        ),
      ],
    );
  }

  double _estimatedExpandedPx(double safeBottom) {
    // handle (10 top + 4 bar + 8 bottom = 22)
    // + Start button area (14 top gap + 50 button + 12 bottom + safeBottom)
    double h = 22 + 14 + 50 + 12 + safeBottom;
    if (_isLoadingTrails) {
      h += 80;
    } else if (_selectedTrail == null) {
      h += 182;
    } else {
      h += 140;
      h += 14;
      h += 150;
      h += 14;
      h += 56;
    }
    return h;
  }

  Widget _buildSheetBody(ScrollController scrollController) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final screenH = MediaQuery.of(context).size.height;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final target = (_sheetCtl.size >
                    (_sheetMinSize + _sheetMaxSize) / 2)
                ? _sheetMinSize
                : _sheetMaxSize;
            _sheetCtl.animateTo(target,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut);
            Future.delayed(const Duration(milliseconds: 240), _refitMapToSheet);
          },
          onVerticalDragUpdate: (d) {
            final next = (_sheetCtl.size - d.delta.dy / screenH)
                .clamp(_sheetMinSize, _sheetMaxSize);
            _sheetCtl.jumpTo(next);
          },
          onVerticalDragEnd: (_) {
            final mid = (_sheetMinSize + _sheetMaxSize) / 2;
            _sheetCtl.animateTo(
                _sheetCtl.size >= mid ? _sheetMaxSize : _sheetMinSize,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut);
            Future.delayed(const Duration(milliseconds: 240), _refitMapToSheet);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            color: AppColors.surface,
            child: Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            controller: scrollController,
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isLoadingTrails)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(
                          color: AppColors.primary),
                    ),
                  )
                else if (_selectedTrail == null)
                  _buildPickPrompt()
                else ...[
                  _buildSelectedTrailCard(_selectedTrail!),
                  const SizedBox(height: 14),
                  _buildCheckpointsSection(),
                  const SizedBox(height: 14),
                  _buildTargetLapsRow(),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, safeBottom + 12),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: (_isLoadingTrails || _selectedTrail == null)
                  ? null
                  : _onStartSession,
              icon: const Icon(Icons.play_arrow, size: 22),
              label: Text(
                _selectedTrail == null
                    ? 'Select Trail to Start'
                    : 'Start $_targetLaps-Lap Session',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppColors.primary.withValues(alpha: 0.4),
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPickPrompt() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            children: [
              Icon(Icons.explore_outlined,
                  size: 40, color: AppColors.textSecondary),
              SizedBox(height: 8),
              Text('No trail selected',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              SizedBox(height: 4),
              Text('Pick a lap trail to begin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _trails.isEmpty
                ? null
                : () => _openTrailSelector(initial: true),
            icon: const Icon(Icons.list, size: 20),
            label: Text(
                _trails.isEmpty ? 'No lap trails available' : 'Select Trail',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedTrailCard(Trail trail) {
    final id = int.tryParse(trail.id ?? '');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildTrailThumb(id, trail.imageUrl),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.loop,
                            size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            trail.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _difficultyColor(trail.difficulty)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _difficultyLabel(trail.difficulty),
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: _difficultyColor(trail.difficulty)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(trail.distance ?? 0).toStringAsFixed(2)} km · ${trail.creatorName ?? ""}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: () => _openTrailSelector(initial: false),
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: const Text('Change',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _infoStat(Icons.straighten,
                      '${(trail.distance ?? 0).toStringAsFixed(2)} km')),
              Expanded(
                  child: _infoStat(Icons.trending_up,
                      '${(trail.elevation ?? 0).toStringAsFixed(0)} m')),
              Expanded(
                  child: _infoStat(
                      Icons.scatter_plot, '$_trailPointCount pts')),
            ],
          ),
          if (trail.location != null && trail.location!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.location_on,
                    size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    trail.location!,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCheckpointsSection() {
    final n = _checkpoints.length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text('Checkpoints ($n/4)',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const Spacer(),
              TextButton.icon(
                onPressed: n >= 4 ? null : _enterCheckpointPickMode,
                icon: const Icon(Icons.add_location_alt, size: 16),
                label: const Text('Add', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ],
          ),
          if (n == 0)
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 2),
              child: Text(
                'No personal checkpoints yet. Add up to 4 to split this lap.',
                style:
                    TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6, runSpacing: 6,
                children: _checkpoints
                    .map((cp) => Chip(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.08),
                          side: BorderSide(
                              color: AppColors.primary
                                  .withValues(alpha: 0.3)),
                          label: Text('CP ${cp.sequenceIndex}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary)),
                          deleteIcon: const Icon(Icons.close,
                              size: 14, color: AppColors.error),
                          onDeleted: () => _deleteCheckpoint(cp),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTargetLapsRow() {
    return Row(
      children: [
        const Text('Target Laps',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const Spacer(),
        _lapCountBtn(Icons.remove,
            _targetLaps > 1 ? () => setState(() => _targetLaps--) : null),
        Container(
          width: 56, alignment: Alignment.center,
          child: Text('$_targetLaps',
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary)),
        ),
        _lapCountBtn(Icons.add,
            _targetLaps < 50 ? () => setState(() => _targetLaps++) : null),
      ],
    );
  }

  // ── Checkpoint pick view ─────────────────────────────────
  Widget _buildCheckpointPickView() {
    final safeTop = MediaQuery.of(context).padding.top;

    LatLng mapCenter;
    if (_trailRoute.isNotEmpty) {
      mapCenter = _trailRoute[_trailRoute.length ~/ 2];
    } else if (_userLocation != null) {
      mapCenter = _userLocation!;
    } else {
      mapCenter = const LatLng(22.8956, 113.8739);
    }

    final draftPos = _trailRoute.length >= 2
        ? _positionAtFraction(_sliderT)
        : (_trailRoute.isNotEmpty ? _trailRoute.first : mapCenter);

    return Stack(
      fit: StackFit.expand,
      children: [
        amap_map.AMapWidget(
          privacyStatement: AmapAdapter.privacy(),
          apiKey: AmapAdapter.apiKey(),
          initialCameraPosition: amap_map.CameraPosition(
            target: AmapAdapter.toAmap(mapCenter),
            zoom: 16,
          ),
          scrollGesturesEnabled: true,
          zoomGesturesEnabled: true,
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          gestureRecognizers: _gestures,
          polylines: {
            if (_trailRoute.length >= 2) ...[
              AmapAdapter.routePolyline(_trailRoute,
                  color: MapStyles.trailHaloColor,
                  width: MapStyles.trailHaloWidth),
              AmapAdapter.routePolyline(_trailRoute,
                  color: MapStyles.trailColor,
                  width: MapStyles.trailWidth),
            ],
          },
          markers: {
            if (_trailRoute.isNotEmpty)
              amap_map.Marker(
                position: AmapAdapter.toAmap(_trailRoute.first),
                icon: StartEndMarkerIconsAmap.start,
                anchor: const Offset(0.5, 0.5),
              ),
            // Module bike → native AMap blue dot suppressed; draw our
            // own once the module reports a fix.
            if (_hasModule && _svc.telemetry != null)
              amap_map.Marker(
                position: AmapAdapter.toAmap(_svc.currentPos),
                icon: amap_map.BitmapDescriptor.defaultMarker,
                anchor: const Offset(0.5, 0.5),
                infoWindow: const amap_map.InfoWindow(
                    title: 'My bike location'),
              ),
            for (final cp in _checkpoints)
              amap_map.Marker(
                position: AmapAdapter.toAmap(
                    LatLng(cp.latitude, cp.longitude)),
                icon: _cpIcon(cp.sequenceIndex),
                anchor: const Offset(0.5, 0.5),
                infoWindow: amap_map.InfoWindow(
                    title: 'Checkpoint ${cp.sequenceIndex}'),
              ),
            if (_trailRoute.length >= 2 && _checkpoints.length < 4)
              amap_map.Marker(
                position: AmapAdapter.toAmap(draftPos),
                icon: _draftCpIcon ??
                    amap_map.BitmapDescriptor.defaultMarker,
                anchor: const Offset(0.5, 0.5),
                zIndex: 5,
                infoWindow: amap_map.InfoWindow(
                    title:
                        'New Checkpoint ${_checkpoints.length + 1}'),
              ),
          },
          onMapCreated: (c) {
            _mapController = c;
            _mapReady = true;
            if (_trailRoute.isNotEmpty) _fitTrailBounds(_trailRoute);
          },
          onCameraMove: (_) {},
          onCameraMoveEnd: (_) {},
        ),

        Positioned(
          top: safeTop + 8, left: 12, right: 12,
          child: Row(
            children: [
              _circleBtn(Icons.arrow_back, _exitCheckpointPickMode),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 6),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.flag,
                          size: 18, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Add Checkpoint  ${_checkpoints.length}/4',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Live satellite count (module bikes only)
        if (_hasModule)
          Positioned(
            top: safeTop + 56,
            right: 12,
            child: SatelliteBadge(count: _svc.telemetry?.satellites),
          ),

        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8, offset: Offset(0, -2)),
              ],
            ),
            padding: EdgeInsets.fromLTRB(
                16, 14, 16, MediaQuery.of(context).padding.bottom + 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.tune,
                        color: AppColors.primary, size: 16),
                    const SizedBox(width: 6),
                    const Text(
                      'Drag the slider to position the checkpoint along the trail',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildCheckpointSlider(),
                const SizedBox(height: 4),
                if (_checkpoints.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, top: 4),
                    child: Wrap(
                      spacing: 6, runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: _checkpoints
                          .map((cp) => Chip(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4),
                                backgroundColor: AppColors.primary
                                    .withValues(alpha: 0.08),
                                side: BorderSide(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.3)),
                                label: Text('CP ${cp.sequenceIndex}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary)),
                                deleteIcon: const Icon(Icons.close,
                                    size: 14, color: AppColors.error),
                                onDeleted: () => _deleteCheckpoint(cp),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ))
                          .toList(),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _addingCheckpoint
                            ? null
                            : _exitCheckpointPickMode,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: BorderSide(
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Done'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: (_addingCheckpoint ||
                                _checkpoints.length >= 4)
                            ? null
                            : _confirmCheckpointAtCenter,
                        icon: _addingCheckpoint
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.add_location_alt,
                                size: 18, color: Colors.white),
                        label: Text(
                          _addingCheckpoint ? 'Adding…' : 'Add',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckpointSlider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 18,
            child: LayoutBuilder(
              builder: (ctx, c) {
                return Stack(
                  children: [
                    for (var i = 0; i < _checkpointTicks.length; i++)
                      Positioned(
                        left: (c.maxWidth - 10) * _checkpointTicks[i] + 5,
                        top: 2,
                        child: Container(
                          width: 2,
                          height: 14,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: AppColors.primary,
              inactiveTrackColor:
                  AppColors.primary.withValues(alpha: 0.25),
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.18),
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 9),
            ),
            child: Slider(
              value: _sliderT,
              min: 0,
              max: 1,
              onChanged: _trailRoute.length < 2 || _addingCheckpoint
                  ? null
                  : (v) => setState(() => _sliderT = v),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('Start',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600)),
              Text('End',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Small helpers ─────────────────────────────────────────
  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40, height: 40,
          child: Icon(icon, size: 20, color: AppColors.textPrimary),
        ),
      ),
    );
  }

  Widget _lapCountBtn(IconData icon, VoidCallback? onTap) {
    return Material(
      color: onTap != null
          ? AppColors.primary.withValues(alpha: 0.1)
          : AppColors.background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36, height: 36,
          child: Icon(icon,
              size: 20,
              color: onTap != null
                  ? AppColors.primary
                  : AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildTrailThumb(int? trailId, [String? serverImageUrl]) {
    if (trailId == null) {
      return Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.terrain,
            color: AppColors.textSecondary, size: 24),
      );
    }
    final cached = trailThumbCache[trailId];
    if (cached != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(cached, width: 64, height: 64, fit: BoxFit.cover),
      );
    }
    return FutureBuilder<TrailThumbnailResult>(
      future: loadTrailThumbnail(trailId, serverImageUrl: serverImageUrl),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final bytes = snap.data?.bytes;
        if (bytes != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(bytes,
                width: 64, height: 64, fit: BoxFit.cover),
          );
        }
        return Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.terrain,
              color: AppColors.textSecondary, size: 24),
        );
      },
    );
  }

  Color _difficultyColor(String d) {
    switch (d.toLowerCase()) {
      case 'easy':
        return AppColors.success;
      case 'medium':
        return AppColors.primary;
      case 'hard':
        return Colors.orange;
      case 'extreme':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  String _difficultyLabel(String d) {
    if (d.isEmpty) return 'Medium';
    return d[0].toUpperCase() + d.substring(1);
  }

  Widget _infoStat(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(value,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      ],
    );
  }
}

// ── Trail picker bottom-sheet (identical to the Google version) ──

class _TrailPickerSheet extends StatefulWidget {
  final List<Trail> trails;
  final String? initialSelectedId;
  final bool showCancel;

  const _TrailPickerSheet({
    required this.trails,
    required this.initialSelectedId,
    required this.showCancel,
  });

  @override
  State<_TrailPickerSheet> createState() => _TrailPickerSheetState();
}

class _TrailPickerSheetState extends State<_TrailPickerSheet> {
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialSelectedId;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxH = mq.size.height * 0.75;
    final hasSelection = _selectedId != null;

    return PopScope(
      canPop: widget.showCancel,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(0, 8, 0, mq.padding.bottom + 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.loop, size: 18, color: AppColors.primary),
                  SizedBox(width: 6),
                  Text('Select Trail',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: widget.trails.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No lap trails available.\nRecord one first in Trails tab.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: widget.trails.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final t = widget.trails[i];
                        final isSel = t.id == _selectedId;
                        return _TrailPickerRow(
                          trail: t,
                          selected: isSel,
                          onTap: () => setState(() => _selectedId = t.id),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  if (widget.showCancel) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: BorderSide(
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.4)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: widget.showCancel ? 2 : 1,
                    child: ElevatedButton(
                      onPressed: hasSelection
                          ? () {
                              final picked = widget.trails.firstWhere(
                                  (e) => e.id == _selectedId);
                              Navigator.of(context).pop(picked);
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hasSelection
                            ? AppColors.primary
                            : AppColors.divider,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                      ),
                      child: const Text('OK',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrailPickerRow extends StatelessWidget {
  final Trail trail;
  final bool selected;
  final VoidCallback onTap;

  const _TrailPickerRow({
    required this.trail,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final id = int.tryParse(trail.id ?? '');
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            _thumb(id, trail.imageUrl),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.loop,
                          size: 14,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          trail.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? AppColors.primary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _diffColor(trail.difficulty)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _diffLabel(trail.difficulty),
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: _diffColor(trail.difficulty)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${(trail.distance ?? 0).toStringAsFixed(2)} km · ${trail.creatorName ?? ""}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (selected)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.check_circle,
                    color: AppColors.primary, size: 22),
              ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(int? trailId, [String? serverImageUrl]) {
    if (trailId == null) {
      return Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.terrain,
            color: AppColors.textSecondary, size: 22),
      );
    }
    final cached = trailThumbCache[trailId];
    if (cached != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(cached, width: 56, height: 56, fit: BoxFit.cover),
      );
    }
    return FutureBuilder<TrailThumbnailResult>(
      future: loadTrailThumbnail(trailId, serverImageUrl: serverImageUrl),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final bytes = snap.data?.bytes;
        if (bytes != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(bytes,
                width: 56, height: 56, fit: BoxFit.cover),
          );
        }
        return Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.terrain,
              color: AppColors.textSecondary, size: 22),
        );
      },
    );
  }

  Color _diffColor(String d) {
    switch (d.toLowerCase()) {
      case 'easy':
        return AppColors.success;
      case 'medium':
        return AppColors.primary;
      case 'hard':
        return Colors.orange;
      case 'extreme':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  String _diffLabel(String d) {
    if (d.isEmpty) return 'Medium';
    return d[0].toUpperCase() + d.substring(1);
  }
}
