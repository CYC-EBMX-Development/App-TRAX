import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/ebike.dart';
import '../models/ride_stats.dart';
import '../models/ride_point.dart';
import '../models/module_telemetry.dart';
import '../common/network/trax_api.dart';
import '../common/services/module_telemetry_ws_client.dart';
import '../common/services/ride_lap_ws_client.dart';

enum _SamplingMode { base, fast }

class _SamplingDecision {
  const _SamplingDecision({
    required this.mode,
    required this.reason,
    required this.triggerRadiusM,
    required this.distStartM,
    required this.distEndM,
    required this.speedKmh,
  });

  final _SamplingMode mode;
  final String reason;
  final double triggerRadiusM;
  final double distStartM;
  final double distEndM;
  final double speedKmh;
}

class ActiveRideService extends ChangeNotifier {
  ActiveRideService._();
  static final ActiveRideService instance = ActiveRideService._();

  // Ride state
  int? _rideId;
  String _rideStatus = 'idle'; // idle, active, paused, completed
  EBike? _bike;
  String? _mode;
  String? _source;
  RideStats? _stats;
  ModuleTelemetry? _telemetry;
  final List<LatLng> route = [];
  LatLng currentPos = const LatLng(22.89810, 113.86990);
  int displayDuration = 0;

  // Lap Timer state (only set for lap-timer rides)
  int? _trailId;
  String? _trailName;
  int? _targetLaps;
  // Optional anchor points (start / end) used to drive adaptive
  // sampling near lap boundaries.
  LatLng? _anchorStart;
  LatLng? _anchorEnd;

  // ── Adaptive sampling state ─────────────────────────
  // Phone GPS base cadence is fixed at 1 s: both iOS Core Location and
  // Android FusedLocationProvider bottom out at the GNSS chip's native
  // ~1 Hz regardless of any faster request, so a user-tunable interval
  // was misleading and was removed (2026-06-11).
  //
  // The adaptive "fast mode" decision machinery below ([setSamplingAnchors],
  // [_decideSamplingMode], [_applySamplingDecision], speed-tiered radii)
  // is RETAINED on purpose: it will drive the TRAX module firmware's
  // variable sampling rate. When the rider enters the speed-tiered radius
  // near a finish-line anchor, the module should be told (over BLE/MQTT)
  // to boost its emission rate, and revert on leave. On the phone path
  // [_applySamplingDecision] re-subscribes the GPS stream at the faster
  // interval, but the OS still caps delivery at ~1 Hz — harmless no-op
  // until the module firmware lands.
  static const int _kBaseIntervalMs = 1000;
  static const int _kFastIntervalMs = 200;
  static const int _kFastSpeedThresholdKmh = 50;
  static const double _kFastRadiusLowSpeedM = 25.0;
  static const double _kFastRadiusHighSpeedM = 50.0;
  static const double _kFastExitHysteresisM = 8.0;
  int _currentIntervalMs = _kBaseIntervalMs;
  _SamplingMode _samplingMode = _SamplingMode.base;
  Timer? _samplingPollTimer;
  // Last observed distance to each anchor (metres). Used to detect whether
  // the rider is *approaching* the anchor (distance shrinking) so the
  // fast cadence only kicks in on the way IN — not while leaving.
  double? _lastDistToStartM;
  double? _lastDistToEndM;
  // Timestamp of the last fix accepted by [_onGpsFix]. Used on iOS /
  // macOS to throttle Core Location's free-running stream down to the
  // requested [_currentIntervalMs] cadence.
  DateTime? _lastAcceptedFixAt;

