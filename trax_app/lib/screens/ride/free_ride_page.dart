import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../common/utils/map_gesture_recognizers.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/ebike.dart';
import '../../models/module_telemetry.dart';
import '../../services/active_ride_service.dart';
import '../../common/network/trax_api.dart';
import '../../common/utils/location_signal_gate.dart';
import '../../common/utils/keep_awake_mixin.dart';
import '../../common/services/location_service.dart';
import '../../common/widgets/my_location_fab.dart';
import '../../common/widgets/satellite_badge.dart';
import '../../common/widgets/trax_dialog.dart';
import '../../common/utils/map_styles.dart';
import '../../theme/app_theme.dart';
import '../../common/widgets/map_router.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class FreeRidePage extends StatefulWidget {
  final EBike selectedBike;
  const FreeRidePage({super.key, required this.selectedBike});

  @override
  State<FreeRidePage> createState() => _FreeRidePageState();
}

class _FreeRidePageState extends State<FreeRidePage>
    with KeepAwakeMixin<FreeRidePage> {
  final _svc = ActiveRideService.instance;

  // Map
  GoogleMapController? _mapController;
  bool _mapReady = false;

  bool get _hasModule => widget.selectedBike.traxSerialNumber != null;

  @override
  void initState() {
    super.initState();
    // Screen stays awake throughout the ride session (KeepAwakeMixin),
    // re-asserted on app resume so iOS can't drop it mid-ride.
    _svc.addListener(_onServiceUpdate);
    _initLocation();
    // Pre-Start preview: subscribe to module telemetry now so the
    // my-location button can show the bike's live position before the
    // rider taps Start. Pre-Start frames are NOT persisted into the
    // recorded route (see ActiveRideService._onModuleTelemetryJson).
    if (_hasModule) {
      _svc.previewModule(widget.selectedBike);
    }
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
    // Auto-follow camera only during active ride
    if (_mapReady && _mapController != null && _svc.rideStatus != 'idle') {
      _mapController!.animateCamera(CameraUpdate.newLatLng(_svc.currentPos));
    }
  }

  Future<void> _initLocation() async {
    // With-module bikes show the bike's position only — never the
    // phone GPS. If the module has no signal yet, the map simply stays
    // at the default camera until the first telemetry arrives.
    if (_hasModule) return;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      _svc.currentPos = LatLng(pos.latitude, pos.longitude);
      setState(() {});
      _animateToCurrentPos();
    } catch (_) {}
  }

  void _animateToCurrentPos() {
    if (_mapReady && _mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(_svc.currentPos));
    }
  }

  @override
  void dispose() {
    _svc.removeListener(_onServiceUpdate);
    // Tear down the pre-Start preview subscription if the rider left
    // without starting a ride. No-op if a ride is already active.
    _svc.stopPreview();
    _mapController?.dispose();
    super.dispose();
  }

  // ── My Location ───────────────────────────────────────────

  /// Recenter camera on user's current position. If no signal is available,
  /// show a snackbar explaining whether the module or phone GPS is the
  /// missing source.
  Future<void> _onMyLocationTap() async {
    if (_hasModule) {
      // With-module path: rely on the module telemetry stream.
      if (_svc.telemetry == null) {
        if (!mounted) return;
        showTraxSnackBar(context, 'Unable to get bike module signal', isError: true);
        return;
      }
      _animateToCurrentPos();
      return;
    }

    // Phone-GPS path: dual-source fix (Geolocator + AMap, first wins) so it
    // also works indoors in mainland China and never hangs.
    final fix = await LocationService.getFix();
    if (!mounted) return;
    if (fix == null) {
      showTraxSnackBar(context, 'Unable to get phone GPS signal', isError: true);
      return;
    }
    _svc.currentPos = fix;
    setState(() {});
    _animateToCurrentPos();
  }

  // ── Ride Controls ─────────────────────────────────────────

  Future<void> _onStart() async {
    final gateOk = await LocationSignalGate.ensureSignalOrConfirm(
      context: context,
      bike: widget.selectedBike,
    );
    if (!gateOk || !mounted) return;
    final ok = await _svc.startRide(widget.selectedBike);
    if (!mounted || !ok) return;
  }

  Future<void> _onPause() async {
    await _svc.pauseRide();
  }

  Future<void> _onResume() async {
    await _svc.resumeRide();
  }

  Future<void> _onStop() async {
    TraxDialog.showBottomTipsDialog(
      title: 'End Ride?',
      content: 'Your ride will be saved.',
      mainBtnText: 'End Ride',
      mainBtnOnPressed: () async {
        Get.back(); // dismiss GetX bottom sheet
        await _svc.stopRide();
      },
      subBtnText: 'Cancel',
    );
  }

  Future<void> _onDeleteRide(int? rideId) async {
    if (rideId == null) return;
    TraxDialog.showBottomTipsDialog(
      title: 'Delete Ride?',
      content: 'This ride record will be permanently deleted.',
      mainBtnText: 'Delete',
      mainBtnOnPressed: () async {
        Get.back(); // dismiss GetX bottom sheet
        final resp = await TraxApi.deleteRide(rideId);
        if (!mounted) return;
        if (resp.isSuccess()) {
          _svc.clearCompleted();
          showTraxSnackBar(context, 'Ride deleted');
          Navigator.pop(context); // go back to previous screen
        } else {
          showTraxSnackBar(context, resp.message ?? 'Failed to delete ride', isError: true);
        }
      },
      subBtnText: 'Cancel',
    );
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '401', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;
    final rideStatus = _svc.rideStatus;
    final route = _svc.route;
    final currentPos = _svc.currentPos;
    final stats = _svc.stats;
    final telemetry = _svc.telemetry;
    final displayDuration = _svc.displayDuration;

    return Scaffold(
      body: Stack(
        children: [
          // Map
          GoogleMap(
            initialCameraPosition: CameraPosition(target: currentPos, zoom: 16),
            // Native blue-dot is phone GPS — hide it on module bikes so the
            // map only ever shows the bike's location.
            myLocationEnabled: !_hasModule,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            gestureRecognizers: kMapGestureRecognizers,
            polylines: route.length >= 2
                ? {
                    Polyline(
                      polylineId: const PolylineId('route'),
                      points: route,
                      color: MapStyles.rideTrackColor,
                      width: MapStyles.rideTrackWidth,
                    ),
                  }
                : {},
            markers: {
              // Show current-position marker during ride
              if (rideStatus != 'idle' && route.isNotEmpty)
                Marker(
                  markerId: const MarkerId('current'),
                  position: currentPos,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueOrange),
                ),
              // Pre-ride my-location dot for module bikes: native blue dot
              // is disabled when `_hasModule`, so we draw our own once the
              // module reports its first fix. Suppressed during the ride
              // because the 'current' marker above already represents the
              // rider's live position.
              if (rideStatus == 'idle' &&
                  _hasModule &&
                  telemetry != null)
                Marker(
                  markerId: const MarkerId('me_module'),
                  position: currentPos,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueAzure),
                  anchor: const Offset(0.5, 0.5),
                  infoWindow:
                      const InfoWindow(title: 'My bike location'),
                ),
            },
            onMapCreated: (c) {
              _mapController = c;
              setState(() => _mapReady = true);
              _animateToCurrentPos();
            },
          ),

          // Back button — just pops, ride continues in background
          Positioned(
            top: safeTop + 8,
            left: 16,
            child: CircleAvatar(
              backgroundColor: AppColors.surface,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),

          // My-location button (bottom-right, above bottom panel)
          Positioned(
            right: 14,
            bottom: 256, // bottom panel (~240) + 16 margin
            child: MyLocationFab(onTap: _onMyLocationTap),
          ),

          // GPS info chip (top-right)
          Positioned(
            top: safeTop + 8,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _GpsInfoChip(position: currentPos),
                if (_hasModule) ...[
                  const SizedBox(height: 8),
                  SatelliteBadge(count: telemetry?.satellites),
                ],
                if (_hasModule && telemetry != null) ...[
                  const SizedBox(height: 8),
                  _ModuleInfoChip(telemetry: telemetry),
                ],
              ],
            ),
          ),

          // Bottom panel
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomPanel(rideStatus, stats, displayDuration, route.length),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(String rideStatus, dynamic stats, int displayDuration, int pointCount) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, -2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _StatTile('Duration', _formatDuration(displayDuration)),
              _StatTile('Distance', '${(stats?.distanceKm ?? 0).toStringAsFixed(2)} km'),
              _StatTile('Avg Speed', '${(stats?.avgSpeedKmh ?? 0).toStringAsFixed(1)} km/h'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatTile('Max Speed', '${(stats?.maxSpeedKmh ?? 0).toStringAsFixed(1)} km/h'),
              _StatTile('Elevation', '${(stats?.elevationMeters ?? 0).toStringAsFixed(0)} m'),
              _StatTile('Points', '$pointCount'),
            ],
          ),
          const SizedBox(height: 20),
          _buildControls(rideStatus),
        ],
      ),
    );
  }

  Widget _buildControls(String rideStatus) {
    switch (rideStatus) {
      case 'idle':
        return SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _onStart,
            icon: const Icon(Icons.play_arrow, size: 28),
            label: const Text('Start Ride', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
          ),
        );
      case 'active':
        return Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _onPause,
                  icon: const Icon(Icons.pause, size: 22),
                  label: const Text('Pause', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary, width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 52,
              height: 52,
              child: ElevatedButton(
                onPressed: _onStop,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                ),
                child: const Icon(Icons.stop, color: Colors.white, size: 24),
              ),
            ),
          ],
        );
      case 'paused':
        return Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _onResume,
                  icon: const Icon(Icons.play_arrow, size: 22),
                  label: const Text('Resume', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 52,
              height: 52,
              child: ElevatedButton(
                onPressed: _onStop,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                ),
                child: const Icon(Icons.stop, color: Colors.white, size: 24),
              ),
            ),
          ],
        );
      case 'completed':
        final rideId = _svc.rideId;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () {
                  _svc.clearCompleted();
                  if (rideId != null) {
                    MapRouter.openRideSummary(context, rideId: rideId, replace: true);
                  } else {
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.check, size: 24),
                label: const Text('View Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => _onDeleteRide(rideId),
                icon: const Icon(Icons.delete_outline, size: 20),
                label: const Text('Delete Ride', style: TextStyle(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
              ),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

// ── Stat Tile ───────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ── GPS Info Chip ──────────────────────────────────────────

class _GpsInfoChip extends StatelessWidget {
  final LatLng position;
  const _GpsInfoChip({required this.position});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.gps_fixed, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

// ── Module Info Chip ────────────────────────────────────────

class _ModuleInfoChip extends StatelessWidget {
  final ModuleTelemetry telemetry;
  const _ModuleInfoChip({required this.telemetry});

  @override
  Widget build(BuildContext context) {
    final bars = (telemetry.signalStrength / 25).ceil().clamp(0, 4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            telemetry.batteryPercent > 50
                ? Icons.battery_full
                : telemetry.batteryPercent > 20
                    ? Icons.battery_3_bar
                    : Icons.battery_1_bar,
            size: 18,
            color: telemetry.batteryPercent > 20 ? AppColors.success : AppColors.error,
          ),
          const SizedBox(width: 4),
          Text('${telemetry.batteryPercent}%',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(width: 10),
          Icon(Icons.signal_cellular_alt, size: 16,
              color: bars >= 3 ? AppColors.success : bars >= 2 ? AppColors.primary : AppColors.error),
          const SizedBox(width: 2),
          Text('$bars/4', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
