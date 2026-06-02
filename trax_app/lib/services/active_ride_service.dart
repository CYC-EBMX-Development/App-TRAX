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
import '../common/services/gps_interval_settings.dart';

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
  // Optional anchor points (start / end) used to drive the adaptive
  // 1 s / 0.1 s GPS sampling near lap boundaries.
  LatLng? _anchorStart;
  LatLng? _anchorEnd;

  // ── Adaptive sampling state ─────────────────────────
  // Base cadence is user-configurable via Profile → Settings
  // (GpsIntervalSettings). Near a lap boundary the stream re-subscribes
  // at [_kFastIntervalMs] for higher precision; the fast rate is never
  // slower than the configured base.
  int get _kBaseIntervalMs => GpsIntervalSettings.baseIntervalMs;
  int get _kFastIntervalMs =>
      GpsIntervalSettings.baseIntervalMs < 100 ? GpsIntervalSettings.baseIntervalMs : 100;
  static const double _kFastSampleRadiusM = 10.0;
  int _currentIntervalMs = GpsIntervalSettings.baseIntervalMs;
  Timer? _samplingPollTimer;  // Last observed distance to each anchor (metres). Used to detect whether
  // the rider is *approaching* the anchor (distance shrinking) so the
  // 100 ms cadence only kicks in on the way IN — not while leaving.
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
  final List<RidePoint> _pendingPoints = [];

  // Force-phone-GPS flag. When true, [_startTimers] always uses the
  // phone GPS path even if the bike has a TRAX module configured.
  // Lap Timer sessions set this so the rider's actual movement drives
  // the map / lap detection, instead of the backend module simulator.
  bool _forcePhoneGps = false;

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
  /// Always uses the phone's real GPS for tracking, even if the bike
  /// has a TRAX module configured. The backend module simulator is not
  /// started for Lap Timer rides.
  Future<bool> startLapTimer({
    required EBike bike,
    required int trailId,
    required String trailName,
    required int targetLaps,
  }) async {
    _bike = bike;
    _forcePhoneGps = true;
    _mode = 'without_module';
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

    if (_hasModule && !_forcePhoneGps) {
      _startModuleTracking();
    } else {
      _startPhoneGps();
    }
  }

  Future<void> _startModuleTracking() async {
    // Use currentPos (may be user-picked) as the simulation starting point
    await TraxApi.startSimulation(_serialNo,
        latitude: currentPos.latitude,
        longitude: currentPos.longitude,
        rideId: _rideId);
    _telemetryTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollTelemetry());
  }

  void _startPhoneGps() {
    _currentIntervalMs = _kBaseIntervalMs;
    _lastAcceptedFixAt = null;
    _geoSub = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(_kBaseIntervalMs),
    ).listen(_onGpsFix);

    _samplingPollTimer?.cancel();
    _samplingPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_rideStatus != 'active') return;
      _maybeAdjustSamplingRate(currentPos);
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
    _maybeAdjustSamplingRate(latlng);
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
  /// stays at the 1 s base rate.
  void setSamplingAnchors({LatLng? start, LatLng? end}) {
    _anchorStart = start;
    _anchorEnd = end;
    _lastDistToStartM = null;
    _lastDistToEndM = null;
  }

  void _maybeAdjustSamplingRate(LatLng pos) {
    if (_rideStatus != 'active') return;
    if (_anchorStart == null && _anchorEnd == null) return;
    final dStart = _anchorStart == null
        ? double.infinity
        : _haversineMeters(pos, _anchorStart!);
    final dEnd = _anchorEnd == null
        ? double.infinity
        : _haversineMeters(pos, _anchorEnd!);

    // Approaching = inside the radius AND distance shrinking compared to
    // the previous fix. This guarantees the 100 ms cadence only kicks in
    // on the way TOWARDS a boundary, not while leaving it.
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
      // We were sampling fast and have now crossed / are moving away — go
      // back to the 1 s base cadence.
      desiredMs = _kBaseIntervalMs;
    } else {
      desiredMs = _currentIntervalMs;
    }
    if (desiredMs == _currentIntervalMs) return;
    _currentIntervalMs = desiredMs;
    _lastAcceptedFixAt = null;
    if (_mode != 'without_module') return; // module mode doesn't use phone GPS
    _geoSub?.cancel();
    _geoSub = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(desiredMs),
    ).listen(_onGpsFix);
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
    if (_hasModule) await TraxApi.pauseSimulation(_serialNo);
    notifyListeners();
    return true;
  }

  Future<bool> resumeRide() async {
    if (_rideId == null) return false;
    final resp = await TraxApi.resumeRide(_rideId!);
    if (!resp.isSuccess()) return false;
    _rideStatus = 'active';
    _geoSub?.resume();
    if (_hasModule) await TraxApi.resumeSimulation(_serialNo);
    notifyListeners();
    return true;
  }

  Future<bool> stopRide() async {
    if (_rideId == null) return false;

    // Flush pending points
    if (_pendingPoints.isNotEmpty) await _uploadPendingPoints();

    final resp = await TraxApi.stopRide(_rideId!);
    if (_hasModule) await TraxApi.stopSimulation(_serialNo);
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
    _forcePhoneGps = false;
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

  void _startBackgroundTimers() {
    _cancelTimers();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_rideStatus == 'active') {
        displayDuration++;
        notifyListeners();
      }
    });
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollStats());

    // For phone GPS mode, restart GPS stream
    if (_mode == 'without_module') {
      _startPhoneGps();
    } else if (_mode == 'with_module' && _bike != null) {
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
      if (_hasModule) await TraxApi.stopSimulation(_serialNo);
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
    route.add(pos);
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
    _statsTimer = null;
    _telemetryTimer = null;
    _durationTimer = null;
    _uploadTimer = null;
    _samplingPollTimer = null;
    _geoSub = null;
  }
}
