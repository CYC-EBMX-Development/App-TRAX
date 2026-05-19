import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:async';
import '../../common/utils/chaser_dot_icon.dart';
import '../../common/utils/map_gesture_recognizers.dart';
import '../../common/utils/cp_marker_icons.dart';
import '../../common/utils/avatar_marker_icons.dart';
import '../../common/utils/polyline_chaser.dart';
import '../../common/utils/start_end_marker_icons.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;
import '../../models/ebike.dart';
import '../../models/trail.dart';
import '../../models/ride_lap.dart';
import '../../models/user_checkpoint.dart';
import '../../services/active_ride_service.dart';
import '../../common/network/trax_api.dart';
import '../../common/widgets/trax_dialog.dart';
import '../../theme/app_theme.dart';
import '../../widgets/lap_splits_grid.dart';
import '../../common/widgets/map_router.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';
import '../../common/global/global_user_info.dart';

class LapTimerPage extends StatefulWidget {
  final EBike selectedBike;
  final Trail trail;
  final int targetLaps;
  final LatLng? startLocation;
  final bool autoStart;

  const LapTimerPage({
    super.key,
    required this.selectedBike,
    required this.trail,
    required this.targetLaps,
    this.startLocation,
    this.autoStart = false,
  });

  @override
  State<LapTimerPage> createState() => _LapTimerPageState();
}

class _LapTimerPageState extends State<LapTimerPage> {
  final _svc = ActiveRideService.instance;

  GoogleMapController? _mapController;
  bool _mapReady = false;

  List<LatLng> _trailRoute = [];
  bool _navigatedToSummary = false;

  // Lap overlap tracking
  int _lastKnownLapCount = 0;
  final Map<int, double> _lapOverlaps = {}; // lapNumber -> overlap %

  // ── Client-side start-line crossing detection ───────────
  // The lap timer arms when the rider first enters the trail's start
  // zone, then closes each lap on the next entry into the zone (after
  // having left it). The timer is paused at 0:00 until the first arm.
  // Lap counting is therefore the rider's own ground-truth crossing of
  // the start/finish line, not a server-side guess.
  DateTime? _lapStartedAt;
  bool _wasInsideStart = false;
  final List<RideLap> _localLaps = [];
  static const int _minLapSeconds = 10;
  // Gate threshold in metres for arming the display timer (matches server
  // LAP_FINISH_ZONE_KM = 30 m).
  static const double _gateArmMeters = 30.0;

  // User-defined checkpoints for this trail (used for live in-progress
  // checkpoint-pass detection on the lap splits grid).
  List<UserCheckpoint> _userCheckpoints = [];
  // Pass-through tolerance in metres (matches backend CHECKPOINT_PASS_KM=0.025).
  static const double _cpPassMeters = 25.0;
  // Live passes for the in-progress lap: sequenceIndex -> secondsFromLapStart.
  final Map<int, int> _currentLapPasses = {};
  int _currentLapNumberLive = 1;

  // Whether checkpoint markers are shown on the map (toggleable).
  bool _showCheckpoints = true;

  // Self-avatar map marker (built lazily once per session).
  BitmapDescriptor? _meIcon;

  // Direction-of-travel hint on the trail polyline (mirrors trail
  // detail header). The dot keeps sliding regardless of ride state so
  // riders can see the trail direction even while paused at the start.
  PolylineChaser? _chaser;
  BitmapDescriptor? _chaserDot;
  Timer? _chaserTimer;
  double _chaserPhase = 0;

  @override
  void initState() {
    super.initState();
    // Keep the screen awake throughout the lap session.
    WakelockPlus.enable();
    _svc.addListener(_onSvcUpdate);
    _loadTrailRoute();
    _loadUserCheckpoints();
    _initLocation();
    _warmMeIcon();
    _loadChaserDot();
  }

