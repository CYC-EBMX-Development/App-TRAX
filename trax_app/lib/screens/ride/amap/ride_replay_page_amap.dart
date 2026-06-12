import 'dart:async';

import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:amap_flutter_base/amap_flutter_base.dart' as amap;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:trax_app/common/widgets/page_code_badge.dart';

import '../../../common/utils/amap_adapter.dart';
import '../../../common/utils/map_styles.dart';
import '../../../common/utils/replay_resample.dart';
import '../../../common/utils/avatar_marker_icons_amap.dart';
import '../../../common/global/global_user_info.dart';
import '../../../common/widgets/trax_refresh_button.dart';
import '../../../models/ride_lap.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/lap_splits_grid.dart';

/// Native-AMap variant of `RideReplayPage`. Renders the recorded trail on a
/// real [AMapWidget] so it works inside mainland China without depending on
/// Google Maps tiles.
///
/// Feature parity with the Google variant: timeline scrubbing, play/pause,
/// 0.25× → 8× speed, traversed-vs-remaining polylines, lap splits grid.
/// Custom CP/start markers are replaced with AMap default markers since the
/// SDK marker icon pipeline is different.
class RideReplayPageAmap extends StatefulWidget {
  final List<Map<String, dynamic>> points;
  final String rideName;
  final List<RideLap> laps;

  const RideReplayPageAmap({
    super.key,
    required this.points,
    required this.rideName,
    this.laps = const [],
  });

  @override
  State<RideReplayPageAmap> createState() => _RideReplayPageAmapState();
}

class _RideReplayPageAmapState extends State<RideReplayPageAmap> {
  AMapController? _mapController;

  int _currentIndex = 0;
  bool _isPlaying = false;
  Timer? _timer;
  double _speed = 1.0;

  late final List<LatLng> _positions;
  late final List<DateTime> _timestamps;
  late final List<double> _speeds;

  // Self-avatar marker for the replay dot.
  BitmapDescriptor? _riderIcon;

  /// Points used to frame the camera on load. For a lap-timer ride (has
  /// laps) we frame only the lap-timed portion (the trail), excluding any
  /// warm-up / cool-down riding. For a free ride (no laps) we frame the
  /// entire recorded track.
  List<LatLng> _trackForFit() {
    if (widget.laps.isEmpty) return _positions;
    final start = widget.laps.first.startTime;
    final end = widget.laps.last.endTime;
    if (start == null || end == null) return _positions;
    final n = _positions.length < _timestamps.length
        ? _positions.length
        : _timestamps.length;
    final sub = <LatLng>[];
    for (int i = 0; i < n; i++) {
      final t = _timestamps[i];
      if (!t.isBefore(start) && !t.isAfter(end)) sub.add(_positions[i]);
    }
    return sub.length >= 2 ? sub : _positions;
  }

  /// Fit the camera to the relevant geometry on load (trail for a lap-timer
  /// ride, full route for a free ride).
  void _fitToTrack() {
    final ctrl = _mapController;
    if (ctrl == null || _positions.isEmpty) return;
    final pts = _trackForFit();
    if (pts.length == 1) {
      ctrl.moveCamera(
          CameraUpdate.newLatLngZoom(AmapAdapter.toAmap(pts.first), 16));
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
    ctrl.moveCamera(CameraUpdate.newLatLngBounds(
      amap.LatLngBounds(
        southwest: AmapAdapter.toAmap(LatLng(minLat, minLng)),
        northeast: AmapAdapter.toAmap(LatLng(maxLat, maxLng)),
      ),
      48,
    ));
  }

  @override
  void initState() {
    super.initState();
    _parsePoints();
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmRiderIcon());
  }

  Future<void> _warmRiderIcon() async {
    final u = GlobalUserInfo.instance;
    final url = u.avatar.value;
    final name = u.name.value;
    final icon = await AvatarMarkerIconsAmap.build(
      context,
      avatarUrl: url.isEmpty ? null : url,
      name: name,
      color: AppColors.primary,
      isMe: true,
    );
    if (mounted) setState(() => _riderIcon = icon);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _mapController?.disponse();
    super.dispose();
  }

  void _parsePoints() {
    final positions = <LatLng>[];
    final timestamps = <DateTime>[];
    final speeds = <double>[];
    for (final p in widget.points) {
      positions.add(LatLng(
        (p['latitude'] as num).toDouble(),
        (p['longitude'] as num).toDouble(),
      ));
      timestamps.add(DateTime.parse(p['timestamp'] as String));
      speeds.add((p['speed'] as num?)?.toDouble() ?? 0);
    }
    // Resample onto a fixed 200ms grid: one point per 200ms, sparse 1s gaps
    // split into 5 interpolated sub-points along the straight line.
    final resampled = resampleReplayTrack(
      route: positions,
      times: timestamps,
      speeds: speeds,
    );
    _positions = resampled.route;
    _timestamps = resampled.times ?? timestamps;
    _speeds = resampled.speeds;
  }

