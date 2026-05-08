import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../common/utils/map_gesture_recognizers.dart';
import '../../common/utils/cp_marker_icons.dart';
import '../../common/utils/ride_checkpoints.dart';
import '../../common/utils/start_end_marker_icons.dart';
import '../../models/ride_lap.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../theme/app_theme.dart';
import '../../widgets/lap_splits_grid.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class RideReplayPage extends StatefulWidget {
  final List<Map<String, dynamic>> points;
  final String rideName;
  final List<RideLap> laps;

  const RideReplayPage({
    super.key,
    required this.points,
    required this.rideName,
    this.laps = const [],
  });

  @override
  State<RideReplayPage> createState() => _RideReplayPageState();
}

class _RideReplayPageState extends State<RideReplayPage> {
  GoogleMapController? _mapController;
  bool _mapReady = false;

  // Replay state
  int _currentIndex = 0;
  bool _isPlaying = false;
  Timer? _timer;
  double _speed = 1.0;

  // Parsed data
  late final List<LatLng> _positions;
  late final List<DateTime> _timestamps;
  late final List<double> _speeds; // km/h

  @override
  void initState() {
    super.initState();
    _parsePoints();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _parsePoints() {
    _positions = [];
    _timestamps = [];
    _speeds = [];
    for (final p in widget.points) {
      _positions.add(LatLng(
        (p['latitude'] as num).toDouble(),
        (p['longitude'] as num).toDouble(),
      ));
      _timestamps.add(DateTime.parse(p['timestamp'] as String));
      _speeds.add((p['speed'] as num?)?.toDouble() ?? 0);
    }
  }

  void _play() {
    if (_positions.length < 2) return;
    if (_currentIndex >= _positions.length - 1) {
      _currentIndex = 0;
    }
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

    // Calculate delay based on real time difference between points
    final dt = _timestamps[_currentIndex + 1]
        .difference(_timestamps[_currentIndex])
        .inMilliseconds;
    final delay = (dt / _speed).clamp(16, 5000).toInt(); // min 16ms, max 5s

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

  void _animateToCurrentPos() {
    if (_mapReady && _mapController != null && _currentIndex < _positions.length) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(_positions[_currentIndex]),
      );
    }
  }

