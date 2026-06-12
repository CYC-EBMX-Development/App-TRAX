import 'dart:async';
import 'dart:math';

import 'package:amap_flutter_base/amap_flutter_base.dart' show LatLngBounds;
import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../../../common/services/map_service.dart';
import '../../../common/utils/amap_adapter.dart';
import '../../../common/utils/keep_awake_mixin.dart';
import '../../../common/network/trax_api.dart';
import '../../../common/services/module_telemetry_ws_client.dart';
import '../../../common/utils/start_end_marker_icons_amap.dart';
import '../../../common/widgets/bike_picker.dart';
import '../../../common/widgets/map_router.dart';
import '../../../common/widgets/satellite_badge.dart';
import '../../../common/widgets/page_code_badge.dart';
import '../../../models/module_telemetry.dart';
import '../../../common/utils/map_styles.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/map_search_box.dart';
import '../trail_record_mode.dart';

/// Native-AMap variant of `TrailRecordPage` used when the rider is inside
/// Chinese mainland. Phase 4 core implementation: supports the everyday
/// recording flow (Start → Pause/Resume → Stop) rendered on a real
/// `AMapWidget` so map tiles load from AMap (not from `clients4.google.com`
/// which is unreachable in CN and previously froze the main thread).
///
/// Features intentionally NOT ported from the Google variant (scoped to a
/// later phase): location picker, simulate-lap (pick / draw), lap-recording
/// auto-stop, map type switcher, mock GPS replay.
class TrailRecordPageAmap extends StatefulWidget {
  final TrailRecordLaunchMode initialMode;
  const TrailRecordPageAmap({
    super.key,
    this.initialMode = TrailRecordLaunchMode.trailRecord,
  });

  @override
  State<TrailRecordPageAmap> createState() => _TrailRecordPageAmapState();
}