  void _play() {
    if (_positions.length < 2) return;
    if (_currentIndex >= _positions.length - 1) _currentIndex = 0;
    setState(() => _isPlaying = true);
    _scheduleNext();
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _isPlaying = false);
  }

  void _scheduleNext() {
    if (_currentIndex >= _positions.length - 1) {
      setState(() => _isPlaying = false);
      return;
    }
    // Fixed 200ms cadence (scaled by _speed); points are already resampled
    // to a 200ms grid in _parsePoints.
    final delay = (200 / _speed).clamp(16, 4000).toInt();
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: delay), () {
      if (!mounted || !_isPlaying) return;
      setState(() => _currentIndex++);
      _scheduleNext();
    });
  }

  void _speedUp() {
    if (_speed >= 8) return;
    setState(() => _speed *= 2);
    if (_isPlaying) {
      _timer?.cancel();
      _scheduleNext();
    }
  }

  void _speedDown() {
    if (_speed <= 0.25) return;
    setState(() => _speed /= 2);
    if (_isPlaying) {
      _timer?.cancel();
      _scheduleNext();
    }
  }

  void _seekTo(double value) {
    final idx = value.round().clamp(0, _positions.length - 1);
    setState(() => _currentIndex = idx);
    if (_isPlaying) {
      _timer?.cancel();
      _scheduleNext();
    }
  }

  LatLng? _trailStartPoint() {
    if (widget.laps.isEmpty || _positions.isEmpty || _timestamps.isEmpty) {
      return null;
    }
    final t0 = widget.laps.first.startTime;
    if (t0 == null) return null;
    int bestIdx = 0;
    int bestDiff = 1 << 31;
    for (int i = 0; i < _timestamps.length; i++) {
      final d = _timestamps[i].difference(t0).inMilliseconds.abs();
      if (d < bestDiff) {
        bestDiff = d;
        bestIdx = i;
      }
    }
    return _positions[bestIdx];
  }

  String _formatTime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) =>
      PageCodeBadge(code: '412', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    if (_positions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: traxTitle('Ride Replay')),
        body: const Center(child: Text('No route data available')),
      );
    }

    final currentPos = _positions[_currentIndex];
    final elapsed =
        _timestamps[_currentIndex].difference(_timestamps.first).inSeconds;
    final total =
        _timestamps.last.difference(_timestamps.first).inSeconds;
    final currentSpeed = _speeds[_currentIndex];
    final currentTime = _timestamps[_currentIndex];

    final completedLaps = widget.laps
        .where((l) => l.endTime != null && !currentTime.isBefore(l.endTime!))
        .toList();
    final currentLapNum = completedLaps.length + 1;

    final traversed = _positions.sublist(0, _currentIndex + 1);
    final remaining = _positions.sublist(_currentIndex);
    final trailStart = _trailStartPoint();

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                AMapWidget(
                  privacyStatement: AmapAdapter.privacy(),
                  apiKey: AmapAdapter.apiKey(),
                  initialCameraPosition: CameraPosition(
                    target: AmapAdapter.toAmap(_positions.first),
                    zoom: 15,
                  ),
                  polylines: {
                    if (remaining.length >= 2)
                      Polyline(
                        points: AmapAdapter.toAmapList(remaining),
                        color: MapStyles.trailColor.withValues(alpha: 0.25),
                        width: MapStyles.trailWidth.toDouble(),
                      ),
                    if (traversed.length >= 2) ...[
                      Polyline(
                        points: AmapAdapter.toAmapList(traversed),
                        color: MapStyles.trailHaloColor,
                        width: MapStyles.trailHaloWidth.toDouble(),
                      ),
                      Polyline(
                        points: AmapAdapter.toAmapList(traversed),
                        color: MapStyles.trailColor,
                        width: MapStyles.trailWidth.toDouble(),
                      ),
                    ],
                  },
                  markers: {
                    if (trailStart != null)
                      Marker(
                        position: AmapAdapter.toAmap(trailStart),
                        infoWindow: const InfoWindow(title: 'Start / Finish'),
                      ),
                    Marker(
                      position: AmapAdapter.toAmap(currentPos),
                      icon: _riderIcon ?? BitmapDescriptor.defaultMarker,
                      anchor: const Offset(0.5, 0.5),
                      infoWindow: InfoWindow(
                        title: '${currentSpeed.toStringAsFixed(1)} km/h',
                      ),
                    ),
                  },
                  onMapCreated: (c) {
                    _mapController = c;
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _fitToTrack());
                  },
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 12,
                  child: _circleBtn(Icons.arrow_back,
                      () => Navigator.of(context).pop()),
                ),
              ],
            ),
          ),
          _buildControlPanel(
            elapsed,
            total,
            currentSpeed,
            completedLaps: completedLaps,
            currentLapNum: currentLapNum,
            currentTime: currentTime,
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

  Widget _buildControlPanel(
    int elapsed,
    int total,
    double speed, {
    required List<RideLap> completedLaps,
    required int currentLapNum,
    required DateTime currentTime,
  }) {
    final speedLabel = _speed >= 1
        ? '${_speed.toInt()}x'
        : '${(1 / _speed).toInt()}/1x';

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 14, 16, MediaQuery.of(context).padding.bottom + 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _infoChip(Icons.speed, '${speed.toStringAsFixed(1)} km/h'),
              const SizedBox(width: 8),
              _infoChip(Icons.timer, _formatTime(elapsed)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(speedLabel,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(_formatTime(elapsed),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor:
                        AppColors.primary.withValues(alpha: 0.2),
                    thumbColor: AppColors.primary,
                    overlayColor:
                        AppColors.primary.withValues(alpha: 0.1),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: _currentIndex.toDouble(),
                    min: 0,
                    max: (_positions.length - 1).toDouble(),
                    onChanged: _seekTo,
                  ),
                ),
              ),
              Text(_formatTime(total),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.laps.isNotEmpty) ...[
            _buildLapInfo(completedLaps, currentLapNum, currentTime),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _controlBtn(Icons.fast_rewind,
                  _speed > 0.25 ? _speedDown : null),
              const SizedBox(width: 20),
              SizedBox(
                width: 56,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isPlaying ? _pause : _play,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                  ),
                  child: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 30),
                ),
              ),
              const SizedBox(width: 20),
              _controlBtn(
                  Icons.fast_forward, _speed < 8 ? _speedUp : null),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLapInfo(List<RideLap> completedLaps, int currentLapNum,
      DateTime currentTime) {
    int currentLapElapsed = 0;
    if (widget.laps.isNotEmpty) {
      final currentLap = widget.laps
          .where((l) => l.lapNumber == currentLapNum)
          .firstOrNull;
      if (currentLap?.startTime != null) {
        currentLapElapsed = currentTime
            .difference(currentLap!.startTime!)
            .inSeconds
            .clamp(0, 9999);
      } else if (completedLaps.isEmpty) {
        currentLapElapsed = currentTime
            .difference(_timestamps.first)
            .inSeconds
            .clamp(0, 9999);
      }
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('Lap $currentLapNum / ${widget.laps.length}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const Spacer(),
              Text(_formatTime(currentLapElapsed),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 6),
          const Divider(height: 1),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: LapSplitsGrid(
                laps: completedLaps,
                accentColor: AppColors.primary,
                targetLaps: widget.laps.length,
                checkpointCount: _maxCheckpointCount(),
                currentLapNumber: currentLapNum,
                currentLapElapsed: currentLapElapsed,
                currentLapPasses:
                    _currentLapPassesUpTo(currentLapNum, currentLapElapsed),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<({int sequenceIndex, int secondsFromLapStart})>
      _currentLapPassesUpTo(int lapNumber, int elapsedSec) {
    final lap =
        widget.laps.where((l) => l.lapNumber == lapNumber).firstOrNull;
    if (lap == null) return const [];
    return lap.checkpointPasses
        .where((p) => p.secondsFromLapStart <= elapsedSec)
        .map((p) => (
              sequenceIndex: p.sequenceIndex,
              secondsFromLapStart: p.secondsFromLapStart,
            ))
        .toList();
  }

  int _maxCheckpointCount() {
    int n = 0;
    for (final l in widget.laps) {
      if (l.checkpointPasses.length > n) n = l.checkpointPasses.length;
    }
    return n;
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _controlBtn(IconData icon, VoidCallback? onTap) {
    return Material(
      color: onTap != null
          ? AppColors.background
          : AppColors.background.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon,
              size: 24,
              color: onTap != null
                  ? AppColors.textPrimary
                  : AppColors.textSecondary),
        ),
      ),
    );
  }
}