  /// Trail start point for this ride: the rider's position at the exact
  /// moment lap 1 began (i.e. when the start/finish gate was first crossed).
  /// Returns null if there are no completed laps recorded.
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
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '412', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    if (_positions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: traxTitle('Ride Replay')),
        body: const Center(child: Text('No route data available')),
      );
    }

    final currentPos = _positions[_currentIndex];
    final elapsed = _timestamps[_currentIndex].difference(_timestamps.first).inSeconds;
    final total = _timestamps.last.difference(_timestamps.first).inSeconds;
    final currentSpeed = _speeds[_currentIndex];
    final currentTime = _timestamps[_currentIndex];

    // Determine completed laps at current replay time
    final completedLaps = widget.laps
        .where((l) => l.endTime != null && !currentTime.isBefore(l.endTime!))
        .toList();
    final currentLapNum = completedLaps.length + 1;

    // Trail already traversed
    final traversed = _positions.sublist(0, _currentIndex + 1);
    // Remaining path
    final remaining = _positions.sublist(_currentIndex);

    return Scaffold(
      body: Column(
        children: [
          // Map area — always takes the remaining space above the panel,
          // so the visible map region stays constant regardless of how
          // much content (lap splits etc.) the bottom panel renders.
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _positions.first,
                    zoom: 15,
                  ),
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  gestureRecognizers: kMapGestureRecognizers,
                  polylines: {
                    if (remaining.length >= 2)
                      Polyline(
                        polylineId: const PolylineId('remaining'),
                        points: remaining,
                        color: AppColors.primary.withValues(alpha: 0.25),
                        width: 4,
                      ),
                    if (traversed.length >= 2)
                      Polyline(
                        polylineId: const PolylineId('traversed'),
                        points: traversed,
                        color: AppColors.primary,
                        width: 5,
                      ),
                  },
                  markers: {
                    if (_trailStartPoint() != null)
                      Marker(
                        markerId: const MarkerId('trail_start'),
                        position: _trailStartPoint()!,
                        icon: StartEndMarkerIcons.start,
                        infoWindow: const InfoWindow(title: 'Start / Finish'),
                      ),
                    ...CpMarkerIcons.buildMarkers(
                      context,
                      rideCheckpointPositions(widget.laps),
                      onWarmed: () { if (mounted) setState(() {}); },
                    ),
                    Marker(
                      markerId: const MarkerId('rider'),
                      position: currentPos,
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                      infoWindow: InfoWindow(
                        title: '${currentSpeed.toStringAsFixed(1)} km/h',
                      ),
                    ),
                  },
                  onMapCreated: (c) {
                    _mapController = c;
                    _mapReady = true;
                  },
                ),

                // Top bar (overlays the map only)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 12,
                  right: 12,
                  child: Row(
                    children: [
                      _circleBtn(Icons.arrow_back, () => Navigator.of(context).pop()),
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
                              const Icon(Icons.replay, size: 18, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  widget.rideName,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bottom control panel — sits below the map, never overlapping it.
          _buildControlPanel(
            elapsed, total, currentSpeed,
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

  Widget _buildControlPanel(int elapsed, int total, double speed, {
    required List<RideLap> completedLaps,
    required int currentLapNum,
    required DateTime currentTime,
  }) {
    final speedLabel = _speed >= 1
        ? '${_speed.toInt()}x'
        : '${(1 / _speed).toInt().toString()}/${1.toString()}x';

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        16, 14, 16, MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Speed & time info
          Row(
            children: [
              _infoChip(Icons.speed, '${speed.toStringAsFixed(1)} km/h'),
              const SizedBox(width: 8),
              _infoChip(Icons.timer, _formatTime(elapsed)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  speedLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Seek slider
          Row(
            children: [
              Text(
                _formatTime(elapsed),
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: AppColors.primary.withValues(alpha: 0.2),
                    thumbColor: AppColors.primary,
                    overlayColor: AppColors.primary.withValues(alpha: 0.1),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: _currentIndex.toDouble(),
                    min: 0,
                    max: (_positions.length - 1).toDouble(),
                    onChanged: _seekTo,
                  ),
                ),
              ),
              Text(
                _formatTime(total),
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Lap splits (only when laps exist)
          if (widget.laps.isNotEmpty) ...[
            _buildLapInfo(completedLaps, currentLapNum, currentTime),
            const SizedBox(height: 8),
          ],

          // Playback controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Slow down
              _controlBtn(
                Icons.fast_rewind,
                _speed > 0.25 ? _speedDown : null,
              ),
              const SizedBox(width: 20),
              // Play / Pause
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
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              // Speed up
              _controlBtn(
                Icons.fast_forward,
                _speed < 8 ? _speedUp : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLapInfo(List<RideLap> completedLaps, int currentLapNum, DateTime currentTime) {
    // Current lap elapsed time
    int currentLapElapsed = 0;
    if (widget.laps.isNotEmpty) {
      final currentLap = widget.laps.where((l) => l.lapNumber == currentLapNum).firstOrNull;
      if (currentLap?.startTime != null) {
        currentLapElapsed = currentTime.difference(currentLap!.startTime!).inSeconds.clamp(0, 9999);
      } else if (completedLaps.isEmpty) {
        currentLapElapsed = currentTime.difference(_timestamps.first).inSeconds.clamp(0, 9999);
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
          // Current lap header
          Row(
            children: [
              Text(
                'Lap $currentLapNum / ${widget.laps.length}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const Spacer(),
              Text(
                _formatTime(currentLapElapsed),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary),
              ),
            ],
          ),
          // Always render the lap splits skeleton so the layout matches the
          // tracking page and is stable across the entire replay.
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
                currentLapPasses: _currentLapPassesUpTo(
                    currentLapNum, currentLapElapsed),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Returns the in-progress lap's checkpoint passes that occurred at or
  /// before [elapsedSec] from the lap start. Used to live-fill the current
  /// lap row in the splits grid as replay progresses.
  List<({int sequenceIndex, int secondsFromLapStart})> _currentLapPassesUpTo(
      int lapNumber, int elapsedSec) {
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
          Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _controlBtn(IconData icon, VoidCallback? onTap) {
    return Material(
      color: onTap != null ? AppColors.background : AppColors.background.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            size: 24,
            color: onTap != null ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
