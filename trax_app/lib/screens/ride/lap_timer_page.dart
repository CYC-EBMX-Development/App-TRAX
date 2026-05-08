import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../common/utils/map_gesture_recognizers.dart';
import '../../common/utils/cp_marker_icons.dart';
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
import 'ride_summary_page.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

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

  // Client-side gate-arm timestamp — ONLY used to drive the displayed
  // "current lap" elapsed time before the server has reported any
  // completed lap. Lap COUNTING stays server-authoritative.
  DateTime? _displayGateArmedAt;
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

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onSvcUpdate);
    _loadTrailRoute();
    _loadUserCheckpoints();
    _initLocation();
  }

  @override
  void dispose() {
    _svc.removeListener(_onSvcUpdate);
    _mapController?.dispose();
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
    if (pts.isNotEmpty && _svc.rideStatus == 'idle') {
      // Use custom start location if provided, otherwise keep current position
      if (widget.startLocation != null) {
        _svc.currentPos = widget.startLocation!;
      }
      final startPos = _svc.currentPos;
      _animateTo(startPos);
      // Auto-start the ride if requested from setup page
      if (widget.autoStart) {
        _onStart();
      }
    }
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

    // Arm the display timer the first time we get within the gate zone of
    // the trail start point while the ride is active. This only controls
    // the live "Lap time" readout — lap counting/closing is decided by
    // the server.
    if (_displayGateArmedAt == null &&
        _svc.rideStatus == 'active' &&
        _trailRoute.isNotEmpty) {
      final d = _distMeters(_svc.currentPos, _trailRoute.first);
      if (d <= _gateArmMeters) {
        _displayGateArmedAt = DateTime.now();
      }
    }

    // Lap completion detection — server is the single source of truth
    // (same logic race uses: read completed laps from RideStats).
    final laps = _svc.stats?.laps ?? const <RideLap>[];
    if (laps.length > _lastKnownLapCount) {
      for (int i = _lastKnownLapCount; i < laps.length; i++) {
        final lap = laps[i];
        _lapOverlaps[lap.lapNumber] = lap.overlapPercent ?? 0;
      }
      _lastKnownLapCount = laps.length;
      // A new lap was just completed — reset the live in-progress pass map
      // so the next lap's row starts fresh.
      _currentLapPasses.clear();
      _currentLapNumberLive = laps.length + 1;
    }

    // Live in-progress checkpoint-pass detection. Lap-elapsed is derived
    // from the last completed lap's endTime (server-authoritative); before
    // the first lap closes we fall back to the running ride duration.
    if (_svc.rideStatus == 'active') {
      final completed = laps.length;
      final lapElapsed = _currentLapElapsedSec(laps);
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

  /// Seconds elapsed in the in-progress lap.
  /// - At least one lap completed → now - lastLap.endTime (server-authoritative).
  /// - No lap completed yet → now - clientGateArmedAt, or 0 if the rider
  ///   has not yet crossed/entered the trail start zone.
  int _currentLapElapsedSec(List<RideLap> laps) {
    if (laps.isNotEmpty) {
      final lastEnd = laps.last.endTime;
      if (lastEnd != null) {
        final s = DateTime.now().difference(lastEnd).inSeconds;
        return s < 0 ? 0 : s;
      }
    }
    if (_displayGateArmedAt != null) {
      final s = DateTime.now().difference(_displayGateArmedAt!).inSeconds;
      return s < 0 ? 0 : s;
    }
    return 0;
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
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => RideSummaryPage(rideId: rideId)),
    );
    _svc.clearCompleted();
  }

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '405', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    final rideStatus = _svc.rideStatus;
    final stats = _svc.stats;
    final laps = stats?.laps ?? const <RideLap>[];
    final completedLaps = laps.length;
    final currentLapNumber = (completedLaps + 1).clamp(1, widget.targetLaps);
    final isRunning = rideStatus == 'active' || rideStatus == 'paused';

    // Current lap elapsed seconds — server-authoritative: derived from
    // the last completed lap's endTime, or the ride's running duration
    // before the first lap closes.
    final totalSec = _svc.displayDuration;
    final currentLapSec = _currentLapElapsedSec(laps);

    // Initial map target
    final mapTarget = _trailRoute.isNotEmpty
        ? _trailRoute[_trailRoute.length ~/ 2]
        : _svc.currentPos;

    final screenH = MediaQuery.of(context).size.height;
    final mapH = (screenH * 0.45).clamp(280.0, 460.0);

    return Scaffold(
      body: Stack(
        children: [
          // Map (top half)
          Positioned(
            top: 0, left: 0, right: 0,
            height: mapH,
            child: GoogleMap(
            initialCameraPosition: CameraPosition(target: mapTarget, zoom: 15),
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
                  width: 5,
                ),
              if (_svc.route.length >= 2)
                Polyline(
                  polylineId: const PolylineId('ride'),
                  points: _svc.route,
                  color: AppColors.primary,
                  width: 4,
                ),
            },
            markers: {
              if (_trailRoute.isNotEmpty)
                Marker(
                  markerId: const MarkerId('start'),
                  position: _trailRoute.first,
                  icon: StartEndMarkerIcons.start,
                  infoWindow: const InfoWindow(title: 'Start / Finish'),
                ),
              for (final cp in _showCheckpoints ? _userCheckpoints : const <UserCheckpoint>[])
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
                  icon: BitmapDescriptor.defaultMarker,
                ),
            },
            onMapCreated: (c) {
              _mapController = c;
              _mapReady = true;
              if (_trailRoute.isNotEmpty) _animateTo(_trailRoute.first);
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.timer, size: 18, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.trail.name,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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

          // Bottom panel
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _buildBottomPanel(
              isRunning: isRunning,
              currentLapNumber: currentLapNumber,
              completedLaps: completedLaps,
              currentLapSec: currentLapSec,
              totalSec: totalSec,
              laps: laps,
            ),
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
