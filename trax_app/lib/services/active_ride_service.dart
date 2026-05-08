import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/ebike.dart';
import '../models/ride_stats.dart';
import '../models/ride_point.dart';
import '../models/module_telemetry.dart';
import '../common/network/trax_api.dart';

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

  // Timers
  Timer? _statsTimer;
  Timer? _telemetryTimer;
  Timer? _durationTimer;
  Timer? _uploadTimer;
  StreamSubscription<Position>? _geoSub;
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

    if (_hasModule) {
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
    _geoSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) {
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
    });

    _uploadTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_pendingPoints.isNotEmpty) _uploadPendingPoints();
    });
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
    _geoSub?.cancel();
    _statsTimer = null;
    _telemetryTimer = null;
    _durationTimer = null;
    _uploadTimer = null;
    _geoSub = null;
  }
}