  // ── GPS quality filters ──────────────────────────────
  // Drop fixes whose reported horizontal accuracy is worse than this
  // many metres (i.e. 30 m+ of estimated error). Most modern phones
  // report 3–10 m in the open and 20–40 m in dense urban canyons; the
  // 30 m threshold catches the worst urban-canyon multi-path noise
  // without throwing away normal samples.
  static const double _kMaxAccuracyM = 30.0;
  // Reject “teleport” fixes whose implied speed since the previous
  // accepted fix exceeds this many km/h. This catches sudden GPS jumps
  // that physically cannot happen on a bike. Two consecutive jump fixes
  // override the filter (in case the rider really did move).
  static const double _kMaxJumpKmh = 100.0;
  int _consecutiveJumpDrops = 0;
  // Timers
  Timer? _statsTimer;
  Timer? _telemetryTimer;
  Timer? _durationTimer;
  Timer? _uploadTimer;
  StreamSubscription<Position>? _geoSub;
  // WebSocket push channel for module telemetry (with-module path).
  // Falls back to [_telemetryTimer] polling if the WS never connects.
  ModuleTelemetryWsClient? _wsClient;
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  // WebSocket push channel for lap-completion events on the active ride.
  // Each push triggers an immediate [_pollStats] so the UI updates with
  // no 3 s polling lag. The 3 s [_statsTimer] still runs as a safety net.
  RideLapWsClient? _lapWsClient;
  StreamSubscription<Map<String, dynamic>>? _lapWsSub;
  final List<RidePoint> _pendingPoints = [];

  // Getters
  int? get rideId => _rideId;
  String get rideStatus => _rideStatus;
  EBike? get bike => _bike;
  RideStats? get stats => _stats;
  String? get source => _source;
  ModuleTelemetry? get telemetry => _telemetry;
  bool get isActive => _rideStatus == 'active' || _rideStatus == 'paused';
  bool get _hasModule => _bike?.traxSerialNumber != null;
  String get _serialNo => _bike?.traxSerialNumber ?? '';

  // Lap timer getters
  int? get trailId => _trailId;
  String? get trailName => _trailName;
  int? get targetLaps => _targetLaps;
  bool get isLapTimer => _trailId != null && _targetLaps != null;

  // ── Start Ride ──────────────────────────────────────────

  Future<bool> startRide(EBike bike) async {
    _bike = bike;
    _mode = _hasModule ? 'with_module' : 'without_module';
    final bikeId = int.tryParse(bike.id) ?? 0;
    final resp = await TraxApi.startRide(bicycleId: bikeId, mode: _mode!);
    if (!resp.isSuccess()) return false;

    final data = resp.data as Map<String, dynamic>;
    _rideId = data['id'] as int;
    _rideStatus = 'active';
    displayDuration = 0;
    route.clear();
    _stats = null;
    _telemetry = null;
    _trailId = null;
    _trailName = null;
    _targetLaps = null;
    _source = 'free_ride';
    notifyListeners();

    _startTimers();
    return true;
  }

  /// Start a Lap Timer ride bound to a Lap-type trail.
  ///
  /// Location source follows the bike selection (module if the bike has a
  /// TRAX serial, phone GPS otherwise) — same rule as every other ride.
  Future<bool> startLapTimer({
    required EBike bike,
    required int trailId,
    required String trailName,
    required int targetLaps,
  }) async {
    _bike = bike;
    _mode = _hasModule ? 'with_module' : 'without_module';
    final bikeId = int.tryParse(bike.id) ?? 0;
    final resp = await TraxApi.startRide(
      bicycleId: bikeId,
      mode: _mode!,
      trailId: trailId,
      targetLaps: targetLaps,
    );
    if (!resp.isSuccess()) return false;

    final data = resp.data as Map<String, dynamic>;
    _rideId = data['id'] as int;
    _rideStatus = 'active';
    displayDuration = 0;
    route.clear();
    _stats = null;
    _telemetry = null;
    _trailId = trailId;
    _trailName = trailName;
    _targetLaps = targetLaps;
    _source = 'lap_timer';
    notifyListeners();

    _startTimers();
    return true;
  }