  Future<void> _loadChaserDot() async {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final dpr = views.isNotEmpty ? views.first.devicePixelRatio : 3.0;
    final icon = await ChaserDotIcon.bitmap(dpr);
    if (!mounted) return;
    setState(() => _chaserDot = icon);
  }

  void _startChaser() {
    _chaserTimer?.cancel();
    if (_trailRoute.length < 3) return;
    _chaser = PolylineChaser(_trailRoute);
    _chaserTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      setState(() => _chaserPhase = (_chaserPhase + 0.00222) % 1.0);
    });
  }

  Future<void> _warmMeIcon() async {
    final userInfo = GlobalUserInfo.instance;
    final url = userInfo.avatar.value;
    final name = userInfo.name.value;
    final icon = await AvatarMarkerIcons.build(
      context,
      avatarUrl: url.isEmpty ? null : url,
      name: name,
      color: AppColors.primary,
      isMe: true,
    );
    if (mounted) setState(() => _meIcon = icon);
  }

  @override
  void dispose() {
    _svc.removeListener(_onSvcUpdate);
    _mapController?.dispose();
    _chaserTimer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _loadUserCheckpoints() async {
    final id = int.tryParse(widget.trail.id ?? '');
    if (id == null) return;
    final resp = await TraxApi.getTrailCheckpoints(id);
    if (!mounted || !resp.isSuccess() || resp.data is! List) return;
    final cps = (resp.data as List)
        .map((e) => UserCheckpoint.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.sequenceIndex.compareTo(b.sequenceIndex));
    if (!mounted) return;
    setState(() => _userCheckpoints = cps);
    // Pre-build numbered marker bitmaps so they render on the next frame.
    final changed = await CpMarkerIcons.warm(
        context, cps.map((c) => c.sequenceIndex));
    if (changed && mounted) setState(() {});
  }

  Future<void> _loadTrailRoute() async {
    final id = int.tryParse(widget.trail.id ?? '');
    if (id == null) return;
    final resp = await TraxApi.getTrailPoints(id);
    if (!mounted || !resp.isSuccess() || resp.data is! List) return;
    final pts = (resp.data as List).map((p) {
      final m = p as Map<String, dynamic>;
      return LatLng(
        (m['latitude'] as num).toDouble(),
        (m['longitude'] as num).toDouble(),
      );
    }).toList();
    setState(() => _trailRoute = pts);
    _startChaser();
    if (pts.isNotEmpty) {
      if (_svc.rideStatus == 'idle' && widget.startLocation != null) {
        _svc.currentPos = widget.startLocation!;
      }
      _fitTrailBounds();
      if (_svc.rideStatus == 'idle' && widget.autoStart) {
        _onStart();
      }
    }
  }

  /// Fit the camera to the whole trail (plus checkpoints) so the user
  /// can see the full loop on entry instead of a fixed 15-zoom centered
  /// on the route midpoint.
  void _fitTrailBounds() {
    if (!_mapReady || _mapController == null) return;
    final pts = <LatLng>[
      ..._trailRoute,
      for (final cp in _userCheckpoints) LatLng(cp.latitude, cp.longitude),
    ];
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(pts.first, 16),
      );
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
        60,
      ),
    );
  }

  Future<void> _initLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      if (widget.startLocation == null && _svc.rideStatus == 'idle') {
        _svc.currentPos = LatLng(pos.latitude, pos.longitude);
        setState(() {});
      }
    } catch (_) {}
  }

  void _onSvcUpdate() {
    if (!mounted) return;

    // ── Client-side start-line crossing detection ──────────
    // Detect entering / leaving the start zone, then close laps on the
    // re-entry edge. This is the source of truth for lap counting; we
    // ignore server-reported laps (which arrive with delay and missed
    // the "start counting when the rider crosses the line" requirement).
    if (_svc.rideStatus == 'active' && _trailRoute.isNotEmpty) {
      final d = _distMeters(_svc.currentPos, _trailRoute.first);
      final inside = d <= _gateArmMeters;
      if (inside && !_wasInsideStart) {
        final now = DateTime.now();
        if (_lapStartedAt == null) {
          // First crossing of the start line — the lap timer arms now.
          _lapStartedAt = now;
        } else {
          final elapsed = now.difference(_lapStartedAt!).inSeconds;
          if (elapsed >= _minLapSeconds) {
            // Close the in-progress lap and immediately start the next.
            final lapNum = _localLaps.length + 1;
            _localLaps.add(RideLap(
              lapNumber: lapNum,
              durationSeconds: elapsed,
              distanceKm: 0,
              startTime: _lapStartedAt,
              endTime: now,
            ));
            _currentLapPasses.clear();
            _currentLapNumberLive = _localLaps.length + 1;
            _lapStartedAt = now;
            // Auto-finish if target reached.
            if (_localLaps.length >= widget.targetLaps &&
                !_navigatedToSummary) {
              _onTargetReached();
            }
          }
        }
      }
      _wasInsideStart = inside;
    }

    // Keep _lastKnownLapCount/_lapOverlaps in sync with our local laps so
    // the rest of the UI keeps reacting.
    if (_localLaps.length > _lastKnownLapCount) {
      _lastKnownLapCount = _localLaps.length;
    }

    // Live in-progress checkpoint-pass detection. Lap-elapsed is derived
    // from _lapStartedAt; before the first arm it stays at 0.
    if (_svc.rideStatus == 'active') {
      final completed = _localLaps.length;
      final lapElapsed = _currentLapElapsedSec(_localLaps);
      _currentLapNumberLive =
          (completed + 1).clamp(1, widget.targetLaps);
      for (final cp in _userCheckpoints) {
        if (_currentLapPasses.containsKey(cp.sequenceIndex)) continue;
        final d = _distMeters(
            _svc.currentPos, LatLng(cp.latitude, cp.longitude));
        if (d <= _cpPassMeters) {
          _currentLapPasses[cp.sequenceIndex] = lapElapsed;
        }
      }
    }

    setState(() {});
    if (_svc.rideStatus == 'active' &&
        _mapReady &&
        _mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(_svc.currentPos));
    }
    // Auto-navigate to summary when ride auto-completed by server (target reached)
    if (_svc.rideStatus == 'completed' &&
        _svc.rideId != null &&
        !_navigatedToSummary) {
      _navigatedToSummary = true;
      _goToSummary(_svc.rideId!);
    }
  }

  Future<void> _onTargetReached() async {
    final rideId = _svc.rideId;
    await _svc.stopRide();
    if (!mounted || rideId == null) return;
    _navigatedToSummary = true;
    _goToSummary(rideId);
  }

  /// Seconds elapsed in the in-progress lap. Returns 0 until the rider
  /// has crossed the trail start line (i.e. [_lapStartedAt] is set).
  int _currentLapElapsedSec(List<RideLap> laps) {
    if (_lapStartedAt == null) return 0;
    final s = DateTime.now().difference(_lapStartedAt!).inSeconds;
    return s < 0 ? 0 : s;
  }

  /// Haversine distance in meters between two LatLng points.
  static double _distMeters(LatLng a, LatLng b) {
    const R = 6371000.0; // earth radius in meters
    final dLat = _toRad(b.latitude - a.latitude);
    final dLng = _toRad(b.longitude - a.longitude);
    final sinLat = math.sin(dLat / 2);
    final sinLng = math.sin(dLng / 2);
    final h = sinLat * sinLat +
        math.cos(_toRad(a.latitude)) * math.cos(_toRad(b.latitude)) * sinLng * sinLng;
    return 2 * R * math.asin(math.sqrt(h));
  }

  static double _toRad(double deg) => deg * math.pi / 180;

  Color _overlapColor(double pct) {
    if (pct >= 80) return AppColors.success;
    if (pct >= 50) return AppColors.primary;
    return AppColors.error;
  }

  void _animateTo(LatLng pos) {
    if (_mapReady && _mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(pos));
    }
  }

  // ── Lifecycle ────────────────────────────────────────────

  Future<void> _onStart() async {
    final id = int.tryParse(widget.trail.id ?? '');
    if (id == null) return;
    // Anchor adaptive GPS sampling to the trail's start (lap = same as end).
    if (_trailRoute.isNotEmpty) {
      _svc.setSamplingAnchors(
        start: _trailRoute.first,
        end: _trailRoute.last,
      );
    }
    final ok = await _svc.startLapTimer(
      bike: widget.selectedBike,
      trailId: id,
      trailName: widget.trail.name,
      targetLaps: widget.targetLaps,
    );
    if (!mounted) return;
    if (!ok) {
      showTraxSnackBar(context, 'Failed to start lap timer', isError: true);
    }
  }

  Future<void> _onStop() async {
    TraxDialog.showBottomTipsDialog(
      title: 'End Lap Timer?',
      content: 'Your lap session will be saved.',
      mainBtnText: 'End',
      mainBtnOnPressed: () async {
        Get.back();
        final rideId = _svc.rideId;
        await _svc.stopRide();
        if (!mounted || rideId == null) return;
        _navigatedToSummary = true;
        _goToSummary(rideId);
      },
      subBtnText: 'Cancel',
    );
  }

  Future<void> _goToSummary(int rideId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    await MapRouter.openRideSummary(context, rideId: rideId, replace: true);
    _svc.clearCompleted();
  }

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '405', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    final rideStatus = _svc.rideStatus;
    final laps = _localLaps;
    final completedLaps = laps.length;
    final currentLapNumber = (completedLaps + 1).clamp(1, widget.targetLaps);
    final isRunning = rideStatus == 'active' || rideStatus == 'paused';

    // Current lap elapsed seconds — client-side: derived from
    // [_lapStartedAt] (the moment the rider crossed the start line).
    final totalSec = _svc.displayDuration;
    final currentLapSec = _currentLapElapsedSec(laps);

    final mapTarget = _trailRoute.isNotEmpty
        ? _trailRoute[_trailRoute.length ~/ 2]
        : _svc.currentPos;

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GoogleMap(
                    initialCameraPosition:
                        CameraPosition(target: mapTarget, zoom: 15),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    gestureRecognizers: kMapGestureRecognizers,
                    polylines: {
                      if (_trailRoute.length >= 2)
                        Polyline(
                          polylineId: const PolylineId('trail'),
                          points: _trailRoute,
                          color: AppColors.primary.withValues(alpha: 0.5),
                          width: 3,
                        ),
                      if (_svc.route.length >= 2)
                        Polyline(
                          polylineId: const PolylineId('ride'),
                          points: _svc.route,
                          color: AppColors.primary,
                          width: 2,
                        ),
                    },
                    markers: {
                      if (_trailRoute.isNotEmpty)
                        Marker(
                          markerId: const MarkerId('start'),
                          position: _trailRoute.first,
                          icon: StartEndMarkerIcons.start,
                          infoWindow:
                              const InfoWindow(title: 'Start / Finish'),
                        ),
                      for (final cp in _showCheckpoints
                          ? _userCheckpoints
                          : const <UserCheckpoint>[])
                        Marker(
                          markerId: MarkerId('cp_${cp.sequenceIndex}'),
                          position: LatLng(cp.latitude, cp.longitude),
                          icon: CpMarkerIcons.getOrFallback(
                              context, cp.sequenceIndex),
                          infoWindow:
                              InfoWindow(title: 'CP${cp.sequenceIndex}'),
                        ),
                      if (isRunning)
                        Marker(
                          markerId: const MarkerId('me'),
                          position: _svc.currentPos,
                          icon: _meIcon ?? BitmapDescriptor.defaultMarker,
                          anchor: const Offset(0.5, 0.5),
                        ),
                      if (_chaserDot != null &&
                          (_chaser?.canRender ?? false))
                        Marker(
                          markerId: const MarkerId('trail_chaser'),
                          position: _chaser!.headAt(_chaserPhase),
                          icon: _chaserDot!,
                          anchor: const Offset(0.5, 0.5),
                          flat: true,
                          zIndex: 6,
                        ),
                    },
                    onMapCreated: (c) {
                      _mapController = c;
                      _mapReady = true;
                      _fitTrailBounds();
                    },
                  ),
                ),

                // Top app bar
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 12,
                  right: 12,
                  child: Row(
                    children: [
                      _circleBtn(
                        Icons.arrow_back,
                        () => Navigator.of(context).pop(),
                      ),
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
                                  color:
                                      Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 6),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.timer,
                                  size: 18, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  widget.trail.name,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_userCheckpoints.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _cpToggleBtn(),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          _buildBottomPanel(
            isRunning: isRunning,
            currentLapNumber: currentLapNumber,
            completedLaps: completedLaps,
            currentLapSec: currentLapSec,
            totalSec: totalSec,
            laps: laps,
          ),
        ],
      ),
    );
  }

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

  Widget _cpToggleBtn() {
    final on = _showCheckpoints;
    return Material(
      color: on ? AppColors.primary : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _showCheckpoints = !_showCheckpoints),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                on ? Icons.flag : Icons.flag_outlined,
                size: 16,
                color: on ? Colors.white : AppColors.textPrimary,
              ),
              const SizedBox(width: 4),
              Text(
                on ? 'Hide CP' : 'Show CP',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPanel({
    required bool isRunning,
    required int currentLapNumber,
    required int completedLaps,
    required int currentLapSec,
    required int totalSec,
    required List<RideLap> laps,
  }) {
    final fastest = laps.isEmpty
        ? null
        : laps.reduce((a, b) => a.durationSeconds < b.durationSeconds ? a : b);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.of(context).padding.bottom + 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Lap counter row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Current lap',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    const SizedBox(height: 2),
                    Text(
                      'Lap $currentLapNumber / ${widget.targetLaps}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Lap time',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  Text(
                    _formatDuration(currentLapSec),
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Total + best
          Row(
            children: [
              _miniStat('Total', _formatDuration(totalSec)),
              const SizedBox(width: 8),
              _miniStat('Completed', '$completedLaps'),
              const SizedBox(width: 8),
              _miniStat('Best lap',
                  fastest == null ? '—' : fastest.formatted),
            ],
          ),
          // Always render the lap splits skeleton so the grid is visible
          // from the start of the session and fills in live as checkpoints
          // are passed.
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: SingleChildScrollView(
              child: LapSplitsGrid(
                laps: laps,
                accentColor: AppColors.primary,
                targetLaps: widget.targetLaps,
                checkpointCount: _userCheckpoints.length,
                currentLapNumber: isRunning ? currentLapNumber : null,
                currentLapPasses: _currentLapPasses.entries
                    .map((e) => (
                          sequenceIndex: e.key,
                          secondsFromLapStart: e.value,
                        ))
                    .toList(),
                currentLapElapsed: isRunning ? currentLapSec : null,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildControls(isRunning),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(bool isRunning) {
    if (!isRunning) {
      return SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: _onStart,
          icon: const Icon(Icons.play_arrow, size: 22),
          label: Text('Start ${widget.targetLaps}-Lap Session',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          ),
        ),
      );
    }
    return Row(
      children: [
        if (_svc.rideStatus == 'active')
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => _svc.pauseRide(),
                icon: const Icon(Icons.pause, size: 20),
                label: const Text('Pause'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
              ),
            ),
          )
        else
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => _svc.resumeRide(),
                icon: const Icon(Icons.play_arrow, size: 20),
                label: const Text('Resume'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
              ),
            ),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _onStop,
              icon: const Icon(Icons.stop, size: 20),
              label: const Text('Finish'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDuration(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:$mm:$ss';
    return '$mm:$ss';
  }
}
