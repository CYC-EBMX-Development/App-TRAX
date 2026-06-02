import 'dart:async';
import 'dart:math' as math;

import 'package:amap_flutter_base/amap_flutter_base.dart' as amap;
import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:trax_app/common/widgets/page_code_badge.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../common/network/trax_api.dart';
import '../../../common/utils/amap_adapter.dart';
import '../../../common/utils/avatar_marker_icons_amap.dart';
import '../../../common/utils/cp_marker_icons_amap.dart';
import '../../../common/utils/start_end_marker_icons_amap.dart';
import '../../../common/global/global_user_info.dart';
import '../../../common/widgets/map_router.dart';
import '../../../common/widgets/trax_dialog.dart';
import '../../../models/ebike.dart';
import '../../../models/ride_lap.dart';
import '../../../models/trail.dart';
import '../../../models/user_checkpoint.dart';
import '../../../services/active_ride_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/lap_splits_grid.dart';

/// Native-AMap variant of `LapTimerPage`. Identical state machine, just
/// renders the map with [AMapWidget] so it works inside mainland China.
/// Custom start/checkpoint pictograms are replaced with AMap default
/// markers (different icon pipeline; no asset bundling needed).
class LapTimerPageAmap extends StatefulWidget {
  final EBike selectedBike;
  final Trail trail;
  final int targetLaps;
  final LatLng? startLocation;
  final bool autoStart;

  const LapTimerPageAmap({
    super.key,
    required this.selectedBike,
    required this.trail,
    required this.targetLaps,
    this.startLocation,
    this.autoStart = false,
  });

  @override
  State<LapTimerPageAmap> createState() => _LapTimerPageAmapState();
}

class _LapTimerPageAmapState extends State<LapTimerPageAmap> {
  final _svc = ActiveRideService.instance;

  AMapController? _mapController;
  bool _mapReady = false;

  List<LatLng> _trailRoute = [];
  bool _navigatedToSummary = false;

  int _lastKnownLapCount = 0;
  final Map<int, double> _lapOverlaps = {};

  DateTime? _displayGateArmedAt;
  static const double _gateArmMeters = 30.0;

  List<UserCheckpoint> _userCheckpoints = [];
  static const double _cpPassMeters = 25.0;
  final Map<int, int> _currentLapPasses = {};
  int _currentLapNumberLive = 1;

  bool _showCheckpoints = true;