  void _startTimers() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_rideStatus == 'active') {
        displayDuration++;
        notifyListeners();
      }
    });

    _statsTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollStats());

    // Lap-completion push (server-driven, near-zero lag). The 3 s stats
    // poll above is the fallback if the WS never connects.
    _subscribeLapWs();

    if (_hasModule) {
      _startModuleTracking();
    } else {
      _startPhoneGps();
    }
  }

  Future<void> _startModuleTracking() async {
    // Real module sends NMEA → MQTT broker → trax-backend, which fans
    // out to WebSocket subscribers. The App no longer drives the
    // backend simulator — it just subscribes to the live stream.
    //
    // Fallback: a 2 s HTTP poll runs in parallel until the WS reports
    // its first frame. If the bike has no module data yet (offline),
    // both channels silently produce nothing and the UI stays put.
    _subscribeModuleWs();
    _telemetryTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _pollTelemetry());
    // Same upload cadence as phone-GPS path so the backend ride gets
    // points to render polyline / replay / riding info from.
    _uploadTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_pendingPoints.isNotEmpty) _uploadPendingPoints();
    });
  }

  void _subscribeModuleWs() {
    _wsSub?.cancel();
    _wsClient?.dispose();
    final client = ModuleTelemetryWsClient(serialNo: _serialNo);
    _wsClient = client;
    _wsSub = client.stream.listen(_onModuleTelemetryJson);
    // Fire-and-forget; client schedules its own reconnect on failure.
    unawaited(client.connect());
  }

  /// Subscribe to `/ws/rides/{rideId}/laps` for the active ride. Each
  /// incoming event (`type:"lap"` or `type:"completed"`) triggers an
  /// immediate [_pollStats] so the UI gets the new lap with no 3 s
  /// polling lag. Idempotent — safe to call after re-attaching to an
  /// in-progress ride via [checkActiveRide].
  void _subscribeLapWs() {
    if (_rideId == null) return;
    _lapWsSub?.cancel();
    _lapWsClient?.dispose();
    final client = RideLapWsClient(rideId: _rideId!);
    _lapWsClient = client;
    _lapWsSub = client.stream.listen((_) {
      // Don't trust the WS payload's lap counts; just refetch the
      // canonical stats (laps array + completedLaps + status) so the UI
      // renders the same server state it would have on the next poll.
      _pollStats();
    });
    unawaited(client.connect());
  }

  void _onModuleTelemetryJson(Map<String, dynamic> json) {
    try {
      final t = ModuleTelemetry.fromJson(json);
      _telemetry = t;
      final pos = LatLng(t.latitude, t.longitude);
      currentPos = pos;
      // Only persist the point to the local route list when an actual ride
      // is running. Pre-Start (preview) frames are used to populate the
      // my-location pin / signal indicator only — they must NOT seed the
      // recorded polyline.
      if (isActive) {
        route.add(pos);
        _enqueueModulePoint(t);
        _evaluateAndApplySamplingMode(pos, speedKmh: t.speed.toDouble());
      }
      notifyListeners();
    } catch (_) {/* ignore malformed */}
  }

  /// Queue a module-sourced fix for the next [_uploadTimer] flush so
  /// the backend ride gets a polyline / replay / riding-info just like
  /// a phone-GPS ride. Module speed is already km/h (UI consumers treat
  /// it as such). Altitude is forwarded when present (added 2026-06-04);
  /// frames without altitude fall back to 0 for back-compat.
  void _enqueueModulePoint(ModuleTelemetry t) {
    final ts = t.timestamp;
    DateTime when;
    if (ts != null && ts.isNotEmpty) {
      when = DateTime.tryParse(ts) ?? DateTime.now();
    } else {
      when = DateTime.now();
    }
    _pendingPoints.add(RidePoint(
      latitude: t.latitude,
      longitude: t.longitude,
      speed: t.speed.clamp(0, 200).toDouble(),
      altitude: t.altitude ?? 0,
      timestamp: when,
    ));
  }

  /// Pre-start preview: subscribe to the module telemetry WebSocket so
  /// the my-location button and signal indicator can light up before the
  /// rider taps Start. NO ride is created on the backend, NO timers run,
  /// and incoming frames are NOT appended to the [route] list (see
  /// [_onModuleTelemetryJson]).
  ///
  /// Safe to call repeatedly; calls during an active ride are no-ops.
  void previewModule(EBike bike) {
    if (_rideStatus != 'idle') return;
    final serial = bike.traxSerialNumber;
    if (serial == null || serial.isEmpty) return;
    if (_bike?.traxSerialNumber == serial && _wsClient != null) return;
    _bike = bike;
    _subscribeModuleWs();
  }

  /// Tear down a preview subscription started by [previewModule]. No-op
  /// if the ride has progressed past idle (the active ride owns the
  /// subscription at that point).
  void stopPreview() {
    if (_rideStatus != 'idle') return;
    _wsSub?.cancel();
    _wsSub = null;
    _wsClient?.dispose();
    _wsClient = null;
    _telemetry = null;
    _bike = null;
    notifyListeners();
  }

  void _startPhoneGps() {
    _currentIntervalMs = _kBaseIntervalMs;
    _samplingMode = _SamplingMode.base;
    _lastAcceptedFixAt = null;
    _geoSub = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(_kBaseIntervalMs),
    ).listen(_onGpsFix);

    _samplingPollTimer?.cancel();
    _samplingPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_rideStatus != 'active') return;
      final speedKmh = (_telemetry?.speed ?? 0).toDouble();
      _evaluateAndApplySamplingMode(currentPos, speedKmh: speedKmh);
    });

    _uploadTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_pendingPoints.isNotEmpty) _uploadPendingPoints();
    });
  }

  void _onGpsFix(Position pos) {
    // 1) Accuracy filter — reject low-confidence fixes.
    if (pos.accuracy.isFinite && pos.accuracy > _kMaxAccuracyM) {
      return;
    }
    // 2) Jump filter — reject implausible position jumps that imply
    //    speeds above [_kMaxJumpKmh]. Two such fixes in a row override
    //    the filter so a genuine large move can still be recorded.
    if (route.isNotEmpty && _lastAcceptedFixAt != null) {
      final last = route.last;
      final dtMs =
          DateTime.now().difference(_lastAcceptedFixAt!).inMilliseconds;
      if (dtMs > 0) {
        final dM = _haversineMeters(last, LatLng(pos.latitude, pos.longitude));
        final implKmh = (dM / dtMs) * 3600.0; // m/ms * 1000 ms/s * 3.6 km/h
        if (implKmh > _kMaxJumpKmh) {
          if (_consecutiveJumpDrops < 2) {
            _consecutiveJumpDrops++;
            return;
          }
          // Two jumps in a row — trust this one and reset the counter.
        }
      }
    }
    _consecutiveJumpDrops = 0;

    // iOS / macOS Core Location is event-driven — there's no
    // [intervalDuration] to clamp the delivery rate. When the user picks
    // a slow base cadence (e.g. 1 s) but the hardware delivers 5–10 Hz,
    // we drop intermediate fixes here so the recorded cadence matches
    // the requested [_currentIntervalMs] across all platforms. Android
    // already throttles in the OS via `intervalDuration`, so this
    // throttle is effectively a no-op on Android.
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      final last = _lastAcceptedFixAt;
      if (last != null) {
        // Allow ~10 % jitter so we don't reject a fix arriving 1 ms early.
        final minGap = (_currentIntervalMs * 0.9).round();
        if (DateTime.now().difference(last).inMilliseconds < minGap) {
          return;
        }
      }
      _lastAcceptedFixAt = DateTime.now();
    }

    final latlng = LatLng(pos.latitude, pos.longitude);
    _pendingPoints.add(RidePoint(
      latitude: pos.latitude,
      longitude: pos.longitude,
      speed: (pos.speed * 3.6).clamp(0, 200),
      altitude: pos.altitude,
      timestamp: DateTime.now(),
    ));
    currentPos = latlng;
    route.add(latlng);
    notifyListeners();
    _evaluateAndApplySamplingMode(latlng, speedKmh: (pos.speed * 3.6));
  }

  /// Configure background-capable location updates for the active ride.
  /// On Android we pin a foreground-service notification so the OS keeps
  /// the GPS stream alive when the screen is off; on iOS we enable
  /// allowBackgroundLocationUpdates which (combined with UIBackgroundModes
  /// = location in Info.plist) keeps updates flowing while suspended.
  LocationSettings _buildLocationSettings(int intervalMs) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: Duration(milliseconds: intervalMs),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'TRAX is tracking your ride',
          notificationText: 'Recording continues while the screen is off',
          enableWakeLock: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      // iOS Core Location does not honour a fixed interval. To get
      // sub-second updates we must request `bestForNavigation`
      // (hardware delivers up to ~10 Hz on modern iPhones); plain
      // `high`/`best` cap around 1 Hz which is why earlier rides ended
      // up logged at ≈1 s spacing despite a 100 ms preference. The
      // requested cadence is enforced client-side in [_onGpsFix].
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
        activityType: ActivityType.fitness,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
    );
  }

  /// Set the anchor points used for adaptive sampling. For a lap-timer ride
  /// pass start = end (loop). For a free ride leave both null — sampling
  /// stays at the configured base rate.
  void setSamplingAnchors({LatLng? start, LatLng? end}) {
    _anchorStart = start;
    _anchorEnd = end;
    _samplingMode = _SamplingMode.base;
    _currentIntervalMs = _kBaseIntervalMs;
    _lastDistToStartM = null;
    _lastDistToEndM = null;
  }

  void _evaluateAndApplySamplingMode(LatLng pos, {required double speedKmh}) {
    final decision = _decideSamplingMode(pos, speedKmh: speedKmh);
    if (decision == null) return;
    _applySamplingDecision(decision);
  }

  _SamplingDecision? _decideSamplingMode(LatLng pos, {required double speedKmh}) {
    if (_rideStatus != 'active') return null;
    if (_anchorStart == null && _anchorEnd == null) return null;

    final speed = speedKmh.clamp(0, 200).toDouble();
    final triggerRadius = speed >= _kFastSpeedThresholdKmh
        ? _kFastRadiusHighSpeedM
        : _kFastRadiusLowSpeedM;
    final exitRadius = triggerRadius + _kFastExitHysteresisM;

    final dStart = _anchorStart == null
        ? double.infinity
        : _haversineMeters(pos, _anchorStart!);
    final dEnd = _anchorEnd == null
        ? double.infinity
        : _haversineMeters(pos, _anchorEnd!);

    // Approaching = inside the radius AND distance shrinking compared to
    // the previous fix. This guarantees the fast cadence only kicks in
    // on the way TOWARDS a boundary, not while leaving it.
    final approachingStart = dStart <= triggerRadius &&
        (_lastDistToStartM == null || dStart < _lastDistToStartM!);
    final approachingEnd = dEnd <= triggerRadius &&
        (_lastDistToEndM == null || dEnd < _lastDistToEndM!);
    final leavingStart = _lastDistToStartM != null && dStart > _lastDistToStartM!;
    final leavingEnd = _lastDistToEndM != null && dEnd > _lastDistToEndM!;

    _lastDistToStartM = dStart;
    _lastDistToEndM = dEnd;

    _SamplingMode desiredMode = _samplingMode;
    String reason = 'hold';
    if (approachingStart || approachingEnd) {
      desiredMode = _SamplingMode.fast;
      reason = 'approaching';
    } else if (_samplingMode == _SamplingMode.fast) {
      final leftFastZone = (dStart >= exitRadius || dEnd >= exitRadius) &&
          (leavingStart || leavingEnd);
      if (leftFastZone) {
        desiredMode = _SamplingMode.base;
        reason = 'leaving';
      }
    }

    return _SamplingDecision(
      mode: desiredMode,
      reason: reason,
      triggerRadiusM: triggerRadius,
      distStartM: dStart,
      distEndM: dEnd,
      speedKmh: speed,
    );
  }

  void _applySamplingDecision(_SamplingDecision decision) {
    if (decision.mode == _samplingMode) return;

    _samplingMode = decision.mode;
    final desiredMs =
        decision.mode == _SamplingMode.fast ? _kFastIntervalMs : _kBaseIntervalMs;
    _currentIntervalMs = desiredMs;

    if (_mode == 'with_module') {
      _requestModuleSamplingMode(
        mode: decision.mode,
        reason: decision.reason,
        triggerRadiusM: decision.triggerRadiusM,
        speedKmh: decision.speedKmh,
        distStartM: decision.distStartM,
        distEndM: decision.distEndM,
      );
      return;
    }

    _lastAcceptedFixAt = null;
    _geoSub?.cancel();
    _geoSub = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(desiredMs),
    ).listen(_onGpsFix);
  }

  void _requestModuleSamplingMode({
    required _SamplingMode mode,
    required String reason,
    required double triggerRadiusM,
    required double speedKmh,
    required double distStartM,
    required double distEndM,
  }) {
    // Reserved interface: with-module uses the same fast/base decision
    // engine as phone GPS, but firmware cadence remains fixed for now.
    // Future implementation should send a BLE/MQTT command here.
    if (!kDebugMode) return;
    final target = mode == _SamplingMode.fast ? 'FAST' : 'BASE';
    debugPrint(
      '[sampling][module] mode=$target reason=$reason '
      'speed=${speedKmh.toStringAsFixed(1)}kmh '
      'r=${triggerRadiusM.toStringAsFixed(1)}m '
      'dS=${distStartM.toStringAsFixed(1)} dE=${distEndM.toStringAsFixed(1)}',
    );
  }

  static double _haversineMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final sLat = math.sin(dLat / 2);
    final sLng = math.sin(dLng / 2);
    final h = sLat * sLat +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            sLng *
            sLng;
    return 2 * r * math.asin(math.sqrt(h));
  }

  // ── Pause / Resume / Stop ────────────────────────────────

  Future<bool> pauseRide() async {
    if (_rideId == null) return false;
    final resp = await TraxApi.pauseRide(_rideId!);
    if (!resp.isSuccess()) return false;
    _rideStatus = 'paused';
    _geoSub?.pause();
    notifyListeners();
    return true;
  }

  Future<bool> resumeRide() async {
    if (_rideId == null) return false;
    final resp = await TraxApi.resumeRide(_rideId!);
    if (!resp.isSuccess()) return false;
    _rideStatus = 'active';
    _geoSub?.resume();
    notifyListeners();
    return true;
  }

  Future<bool> stopRide() async {
    if (_rideId == null) return false;

    // Flush pending points
    if (_pendingPoints.isNotEmpty) await _uploadPendingPoints();

    final resp = await TraxApi.stopRide(_rideId!);
    _cancelTimers();

    if (!resp.isSuccess()) return false;

    // Get final stats
    final statsResp = await TraxApi.getRideStats(_rideId!);
    if (statsResp.isSuccess() && statsResp.data != null) {
      _stats = RideStats.fromJson(statsResp.data as Map<String, dynamic>);
    }
    _rideStatus = 'completed';
    notifyListeners();
    return true;
  }

  void clearCompleted() {
    _rideId = null;
    _rideStatus = 'idle';
    _bike = null;
    _mode = null;
    _source = null;
    _stats = null;
    _telemetry = null;
    route.clear();
    displayDuration = 0;
    notifyListeners();
  }

  // ── Check for active ride on app launch / screen return ──

  Future<void> checkActiveRide() async {
    if (isActive) return; // Already tracking
    final resp = await TraxApi.getActiveRide();
    if (!resp.isSuccess() || resp.data == null) return;

    final data = resp.data as Map<String, dynamic>;
    _rideId = data['id'] as int;
    _rideStatus = data['status'] as String? ?? 'active';
    _mode = data['mode'] as String?;
    _source = data['source'] as String?;
    _trailId = (data['trailId'] as num?)?.toInt();
    _trailName = data['trailName'] as String?;
    _targetLaps = (data['targetLaps'] as num?)?.toInt();

    // Parse start time to compute elapsed duration
    final startTimeStr = data['startTime'] as String?;
    if (startTimeStr != null) {
      final startTime = DateTime.parse(startTimeStr);
      displayDuration = DateTime.now().difference(startTime).inSeconds;
    }

    // Fetch current stats
    final statsResp = await TraxApi.getRideStats(_rideId!);
    if (statsResp.isSuccess() && statsResp.data != null) {
      _stats = RideStats.fromJson(statsResp.data as Map<String, dynamic>);
      if (_stats!.durationSeconds > 0) {
        displayDuration = _stats!.durationSeconds;
      }
    }

    notifyListeners();

    // Restart timers for background tracking
    _startBackgroundTimers();
  }

  /// Attach the canonical GPS sampling pipeline to an already-created **race**
  /// ride. The race ride is created server-side when the host hits "Go Race"
  /// (one [RideRecord] per rider, owned by that rider, carrying the race
  /// trail + target laps). This binds to the rider's active race ride — it
  /// does **not** create a new ride.
  ///
  /// Multiplayer per-rider sampling is therefore identical to the solo lap
  /// timer: 100 ms base cadence + 200 ms finish-line densification via the
  /// adaptive-sampling anchors. Dense points batch-upload through
  /// [_uploadPendingPoints] → `addRidePoints`, which drives the shared
  /// finish-line / lap-detection pipeline on the backend.
  ///
  /// Returns false (and tracks nothing) if there is no active ride, the
  /// active ride is not a race ride, or the ride is a module ride (module
  /// bikes already record dense points via the MQTT ingest path).
  Future<bool> startRaceTracking({
    EBike? bike,
    LatLng? finishLine,
  }) async {
    // Already tracking this race ride — nothing to do.
    if (isActive && _source == 'race') return true;

    final resp = await TraxApi.getActiveRide();
    if (!resp.isSuccess() || resp.data == null) return false;
    final data = resp.data as Map<String, dynamic>;
    if ((data['source'] as String?) != 'race') return false;
    // Module rides record their dense points via MQTT (ModuleTelemetryService
    // → ingestModule); driving them through this phone pipeline too would
    // double-write points. Only phone rides need the ActiveRideService path.
    if ((data['mode'] as String?) == 'with_module') return false;

    if (bike != null) _bike = bike;
    _rideId = data['id'] as int;
    _rideStatus = data['status'] as String? ?? 'active';
    _mode = data['mode'] as String?;
    _source = 'race';
    _trailId = (data['trailId'] as num?)?.toInt();
    _trailName = data['trailName'] as String?;
    _targetLaps = (data['targetLaps'] as num?)?.toInt();
    // Fresh tracking session — drop any stale route from a previous ride so
    // consumers can use `route.isNotEmpty` to detect the first real fix.
    route.clear();
    _stats = null;
    _telemetry = null;

    final startTimeStr = data['startTime'] as String?;
    if (startTimeStr != null) {
      displayDuration =
          DateTime.now().difference(DateTime.parse(startTimeStr)).inSeconds;
    }

    final statsResp = await TraxApi.getRideStats(_rideId!);
    if (statsResp.isSuccess() && statsResp.data != null) {
      _stats = RideStats.fromJson(statsResp.data as Map<String, dynamic>);
      if (_stats!.durationSeconds > 0) displayDuration = _stats!.durationSeconds;
    }

    // Arm finish-line densification. A race over a Lap trail crosses the same
    // line each lap, so start == end (identical to the solo lap timer).
    if (finishLine != null) {
      setSamplingAnchors(start: finishLine, end: finishLine);
    }

    notifyListeners();
    _startBackgroundTimers();
    return true;
  }

  void _startBackgroundTimers() {
    _cancelTimers();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_rideStatus == 'active') {
        displayDuration++;
        notifyListeners();
      }
    });
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollStats());
    _subscribeLapWs();

    // For phone GPS mode, restart GPS stream
    if (_mode == 'without_module') {
      _startPhoneGps();
    } else if (_mode == 'with_module' && _bike != null) {
      _subscribeModuleWs();
      _telemetryTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollTelemetry());
    }
  }

  // ── Polling ──────────────────────────────────────────────

  Future<void> _pollStats() async {
    if (_rideId == null) return;
    final resp = await TraxApi.getRideStats(_rideId!);
    if (!resp.isSuccess() || resp.data == null) return;
    final s = RideStats.fromJson(resp.data as Map<String, dynamic>);
    _stats = s;
    if (s.durationSeconds > 0) displayDuration = s.durationSeconds;

    // Lap Timer: server may have auto-completed this ride when target reached
    if (s.status == 'completed' && _rideStatus != 'completed') {
      _rideStatus = 'completed';
      _cancelTimers();
    }
    notifyListeners();
  }

  Future<void> _pollTelemetry() async {
    if (!_hasModule) return;
    final resp = await TraxApi.getModuleTelemetry(_serialNo);
    if (!resp.isSuccess() || resp.data == null) return;
    final t = ModuleTelemetry.fromJson(resp.data as Map<String, dynamic>);
    final pos = LatLng(t.latitude, t.longitude);
    _telemetry = t;
    currentPos = pos;
    if (isActive) {
      route.add(pos);
      _enqueueModulePoint(t);
    }
    notifyListeners();
  }

  Future<void> _uploadPendingPoints() async {
    if (_rideId == null || _pendingPoints.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(
        _pendingPoints.map((p) => p.toJson()));
    _pendingPoints.clear();
    await TraxApi.addRidePoints(_rideId!, batch);
  }

  void _cancelTimers() {
    _statsTimer?.cancel();
    _telemetryTimer?.cancel();
    _durationTimer?.cancel();
    _uploadTimer?.cancel();
    _samplingPollTimer?.cancel();
    _geoSub?.cancel();
    _wsSub?.cancel();
    _wsClient?.dispose();
    _lapWsSub?.cancel();
    _lapWsClient?.dispose();
    _statsTimer = null;
    _telemetryTimer = null;
    _durationTimer = null;
    _uploadTimer = null;
    _samplingPollTimer = null;
    _geoSub = null;
    _wsSub = null;
    _wsClient = null;
    _lapWsSub = null;
    _lapWsClient = null;
  }

  /// Hard-reset called by the auth interceptor when a 401/403 forces
  /// the user back to the welcome page. Cancels every background
  /// timer / WS subscription and clears ride state so the abandoned
  /// ride stops 401-spamming the API and bouncing the user off the
  /// login form. Safe to call multiple times; no-op when already idle.
  void forceResetForLogout() {
    _cancelTimers();
    _pendingPoints.clear();
    _rideId = null;
    _rideStatus = 'idle';
    _bike = null;
    _mode = null;
    _source = null;
    _stats = null;
    _telemetry = null;
    route.clear();
    displayDuration = 0;
    _trailId = null;
    _trailName = null;
    _targetLaps = null;
    _anchorStart = null;
    _anchorEnd = null;
    _samplingMode = _SamplingMode.base;
    _currentIntervalMs = _kBaseIntervalMs;
    _lastDistToStartM = null;
    _lastDistToEndM = null;
    _lastAcceptedFixAt = null;
    _consecutiveJumpDrops = 0;
    notifyListeners();
  }
}
