import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../common/utils/map_gesture_recognizers.dart';
import '../../common/utils/cp_marker_icons.dart';
import '../../common/utils/ride_checkpoints.dart';
import '../../common/utils/start_end_marker_icons.dart';
import 'package:intl/intl.dart';
import '../../models/ride_record.dart';
import '../../models/ride_lap.dart';
import '../../common/network/trax_api.dart';
import '../../common/widgets/trax_dialog.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../theme/app_theme.dart';
import '../../widgets/lap_splits_grid.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class RideSummaryPage extends StatefulWidget {
  final int rideId;
  const RideSummaryPage({super.key, required this.rideId});

  @override
  State<RideSummaryPage> createState() => _RideSummaryPageState();
}

class _RideSummaryPageState extends State<RideSummaryPage> {
  RideRecord? _ride;
  List<LatLng> _route = [];
  List<RideLap> _laps = [];
  bool _isLoading = true;

  String _rideTypeLabel(RideRecord ride) {
    final s = ride.source;
    if (s == 'race') return 'Race';
    if (s == 'lap_timer') return 'Lap Timer';
    if (s == 'free_ride') return 'Free Ride';
    return ride.trailId != null ? 'Lap Timer' : 'Free Ride';
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final rideResp = TraxApi.getRideById(widget.rideId);
    final pointsResp = TraxApi.getRidePoints(widget.rideId);
    final lapsResp = TraxApi.getRideLaps(widget.rideId);
    final results = await Future.wait([rideResp, pointsResp, lapsResp]);

    if (!mounted) return;

    RideRecord? ride;
    if (results[0].isSuccess() && results[0].data != null) {
      ride = RideRecord.fromJson(results[0].data as Map<String, dynamic>);
    }

    List<LatLng> route = [];
    if (results[1].isSuccess() && results[1].data is List) {
      route = (results[1].data as List).map((p) {
        final m = p as Map<String, dynamic>;
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
      _laps = laps;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '413', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: traxTitle('Ride Summary')),
        body: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final ride = _ride;
    if (ride == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: traxTitle('Ride Summary')),
        body: const Center(child: Text('Ride not found')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: traxTitle('Ride Summary')),
      body: Column(
        children: [
          // Map header — fixed height so the map's own gestures are not
          // stolen by the surrounding scroll view.
          SizedBox(
            height: 240,
            width: double.infinity,
            child: _route.isNotEmpty
                ? GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _route[_route.length ~/ 2],
                      zoom: 14,
                    ),
                    polylines: {
                      Polyline(
                        polylineId: const PolylineId('route'),
                        points: _route,
                        color: Colors.red,
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
                      ...CpMarkerIcons.buildMarkers(
                        context,
                        rideCheckpointPositions(_laps),
                        onWarmed: () { if (mounted) setState(() {}); },
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
          // Scrollable summary content
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBikeInfo(ride),
                  const SizedBox(height: 16),
                  _buildTimeInfo(ride),
                  const SizedBox(height: 16),
                  _buildStatsGrid(ride),
                  if (_laps.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildLapSplits(),
                  ],
                  const SizedBox(height: 24),
                  _buildDoneButton(),
                  const SizedBox(height: 12),
                  _buildDeleteButton(),
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
                  '${_rideTypeLabel(ride)} · ${ride.mode == 'with_module' ? 'TRAX Module' : 'Phone GPS'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                if (ride.trailId != null && ride.trailName != null)
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Completed',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.success),
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

  Widget _buildLapSplits() {
    final totalLapSec = _laps.fold<int>(0, (sum, l) => sum + l.durationSeconds);
    final avgLapSec = totalLapSec ~/ _laps.length;

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
            reverse: false,
            title: 'Lap splits',
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

  Widget _buildDoneButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: () {
          // Pop all the way back to ride screen or main
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
        icon: const Icon(Icons.check, size: 24),
        label: const Text('Done', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
      ),
    );
  }

  Widget _buildDeleteButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _onDeleteRide,
        icon: const Icon(Icons.delete_outline, size: 20),
        label: const Text('Delete Ride', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
    );
  }

  Future<void> _onDeleteRide() async {
    TraxDialog.showBottomTipsDialog(
      title: 'Delete Ride?',
      content: 'This ride record will be permanently deleted.',
      mainBtnText: 'Delete',
      mainBtnOnPressed: () async {
        Get.back();
        final resp = await TraxApi.deleteRide(widget.rideId);
        if (!mounted) return;
        if (resp.isSuccess()) {
          showTraxSnackBar(context, 'Ride deleted');
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          showTraxSnackBar(context, resp.message ?? 'Failed to delete ride', isError: true);
        }
      },
      subBtnText: 'Cancel',
    );
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
