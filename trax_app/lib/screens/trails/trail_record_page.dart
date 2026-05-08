import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../common/utils/start_end_marker_icons.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../theme/app_theme.dart';
import 'trail_save_page.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class TrailRecordPage extends StatefulWidget {
  const TrailRecordPage({super.key});

  @override
  State<TrailRecordPage> createState() => _TrailRecordPageState();
}

class _TrailRecordPageState extends State<TrailRecordPage> {
  GoogleMapController? _mapController;
  bool _mapReady = false;
  MapType _mapType = MapType.normal;

  String _status = 'idle'; // idle, recording, paused, stopped
  LatLng _currentPos = const LatLng(22.89810, 113.86990);
  final List<LatLng> _route = [];
  final List<_RecordedPoint> _points = [];
  StreamSubscription<Position>? _geoSub;
  Timer? _durationTimer;
  Timer? _mockTimer;
  int _durationSeconds = 0;
  String? _errorMessage;
  bool _isMockMode = false;
  int _mockTickIndex = 0;

  // Location picker state
  bool _isPicking = false; // true = crosshair visible, panning to pick
  LatLng? _pickedLocation; // confirmed picked location

  // Simulate Lap – user picks waypoints on map
  bool _isPickingLapPoints = false;
  final List<LatLng> _lapWaypoints = [];
  final TextEditingController _latLngController = TextEditingController();

  // Simulate Lap (Draw) – user freehand-draws the lap with their finger.
  // While `_isDrawingLap` is true the GoogleMap's pan/zoom/rotate gestures
  // are disabled and a transparent GestureDetector captures pointer movement
  // to convert each screen position into a LatLng via
  // `_mapController.getLatLng`. On Finish the points become the trail.
  bool _isDrawingLap = false;
  final List<LatLng> _drawnLapPoints = [];
  Offset? _lastDrawScreenPos;
  // Serializes async getLatLng calls in pointer order.
  Future<void> _drawChain = Future.value();

  // ── Lap Recording mode ────────────────────────────────
  // When true, recording auto-stops the moment the rider crosses back
  // through a perpendicular finish line at the start point — mirroring
  // the backend's lap detection in RideService.detectAndPersistLaps.
  bool _isLapRecordingMode = false;
  LatLng? _lapStart; // first sample of the lap
  // Trail heading unit vector (local equirectangular metres frame), once
  // the rider has moved at least HEADING_REF_MIN_METERS from the start.
  double? _hX, _hY;
  double _maxAwayKm = 0; // hysteresis: max distance from start so far
  // Mirror the backend constants verbatim so behaviour matches.
  static const double _kLapMinExcursionKm = 0.15; // 150 m
  static const int _kLapMinDurationSec = 15;
  static const double _kLapFinishLineHalfWidthKm = 0.015; // ±15 m
  static const double _kHeadingRefMinMeters = 5.0;

  // ── Adaptive GPS sampling ────────────────────────────
  // Default sampling cadence is 1 s; when the rider is approaching the
  // start or end point (distance shrinking AND within
  // [_kFastSampleRadiusM]) we drop to 100 ms to capture the lap boundary
  // precisely. Once the rider crosses the boundary and the distance
  // begins to grow again we return to 1 s.
  static const int _kBaseIntervalMs = 1000;
  static const int _kFastIntervalMs = 100;
  static const double _kFastSampleRadiusM = 10.0;
  Timer? _samplingPollTimer;
  int _currentIntervalMs = _kBaseIntervalMs;
  double? _lastDistToStartM;
  double? _lastDistToEndM;

  @override
  void initState() {
    super.initState();
    // Keep the screen awake throughout the recording session.
    WakelockPlus.enable();
    _initLocation();
  }

