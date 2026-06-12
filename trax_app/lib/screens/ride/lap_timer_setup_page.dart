import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../common/services/location_service.dart';

import '../../common/utils/location_signal_gate.dart';
import '../../common/utils/map_gesture_recognizers.dart';
import '../../common/utils/start_end_marker_icons.dart';
import '../../common/utils/trail_thumbnail.dart';
import '../../common/network/trax_api.dart';
import '../../common/widgets/page_code_badge.dart';
import '../../models/ebike.dart';
import '../../models/trail.dart';
import '../../models/user_checkpoint.dart';
import '../../services/active_ride_service.dart';
import '../../common/utils/map_styles.dart';
import '../../theme/app_theme.dart';
import '../../common/widgets/map_router.dart';
import '../../common/widgets/my_location_fab.dart';
import '../../common/widgets/satellite_badge.dart';

/// Lap Timer Setup
///
/// Layout:
///   ┌──────────────────────────┐
///   │           MAP            │  ~ top 45%
///   │      (selected trail)    │
///   ├──────────────────────────┤
///   │  Selected Trail card     │  bottom panel (selected trail
///   │  Checkpoints (0/4) [Add] │   info + checkpoints + laps +
///   │  Target Laps  −  3  +    │   start session)
///   │  [ Start N-Lap Session ] │
///   └──────────────────────────┘
///
/// On first entry the trail selector bottom-sheet is automatically opened
/// (OK only — user must choose). Tapping the small "Change" button on the
/// trail card re-opens the same sheet with both Cancel and OK buttons.
///
/// Checkpoint placement uses a full-screen map with a centered drop pin
/// and a Cancel / "Add Checkpoint" action bar (max 4 per user-trail).
class LapTimerSetupPage extends StatefulWidget {
  final EBike selectedBike;
  final Trail? initialTrail;
  const LapTimerSetupPage({
    super.key,
    required this.selectedBike,
    this.initialTrail,
  });

  @override
  State<LapTimerSetupPage> createState() => _LapTimerSetupPageState();
}

class _LapTimerSetupPageState extends State<LapTimerSetupPage> {
  final _svc = ActiveRideService.instance;
  bool get _hasModule =>
      (widget.selectedBike.traxSerialNumber ?? '').isNotEmpty;

  // Bottom sheet controller — lets the pinned handle resize the sheet.
  final DraggableScrollableController _sheetCtl =
      DraggableScrollableController();
  double _sheetMinSize = 0.10;
  double _sheetMaxSize = 0.60;
  // Live sheet height in logical px (updated by _sheetCtl listener).
  // Drives GoogleMap bottom padding so the visible area above the sheet
  // stays in sync as the user drags / snaps.
  double _sheetSizePx = 0;
  // Sheet extent when the most recent finger-down started; used to bias
  // the manual snap so a small downward drag anywhere on the body
  // collapses the sheet.
  double _dragStartExtent = 0;

  // ── Data ──────────────────────────────────────────────────
  List<Trail> _trails = [];
  bool _isLoadingTrails = true;
  Trail? _selectedTrail;
  int _targetLaps = 3;

  // Trail route preview
  List<LatLng> _trailRoute = [];
  bool _isLoadingRoute = false;
  int _trailPointCount = 0;

  // Map
  GoogleMapController? _mapController;
  bool _mapReady = false;
  LatLng? _userLocation;

  // Checkpoints
  List<UserCheckpoint> _checkpoints = [];
  bool _isPickingCheckpoint = false;
  bool _addingCheckpoint = false;

  // ── Slider-along-trail checkpoint placement ─────────────
  // Cumulative metres along [_trailRoute]; same length as the route.
  List<double> _cumDistM = const [];
  double _trailLengthM = 0;
  // Slider value in [0, 1] mapping to arc-length along the trail.
  double _sliderT = 0.5;
  // Existing checkpoint positions expressed as a fraction along the trail
  // (0..1) so they can be drawn as ticks on the slider.
  List<double> _checkpointTicks = const [];

  // Cache of numbered checkpoint marker bitmaps, keyed by sequence index.
  final Map<int, BitmapDescriptor> _cpMarkerCache = {};

