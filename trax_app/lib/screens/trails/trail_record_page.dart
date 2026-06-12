import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../common/services/map_service.dart';
import '../../common/utils/start_end_marker_icons.dart';
import 'package:geolocator/geolocator.dart';
import '../../common/utils/keep_awake_mixin.dart';
import '../../common/utils/map_styles.dart';
import '../../theme/app_theme.dart';
import '../../common/network/trax_api.dart';
import '../../common/services/module_telemetry_ws_client.dart';
import '../../common/widgets/map_router.dart';
import '../../common/widgets/satellite_badge.dart';
import '../../common/widgets/bike_picker.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';
import '../../models/module_telemetry.dart';
import '../../widgets/map_search_box.dart';
import 'trail_record_mode.dart';

class TrailRecordPage extends StatefulWidget {
  final TrailRecordLaunchMode initialMode;
  const TrailRecordPage({
    super.key,
    this.initialMode = TrailRecordLaunchMode.trailRecord,
  });

  @override
  State<TrailRecordPage> createState() => _TrailRecordPageState();
}

class _TrailRecordPageState extends State<TrailRecordPage>
    with KeepAwakeMixin<TrailRecordPage> {
  GoogleMapController? _mapController;
  bool _mapReady = false;
  MapType _mapType = MapType.normal;

  String _status = 'idle'; // idle, recording, paused, stopped
  // Initial fallback only used when GPS is unavailable / denied. The map is
  // not rendered until [_currentPos] becomes non-null so the user does not
  // briefly see a hardcoded location before being recentred to their own.
  static const LatLng _kFallbackPos = LatLng(22.89810, 113.86990);
  LatLng? _currentPos;
  LatLng get _safeCurrentPos => _currentPos ?? _kFallbackPos;
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
  // Phone GPS base cadence is fixed at 1 s — iOS / Android both cap GPS
  // delivery at the GNSS chip's native ~1 Hz, so a user-tunable interval
  // was misleading and was removed (2026-06-11). The fast-cadence
  // machinery is retained for the future TRAX module variable-rate
  // firmware (the phone OS still caps delivery, so it's a no-op on the
  // phone path until then).
  static const int _kBaseIntervalMs = 1000;
  static const int _kFastIntervalMs = 100;
  static const double _kFastSampleRadiusM = 10.0;
  Timer? _samplingPollTimer;
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
  // Last position reported by the bike module (live telemetry only).
  // `_currentPos` may contain a stale phone-GPS seed from before the bike
  // list loaded, so `_locateMe` must NOT trust it for module bikes.
  LatLng? _moduleFixPos;
  int? _moduleSatellites; // latest live satellite count from the module

  @override
  void initState() {
    super.initState();
    // Screen stays awake throughout the recording session (KeepAwakeMixin),
    // re-asserted on app resume so iOS can't drop it mid-session.
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
          // Do NOT auto-start lap recording — testers were surprised that
          // tapping the lap entry from the Map tab immediately began
          // tracking. The page already exposes a Start button (see
          // `_onStartLapRecording` in the action bar); make the user
          // press it explicitly.
          break;
        case TrailRecordLaunchMode.pickPoint:
          _enterLapPickMode();
          break;
      }
    });
  }

  Future<void> _initLocation() async {
    // Module bike selected → do NOT seed phone GPS into _currentPos.
    // Location source must follow the bike's TRAX module instead.
    if (_modeUsesBikeSource && _selectedBikeHasModule) return;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      // Permission denied — fall back to the world fallback so the map can
      // still be shown (mock mode + manual pick still work).
      if (mounted && _currentPos == null) {
        setState(() => _currentPos = _kFallbackPos);
      }
      return;
    }
    // Try a fast-and-loose last-known fix first so the map shows up
    // immediately even indoors / before the first satellite lock.
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted && _currentPos == null) {
        setState(() => _currentPos = LatLng(last.latitude, last.longitude));
      }
    } catch (_) {}
    // Then upgrade to a fresh high-accuracy fix in the background, with a
    // strict 8s timeout so we never spin forever.
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
      // Either timed out or hardware unavailable. If we still have nothing,
      // show the fallback position so the user can at least interact.
      if (mounted && _currentPos == null) {
        setState(() => _currentPos = _kFallbackPos);
      }
    }
  }

  void _animateToCurrentPos() {
    final pos = _currentPos;
    if (pos != null && _mapReady && _mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(pos));
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
      // Pre-Start: still subscribe so the my-location button works and
      // shows "signal" as soon as the module pushes a frame. Frames are
      // NOT persisted into _route until _status flips to 'recording'
      // (gated inside _onModuleFrame).
      _ensureModuleSubscription();
    }
  }

  void _onBikeSelected(int? bikeId) {
    if (bikeId == null) return;
    setState(() {
      _selectedBikeId = bikeId;
      _errorMessage = null;
    });
    // Always (re)subscribe — pre-Start preview is allowed; persistence
    // is gated separately inside _onModuleFrame.
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

  // ── Location Picker ───────────────────────────────────────

  // GlobalKey on the map area so we can read its real pixel size to
  // resolve the geographic centre when confirming a picked location.
  final GlobalKey _mapKey = GlobalKey();

  Future<void> _onPickLocationTap() async {
    if (_isPicking) {
      // Second tap: confirm the centre of the visible map area
      if (_mapController == null) return;
      final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
      final size = box?.size ?? MediaQuery.of(context).size;
      // GoogleMap's ScreenCoordinate is in physical pixels, not logical.
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final center = await _mapController!.getLatLng(
        ScreenCoordinate(
          x: (size.width / 2 * dpr).round(),
          y: (size.height / 2 * dpr).round(),
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
    _moduleWsSub?.cancel();
    _moduleWs?.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _locateMe() {
    if (_modeUsesBikeSource && _selectedBikeHasModule) {
      // Only trust live module telemetry — never fall back to the phone GPS
      // seed when the active source is the bike module.
      final fix = _moduleFixPos;
      if (fix == null) {
        showTraxSnackBar(context, 'Unable to get bike module signal', isError: true);
        return;
      }
      if (_mapReady && _mapController != null) {
        _mapController!.animateCamera(CameraUpdate.newLatLng(fix));
      }
      return;
    }
    _initLocation();
  }

  // ── Recording Controls ─────────────────────────────────

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
      _pickedLocation = null;
      _isPicking = false;
    });
    _durationSeconds = 0;
    _route.clear();
    _points.clear();
    _consecutiveAccuracyDrops = 0;
    _consecutiveJumpDrops = 0;
    _lastAcceptedFixAt = null;
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
    if (_modeUsesBikeSource && _selectedBikeHasModule) {
      _ensureModuleSubscription();
    } else {
      _geoSub = Geolocator.getPositionStream(
        locationSettings: _buildLocationSettings(_kBaseIntervalMs),
      ).listen(_onPhoneGpsFix);
    }
    // Every second re-evaluate the sampling rate even if no fix has come
    // through (e.g. user is stationary near the start point).
    _samplingPollTimer?.cancel();
    _samplingPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_status != 'recording') return;
      if (_modeUsesBikeSource && _selectedBikeHasModule) return;
      _maybeAdjustSamplingRate(_safeCurrentPos);
    });
  }

  void _onPhoneGpsFix(Position pos) {
    if (!_acceptGpsFix(pos)) return;
    _appendRecordedPoint(
      latlng: LatLng(pos.latitude, pos.longitude),
      altitude: pos.altitude,
      timestamp: DateTime.now(),
    );
    _maybeAdjustSamplingRate(LatLng(pos.latitude, pos.longitude));
  }

  /// Drop low-quality / implausible GPS fixes before they are appended
  /// to the recorded route. Returns true when the fix should be kept.
  bool _acceptGpsFix(Position pos) {
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
    setState(() {
      _currentPos = latlng;
      _route.add(latlng);
      _points.add(_RecordedPoint(
        latitude: latlng.latitude,
        longitude: latlng.longitude,
        altitude: altitude,
        timestamp: timestamp,
      ));
    });
    _animateToCurrentPos();
    if (_isLapRecordingMode) {
      _lapModeOnNewPoint(prev, _points.last);
    }
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
    if (_modeUsesBikeSource && _selectedBikeHasModule) return;
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
    ).listen(_onPhoneGpsFix);
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
    _stopModuleSubscription();
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
    final saved = await MapRouter.openTrailSave(
      context,
      points: _points.map((p) => p.toJson()).toList(),
      route: List.from(_route),
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
      _legSegments.clear();
      _closingLeg = null;
      _errorMessage = null;
    });
  }

  Future<void> _onMapTapForLap(LatLng pos) async {
    if (!_isPickingLapPoints || _isFetchingRoute) return;
    if (_closingLeg != null) {
      setState(() => _closingLeg = null);
    }
    if (_lapWaypoints.isEmpty) {
      setState(() {
        _lapWaypoints.add(pos);
        _errorMessage = null;
      });
      StartEndMarkerIcons.ensureNumbered(1).then((_) {
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
    StartEndMarkerIcons.ensureNumbered(n).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _addLapWaypointAtCenter() async {
    // No longer used — pick mode now uses tap-to-add (see _onMapTapForLap).
    // Kept as a no-op stub in case any external caller still references it.
  }

  void _undoLastLapPoint() {
    if (_isFetchingRoute) return;
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
    final dpr = MediaQuery.devicePixelRatioOf(context);
    _drawChain = _drawChain.then((_) async {
      try {
        final ll = await _mapController!.getLatLng(
          ScreenCoordinate(
            x: (captured.dx * dpr).round(),
            y: (captured.dy * dpr).round(),
          ),
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

    final saved = await MapRouter.openTrailSave(
      context,
      points: pts.map((p) => p.toJson()).toList(),
      route: route,
    );
    if (!mounted) return;
    if (saved == true) Navigator.of(context).pop(true);
  }

  Future<void> _onFinishLapPick() async {
    // Legacy entry point kept so any external caller still compiles.
    // The Pick-Points flow is now incremental — see _onMapTapForLap,
    // _onConfirmLoop and _onDoneSaveLap.
    return;
  }

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

  Future<void> _onDoneSaveLap() async {
    if (_legSegments.isEmpty || _closingLeg == null) return;
    final full = <LatLng>[];
    for (final leg in _legSegments) {
      if (full.isEmpty) {
        full.addAll(leg);
      } else {
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

  /// Build a closed-loop road route through [waypoints] and back to the first.
  Future<List<LatLng>?> _fetchLapRouteFromWaypoints(List<LatLng> waypoints) async {
    if (waypoints.isEmpty) return null;
    try {
      final pts = await MapService.directionsRoundTrip(
        origin: waypoints.first,
        waypoints: waypoints.skip(1).toList(),
      );
      if (pts == null || pts.length < 5) return null;
      pts[pts.length - 1] = pts.first; // ensure closure
      return pts;
    } catch (e) {
      debugPrint('Directions API (lap) error: $e');
      return null;
    }
  }

  // ── Mock Simulation (shared) ────────────────────────────

  List<LatLng> _mockRoute = [];  // pre-fetched road-following route
  bool _isFetchingRoute = false;
  int _mockEmitIntervalMs = 2000;

  // ── Pick-Points → Snap-and-leg incremental routing ──────
  // Each tap is snapped to the nearest road, and the leg from the
  // previous waypoint is appended live. Confirm closes the loop back
  // to the first point; Done saves the synthesised trail.
  final List<List<LatLng>> _legSegments = [];
  List<LatLng>? _closingLeg;

  void _onStartMockRoute() async {
    setState(() {
      _isFetchingRoute = true;
      _errorMessage = null;
    });

    final route = await _fetchRoadLapRoute(_safeCurrentPos);
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

    // Two ADJACENT waypoints – North then East – forming a triangle with center
    final ptN = LatLng(center.latitude + latOff, center.longitude);
    final ptE = LatLng(center.latitude, center.longitude + lngOff);

    try {
      final allPoints = await MapService.directionsRoundTrip(
        origin: center,
        waypoints: [ptN, ptE],
      );
      if (allPoints == null || allPoints.length < 5) return null;
      // Ensure closure
      allPoints[allPoints.length - 1] = allPoints.first;
      return allPoints;
    } catch (e) {
      debugPrint('Directions API error: $e');
      return null;
    }
  }

  // ── Build ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '602', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Column(
        children: [
          // ─── Map area (takes the upper, expanded region; bottom panel
          // sits beneath it instead of overlaying it) ───────────────
          Expanded(
            child: Stack(
              key: _mapKey,
              children: [
          // Map — only render once we have a real GPS fix (or fallback)
          // so the user does not briefly see a hardcoded preset location.
          if (_currentPos == null)
            const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          else
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _safeCurrentPos, zoom: 16),
            mapType: _mapType,
            // Default map: flat 2D — disable 3D buildings and tilt entirely.
            // Satellite keeps tilt available for inspecting terrain.
            buildingsEnabled: _mapType != MapType.normal,
            // Hide native blue dot when the bike has a TRAX module —
            // location source must come from the module, not the phone.
            myLocationEnabled: !(_modeUsesBikeSource && _selectedBikeHasModule),
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            // Lock map gestures while freehand-drawing the lap so finger
            // movement is captured by the overlay GestureDetector below.
            scrollGesturesEnabled: !_isDrawingLap,
            zoomGesturesEnabled: !_isDrawingLap,
            rotateGesturesEnabled: !_isDrawingLap,
            // Disable tilt gestures on the default 2D map; allow only on
            // satellite where the tilted view is meaningful.
            tiltGesturesEnabled: !_isDrawingLap && _mapType != MapType.normal,
            onTap: _isPickingLapPoints ? _onMapTapForLap : null,
            polylines: {
              if (_route.length >= 2) ...[
                Polyline(
                  polylineId: const PolylineId('trail_halo'),
                  points: _route,
                  color: MapStyles.trailHaloColor,
                  width: MapStyles.trailHaloWidth,
                ),
                Polyline(
                  polylineId: const PolylineId('trail'),
                  points: _route,
                  color: MapStyles.trailColor,
                  width: MapStyles.trailWidth,
                ),
              ],
              if (_isDrawingLap && _drawnLapPoints.length >= 2)
                Polyline(
                  polylineId: const PolylineId('drawn_lap'),
                  points: _drawnLapPoints,
                  color: AppColors.primary,
                  width: 2,
                ),
              if (_isPickingLapPoints)
                ..._legSegments.asMap().entries.map((e) => Polyline(
                      polylineId: PolylineId('leg_${e.key}'),
                      points: e.value,
                      color: AppColors.primary,
                      width: 3,
                    )),
              if (_isPickingLapPoints && _closingLeg != null)
                Polyline(
                  polylineId: const PolylineId('closing_leg'),
                  points: _closingLeg!,
                  color: AppColors.primary.withValues(alpha: 0.65),
                  width: 3,
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
                  position: _safeCurrentPos,
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
                ),
              // Confirmed picked-location pin when idle
              if (_status == 'idle' && _pickedLocation != null && !_isPicking)
                Marker(
                  markerId: const MarkerId('picked'),
                  position: _pickedLocation!,
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                ),
              // Lap waypoint markers (numbered violet badges)
              for (int i = 0; i < _lapWaypoints.length; i++)
                Marker(
                  markerId: MarkerId('lap_wp_$i'),
                  position: _lapWaypoints[i],
                  icon: StartEndMarkerIcons.numbered(i + 1),
                  infoWindow: InfoWindow(title: 'Point ${i + 1}'),
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

          // Center crosshair when picking (centred within the map area)
          if (_isPicking)
            const Positioned.fill(
              child: IgnorePointer(
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

          // Address / place search box — inlined on the top bar next to
          // the back button so it stays aligned with the back arrow.
          if (!_isPicking && !_isDrawingLap)
            Positioned(
              top: safeTop + 8,
              left: 64,
              right: 12,
              child: MapSearchBox(
                near: _safeCurrentPos,
                margin: EdgeInsets.zero,
                onPick: (place) {
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLngZoom(place.location, 16),
                  );
                },
              ),
            ),

          // Pick-location feature is hidden for now — keep code paths
          // intact in case we re-enable manual location override later.
          // if (_status == 'idle')
          //   Positioned(
          //     top: safeTop + 8,
          //     left: 72,
          //     child: CircleAvatar(
          //       backgroundColor: _isPicking ? AppColors.primary : AppColors.surface,
          //       child: IconButton(
          //         icon: Icon(
          //           _isPicking ? Icons.check : Icons.pin_drop,
          //           color: _isPicking ? Colors.white : AppColors.textPrimary,
          //           size: 20,
          //         ),
          //         onPressed: _onPickLocationTap,
          //         tooltip: _isPicking ? 'Confirm Location' : 'Pick Location',
          //       ),
          //     ),
          //   ),

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
              child: _GpsChip(position: _safeCurrentPos),
            ),

          // Live satellite count (module bikes only)
          if (!_isPicking && _pickedLocation == null && _selectedBikeHasModule)
            Positioned(
              top: safeTop + 56,
              right: 16,
              child: SatelliteBadge(count: _moduleSatellites),
            ),

          // Map layout switch (default/satellite) — bottom-left of map area
          Positioned(
            bottom: 16,
            left: 16,
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

          // Direct lat,lng input bar removed by request — location is now
          // chosen via the pin-drop button or by GPS auto-locate.

          // Pick-points mode now uses tap-to-add (mirrors the AMap variant)
          // and the controls live in the bottom panel — no centered pin or
          // floating top toolbar is needed.

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

          // Locate-me button — bottom-right of map area; recentres camera
          // on the user's current location.
          Positioned(
            right: 16,
            bottom: 16,
            child: Material(
              color: AppColors.surface,
              shape: const CircleBorder(),
              elevation: 4,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _locateMe,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.my_location,
                      size: 22, color: AppColors.primary),
                ),
              ),
            ),
          ),
        ],
      ),
          ),
          // Bottom panel — hidden only while drawing. Pick-mode now uses
          // the same panel and renders pick controls via _buildControls.
          if (!_isDrawingLap) _buildBottomPanel(),
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

  /// Idle-state controls. Single big Start button tailored to the mode
  /// the user picked on the previous screen. No mode-switching here —
  /// each mode now lives on its own dedicated page entry.
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
        // Pick-point mode normally auto-enters _enterLapPickMode in
        // initState, so this is just a safety fallback.
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
            _isPickingLapPoints
                ? 'Pick Waypoints'
                : ((_isLapRecordingMode ||
                        widget.initialMode == TrailRecordLaunchMode.lap)
                    ? 'Lap Recording'
                    : 'Free Recording'),
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
          if (!_isPickingLapPoints)
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
    if (_isPickingLapPoints) {
      return _buildPickControls();
    }
    switch (_status) {
      case 'idle':
        // Show ONLY the Start button matching the mode the user picked
        // on the previous screen (trails screen → record pill). The page
        // is mode-dedicated, so we no longer expose the other two modes
        // here as alternative entry points. The user must explicitly
        // press Start — recording never begins automatically on entry.
        return _buildIdleControlsForMode();
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
