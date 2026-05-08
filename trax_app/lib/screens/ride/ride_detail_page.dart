import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../common/utils/map_gesture_recognizers.dart';
import '../../common/utils/start_end_marker_icons.dart';
import 'package:intl/intl.dart';
import '../../models/ride_record.dart';
import '../../models/ride_lap.dart';
import '../../common/network/trax_api.dart';
import '../../common/widgets/trax_dialog.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../theme/app_theme.dart';
import '../../widgets/lap_splits_grid.dart';
import 'ride_replay_page.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class RideDetailPage extends StatefulWidget {
  final int rideId;
  const RideDetailPage({super.key, required this.rideId});

  @override
  State<RideDetailPage> createState() => _RideDetailPageState();
}

class _RideDetailPageState extends State<RideDetailPage> {
  RideRecord? _ride;
  List<LatLng> _route = [];
  List<RideLap> _laps = [];
  List<Map<String, dynamic>> _rawPoints = []; // points with timestamps
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  bool get _isLapTimer => _ride?.trailId != null;

  String get _rideTypeLabel {
    final s = _ride?.source;
    if (s == 'race') return 'Race';
    if (s == 'lap_timer') return 'Lap Timer';
    if (s == 'free_ride') return 'Free Ride';
    return _isLapTimer ? 'Lap Timer' : 'Free Ride';
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final results = await Future.wait([
      TraxApi.getRideById(widget.rideId),
      TraxApi.getRidePoints(widget.rideId),
      TraxApi.getRideLaps(widget.rideId),
    ]);

    if (!mounted) return;

    RideRecord? ride;
    if (results[0].isSuccess() && results[0].data != null) {
      ride = RideRecord.fromJson(results[0].data as Map<String, dynamic>);
    }

    List<LatLng> route = [];
    List<Map<String, dynamic>> rawPoints = [];
    if (results[1].isSuccess() && results[1].data is List) {
      rawPoints = (results[1].data as List).cast<Map<String, dynamic>>();
      route = rawPoints.map((m) {
        return LatLng(
          (m['latitude'] as num).toDouble(),
          (m['longitude'] as num).toDouble(),
        );
      }).toList();
    }

    List<RideLap> laps = [];
    if (results[2].isSuccess() && results[2].data is List) {
      laps = (results[2].data as List)
          .map((e) => RideLap.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    setState(() {
      _ride = ride;
      _route = route;
      _rawPoints = rawPoints;
      _laps = laps;
      _isLoading = false;
      if (ride == null) {
        _errorMessage = results[0].message;
      }
    });
  }

  void _confirmDelete() {
    TraxDialog.showBottomTipsDialog(
      title: 'Delete Ride',
      content: 'This ride record will be removed from your history.',
      mainBtnText: 'Delete',
      mainBtnOnPressed: () async {
        Navigator.of(context).pop(); // dismiss dialog
        final resp = await TraxApi.deleteRide(widget.rideId);
        if (!mounted) return;
        if (resp.isSuccess()) {
          Navigator.of(context).pop(true); // pop with deleted=true
        } else {
          showTraxSnackBar(context, resp.message ?? 'Failed to delete ride', isError: true);
        }
      },
      subBtnText: 'Cancel',
    );
  }

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '411', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: traxTitle('Ride Detail')),
        body: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final ride = _ride;
    if (ride == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: traxTitle('Ride Detail')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage ?? 'Ride not found'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadData,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            title: traxTitle('Ride Detail'),
            actions: [
              if (_route.length >= 2)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.play_circle_outline, color: AppColors.primary),
                    tooltip: 'Replay Ride',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RideReplayPage(
                            points: _rawPoints,
                            rideName: ride.trailName ?? ride.bicycleName ?? 'Ride',
                            laps: _laps,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              Container(
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  onPressed: _confirmDelete,
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _route.isNotEmpty
                  ? GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _route[_route.length ~/ 2],
                        zoom: 14,
                      ),
                      polylines: {
                        Polyline(
                          polylineId: const PolylineId('route'),
                          points: _route,
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
                        if (_route.length > 1)
                          Marker(
                            markerId: const MarkerId('end'),
                            position: _route.last,
                            icon: StartEndMarkerIcons.finish,
                          ),
                      },
                      myLocationEnabled: false,
                      zoomControlsEnabled: false,
                      gestureRecognizers: kMapGestureRecognizers,
                    )
                  : Container(
                      color: AppColors.background,
                      child: const Center(
                        child: Icon(Icons.map_outlined, size: 64, color: AppColors.textSecondary),
                      ),
                    ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBikeInfo(ride),
                  const SizedBox(height: 16),
                  _buildTimeInfo(ride),
                  const SizedBox(height: 16),
                  _buildStatsGrid(ride),
                  if (_isLapTimer) ...[
                    const SizedBox(height: 16),
                    _buildLapProgress(ride),
                    if (_laps.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildLapSplits(),
                    ],
                  ],
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBikeInfo(RideRecord ride) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.electric_bike, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ride.bicycleName ?? 'Unknown Bike',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                Text(
                  '$_rideTypeLabel · ${ride.mode == 'with_module' ? 'TRAX Module' : 'Phone GPS'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                if (_isLapTimer && ride.trailName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.route, size: 12, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          ride.trailName!,
                          style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (_isLapTimer)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer, size: 14, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text(
                    '${ride.completedLaps ?? 0}/${ride.targetLaps ?? '?'}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeInfo(RideRecord ride) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');
    final dateStr = ride.startTime != null ? dateFormat.format(ride.startTime!) : '--';
    final startStr = ride.startTime != null ? timeFormat.format(ride.startTime!) : '--';
    final endStr = ride.endTime != null ? timeFormat.format(ride.endTime!) : '--';
    final duration = ride.duration;
    final durationStr = duration != null ? _formatDuration(duration.inSeconds) : '--:--:--';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(dateStr, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.access_time, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text('$startStr — $endStr', style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
              const Spacer(),
              Text(durationStr, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(RideRecord ride) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Riding Info', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatItem(Icons.straighten, 'Distance', '${(ride.distance ?? 0).toStringAsFixed(2)} km'),
              _StatItem(Icons.speed, 'Avg Speed', '${(ride.avgSpeed ?? 0).toStringAsFixed(1)} km/h'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatItem(Icons.flash_on, 'Max Speed', '${(ride.maxSpeed ?? 0).toStringAsFixed(1)} km/h'),
              _StatItem(Icons.trending_up, 'Elevation', '${(ride.elevation ?? 0).toStringAsFixed(0)} m'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLapProgress(RideRecord ride) {
    final completed = ride.completedLaps ?? 0;
    final target = ride.targetLaps ?? 0;
    final progress = target > 0 ? (completed / target).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('Lap Progress', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const Spacer(),
              Text(
                completed >= target && target > 0 ? 'Completed' : '$completed / $target laps',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: completed >= target && target > 0 ? AppColors.success : AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(
                completed >= target && target > 0 ? AppColors.success : AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLapSplits() {
    final totalLapSec = _laps.fold<int>(0, (sum, l) => sum + l.durationSeconds);
    final avgLapSec = _laps.isEmpty ? 0 : totalLapSec ~/ _laps.length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timer, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Lap Splits (${_laps.length})',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              const Spacer(),
              Text('Avg ${_formatLap(avgLapSec)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 12),
          LapSplitsGrid(
            laps: _laps,
            accentColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  String _formatLap(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatItem(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}