  bool _autoSelectorShown = false;

  // ── Lifecycle ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    // Keep map bottom-padding in sync with the sheet size so the trail
    // stays framed in the visible area above the sheet.
    _sheetCtl.addListener(_onSheetSizeChanged);
    _bootstrap();
    // Pre-Start preview: subscribe to module telemetry so the
    // my-location button can show the bike's live position before the
    // rider taps Start. Pre-Start frames are NOT persisted (see
    // ActiveRideService._onModuleTelemetryJson).
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
      _mapController!
          .animateCamera(CameraUpdate.newLatLngZoom(_userLocation!, 15));
    }
  }

  /// Manual snap-on-release with a downward-drag bias: any drag that
  /// moved the sheet downward by more than a small threshold collapses,
  /// any drag upward by the same threshold expands. This lets the user
  /// collapse the sheet by dragging anywhere on the body (not just the
  /// handle), without waiting until they've crossed the midpoint.
  void _snapAfterDrag() {
    if (!_sheetCtl.isAttached) return;
    final cur = _sheetCtl.size;
    final range = (_sheetMaxSize - _sheetMinSize).clamp(0.0001, 1.0);
    final delta = cur - _dragStartExtent;
    const threshold = 0.04; // ~30–40px of finger travel
    double target;
    if (delta < -threshold) {
      target = _sheetMinSize;
    } else if (delta > threshold) {
      target = _sheetMaxSize;
    } else {
      // Tiny drag — snap to nearest.
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
    _mapController?.dispose();
    // Tear down the pre-Start preview subscription if the rider left
    // without starting a ride. No-op if a ride is already active.
    _svc.stopPreview();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadTrails(), _fetchUserLocation()]);
    if (!mounted) return;
    // Auto-open the selector after first frame, only once.
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
      final initial = widget.initialTrail;
      if (initial != null) {
        final match = _trails.where((t) => t.id == initial.id).toList();
        final picked = match.isNotEmpty ? match.first : initial;
        _autoSelectorShown = true;
        await _applySelectedTrail(picked);
      }
    }
    setState(() => _isLoadingTrails = false);
  }

  Future<void> _fetchUserLocation() async {
    // With a module bike, never auto-pan to phone GPS — the bike's own
    // position is the source of truth and the user can tap My Location
    // (which is module-gated) to recenter.
    if (_hasModule) return;
    // Dual-source fix (Geolocator + AMap, first wins) — works indoors in
    // mainland China and never hangs on a satellite-only lock.
    final fix = await LocationService.getFix();
    if (!mounted || fix == null) return;
    _userLocation = fix;
    if (_mapReady && _selectedTrail == null) {
      _mapController
          ?.animateCamera(CameraUpdate.newLatLngZoom(_userLocation!, 15));
    }
  }

  // ── Trail selection ───────────────────────────────────────
  Future<void> _openTrailSelector({required bool initial}) async {
    final picked = await showModalBottomSheet<Trail>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: !initial, // first time: must pick OK
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

    // Load checkpoints in parallel.
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

  /// Linearly interpolate a position along the trail polyline at
  /// fraction [t] in [0, 1] of total arc length.
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

  /// Project [p] onto the polyline and return the arc-length fraction (0..1).
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
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 15));
      return;
    }
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
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

  // Numbered violet draft icon for the next CP about to be added.
  BitmapDescriptor? _draftCpIcon;
  int? _draftCpIconForSeq;
  Future<void> _warmDraftIcon() async {
    final nextSeq = _checkpoints.length + 1;
    if (_draftCpIconForSeq == nextSeq && _draftCpIcon != null) return;
    final icon =
        await _buildNumberedMarker(nextSeq, const Color(0xFF8E24AA));
    if (!mounted) return;
    setState(() {
      _draftCpIcon = icon;
      _draftCpIconForSeq = nextSeq;
    });
  }

  Future<BitmapDescriptor> _buildNumberedMarker(int seq, Color fill) async {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // Match the smaller circular badge style used for start/finish.
    final r = 11.0 * dpr;
    final borderW = 2.0 * dpr;
    final size = (r + borderW) * 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
    final cx = size / 2;
    final cy = size / 2;
    canvas.drawCircle(
        Offset(cx, cy), r + borderW / 2, Paint()..color = Colors.white);
    canvas.drawCircle(
        Offset(cx, cy), r, Paint()..color = fill);
    final tp = TextPainter(
      text: TextSpan(
        text: '$seq',
        style: TextStyle(
          color: Colors.white,
          fontSize: 13 * dpr,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      byteData!.buffer.asUint8List(),
      width: size / dpr,
      height: size / dpr,
    );
  }

  BitmapDescriptor _cpIcon(int seq) {
    return _cpMarkerCache[seq] ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
  }

  void _enterCheckpointPickMode() {
    if (_selectedTrail == null) return;
    if (_checkpoints.length >= 4) {
      _toast('Max 4 checkpoints');
      return;
    }
    setState(() => _isPickingCheckpoint = true);
    _warmDraftIcon();
    // Re-fit so user sees the trail in the full-screen map.
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
      // Compute the position from the slider's arc-length fraction —
      // by construction this lies on the trail polyline, so the
      // server-side "not on the trail" check will always pass.
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

  double _checkpointBottomBarHeight() =>
      120 + MediaQuery.of(context).padding.bottom;

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
  /// before starting the session. Phone-only bikes use phone GPS.
  Future<void> _onMyLocationTap() async {
    if (_hasModule) {
      if (_svc.telemetry == null) {
        if (!mounted) return;
        _toast('Unable to get bike module signal', isError: true);
        return;
      }
      if (_mapController != null) {
        await _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(_svc.currentPos, 16));
      }
      return;
    }

    // Phone-only path: dual-source fix (Geolocator + AMap, first wins).
    final fix = await LocationService.getFix();
    if (!mounted) return;
    if (fix == null) {
      _toast('Unable to get phone GPS signal', isError: true);
      return;
    }
    setState(() => _userLocation = fix);
    if (_mapController != null) {
      await _mapController!
          .animateCamera(CameraUpdate.newLatLngZoom(fix, 16));
    }
  }

  // ── Start Session ─────────────────────────────────────────
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

  // ── Helpers ───────────────────────────────────────────────
  /// Top-of-screen banner matching the Free Ride / Trails snackbar
  /// style — renders just below the topbar via the root overlay so
  /// every page surfaces errors in the same spot.
  void _toast(String msg, {bool isError = false}) {
    showTraxSnackBar(context, msg, isError: isError);
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) =>
      PageCodeBadge(code: '404', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isPickingCheckpoint
          ? _buildCheckpointPickView()
          : _buildMainView(),
    );
  }

  // ───────────────────────────────────────────────────────────
  // MAIN VIEW (Full-screen map + DraggableScrollableSheet)
  // ───────────────────────────────────────────────────────────
  Widget _buildMainView() {
    final safeTop = MediaQuery.of(context).padding.top;
    final screenH = MediaQuery.of(context).size.height;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    // Sheet collapsed = handle + Start button + paddings.
    final collapsedPx = 100.0 + safeBottom;
    final minSize = (collapsedPx / screenH).clamp(0.10, 0.30);
    // Expanded size estimated from current content so the card stops
    // exactly at its content end (mirrors the Map-tab trail-card popup).
    final expandedPx = _estimatedExpandedPx(safeBottom);
    final maxSize = (expandedPx / screenH).clamp(minSize + 0.05, 0.92);
    // Live sheet bottom-padding for the map. Falls back to expandedPx
    // until the controller has reported its first size.
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
        // Full-screen map
        GoogleMap(
          initialCameraPosition: CameraPosition(target: mapCenter, zoom: 15),
          // Hide native blue dot when bike has a TRAX module — location
          // must come from the module, not the phone GPS. Matches AMap.
          myLocationEnabled: !_hasModule,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          gestureRecognizers: kMapGestureRecognizers,
          padding: EdgeInsets.only(bottom: mapBottomPx),
          polylines: {
            if (_trailRoute.length >= 2) ...[
              Polyline(
                polylineId: const PolylineId('trail_halo'),
                points: _trailRoute,
                color: MapStyles.trailHaloColor,
                width: MapStyles.trailHaloWidth,
              ),
              Polyline(
                polylineId: const PolylineId('trail'),
                points: _trailRoute,
                color: MapStyles.trailColor,
                width: MapStyles.trailWidth,
              ),
            ],
          },
          markers: {
            if (_trailRoute.isNotEmpty)
              Marker(
                markerId: const MarkerId('start'),
                position: _trailRoute.first,
                icon: StartEndMarkerIcons.start,
                infoWindow: const InfoWindow(title: 'Start / Finish'),
              ),
            // Module bike → native blue dot is suppressed. Draw our own
            // dot once the module has a fix so the rider sees where the
            // bike is before picking a trail.
            if (_hasModule && _svc.telemetry != null)
              Marker(
                markerId: const MarkerId('me_module'),
                position: _svc.currentPos,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure),
                anchor: const Offset(0.5, 0.5),
                infoWindow:
                    const InfoWindow(title: 'My bike location'),
              ),
            for (final cp in _checkpoints)
              Marker(
                markerId: MarkerId('cp_${cp.id}'),
                position: LatLng(cp.latitude, cp.longitude),
                icon: _cpIcon(cp.sequenceIndex),
                anchor: const Offset(0.5, 0.5),
                infoWindow:
                    InfoWindow(title: 'Checkpoint ${cp.sequenceIndex}'),
              ),
          },
          onMapCreated: (c) {
            _mapController = c;
            _mapReady = true;
            if (_trailRoute.isNotEmpty) {
              _fitTrailBounds(_trailRoute);
            } else if (_userLocation != null) {
              c.animateCamera(
                  CameraUpdate.newLatLngZoom(_userLocation!, 15));
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

        // My-location FAB (just above the sheet — follows its current height)
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

        // Bottom draggable sheet — handle pinned at top, content scrolls
        // in the middle, Start button pinned at bottom (inside the sheet
        // so its background stays opaque). Manual snap so a small
        // downward drag anywhere on the body collapses it.
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

  /// Heuristic content height (in logical px) used to compute the sheet's
  /// expanded snap point. Tuned to actual rendered heights so the card
  /// stops right at the end of its content — no empty space below.
  ///
  /// Card layout (top → bottom): handle, content (trail/checkpoints/laps
  /// OR pick-prompt), Start button.
  double _estimatedExpandedPx(double safeBottom) {
    // handle (10 top + 4 bar + 8 bottom = 22)
    // + Start button area (14 top gap + 50 button + 12 bottom + safeBottom)
    double h = 22 + 14 + 50 + 12 + safeBottom;
    if (_isLoadingTrails) {
      h += 80;
    } else if (_selectedTrail == null) {
      // pick-prompt card (~120) + gap (14) + select-trail button (48)
      h += 182;
    } else {
      h += 140; // selected trail card
      h += 14;
      h += 150; // checkpoints section (header + chips wrap + add)
      h += 14;
      h += 56;  // target laps row
    }
    return h;
  }

  /// Body of the draggable bottom sheet.
  ///
  /// Layout: pinned handle at top → scrollable content (trail /
  /// checkpoints / target laps) → pinned Start button at bottom.
  /// The handle is draggable to resize the sheet and tap-to-toggle
  /// between collapsed and expanded.
  Widget _buildSheetBody(ScrollController scrollController) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final screenH = MediaQuery.of(context).size.height;
    return Column(
      // Hug content height so there's no empty slack pushing the Start
      // button away from the last section. The DSS extent is sized via
      // `_estimatedExpandedPx` to match this column's intrinsic height,
      // which keeps the sheet bottom flush with the button.
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pinned drag handle — always visible. Drag to resize; tap to
        // toggle between collapsed and expanded.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final target = (_sheetCtl.size > (_sheetMinSize + _sheetMaxSize) / 2)
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

        // Scrollable content. Flexible so a tall content set scrolls
        // when the sheet is collapsed, but hugs its intrinsic height
        // when expanded (since the column is MainAxisSize.min).
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

        // Pinned Start button. Top padding = 14 so the gap to Target Laps
        // matches the inter-section spacing (trail → checkpoints → laps).
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

  // ───────────────────────────────────────────────────────────
  // CHECKPOINT PICK VIEW (full-screen map + bottom action bar)
  // ───────────────────────────────────────────────────────────
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

    // Live draft position from the slider — always on the polyline.
    final draftPos = _trailRoute.length >= 2
        ? _positionAtFraction(_sliderT)
        : (_trailRoute.isNotEmpty ? _trailRoute.first : mapCenter);

    return Stack(
      fit: StackFit.expand,
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: mapCenter, zoom: 16),
          // Module bike → suppress phone blue dot. Matches AMap variant.
          myLocationEnabled: !_hasModule,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          gestureRecognizers: kMapGestureRecognizers,
          polylines: {
            if (_trailRoute.length >= 2) ...[
              Polyline(
                polylineId: const PolylineId('trail_halo'),
                points: _trailRoute,
                color: MapStyles.trailHaloColor,
                width: MapStyles.trailHaloWidth,
              ),
              Polyline(
                polylineId: const PolylineId('trail'),
                points: _trailRoute,
                color: MapStyles.trailColor,
                width: MapStyles.trailWidth,
              ),
            ],
          },
          markers: {
            if (_trailRoute.isNotEmpty)
              Marker(
                markerId: const MarkerId('start'),
                position: _trailRoute.first,
                icon: StartEndMarkerIcons.start,
              ),
            // Module bike → native blue dot suppressed; draw a custom
            // my-location marker once the module has a fix.
            if (_hasModule && _svc.telemetry != null)
              Marker(
                markerId: const MarkerId('me_module'),
                position: _svc.currentPos,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure),
                anchor: const Offset(0.5, 0.5),
                infoWindow:
                    const InfoWindow(title: 'My bike location'),
              ),
            for (final cp in _checkpoints)
              Marker(
                markerId: MarkerId('cp_${cp.id}'),
                position: LatLng(cp.latitude, cp.longitude),
                icon: _cpIcon(cp.sequenceIndex),
                anchor: const Offset(0.5, 0.5),
                infoWindow:
                    InfoWindow(title: 'Checkpoint ${cp.sequenceIndex}'),
              ),
            if (_trailRoute.length >= 2 && _checkpoints.length < 4)
              Marker(
                markerId: const MarkerId('cp_draft'),
                position: draftPos,
                icon: _draftCpIcon ??
                    BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueViolet),
                anchor: const Offset(0.5, 0.5),
                zIndex: 5,
                infoWindow: InfoWindow(
                    title: 'New Checkpoint ${_checkpoints.length + 1}'),
              ),
          },
          onMapCreated: (c) {
            _mapController = c;
            _mapReady = true;
            if (_trailRoute.isNotEmpty) _fitTrailBounds(_trailRoute);
          },
        ),

        // Top bar
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

        // Bottom action bar with slider
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
            padding: EdgeInsets.fromLTRB(16, 14, 16,
                MediaQuery.of(context).padding.bottom + 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.tune,
                        color: AppColors.primary, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Drag the slider to position the checkpoint along the trail',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Slider with start/end labels and existing-CP ticks.
                _buildCheckpointSlider(),
                const SizedBox(height: 4),
                // Existing checkpoint chips (delete during placement).
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
                        onPressed:
                            (_addingCheckpoint || _checkpoints.length >= 4)
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
                          _addingCheckpoint
                              ? 'Adding…'
                              : 'Add',
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

  /// Slider that maps to arc-length along the trail polyline. Existing
  /// checkpoints render as small ticks above the track so the user knows
  /// which spots are already occupied.
  Widget _buildCheckpointSlider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Start / End labels with checkpoint tick marks.
          SizedBox(
            height: 18,
            child: LayoutBuilder(
              builder: (ctx, c) {
                return Stack(
                  children: [
                    // Tick marks for existing checkpoints.
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

// ───────────────────────────────────────────────────────────────
// Trail picker bottom-sheet
// ───────────────────────────────────────────────────────────────
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