  Future<void> _initLocation() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() => _currentPos = LatLng(pos.latitude, pos.longitude));
      _animateToCurrentPos();
    } catch (_) {}
  }

  void _animateToCurrentPos() {
    if (_mapReady && _mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(_currentPos));
    }
  }

  // ── Location Picker ───────────────────────────────────────

  // Approximate bottom panel height (title + stats + controls + padding)
  static const double _bottomPanelHeight = 260.0;

  /// Y-coordinate for the center of the visible map area (above the bottom panel)
  double get _mapCenterY {
    final screenH = MediaQuery.of(context).size.height;
    return (screenH - _bottomPanelHeight) / 2;
  }

  Future<void> _onPickLocationTap() async {
    if (_isPicking) {
      // Second tap: confirm the center of the visible map area
      if (_mapController == null) return;
      final center = await _mapController!.getLatLng(
        ScreenCoordinate(
          x: (MediaQuery.of(context).size.width / 2).round(),
          y: _mapCenterY.round(),
        ),
      );
      setState(() {
        _isPicking = false;
        _pickedLocation = center;
        _currentPos = center;
      });
      _mapController?.animateCamera(CameraUpdate.newLatLng(center));
    } else {
      setState(() {
        _isPicking = true;
        _pickedLocation = null;
      });
    }
  }

  void _clearPickedLocation() {
    setState(() {
      _pickedLocation = null;
      _isPicking = false;
    });
    _initLocation(); // re-fetch real GPS
  }

  @override
  void dispose() {
    _geoSub?.cancel();
    _durationTimer?.cancel();
    _mockTimer?.cancel();
    _samplingPollTimer?.cancel();
    _latLngController.dispose();
    _mapController?.dispose();
    // Release the wake-lock when leaving the page.
    WakelockPlus.disable();
    super.dispose();
  }

  void _locateByLatLngInput() {
    final raw = _latLngController.text.trim();
    final parts = raw.split(',');
    if (parts.length != 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Format must be: latitude,longitude')),
      );
      return;
    }
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Latitude/longitude must be numbers')),
      );
      return;
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coordinates out of range')),
      );
      return;
    }

    final target = LatLng(lat, lng);
    setState(() {
      _currentPos = target;
      if (_status == 'idle') {
        _pickedLocation = target;
        _isPicking = false;
      }
    });
    FocusScope.of(context).unfocus();
    _mapController?.animateCamera(CameraUpdate.newLatLng(target));
  }

  // ── Recording Controls ─────────────────────────────────

  void _onStart() {
    setState(() {
      _status = 'recording';
      _errorMessage = null;
      _pickedLocation = null;
      _isPicking = false;
    });
    _durationSeconds = 0;
    _route.clear();
    _points.clear();
    // Reset lap-mode state every time recording starts so a previous
    // attempt can't poison the next.
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
    _geoSub = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(_kBaseIntervalMs),
    ).listen((pos) {
      final latlng = LatLng(pos.latitude, pos.longitude);
      // Capture the previous sample BEFORE we mutate _points so we can
      // run the segment-vs-finish-line crossing check below.
      final prev = _points.isNotEmpty ? _points.last : null;
      setState(() {
        _currentPos = latlng;
        _route.add(latlng);
        _points.add(_RecordedPoint(
          latitude: pos.latitude,
          longitude: pos.longitude,
          altitude: pos.altitude,
          timestamp: DateTime.now(),
        ));
      });
      _animateToCurrentPos();
      _maybeAdjustSamplingRate(latlng);
      if (_isLapRecordingMode) {
        _lapModeOnNewPoint(prev, _points.last);
      }
    });
    // Every second re-evaluate the sampling rate even if no fix has come
    // through (e.g. user is stationary near the start point).
    _samplingPollTimer?.cancel();
    _samplingPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_status != 'recording') return;
      _maybeAdjustSamplingRate(_currentPos);
    });
  }

  /// Build location settings for the active sampling rate.
  /// Sets distanceFilter=0 so the OS reports updates on the chosen interval
  /// regardless of physical movement.
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
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
        activityType: ActivityType.fitness,
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
    );
  }

  /// Switch between 1 s and 0.1 s sampling depending on proximity to the
  /// start/end points of the recording. Fast cadence only triggers when
  /// the rider is *approaching* a boundary (distance shrinking AND inside
  /// [_kFastSampleRadiusM]); once the rider crosses and starts moving
  /// away the cadence reverts to the 1 s base rate.
  void _maybeAdjustSamplingRate(LatLng pos) {
    if (_status != 'recording' || _points.isEmpty) return;
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
    final leavingStart = _lastDistToStartM != null && dStart > _lastDistToStartM!;
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
    // Re-subscribe with the new cadence.
    _geoSub?.cancel();
    _geoSub = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(desiredMs),
    ).listen((p) {
      final ll = LatLng(p.latitude, p.longitude);
      final prev = _points.isNotEmpty ? _points.last : null;
      setState(() {
        _currentPos = ll;
        _route.add(ll);
        _points.add(_RecordedPoint(
          latitude: p.latitude,
          longitude: p.longitude,
          altitude: p.altitude,
          timestamp: DateTime.now(),
        ));
      });
      _animateToCurrentPos();
      _maybeAdjustSamplingRate(ll);
      if (_isLapRecordingMode) {
        _lapModeOnNewPoint(prev, _points.last);
      }
    });
  }

  void _onPause() {
    setState(() => _status = 'paused');
    if (_isMockMode) {
      _mockTimer?.cancel();
      _mockTimer = null;
    } else {
      _geoSub?.pause();
    }
  }

  void _onResume() {
    setState(() => _status = 'recording');
    if (_isMockMode) {
      _startMockTicks();
    } else {
      _geoSub?.resume();
    }
  }

  Future<void> _onStop() async {
    _geoSub?.cancel();
    _geoSub = null;
    _mockTimer?.cancel();
    _mockTimer = null;
    _durationTimer?.cancel();
    _durationTimer = null;

    if (_points.length < 2) {
      setState(() {
        _status = 'idle';
        _errorMessage = 'Not enough points recorded. Keep riding longer.';
        _isLapRecordingMode = false;
      });
      return;
    }

    // In lap mode the buffers were already trimmed to the closed lap
    // window by `_lapModeOnNewPoint` before it called `_onStop()`. We
    // still reset the mode flag so the next session starts clean.
    final wasLapMode = _isLapRecordingMode;
    _isLapRecordingMode = false;

    // Navigate to save page
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TrailSavePage(
          points: _points.map((p) => p.toJson()).toList(),
          route: List.from(_route),
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true || wasLapMode) {
      Navigator.of(context).pop(saved ?? false);
    } else {
      Navigator.of(context).pop(false);
    }
  }

  // ── Simulate Lap – pick waypoints then build route ──────

  void _enterLapPickMode() {
    setState(() {
      _isPickingLapPoints = true;
      _lapWaypoints.clear();
      _errorMessage = null;
    });
  }

  void _onMapTapForLap(LatLng pos) {
    // Tap-to-add is intentionally disabled; users now drag the map to align
    // the centered pin and tap the “Add Point” button to drop a waypoint.
    if (!_isPickingLapPoints) return;
  }

  Future<void> _addLapWaypointAtCenter() async {
    if (!_isPickingLapPoints || _mapController == null) return;
    final center = await _mapController!.getLatLng(
      ScreenCoordinate(
        x: (MediaQuery.of(context).size.width / 2).round(),
        y: _mapCenterY.round(),
      ),
    );
    setState(() => _lapWaypoints.add(center));
  }

  void _undoLastLapPoint() {
    if (_lapWaypoints.isEmpty) return;
    setState(() => _lapWaypoints.removeLast());
  }

  void _cancelLapPick() {
    setState(() {
      _isPickingLapPoints = false;
      _lapWaypoints.clear();
    });
  }

  // ── Simulate Lap (Draw) – freehand drawing on the map ───

  void _enterDrawLapMode() {
    setState(() {
      _isDrawingLap = true;
      _drawnLapPoints.clear();
      _lastDrawScreenPos = null;
      _errorMessage = null;
    });
  }

  void _cancelDrawLap() {
    setState(() {
      _isDrawingLap = false;
      _drawnLapPoints.clear();
      _lastDrawScreenPos = null;
    });
  }

  void _clearDrawnPath() {
    setState(() {
      _drawnLapPoints.clear();
      _lastDrawScreenPos = null;
    });
  }

  void _onDrawPanStart(DragStartDetails d) {
    if (!_isDrawingLap) return;
    _lastDrawScreenPos = null;
    _addDrawPointAt(d.localPosition, force: true);
  }

  void _onDrawPanUpdate(DragUpdateDetails d) {
    if (!_isDrawingLap) return;
    _addDrawPointAt(d.localPosition);
  }

  /// Convert a screen position to LatLng and append to the drawn path.
  /// Sampling: at least ~6 logical-px from the previous sampled position
  /// to keep the conversion rate sane. Calls are serialized through
  /// `_drawChain` so the resulting LatLngs land in pointer order.
  void _addDrawPointAt(Offset pos, {bool force = false}) {
    if (_mapController == null) return;
    if (!force && _lastDrawScreenPos != null) {
      final dx = pos.dx - _lastDrawScreenPos!.dx;
      final dy = pos.dy - _lastDrawScreenPos!.dy;
      if (dx * dx + dy * dy < 36) return; // < 6 px → skip
    }
    _lastDrawScreenPos = pos;
    final captured = pos;
    _drawChain = _drawChain.then((_) async {
      try {
        final ll = await _mapController!.getLatLng(
          ScreenCoordinate(x: captured.dx.round(), y: captured.dy.round()),
        );
        if (!mounted || !_isDrawingLap) return;
        setState(() => _drawnLapPoints.add(ll));
      } catch (_) {/* ignore single-point conversion failures */}
    });
  }

  // ── Lap Recording (real GPS, auto-stop on finish-line crossing) ─

  /// Enter lap-recording mode and immediately call `_onStart()` so the
  /// real GPS stream begins. The first received sample becomes the start
  /// point; subsequent samples are tested against a virtual finish line
  /// perpendicular to the rider's initial heading.
  void _onStartLapRecording() {
    setState(() {
      _isLapRecordingMode = true;
      _errorMessage = null;
    });
    _onStart();
  }

  /// Called from the position-stream listener after each new GPS sample
  /// while in lap mode. Implements the same algorithm as backend
  /// `RideService.detectAndPersistLaps` but with `_lapStart` taking the
  /// place of the trail start point and the heading derived from the
  /// rider's own first ≥5 m of motion.
  void _lapModeOnNewPoint(_RecordedPoint? prev, _RecordedPoint curr) {
    // First sample → set the start point and bail; nothing to cross yet.
    if (_lapStart == null) {
      _lapStart = LatLng(curr.latitude, curr.longitude);
      _maxAwayKm = 0;
      return;
    }
    final start = _lapStart!;
    const r = 6371000.0;
    final cosLat0 = cos(start.latitude * pi / 180);

    // Equirectangular projection (metres) of curr relative to start.
    double toLocalX(double lng) =>
        (lng - start.longitude) * pi / 180 * r * cosLat0;
    double toLocalY(double lat) => (lat - start.latitude) * pi / 180 * r;
    final cX = toLocalX(curr.longitude);
    final cY = toLocalY(curr.latitude);
    final distFromStartKm =
        _haversineKm(start, LatLng(curr.latitude, curr.longitude));
    if (distFromStartKm > _maxAwayKm) _maxAwayKm = distFromStartKm;

    // Derive heading from the first sample ≥ HEADING_REF_MIN_METERS away.
    if (_hX == null) {
      final mag = sqrt(cX * cX + cY * cY);
      if (mag >= _kHeadingRefMinMeters) {
        _hX = cX / mag;
        _hY = cY / mag;
      }
      return; // need both heading + a prev sample for any crossing test
    }

    if (prev == null) return;
    final pX = toLocalX(prev.longitude);
    final pY = toLocalY(prev.latitude);

    // Finish line: ±15 m perpendicular to heading, centred on start (0,0).
    final perpX = -_hY!;
    final perpY = _hX!;
    final halfW = _kLapFinishLineHalfWidthKm * 1000.0;
    final aX = perpX * halfW, aY = perpY * halfW;
    final bX = -aX, bY = -aY;

    final t = _segmentIntersectionParam(pX, pY, cX, cY, aX, aY, bX, bY);
    if (t == null) return;
    // Forward-only: rider's velocity must have a +ve component along heading.
    final dx = cX - pX;
    final dy = cY - pY;
    if (dx * _hX! + dy * _hY! <= 0) return;

    // Hysteresis: must have travelled ≥150 m AND lap ≥15 s long.
    if (_maxAwayKm < _kLapMinExcursionKm) return;
    final lapStartTs = _points.first.timestamp;
    final crossingMs = (curr.timestamp.difference(prev.timestamp).inMilliseconds * t).round();
    final crossingTs = prev.timestamp.add(Duration(milliseconds: crossingMs));
    final lapSec = crossingTs.difference(lapStartTs).inSeconds;
    if (lapSec < _kLapMinDurationSec) return;

    // ✅ Lap closed. Trim buffers to start..crossing window and auto-stop.
    // Drop the very last sample (it lies past the finish line) and replace
    // it with an interpolated point exactly on the crossing for a clean
    // closing segment.
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

  /// 2-D segment-segment intersection. Returns t∈[0,1] along (p0→p1) where
  /// it crosses (a→b), or null if parallel / outside. Mirrors backend
  /// `RideService.segmentIntersectionParam`.
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

  Future<void> _onFinishDrawLap() async {
    if (_drawnLapPoints.length < 2) {
      setState(() => _errorMessage = 'Draw at least a short line on the map.');
      return;
    }
    // Wait for any in-flight conversions to finish so we use the full path.
    await _drawChain;
    if (!mounted) return;

    // Build a synthetic _RecordedPoint list with 1-second spacing and a
    // gentle altitude wave so downstream consumers (TrailSavePage,
    // thumbnail, lap stats) treat it like a real recording.
    final start = DateTime.now()
        .subtract(Duration(seconds: _drawnLapPoints.length));
    final pts = <_RecordedPoint>[];
    for (var i = 0; i < _drawnLapPoints.length; i++) {
      final p = _drawnLapPoints[i];
      pts.add(_RecordedPoint(
        latitude: p.latitude,
        longitude: p.longitude,
        altitude: 50.0 + sin(i * 0.2) * 5,
        timestamp: start.add(Duration(seconds: i)),
      ));
    }

    final route = List<LatLng>.from(_drawnLapPoints);

    // Reset draw state before navigating away.
    setState(() {
      _isDrawingLap = false;
      _drawnLapPoints.clear();
      _lastDrawScreenPos = null;
    });

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TrailSavePage(
          points: pts.map((p) => p.toJson()).toList(),
          route: route,
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) Navigator.of(context).pop(true);
  }

  Future<void> _onFinishLapPick() async {
    if (_lapWaypoints.length < 2) {
      setState(() => _errorMessage = 'Pick at least 2 waypoints on the map.');
      return;
    }

    setState(() {
      _isFetchingRoute = true;
      _errorMessage = null;
    });

    final route = await _fetchLapRouteFromWaypoints(_lapWaypoints);
    if (!mounted) return;

    if (route == null || route.length < 5) {
      setState(() {
        _isFetchingRoute = false;
        _errorMessage = 'Could not build a loop route through selected points.';
      });
      return;
    }

    // Use the shared mock machinery to emit points
    _isPickingLapPoints = false;
    _lapWaypoints.clear();
    _startMockWithRoute(route);
  }

  /// Build a closed-loop road route through [waypoints] and back to the first.
  Future<List<LatLng>?> _fetchLapRouteFromWaypoints(List<LatLng> waypoints) async {
    final origin = '${waypoints.first.latitude},${waypoints.first.longitude}';
    final wps = waypoints
        .skip(1)
        .map((w) => '${w.latitude},${w.longitude}')
        .join('|');

    try {
      final dio = Dio();
      if (kDebugMode) {
        (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
          final client = HttpClient();
          client.findProxy = (uri) => 'PROXY 127.0.0.1:7897';
          client.badCertificateCallback = (cert, host, port) => true;
          return client;
        };
      }

      final resp = await dio.get(
        'https://maps.googleapis.com/maps/api/directions/json',
        queryParameters: {
          'origin': origin,
          'destination': origin, // back to start
          'waypoints': wps,
          'mode': 'driving',
          'key': _mapsApiKey,
        },
        options: Options(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 5),
        ),
      );

      final json = resp.data as Map<String, dynamic>;
      if (json['status'] != 'OK') return null;

      final routes = json['routes'] as List;
      if (routes.isEmpty) return null;

      final List<LatLng> pts = [];
      for (final leg in (routes[0]['legs'] as List)) {
        for (final step in (leg['steps'] as List)) {
          pts.addAll(_decodePolyline(step['polyline']['points'] as String));
        }
      }
      if (pts.length < 5) return null;
      pts[pts.length - 1] = pts.first; // ensure closure
      return pts;
    } catch (e) {
      debugPrint('Directions API (lap) error: $e');
      return null;
    }
  }

  // ── Mock Simulation (shared) ────────────────────────────

  static const String _mapsApiKey = 'AIzaSyDmzdgVvZu4f5Q7zCKytQ5Syz0RLQzUxng';

  List<LatLng> _mockRoute = [];  // pre-fetched road-following route
  bool _isFetchingRoute = false;
  int _mockEmitIntervalMs = 2000;

  void _onStartMockRoute() async {
    setState(() {
      _isFetchingRoute = true;
      _errorMessage = null;
    });

    final route = await _fetchRoadLapRoute(_currentPos);
    if (!mounted) return;

    if (route == null || route.length < 5) {
      setState(() {
        _isFetchingRoute = false;
        _errorMessage = 'Could not fetch road route. Check network connection.';
      });
      return;
    }

    _startMockWithRoute(route);
  }

  /// Shared: begin mock simulation along a pre-built route.
  void _startMockWithRoute(List<LatLng> route) {
    // Densify so consecutive points are ~8 m apart (≈30 km/h · 1 s).
    // This keeps the trail glued to the actual road geometry returned by
    // Directions instead of cutting straight chords between sparse vertices.
    _mockRoute = _densifyRoute(route, 8.0);
    _mockTickIndex = 0;
    _route.clear();
    _points.clear();
    _durationSeconds = 0;
    // Emit one GPS sample per second, like a real device.
    _mockEmitIntervalMs = 1000;

    setState(() {
      _status = 'recording';
      _isMockMode = true;
      _isFetchingRoute = false;
      _pickedLocation = null;
      _isPicking = false;
    });

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_status == 'recording') {
        setState(() => _durationSeconds++);
      }
    });

    _startMockTicks();
  }

  /// Linearly interpolate extra points between consecutive vertices so that
  /// no two adjacent points are more than [maxStepMeters] apart. The first
  /// and last vertices are preserved exactly.
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
    // Emit first point immediately
    if (_mockTickIndex < _mockRoute.length) _emitMockPoint();

    _mockTimer = Timer.periodic(Duration(milliseconds: _mockEmitIntervalMs), (_) {
      if (_status != 'recording') return;
      if (_mockTickIndex >= _mockRoute.length) {
        _onStop(); // auto-stop when all points emitted
        return;
      }
      _emitMockPoint();
    });
  }

  void _emitMockPoint() {
    final pt = _mockRoute[_mockTickIndex];
    final isFirstOrLast = _mockTickIndex == 0 || _mockTickIndex == _mockRoute.length - 1;

    double lat = pt.latitude;
    double lng = pt.longitude;

    // Add slight GPS jitter (±0.5 m) but NOT on first/last points to preserve
    // lap closure. Kept small so the path still visually hugs the road.
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

    // Note: do NOT attempt heuristic early-stop based on proximity to start.
    // The pre-built `_mockRoute` is already a closed loop; `_startMockTicks`
    // calls `_onStop()` when `_mockTickIndex >= _mockRoute.length`, which
    // guarantees we always traverse the full route. A "back near start"
    // heuristic was previously cutting laps short whenever the road geometry
    // happened to pass close to the origin mid-loop.
  }

  /// Fetch a closed-loop road route via Google Directions API.
  /// Uses a single round-trip call with two ADJACENT waypoints (North then
  /// East) forming a triangle, so each leg follows a different road segment
  /// and the route never backtracks through the center.
  Future<List<LatLng>?> _fetchRoadLapRoute(LatLng center) async {
    const double radiusM = 600.0;
    final double latOff = radiusM / 111320.0;
    final double lngOff = radiusM / (111320.0 * cos(center.latitude * pi / 180));

    final origin = '${center.latitude},${center.longitude}';
    // Two ADJACENT waypoints – North then East – forming a triangle with center
    final ptN = '${center.latitude + latOff},${center.longitude}';           // North
    final ptE = '${center.latitude},${center.longitude + lngOff}';           // East

    try {
      final dio = Dio();
      if (kDebugMode) {
        (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
          final client = HttpClient();
          client.findProxy = (uri) => 'PROXY 127.0.0.1:7897';
          client.badCertificateCallback = (cert, host, port) => true;
          return client;
        };
      }

      final opts = Options(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 5),
      );

      // Single round-trip: center → North → East → center
      final resp = await dio.get(
        'https://maps.googleapis.com/maps/api/directions/json',
        queryParameters: {
          'origin': origin,
          'destination': origin,
          'waypoints': '$ptN|$ptE',
          'mode': 'driving',
          'key': _mapsApiKey,
        },
        options: opts,
      );

      final json = resp.data as Map<String, dynamic>;
      if (json['status'] != 'OK') return null;

      final routes = json['routes'] as List;
      if (routes.isEmpty) return null;

      final List<LatLng> allPoints = [];
      final legs = routes[0]['legs'] as List;
      for (final leg in legs) {
        for (final step in (leg['steps'] as List)) {
          allPoints.addAll(_decodePolyline(step['polyline']['points'] as String));
        }
      }

      if (allPoints.length < 5) return null;

      // Ensure closure
      allPoints[allPoints.length - 1] = allPoints.first;
      return allPoints;
    } catch (e) {
      debugPrint('Directions API error: $e');
      return null;
    }
  }

  /// Decode Google's encoded polyline algorithm.
  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    int lat = 0;
    int lng = 0;
    while (index < encoded.length) {
      int shift = 0, result = 0, b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  // ── Build ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '602', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Stack(
        children: [
          // Map
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _currentPos, zoom: 16),
            mapType: _mapType,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            // Lock map gestures while freehand-drawing the lap so finger
            // movement is captured by the overlay GestureDetector below.
            scrollGesturesEnabled: !_isDrawingLap,
            zoomGesturesEnabled: !_isDrawingLap,
            rotateGesturesEnabled: !_isDrawingLap,
            tiltGesturesEnabled: !_isDrawingLap,
            onTap: _isPickingLapPoints ? _onMapTapForLap : null,
            polylines: {
              if (_route.length >= 2)
                Polyline(
                  polylineId: const PolylineId('trail'),
                  points: _route,
                  color: AppColors.primary,
                  width: 4,
                ),
              if (_isDrawingLap && _drawnLapPoints.length >= 2)
                Polyline(
                  polylineId: const PolylineId('drawn_lap'),
                  points: _drawnLapPoints,
                  color: AppColors.primary,
                  width: 4,
                ),
            },
            markers: {
              if (_route.isNotEmpty)
                Marker(
                  markerId: const MarkerId('start'),
                  position: _route.first,
                  icon: StartEndMarkerIcons.start,
                ),
              // Lap-mode start pin (visible during recording so the rider
              // knows where the auto-finish line sits).
              if (_isLapRecordingMode && _lapStart != null)
                Marker(
                  markerId: const MarkerId('lap_start'),
                  position: _lapStart!,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueAzure),
                  infoWindow: const InfoWindow(title: 'Lap Start / Finish'),
                ),
              if (_status != 'idle')
                Marker(
                  markerId: const MarkerId('current'),
                  position: _currentPos,
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
                ),
              // Confirmed picked-location pin when idle
              if (_status == 'idle' && _pickedLocation != null && !_isPicking)
                Marker(
                  markerId: const MarkerId('picked'),
                  position: _pickedLocation!,
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                ),
              // Lap waypoint markers (numbered)
              for (int i = 0; i < _lapWaypoints.length; i++)
                Marker(
                  markerId: MarkerId('lap_wp_$i'),
                  position: _lapWaypoints[i],
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    i == 0 ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueViolet,
                  ),
                  infoWindow: InfoWindow(title: i == 0 ? 'Start' : 'Point ${i + 1}'),
                ),
            },
            onMapCreated: (c) {
              _mapController = c;
              setState(() => _mapReady = true);
              _animateToCurrentPos();
            },
          ),

          // Freehand draw overlay — captures finger pans and converts each
          // position into a LatLng appended to `_drawnLapPoints`.
          if (_isDrawingLap)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: _onDrawPanStart,
                onPanUpdate: _onDrawPanUpdate,
              ),
            ),

          // Center crosshair when picking
          if (_isPicking)
            Positioned(
              left: 0,
              right: 0,
              top: _mapCenterY - 20,
              child: const IgnorePointer(
                child: Center(
                  child: Icon(Icons.add, size: 40, color: AppColors.error),
                ),
              ),
            ),

          // Back button
          Positioned(
            top: safeTop + 8,
            left: 16,
            child: CircleAvatar(
              backgroundColor: AppColors.surface,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),

          // Pick-location button — only when idle
          if (_status == 'idle')
            Positioned(
              top: safeTop + 8,
              left: 72,
              child: CircleAvatar(
                backgroundColor: _isPicking ? AppColors.primary : AppColors.surface,
                child: IconButton(
                  icon: Icon(
                    _isPicking ? Icons.check : Icons.pin_drop,
                    color: _isPicking ? Colors.white : AppColors.textPrimary,
                    size: 20,
                  ),
                  onPressed: _onPickLocationTap,
                  tooltip: _isPicking ? 'Confirm Location' : 'Pick Location',
                ),
              ),
            ),

          // Picking-mode hint banner
          if (_isPicking)
            Positioned(
              top: safeTop + 8,
              left: 120,
              right: 60,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
                  ],
                ),
                child: const Text(
                  'Move map, then tap ✓ to confirm',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          // Picked-location info chip
          if (_status == 'idle' && _pickedLocation != null && !_isPicking)
            Positioned(
              top: safeTop + 8,
              left: 120,
              right: 60,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pin_drop, size: 16, color: AppColors.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${_pickedLocation!.latitude.toStringAsFixed(5)}, ${_pickedLocation!.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: _clearPickedLocation,
                      child: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),

          // GPS info — hide while picking or when a location is picked
          if (!_isPicking && _pickedLocation == null)
            Positioned(
              top: safeTop + 8,
              right: 16,
              child: _GpsChip(position: _currentPos),
            ),

          // Map layout switch (default/satellite)
          Positioned(
            top: safeTop + 110,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _mapTypeBtn('Default', _mapType == MapType.normal, () {
                    setState(() => _mapType = MapType.normal);
                  }),
                  const SizedBox(width: 4),
                  _mapTypeBtn('Satellite', _mapType == MapType.satellite, () {
                    setState(() => _mapType = MapType.satellite);
                  }),
                ],
              ),
            ),
          ),

          // Direct lat,lng input locate bar
          Positioned(
            top: safeTop + 56,
            left: 16,
            right: 16,
            child: Material(
              color: AppColors.surface,
              elevation: 2,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _latLngController,
                        textInputAction: TextInputAction.done,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        onSubmitted: (_) => _locateByLatLngInput(),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'lat,lng',
                        ),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.my_location,
                          size: 20, color: AppColors.primary),
                      onPressed: _locateByLatLngInput,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Lap-pick floating toolbar
          if (_isPickingLapPoints)
            Positioned(
              top: safeTop + 8,
              left: 72,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _lapWaypoints.isEmpty
                            ? 'Drag map to position pin'
                            : '${_lapWaypoints.length} point${_lapWaypoints.length == 1 ? '' : 's'} selected',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                    ),
                    if (_lapWaypoints.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.undo, size: 20),
                        onPressed: _undoLastLapPoint,
                        tooltip: 'Undo last point',
                        color: AppColors.textSecondary,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: _cancelLapPick,
                      tooltip: 'Cancel',
                      color: AppColors.error,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _lapWaypoints.length >= 2 ? _onFinishLapPick : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),

          // Centered drop-pin while picking lap waypoints
          if (_isPickingLapPoints)
            Positioned(
              left: 0,
              right: 0,
              top: _mapCenterY - 36, // shift up so pin tip sits at center
              child: const IgnorePointer(
                child: Center(
                  child: Icon(Icons.location_pin,
                      size: 40, color: AppColors.error),
                ),
              ),
            ),

          // Draw-mode floating top toolbar (Clear / Cancel / Finish)
          if (_isDrawingLap)
            Positioned(
              top: safeTop + 8,
              left: 72,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _drawnLapPoints.isEmpty
                            ? 'Drag finger on map to draw the lap'
                            : '${_drawnLapPoints.length} pts drawn',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                    ),
                    if (_drawnLapPoints.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: _clearDrawnPath,
                        tooltip: 'Clear',
                        color: AppColors.textSecondary,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: _cancelDrawLap,
                      tooltip: 'Cancel',
                      color: AppColors.error,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _drawnLapPoints.length >= 2 ? _onFinishDrawLap : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Finish', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom panel — hidden while picking lap waypoints or drawing
          if (!_isPickingLapPoints && !_isDrawingLap)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: _buildBottomPanel(),
            ),

          // Compact pick-mode bottom panel with the “Add Point” button
          if (_isPickingLapPoints)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: _buildLapPickBottomPanel(),
            ),
        ],
      ),
    );
  }

  Widget _mapTypeBtn(String label, bool active, VoidCallback onTap) {
    return Material(
      color: active ? AppColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLapPickBottomPanel() {
    final count = _lapWaypoints.length;
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_pin,
                  color: AppColors.error, size: 18),
              const SizedBox(width: 6),
              Text(
                'Drag map to position pin · $count point${count == 1 ? '' : 's'} added',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _addLapWaypointAtCenter,
              icon: const Icon(Icons.add_location_alt,
                  size: 22, color: Colors.white),
              label: const Text('Add Point',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            count < 2
                ? 'Add at least 2 points, then tap Done'
                : 'Tap Done at the top to start the simulated lap',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    final distance = _calcDistance();
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, -2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title
          Text(
            _isLapRecordingMode ? 'Lap Recording' : 'Record Trail',
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 16),
          if (_isLapRecordingMode && _status == 'recording')
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.flag,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _lapStart == null
                            ? 'Waiting for first GPS sample to lock the start point…'
                            : (_hX == null
                                ? 'Heading not set — start moving to lock the finish line.'
                                : 'Auto-stops on next pass through the start point.'),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Stats
          Row(
            children: [
              _StatTile('Duration', _formatDuration(_durationSeconds)),
              _StatTile('Distance', '${distance.toStringAsFixed(2)} km'),
              _StatTile('Points', '${_points.length}'),
            ],
          ),
          const SizedBox(height: 20),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 13, color: AppColors.error, fontWeight: FontWeight.w500),
                      ),
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
    switch (_status) {
      case 'idle':
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _onStart,
                icon: const Icon(Icons.play_arrow, size: 28),
                label: const Text('Start Recording', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _onStartLapRecording,
                icon: const Icon(Icons.flag, size: 22),
                label: const Text(
                  'Start Lap Recording',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.85),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _enterDrawLapMode,
                icon: const Icon(Icons.gesture, size: 20),
                label: const Text(
                  'Simulate Lap (Draw)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: BorderSide(color: AppColors.textSecondary.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _isPickingLapPoints ? null : _enterLapPickMode,
                icon: const Icon(Icons.touch_app, size: 20),
                label: const Text(
                  'Simulate Lap (pick points)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: BorderSide(color: AppColors.textSecondary.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                ),
              ),
            ),
          ],
        );
      case 'recording':
        return Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _onPause,
                  icon: const Icon(Icons.pause, size: 22),
                  label: const Text('Pause', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary, width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 52, height: 52,
              child: ElevatedButton(
                onPressed: _onStop,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                ),
                child: const Icon(Icons.stop, color: Colors.white, size: 24),
              ),
            ),
          ],
        );
      case 'paused':
        return Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _onResume,
                  icon: const Icon(Icons.play_arrow, size: 22),
                  label: const Text('Resume', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 52, height: 52,
              child: ElevatedButton(
                onPressed: _onStop,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                ),
                child: const Icon(Icons.stop, color: Colors.white, size: 24),
              ),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
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
        cos(_rad(a.latitude)) * cos(_rad(b.latitude)) *
        sin(dLng / 2) * sin(dLng / 2);
    return 2 * r * atan2(sqrt(h), sqrt(1 - h));
  }

  double _rad(double deg) => deg * pi / 180;

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

// ── Recorded Point ──────────────────────────────────────

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

// ── Sub-widgets ─────────────────────────────────────────

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _GpsChip extends StatelessWidget {
  final LatLng position;
  const _GpsChip({required this.position});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.gps_fixed, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