  // Self-avatar AMap marker (lazy-built once per session).
  BitmapDescriptor? _meIcon;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _svc.addListener(_onSvcUpdate);
    _loadTrailRoute();
    _loadUserCheckpoints();
    _initLocation();
    _warmMeIcon();
  }

  Future<void> _warmMeIcon() async {
    final userInfo = GlobalUserInfo.instance;
    final url = userInfo.avatar.value;
    final name = userInfo.name.value;
    final icon = await AvatarMarkerIconsAmap.build(
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
    _mapController?.disponse();
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
    // Pre-warm numbered CP badge bitmaps so they appear on first paint.
    if (cps.isNotEmpty) {
      // ignore: discarded_futures
      CpMarkerIconsAmap.warm(context, cps.map((c) => c.sequenceIndex))
          .then((changed) {
        if (changed && mounted) setState(() {});
      });
    }
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
    if (pts.isNotEmpty) {
      if (_svc.rideStatus == 'idle' && widget.startLocation != null) {
        _svc.currentPos = widget.startLocation!;
      }
      _fitTrailBounds();
      if (_svc.rideStatus == 'idle' && widget.autoStart) _onStart();
    }
  }

  /// Fit the camera to the whole trail (plus checkpoints + current pos)
  /// with sensible padding. Called whenever new geometry is loaded so the
  /// initial view is never stuck at a single-point or overly zoomed-in
  /// camera.
  void _fitTrailBounds() {
    if (!_mapReady || _mapController == null) return;
    final pts = <LatLng>[
      ..._trailRoute,
      for (final cp in _userCheckpoints) LatLng(cp.latitude, cp.longitude),
    ];
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _mapController!.moveCamera(
        CameraUpdate.newLatLngZoom(AmapAdapter.toAmap(pts.first), 16),
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
    _mapController!.moveCamera(
      CameraUpdate.newLatLngBounds(
        amap.LatLngBounds(
          southwest: amap.LatLng(minLat, minLng),
          northeast: amap.LatLng(maxLat, maxLng),
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
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
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

    if (_displayGateArmedAt == null &&
        _svc.rideStatus == 'active' &&
        _trailRoute.isNotEmpty) {
      final d = _distMeters(_svc.currentPos, _trailRoute.first);
      if (d <= _gateArmMeters) _displayGateArmedAt = DateTime.now();
    }

    final laps = _svc.stats?.laps ?? const <RideLap>[];
    if (laps.length > _lastKnownLapCount) {
      for (int i = _lastKnownLapCount; i < laps.length; i++) {
        final lap = laps[i];
        _lapOverlaps[lap.lapNumber] = lap.overlapPercent ?? 0;
      }
      _lastKnownLapCount = laps.length;
      _currentLapPasses.clear();
      _currentLapNumberLive = laps.length + 1;
    }

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
    if (_svc.rideStatus == 'active' && _mapReady && _mapController != null) {
      _mapController!.moveCamera(
        CameraUpdate.newLatLng(AmapAdapter.toAmap(_svc.currentPos)),
        animated: true,
      );
    }
    if (_svc.rideStatus == 'completed' &&
        _svc.rideId != null &&
        !_navigatedToSummary) {
      _navigatedToSummary = true;
      _goToSummary(_svc.rideId!);
    }
  }

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

  static double _distMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = _toRad(b.latitude - a.latitude);
    final dLng = _toRad(b.longitude - a.longitude);
    final sinLat = math.sin(dLat / 2);
    final sinLng = math.sin(dLng / 2);
    final h = sinLat * sinLat +
        math.cos(_toRad(a.latitude)) *
            math.cos(_toRad(b.latitude)) *
            sinLng *
            sinLng;
    return 2 * r * math.asin(math.sqrt(h));
  }

  static double _toRad(double deg) => deg * math.pi / 180;

  void _animateTo(LatLng pos) {
    if (_mapReady && _mapController != null) {
      _mapController!.moveCamera(
        CameraUpdate.newLatLng(AmapAdapter.toAmap(pos)),
        animated: true,
      );
    }
  }

  Future<void> _onStart() async {
    final id = int.tryParse(widget.trail.id ?? '');
    if (id == null) return;
    if (_trailRoute.isNotEmpty) {
      _svc.setSamplingAnchors(
          start: _trailRoute.first, end: _trailRoute.last);
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

  @override
  Widget build(BuildContext context) =>
      PageCodeBadge(code: '405', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    final rideStatus = _svc.rideStatus;
    final stats = _svc.stats;
    final laps = stats?.laps ?? const <RideLap>[];
    final completedLaps = laps.length;
    final currentLapNumber =
        (completedLaps + 1).clamp(1, widget.targetLaps);
    final isRunning = rideStatus == 'active' || rideStatus == 'paused';

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
                  child: AMapWidget(
                    privacyStatement: AmapAdapter.privacy(),
                    apiKey: AmapAdapter.apiKey(),
                    initialCameraPosition: CameraPosition(
                        target: AmapAdapter.toAmap(mapTarget), zoom: 15),
                    polylines: {
                      if (_trailRoute.length >= 2)
                        Polyline(
                          points: AmapAdapter.toAmapList(_trailRoute),
                          color: AppColors.primary.withValues(alpha: 0.5),
                          width: 14,
                        ),
                      if (_svc.route.length >= 2)
                        Polyline(
                          points: AmapAdapter.toAmapList(_svc.route),
                          color: Colors.red,
                          width: 14,
                        ),
                    },
                    markers: {
                      if (_trailRoute.isNotEmpty)
                        Marker(
                          position:
                              AmapAdapter.toAmap(_trailRoute.first),
                          icon: StartEndMarkerIconsAmap.start,
                          anchor: const Offset(0.5, 0.5),
                          infoWindow:
                              const InfoWindow(title: 'Start / Finish'),
                        ),
                      if (_showCheckpoints)
                        ...CpMarkerIconsAmap.buildMarkers(
                          context,
                          {
                            for (final cp in _userCheckpoints)
                              cp.sequenceIndex:
                                  LatLng(cp.latitude, cp.longitude),
                          },
                          onWarmed: () {
                            if (mounted) setState(() {});
                          },
                        ),
                      if (isRunning)
                        Marker(
                          position: AmapAdapter.toAmap(_svc.currentPos),
                          icon: _meIcon ?? BitmapDescriptor.defaultMarker,
                          anchor: const Offset(0.5, 0.5),
                          infoWindow: const InfoWindow(title: 'You'),
                        ),
                    },
                    onMapCreated: (c) {
                      _mapController = c;
                      _mapReady = true;
                      _fitTrailBounds();
                    },
                  ),
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 12,
                  right: 12,
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
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text('AMap',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary)),
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
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: AppColors.textPrimary),
        ),
      ),
    );
  }

  Widget _cpToggleBtn() {
    final on = _showCheckpoints;
    return Material(
      color: on ? AppColors.primary : Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _showCheckpoints = !_showCheckpoints),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(on ? Icons.flag : Icons.flag_outlined,
                  size: 16,
                  color: on ? Colors.white : AppColors.textPrimary),
              const SizedBox(width: 4),
              Text(on ? 'Hide CP' : 'Show CP',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color:
                          on ? Colors.white : AppColors.textPrimary)),
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
        : laps.reduce(
            (a, b) => a.durationSeconds < b.durationSeconds ? a : b);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 14, 16, MediaQuery.of(context).padding.bottom + 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Current lap',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 2),
                    Text('Lap $currentLapNumber / ${widget.targetLaps}',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Lap time',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  Text(_formatDuration(currentLapSec),
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
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
        padding:
            const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
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
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25)),
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
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
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
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
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