class _TrailRecordPageAmapState extends State<TrailRecordPageAmap>
    with KeepAwakeMixin<TrailRecordPageAmap> {
  AMapController? _mapController;

  String _status = 'idle'; // idle | recording | paused
  static const LatLng _kFallbackPos = LatLng(39.909187, 116.397451);
  LatLng? _currentPos;
  LatLng get _safeCurrentPos => _currentPos ?? _kFallbackPos;

  final List<LatLng> _route = []; // WGS-84
  final List<_RecordedPoint> _points = [];

  StreamSubscription<Position>? _geoSub;
  Timer? _durationTimer;
  Timer? _samplingPollTimer;
  int _durationSeconds = 0;
  String? _errorMessage;

  // ── Adaptive sampling cadence ─────────────────────────────
  // Mirrors the Google variant: phone GPS base cadence is fixed at 1 s
  // (iOS / Android both cap GPS delivery at the GNSS chip's native ~1 Hz),
  // so the user-tunable interval was removed (2026-06-11). The fast-cadence
  // machinery is retained for the future TRAX module variable-rate firmware.
  static const int _kBaseIntervalMs = 1000;
  static const int _kFastIntervalMs = 100;
  static const double _kFastSampleRadiusM = 10.0;
  int _currentIntervalMs = _kBaseIntervalMs;
  double? _lastDistToStartM;
  double? _lastDistToEndM;

  // ── GPS quality filters (off-road trail fidelity) ─────────
  // Drop fixes with reported horizontal accuracy worse than this many
  // metres — urban-canyon / tree-cover multi-path is what pulls the
  // recorded line onto a nearby road. After 5 consecutive drops we
  // accept the next one anyway so we never silently stop recording.
  static const double _kMaxAccuracyM = 25.0;
  static const int _kMaxConsecutiveAccuracyDrops = 5;
  int _consecutiveAccuracyDrops = 0;
  // Reject "teleport" fixes whose implied speed since the previous
  // accepted fix exceeds this many km/h. Two jumps in a row override
  // the filter (in case the rider really did move).
  static const double _kMaxJumpKmh = 120.0;
  int _consecutiveJumpDrops = 0;
  // Ignore micro-jitter while stationary — keeps the polyline clean and
  // avoids growing _route with hundreds of overlapping points.
  static const double _kMinStepMeters = 1.5;
  DateTime? _lastAcceptedFixAt;

  // Bike selection + source switch (Trail Record / Lap Record only).
  List<Map<String, dynamic>> _myBikes = [];
  int? _selectedBikeId;
  ModuleTelemetryWsClient? _moduleWs;
  StreamSubscription<Map<String, dynamic>>? _moduleWsSub;
  String? _moduleSerial;
  // Last position from live bike-module telemetry. `_currentPos` may carry
  // a stale phone-GPS seed, so the locate-me action must rely on this.
  LatLng? _moduleFixPos;
  int? _moduleSatellites; // latest live satellite count from the module

  // ── Lap-recording mode (mirrors Google variant constants). ──
  bool _isLapRecordingMode = false;
  LatLng? _lapStart;
  double? _hX, _hY;
  double _maxAwayKm = 0;
  static const double _kLapMinExcursionKm = 0.15;
  static const int _kLapMinDurationSec = 15;
  static const double _kLapFinishLineHalfWidthKm = 0.015;
  static const double _kHeadingRefMinMeters = 5.0;

  // ── Pick-Points → incremental snap+route → Save ───────────
  // Each tap is snapped to the nearest road by computing a short driving
  // route from the previous waypoint to the tap location and replacing
  // the tap with the route's snapped destination. Each leg's polyline is
  // accumulated in [_legSegments]. Tapping "Confirm" computes the
  // closing leg (last waypoint → first waypoint) and stores it in
  // [_closingLeg]; once present, "Done" is enabled and saves the trail.
  bool _isPickingLapPoints = false;
  final List<LatLng> _lapWaypoints = [];
  final List<List<LatLng>> _legSegments = []; // legs[i] = wp[i] → wp[i+1]
  List<LatLng>? _closingLeg; // last wp → first wp
  bool _isFetchingRoute = false;
  // Legacy mock-mode fields kept (currently unused) so any code paths
  // still referencing them compile; the timers are never started under
  // the new flow.
  bool _isMockMode = false;
  List<LatLng> _mockRoute = [];
  int _mockTickIndex = 0;
  Timer? _mockTimer;
  static const int _kMockIntervalMs = 1000;

  @override
  void initState() {
    super.initState();
    if (_modeUsesBikeSource) {
      unawaited(_loadMyBikes());
    }
    _initLocation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (widget.initialMode) {
        case TrailRecordLaunchMode.trailRecord:
          break;
        case TrailRecordLaunchMode.lap:
          // Do NOT auto-start lap recording — see trail_record_page.dart
          // for rationale. User must press the Start button.
          break;
        case TrailRecordLaunchMode.pickPoint:
          _enterLapPickMode();
          break;
      }
    });
  }

  Future<void> _initLocation() async {
    if (_modeUsesBikeSource && _selectedBikeHasModule) return;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (mounted && _currentPos == null) {
        setState(() => _currentPos = _kFallbackPos);
      }
      return;
    }
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted && _currentPos == null) {
        setState(() => _currentPos = LatLng(last.latitude, last.longitude));
      }
    } catch (_) {}
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (!mounted) return;
      setState(() => _currentPos = LatLng(pos.latitude, pos.longitude));
      _animateToCurrentPos();
    } catch (_) {
      if (mounted && _currentPos == null) {
        setState(() => _currentPos = _kFallbackPos);
      }
    }
  }

  void _animateToCurrentPos() {
    final pos = _currentPos;
    final c = _mapController;
    if (pos != null && c != null) {
      c.moveCamera(CameraUpdate.newLatLng(AmapAdapter.toAmap(pos)),
          animated: true);
    }
  }

  bool get _modeUsesBikeSource =>
      widget.initialMode == TrailRecordLaunchMode.trailRecord ||
      widget.initialMode == TrailRecordLaunchMode.lap;

  Map<String, dynamic>? get _selectedBike {
    final id = _selectedBikeId;
    if (id == null) return null;
    for (final b in _myBikes) {
      if ((b['id'] as num?)?.toInt() == id) return b;
    }
    return null;
  }

  String? get _selectedBikeSerial {
    final raw = _selectedBike?['traxSerialNumber'] as String?;
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  bool get _selectedBikeHasModule => _selectedBikeSerial != null;

  String get _activeSourceLabel =>
      _selectedBikeHasModule ? 'Bike Module' : 'Phone GPS';

  Future<void> _loadMyBikes() async {
    final resp = await TraxApi.getUserBikes();
    if (!mounted || !resp.isSuccess()) return;
    final list = (resp.data as List?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList() ??
        const <Map<String, dynamic>>[];
    setState(() {
      _myBikes = list;
      final stillValid = _selectedBikeId != null &&
          list.any((b) => (b['id'] as num?)?.toInt() == _selectedBikeId);
      if (!stillValid) {
        _selectedBikeId = list.isNotEmpty ? (list.first['id'] as num).toInt() : null;
      }
    });
    if (_status == 'recording') {
      _ensureModuleSubscription();
    } else {
      // Pre-Start preview — see trail_record_page.dart for rationale.
      _ensureModuleSubscription();
    }
  }

  void _onBikeSelected(int? bikeId) {
    if (bikeId == null) return;
    setState(() {
      _selectedBikeId = bikeId;
      _errorMessage = null;
    });
    // Always (re)subscribe — persistence gated in _onModuleFrame.
    _ensureModuleSubscription();
  }

  void _stopModuleSubscription() {
    _moduleWsSub?.cancel();
    _moduleWsSub = null;
    _moduleWs?.dispose();
    _moduleWs = null;
    _moduleSerial = null;
    _moduleFixPos = null;
  }

  void _ensureModuleSubscription() {
    final serial = _selectedBikeSerial;
    if (serial == _moduleSerial && _moduleWs != null) return;
    _stopModuleSubscription();
    if (serial == null || !_selectedBikeHasModule) {
      return;
    }
    final client = ModuleTelemetryWsClient(serialNo: serial);
    _moduleWs = client;
    _moduleSerial = serial;
    _moduleWsSub = client.stream.listen(_onModuleFrame);
    unawaited(client.connect());
  }

  void _onModuleFrame(Map<String, dynamic> json) {
    if (!mounted) return;
    ModuleTelemetry t;
    try {
      t = ModuleTelemetry.fromJson(json);
    } catch (_) {
      return;
    }
    final lat = t.latitude;
    final lng = t.longitude;
    if (lat == 0 && lng == 0) return;
    // Always refresh the latest fix — used by _locateMe regardless of
    // recording state.
    _moduleFixPos = LatLng(lat, lng);
    if (mounted) setState(() => _moduleSatellites = t.satellites);
    // Persist into the recorded route ONLY while actively recording.
    if (_status != 'recording') return;
    final ts = DateTime.tryParse(t.timestamp ?? '') ?? DateTime.now();
    _appendRecordedPoint(
      latlng: LatLng(lat, lng),
      altitude: 0,
      timestamp: ts,
    );
  }

  @override
  void dispose() {
    _geoSub?.cancel();
    _durationTimer?.cancel();
    _samplingPollTimer?.cancel();
    _mockTimer?.cancel();
    _moduleWsSub?.cancel();
    _moduleWs?.dispose();
    _mapController?.disponse(); // SDK typo, this IS the correct method name
    super.dispose();
  }

  LocationSettings _buildLocationSettings(int intervalMs) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: Duration(milliseconds: intervalMs),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'TRAX is recording your trail',
          notificationText: 'Recording continues while the screen is off',
          enableWakeLock: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      // bestForNavigation = Core Location's strictest tier (sub-5 m in
      // the open, anti multi-path); otherNavigation tells iOS this is a
      // vehicle-class session so it won't throttle for power-saving the
      // way ActivityType.fitness does.
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
        activityType: ActivityType.otherNavigation,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
    );
  }

  void _onStart() {
    if (_modeUsesBikeSource && _selectedBikeId == null) {
      setState(() {
        _errorMessage = 'Please select a bike before recording.';
      });
      return;
    }
    setState(() {
      _status = 'recording';
      _errorMessage = null;
    });
    _durationSeconds = 0;
    _route.clear();
    _points.clear();
    _consecutiveAccuracyDrops = 0;
    _consecutiveJumpDrops = 0;
    _lastAcceptedFixAt = null;
    _lapStart = null;
    _hX = null;
    _hY = null;
    _maxAwayKm = 0;

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_status == 'recording') {
        setState(() => _durationSeconds++);
      }
    });
    _currentIntervalMs = _kBaseIntervalMs;
    _lastDistToStartM = null;
    _lastDistToEndM = null;
    if (_modeUsesBikeSource && _selectedBikeHasModule) {
      _ensureModuleSubscription();
    } else {
      _geoSub = Geolocator.getPositionStream(
        locationSettings: _buildLocationSettings(_kBaseIntervalMs),
      ).listen(_onGpsFix);
    }
    // Re-evaluate the cadence once a second even if no fix arrives —
    // useful when the rider is stationary near the start point.
    _samplingPollTimer?.cancel();
    _samplingPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_status != 'recording') return;
      if (_modeUsesBikeSource && _selectedBikeHasModule) return;
      if (_currentPos != null) _maybeAdjustSamplingRate(_currentPos!);
    });
  }

  void _onGpsFix(Position pos) {
    if (!_acceptGpsFix(pos)) return;
    final latlng = LatLng(pos.latitude, pos.longitude);
    _appendRecordedPoint(
      latlng: latlng,
      altitude: pos.altitude,
      timestamp: DateTime.now(),
    );
    _maybeAdjustSamplingRate(latlng);
  }

  /// Drop low-quality / implausible GPS fixes before they are appended
  /// to the recorded route. Returns true when the fix should be kept.
  bool _acceptGpsFix(Position pos) {
    // 1) Accuracy gate — reject low-confidence fixes, but cap the
    //    consecutive-drop streak so a long tree-cover stretch still
    //    records something rather than going silent.
    if (pos.accuracy.isFinite && pos.accuracy > _kMaxAccuracyM) {
      if (_consecutiveAccuracyDrops < _kMaxConsecutiveAccuracyDrops) {
        _consecutiveAccuracyDrops++;
        return false;
      }
    }
    _consecutiveAccuracyDrops = 0;

    if (_route.isNotEmpty && _lastAcceptedFixAt != null) {
      final last = _route.last;
      final dM = Geolocator.distanceBetween(
          last.latitude, last.longitude, pos.latitude, pos.longitude);
      final dtMs =
          DateTime.now().difference(_lastAcceptedFixAt!).inMilliseconds;
      // 2) Jump filter — implausible speeds = multi-path teleport.
      if (dtMs > 0) {
        final implKmh = (dM / dtMs) * 3600.0;
        if (implKmh > _kMaxJumpKmh) {
          if (_consecutiveJumpDrops < 2) {
            _consecutiveJumpDrops++;
            return false;
          }
        }
      }
      _consecutiveJumpDrops = 0;
      // 3) Stationary jitter — drop sub-1.5 m moves so the recorded
      //    polyline doesn't fatten into a blob while stopped.
      if (dM < _kMinStepMeters) return false;
    }

    _lastAcceptedFixAt = DateTime.now();
    return true;
  }

  void _appendRecordedPoint({
    required LatLng latlng,
    required double altitude,
    required DateTime timestamp,
  }) {
    if (!mounted || _status != 'recording') return;
    final prev = _points.isNotEmpty ? _points.last : null;
    final point = _RecordedPoint(
      latitude: latlng.latitude,
      longitude: latlng.longitude,
      altitude: altitude,
      timestamp: timestamp,
    );
    setState(() {
      _currentPos = latlng;
      _route.add(latlng);
      _points.add(point);
    });
    _animateToCurrentPos();
    if (_isLapRecordingMode) {
      _lapModeOnNewPoint(prev, point);
    }
  }

  /// Switch between 1 s and 0.1 s sampling depending on proximity to the
  /// start/end of the recording. Fast cadence only triggers when the rider
  /// is *approaching* a boundary (distance shrinking AND inside
  /// [_kFastSampleRadiusM]); once they cross and start moving away, we
  /// revert to the 1 s base rate.
  void _maybeAdjustSamplingRate(LatLng pos) {
    if (_modeUsesBikeSource && _selectedBikeHasModule) return;
    if (_status != 'recording' || _route.isEmpty) return;
    final start = _route.first;
    final end = _route.last;
    final dStart = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, start.latitude, start.longitude);
    final dEnd = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, end.latitude, end.longitude);

    final approachingStart = dStart < _kFastSampleRadiusM &&
        (_lastDistToStartM == null || dStart < _lastDistToStartM!);
    final approachingEnd = dEnd < _kFastSampleRadiusM &&
        (_lastDistToEndM == null || dEnd < _lastDistToEndM!);
    final leavingStart =
        _lastDistToStartM != null && dStart > _lastDistToStartM!;
    final leavingEnd = _lastDistToEndM != null && dEnd > _lastDistToEndM!;

    _lastDistToStartM = dStart;
    _lastDistToEndM = dEnd;

    int desiredMs;
    if (approachingStart || approachingEnd) {
      desiredMs = _kFastIntervalMs;
    } else if (_currentIntervalMs == _kFastIntervalMs &&
        (leavingStart || leavingEnd)) {
      desiredMs = _kBaseIntervalMs;
    } else {
      desiredMs = _currentIntervalMs;
    }
    if (desiredMs == _currentIntervalMs) return;
    _currentIntervalMs = desiredMs;
    _geoSub?.cancel();
    _geoSub = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(desiredMs),
    ).listen(_onGpsFix);
  }

  void _onStartLapRecording() {
    setState(() {
      _isLapRecordingMode = true;
      _errorMessage = null;
    });
    _onStart();
  }

  /// Lap detection: auto-stop on finish-line crossing perpendicular to the
  /// rider's initial heading. Mirrors the Google variant and backend
  /// `RideService.detectAndPersistLaps`.
  void _lapModeOnNewPoint(_RecordedPoint? prev, _RecordedPoint curr) {
    if (_lapStart == null) {
      _lapStart = LatLng(curr.latitude, curr.longitude);
      _maxAwayKm = 0;
      return;
    }
    final start = _lapStart!;
    const r = 6371000.0;
    final cosLat0 = cos(start.latitude * pi / 180);
    double toLocalX(double lng) =>
        (lng - start.longitude) * pi / 180 * r * cosLat0;
    double toLocalY(double lat) => (lat - start.latitude) * pi / 180 * r;
    final cX = toLocalX(curr.longitude);
    final cY = toLocalY(curr.latitude);
    final distFromStartKm =
        _haversineKm(start, LatLng(curr.latitude, curr.longitude));
    if (distFromStartKm > _maxAwayKm) _maxAwayKm = distFromStartKm;
    if (_hX == null) {
      final mag = sqrt(cX * cX + cY * cY);
      if (mag >= _kHeadingRefMinMeters) {
        _hX = cX / mag;
        _hY = cY / mag;
      }
      return;
    }
    if (prev == null) return;
    final pX = toLocalX(prev.longitude);
    final pY = toLocalY(prev.latitude);
    final perpX = -_hY!;
    final perpY = _hX!;
    final halfW = _kLapFinishLineHalfWidthKm * 1000.0;
    final aX = perpX * halfW, aY = perpY * halfW;
    final bX = -aX, bY = -aY;
    final t = _segmentIntersectionParam(pX, pY, cX, cY, aX, aY, bX, bY);
    if (t == null) return;
    final dx = cX - pX;
    final dy = cY - pY;
    if (dx * _hX! + dy * _hY! <= 0) return;
    if (_maxAwayKm < _kLapMinExcursionKm) return;
    final lapStartTs = _points.first.timestamp;
    final crossingMs =
        (curr.timestamp.difference(prev.timestamp).inMilliseconds * t).round();
    final crossingTs = prev.timestamp.add(Duration(milliseconds: crossingMs));
    final lapSec = crossingTs.difference(lapStartTs).inSeconds;
    if (lapSec < _kLapMinDurationSec) return;
    final crossLat = prev.latitude + (curr.latitude - prev.latitude) * t;
    final crossLng = prev.longitude + (curr.longitude - prev.longitude) * t;
    final crossAlt = prev.altitude + (curr.altitude - prev.altitude) * t;
    setState(() {
      _points.removeLast();
      _route.removeLast();
      _points.add(_RecordedPoint(
        latitude: crossLat,
        longitude: crossLng,
        altitude: crossAlt,
        timestamp: crossingTs,
      ));
      _route.add(LatLng(crossLat, crossLng));
    });
    _onStop();
  }

  static double? _segmentIntersectionParam(
      double p0x, double p0y, double p1x, double p1y,
      double ax, double ay, double bx, double by) {
    final rx = p1x - p0x, ry = p1y - p0y;
    final sx = bx - ax, sy = by - ay;
    final denom = rx * sy - ry * sx;
    if (denom.abs() < 1e-9) return null;
    final t = ((ax - p0x) * sy - (ay - p0y) * sx) / denom;
    final u = ((ax - p0x) * ry - (ay - p0y) * rx) / denom;
    if (t < 0 || t > 1 || u < 0 || u > 1) return null;
    return t;
  }

  // ── Pick-Points → Auto-Run ────────────────────────────

  void _enterLapPickMode() {
    setState(() {
      _isPickingLapPoints = true;
      _lapWaypoints.clear();
      _legSegments.clear();
      _closingLeg = null;
      _errorMessage = null;
    });
  }

  /// Each tap is snapped to the nearest road by routing from the previous
  /// waypoint to the tap location. The route's snapped destination
  /// becomes the stored waypoint, and the polyline is appended as a leg.
  Future<void> _onMapTapForLap(LatLng pos) async {
    if (!_isPickingLapPoints || _isFetchingRoute) return;
    // Adding a new waypoint invalidates any closing leg — the loop must
    // be re-confirmed after the rider edits the route.
    if (_closingLeg != null) {
      setState(() => _closingLeg = null);
    }
    if (_lapWaypoints.isEmpty) {
      // First point — store as-is. The next tap's leg will start here
      // and AMap will route from the nearest road, which visually
      // shows where the snapped first point really is.
      setState(() {
        _lapWaypoints.add(pos);
        _errorMessage = null;
      });
      StartEndMarkerIconsAmap.ensureNumbered(1).then((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {
      _isFetchingRoute = true;
      _errorMessage = null;
    });
    final prev = _lapWaypoints.last;
    final leg = await MapService.directionsBetween(a: prev, b: pos);
    if (!mounted) return;
    if (leg == null || leg.length < 2) {
      setState(() {
        _isFetchingRoute = false;
        _errorMessage =
            'No road route from the previous point. Try a closer tap.';
      });
      return;
    }
    final snapped = leg.last;
    setState(() {
      _isFetchingRoute = false;
      _lapWaypoints.add(snapped);
      _legSegments.add(leg);
    });
    final n = _lapWaypoints.length;
    StartEndMarkerIconsAmap.ensureNumbered(n).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _undoLastLapPoint() {
    if (_isFetchingRoute) return;
    // If the loop was already confirmed, undo the closing leg first so
    // the rider can keep editing waypoints.
    if (_closingLeg != null) {
      setState(() => _closingLeg = null);
      return;
    }
    if (_lapWaypoints.isEmpty) return;
    setState(() {
      _lapWaypoints.removeLast();
      if (_legSegments.isNotEmpty) {
        _legSegments.removeLast();
      }
      _errorMessage = null;
    });
  }

  void _cancelLapPick() {
    setState(() {
      _isPickingLapPoints = false;
      _lapWaypoints.clear();
      _legSegments.clear();
      _closingLeg = null;
      _isFetchingRoute = false;
    });
  }

  /// Compute the closing leg (last waypoint → first waypoint). Once this
  /// succeeds, [_closingLeg] is non-null and the "Done" button enables.
  Future<void> _onConfirmLoop() async {
    if (_lapWaypoints.length < 2 || _isFetchingRoute) return;
    setState(() {
      _isFetchingRoute = true;
      _errorMessage = null;
    });
    final leg = await MapService.directionsBetween(
      a: _lapWaypoints.last,
      b: _lapWaypoints.first,
    );
    if (!mounted) return;
    if (leg == null || leg.length < 2) {
      setState(() {
        _isFetchingRoute = false;
        _errorMessage =
            'Could not close the loop back to the start point.';
      });
      return;
    }
    setState(() {
      _isFetchingRoute = false;
      _closingLeg = leg;
    });
  }

  /// Build the full polyline by concatenating all legs (and the closing
  /// leg if present), synthesise GPS-style sample points, and hand off
  /// to the Save Trail page.
  Future<void> _onDoneSaveLap() async {
    if (_legSegments.isEmpty || _closingLeg == null) return;
    final full = <LatLng>[];
    for (final leg in _legSegments) {
      if (full.isEmpty) {
        full.addAll(leg);
      } else {
        // Skip the duplicated junction point between legs.
        full.addAll(leg.skip(1));
      }
    }
    full.addAll(_closingLeg!.skip(1));
    if (full.isEmpty) return;
    final dense = _densifyRoute(full, 8.0);
    final start = DateTime.now().subtract(Duration(seconds: dense.length));
    final synthetic = <Map<String, dynamic>>[];
    for (var i = 0; i < dense.length; i++) {
      final p = dense[i];
      synthetic.add({
        'latitude': p.latitude,
        'longitude': p.longitude,
        'altitude': 50.0 + sin(i * 0.2) * 5,
        'timestamp': start.add(Duration(seconds: i)).toIso8601String(),
      });
    }
    final routeForSave = List<LatLng>.from(dense);
    setState(() {
      _isPickingLapPoints = false;
      _lapWaypoints.clear();
      _legSegments.clear();
      _closingLeg = null;
    });
    final saved = await MapRouter.openTrailSave(
      context,
      points: synthetic,
      route: routeForSave,
    );
    if (!mounted) return;
    if (saved == true) Navigator.of(context).pop(true);
  }

  /// Begin mock simulation along [route] (already a closed loop). Mirrors
  /// the Google variant's `_startMockWithRoute`.
  void _startMockWithRoute(List<LatLng> route) {
    _mockRoute = _densifyRoute(route, 8.0);
    _mockTickIndex = 0;
    _route.clear();
    _points.clear();
    _durationSeconds = 0;
    setState(() {
      _status = 'recording';
      _isMockMode = true;
      _isFetchingRoute = false;
    });
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_status == 'recording') {
        setState(() => _durationSeconds++);
      }
    });
    _startMockTicks();
  }

  List<LatLng> _densifyRoute(List<LatLng> route, double maxStepMeters) {
    if (route.length < 2) return List.of(route);
    final out = <LatLng>[route.first];
    for (var i = 1; i < route.length; i++) {
      final a = route[i - 1];
      final b = route[i];
      final distM = _haversineKm(a, b) * 1000.0;
      if (distM <= maxStepMeters) {
        out.add(b);
        continue;
      }
      final steps = (distM / maxStepMeters).ceil();
      for (var s = 1; s <= steps; s++) {
        final t = s / steps;
        out.add(LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        ));
      }
    }
    return out;
  }

  void _startMockTicks() {
    if (_mockTickIndex < _mockRoute.length) _emitMockPoint();
    _mockTimer = Timer.periodic(
        const Duration(milliseconds: _kMockIntervalMs), (_) {
      if (_status != 'recording') return;
      if (_mockTickIndex >= _mockRoute.length) {
        _onStop();
        return;
      }
      _emitMockPoint();
    });
  }

  void _emitMockPoint() {
    final pt = _mockRoute[_mockTickIndex];
    final isFirstOrLast =
        _mockTickIndex == 0 || _mockTickIndex == _mockRoute.length - 1;
    double lat = pt.latitude;
    double lng = pt.longitude;
    if (!isFirstOrLast) {
      final jitter = (Random().nextDouble() - 0.5) * 1.0 / 111320.0;
      lat += jitter;
      lng += jitter / cos(pt.latitude * pi / 180);
    }
    final altitude = 50.0 + sin(_mockTickIndex * 0.2) * 5;
    final latlng = LatLng(lat, lng);
    setState(() {
      _currentPos = latlng;
      _route.add(latlng);
      _points.add(_RecordedPoint(
        latitude: lat,
        longitude: lng,
        altitude: altitude,
        timestamp: DateTime.now(),
      ));
    });
    _animateToCurrentPos();
    _mockTickIndex++;
  }

  Future<void> _recenterOnMe() async {
    if (_modeUsesBikeSource && _selectedBikeHasModule) {
      final fix = _moduleFixPos;
      if (fix == null) {
        showTraxSnackBar(context, 'Unable to get bike module signal', isError: true);
        return;
      }
      final c = _mapController;
      if (c != null) {
        c.moveCamera(
          CameraUpdate.newLatLng(AmapAdapter.toAmap(fix)),
          animated: true,
        );
      }
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      );
      if (!mounted) return;
      setState(() => _currentPos = LatLng(pos.latitude, pos.longitude));
      final c = _mapController;
      if (c != null) {
        c.moveCamera(
          CameraUpdate.newLatLngZoom(
              AmapAdapter.toAmap(LatLng(pos.latitude, pos.longitude)), 17),
          animated: true,
        );
      }
    } catch (_) {
      _animateToCurrentPos();
    }
  }

  void _onPause() {
    setState(() => _status = 'paused');
    _geoSub?.pause();
  }

  void _onResume() {
    setState(() => _status = 'recording');
    _geoSub?.resume();
  }

  Future<void> _onStop() async {
    _geoSub?.cancel();
    _geoSub = null;
    _stopModuleSubscription();
    _durationTimer?.cancel();
    _durationTimer = null;
    _mockTimer?.cancel();
    _mockTimer = null;
    _isLapRecordingMode = false;
    _isMockMode = false;

    if (_points.length < 2) {
      setState(() {
        _status = 'idle';
        _errorMessage = 'Not enough points recorded. Keep riding longer.';
      });
      return;
    }
    final saved = await MapRouter.openTrailSave(
      context,
      points: _points.map((p) => p.toJson()).toList(),
      route: List.from(_route),
    );
    if (!mounted) return;
    Navigator.of(context).pop(saved == true);
  }

  double _calcDistance() {
    double total = 0;
    for (int i = 1; i < _route.length; i++) {
      total += _haversineKm(_route[i - 1], _route[i]);
    }
    return total;
  }

  double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(a.latitude)) *
            cos(_rad(b.latitude)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return 2 * r * atan2(sqrt(h), sqrt(1 - h));
  }

  double _rad(double deg) => deg * pi / 180;

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) =>
      PageCodeBadge(code: '602', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                if (_currentPos == null)
                  const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary))
                else
                  AMapWidget(
                    privacyStatement: AmapAdapter.privacy(),
                    apiKey: AmapAdapter.apiKey(),
                    myLocationStyleOptions: MyLocationStyleOptions(
                      !(_modeUsesBikeSource && _selectedBikeHasModule),
                      circleFillColor:
                          AppColors.primary.withValues(alpha: 0.15),
                      circleStrokeColor: AppColors.primary,
                      circleStrokeWidth: 1,
                    ),
                    initialCameraPosition: CameraPosition(
                      target: AmapAdapter.toAmap(_safeCurrentPos),
                      zoom: 16,
                    ),
                    polylines: {
                      if (_route.length >= 2) ...[
                        Polyline(
                          points: AmapAdapter.toAmapList(_route),
                          color: MapStyles.trailHaloColor,
                          width: MapStyles.trailHaloWidth.toDouble(),
                        ),
                        Polyline(
                          points: AmapAdapter.toAmapList(_route),
                          color: MapStyles.trailColor,
                          width: MapStyles.trailWidth.toDouble(),
                        ),
                      ],
                      // Each picked-leg in solid primary; closing leg in
                      // a slightly different shade so the rider can tell
                      // it apart at a glance.
                      if (_isPickingLapPoints)
                        ..._legSegments.map((leg) => Polyline(
                              points: AmapAdapter.toAmapList(leg),
                              color: AppColors.primary,
                              width: 3,
                            )),
                      if (_isPickingLapPoints && _closingLeg != null)
                        Polyline(
                          points: AmapAdapter.toAmapList(_closingLeg!),
                          color: AppColors.primary.withValues(alpha: 0.65),
                          width: 3,
                        ),
                    },
                    markers: {
                      if (_route.isNotEmpty)
                        Marker(
                          position: AmapAdapter.toAmap(_route.first),
                          infoWindow: const InfoWindow(title: 'Start'),
                        ),
                      if (_status != 'idle')
                        Marker(
                          position: AmapAdapter.toAmap(_safeCurrentPos),
                          infoWindow:
                              const InfoWindow(title: 'You are here'),
                        ),
                      ..._lapWaypoints.asMap().entries.map((e) => Marker(
                            position: AmapAdapter.toAmap(e.value),
                            icon: StartEndMarkerIconsAmap.numbered(e.key + 1),
                            infoWindow:
                                InfoWindow(title: 'Point ${e.key + 1}'),
                          )),
                    },
                    onTap: (latLng) {
                      // AMap SDK returns its native LatLng type (GCJ-02).
                      // Convert back to WGS-84 for storage parity with the
                      // rest of the app. AmapAdapter.fromAmap handles the
                      // CoordTransform invariant.
                      final wgs = AmapAdapter.fromAmap(latLng);
                      _onMapTapForLap(wgs);
                    },
                    onMapCreated: (c) {
                      _mapController = c;
                      _animateToCurrentPos();
                    },
                  ),
                Positioned(
                  top: safeTop + 8,
                  left: 16,
                  child: CircleAvatar(
                    backgroundColor: AppColors.surface,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back,
                          color: AppColors.textPrimary, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
                // Address / place search box — inlined on the top bar
                // next to the back button so it aligns with the back arrow.
                Positioned(
                  top: safeTop + 8,
                  left: 64,
                  right: 12,
                  child: MapSearchBox(
                    near: _safeCurrentPos,
                    margin: EdgeInsets.zero,
                    onPick: (place) {
                      _mapController?.moveCamera(
                        CameraUpdate.newLatLngZoom(
                          AmapAdapter.toAmap(place.location),
                          16,
                        ),
                        animated: true,
                      );
                    },
                  ),
                ),
                // Live satellite count (module bikes only)
                if (_selectedBikeHasModule)
                  Positioned(
                    top: safeTop + 56,
                    right: 16,
                    child: SatelliteBadge(count: _moduleSatellites),
                  ),
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: Material(
                    color: AppColors.surface,
                    shape: const CircleBorder(),
                    elevation: 4,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _recenterOnMe,
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.my_location,
                            color: AppColors.primary, size: 22),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    final distance = _calcDistance();
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _isPickingLapPoints
                ? 'Pick Waypoints'
                : (_isMockMode
                    ? 'Simulating Lap'
                    : ((_isLapRecordingMode ||
                            widget.initialMode == TrailRecordLaunchMode.lap)
                        ? 'Lap Recording'
                        : 'Free Recording')),
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 16),
          if (_modeUsesBikeSource && !_isPickingLapPoints && _status == 'idle') ...[
            BikePickerTile(
              bikes: _myBikes,
              selectedBikeId: _selectedBikeId,
              allowNone: false,
              label: 'Select bike for signal source',
              onSelected: _onBikeSelected,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Signal source: $_activeSourceLabel',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (!_isPickingLapPoints)
            Row(
              children: [
                _StatTile('Duration', _formatDuration(_durationSeconds)),
                _StatTile(
                    'Distance', '${distance.toStringAsFixed(2)} km'),
                _StatTile('Points', '${_points.length}'),
              ],
            ),
          const SizedBox(height: 20),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: AppColors.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_errorMessage!,
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.error,
                              fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ),
            ),
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildControls() {
    if (_isPickingLapPoints) {
      return _buildPickControls();
    }
    switch (_status) {
      case 'idle':
        // Mode-dedicated Start button. No auto-start — user explicitly
        // taps Start. Each launch mode lives on its own focused page.
        return _buildIdleControlsForMode();
      case 'recording':
        return Row(children: [
          Expanded(
            child: SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _onPause,
                icon: const Icon(Icons.pause, size: 22),
                label: const Text('Pause',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side:
                      const BorderSide(color: AppColors.primary, width: 2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 52,
            height: 52,
            child: ElevatedButton(
              onPressed: _onStop,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
              ),
              child: const Icon(Icons.stop,
                  color: Colors.white, size: 24),
            ),
          ),
        ]);
      case 'paused':
        return Row(children: [
          Expanded(
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _onResume,
                icon: const Icon(Icons.play_arrow, size: 22),
                label: const Text('Resume',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 52,
            height: 52,
            child: ElevatedButton(
              onPressed: _onStop,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
              ),
              child: const Icon(Icons.stop,
                  color: Colors.white, size: 24),
            ),
          ),
        ]);
      default:
        return const SizedBox.shrink();
    }
  }

  /// Idle-state controls. Single big Start button tailored to the mode
  /// the user picked on the previous screen.
  Widget _buildIdleControlsForMode() {
    switch (widget.initialMode) {
      case TrailRecordLaunchMode.lap:
        return SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _onStartLapRecording,
            icon: const Icon(Icons.flag, size: 26),
            label: const Text(
              'Start Lap Recording',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
          ),
        );
      case TrailRecordLaunchMode.pickPoint:
        return SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _isPickingLapPoints ? null : _enterLapPickMode,
            icon: const Icon(Icons.touch_app, size: 26),
            label: const Text(
              'Pick Points → Auto-Run',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
          ),
        );
      case TrailRecordLaunchMode.trailRecord:
        return SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _onStart,
            icon: const Icon(Icons.play_arrow, size: 28),
            label: const Text(
              'Start Recording',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
          ),
        );
    }
  }

  Widget _buildPickControls() {
    final n = _lapWaypoints.length;
    final hasLoop = _closingLeg != null;
    String hint;
    if (_isFetchingRoute) {
      hint = 'Snapping to road…';
    } else if (n == 0) {
      hint = 'Tap the map to add the first point';
    } else if (n == 1) {
      hint = 'Tap to add the next point ($n picked)';
    } else if (!hasLoop) {
      hint = 'Tap more points, or tap Confirm to close the loop ($n picked)';
    } else {
      hint = 'Loop closed · tap Done to save ($n waypoints)';
    }
    return Column(
      children: [
        Text(
          hint,
          style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _isFetchingRoute ? null : _cancelLapPick,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Cancel'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: BorderSide(
                      color: AppColors.textSecondary.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed:
                    (_isFetchingRoute || (n == 0 && !hasLoop))
                        ? null
                        : _undoLastLapPoint,
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Undo'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 48,
              child: hasLoop
                  ? ElevatedButton.icon(
                      onPressed: _isFetchingRoute ? null : _onDoneSaveLap,
                      icon: const Icon(Icons.check, size: 20),
                      label: const Text('Done'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: (n < 2 || _isFetchingRoute)
                          ? null
                          : _onConfirmLoop,
                      icon: _isFetchingRoute
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.flag, size: 20),
                      label: Text(_isFetchingRoute ? 'Building…' : 'Confirm'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                      ),
                    ),
            ),
          ),
        ]),
      ],
    );
  }
}

class _RecordedPoint {
  final double latitude;
  final double longitude;
  final double altitude;
  final DateTime timestamp;
  _RecordedPoint({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.timestamp,
  });
  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
        'timestamp': timestamp.toIso8601String(),
      };
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
