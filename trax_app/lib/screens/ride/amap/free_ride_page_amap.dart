import 'package:amap_flutter_base/amap_flutter_base.dart' as amap;
import 'package:amap_flutter_map/amap_flutter_map.dart' as amap_map;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../common/global/global_user_info.dart';
import '../../../common/network/trax_api.dart';
import '../../../common/utils/amap_adapter.dart';
import '../../../common/utils/avatar_marker_icons_amap.dart';
import '../../../common/widgets/map_router.dart';
import '../../../common/widgets/trax_dialog.dart';
import '../../../models/ebike.dart';
import '../../../models/module_telemetry.dart';
import '../../../services/active_ride_service.dart';
import '../../../theme/app_theme.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

/// AMap variant of [FreeRidePage]. Same state machine, same controls — the
/// `GoogleMap` is replaced with an `AMapWidget` and tap-to-pick uses the
/// camera centre (AMap has no `getLatLng` API). Coordinates returned by the
/// SDK are in GCJ-02 and converted back to WGS-84 before being forwarded
/// to [ActiveRideService].
class FreeRidePageAmap extends StatefulWidget {
  final EBike selectedBike;
  const FreeRidePageAmap({super.key, required this.selectedBike});

  @override
  State<FreeRidePageAmap> createState() => _FreeRidePageAmapState();
}

class _FreeRidePageAmapState extends State<FreeRidePageAmap> {
  final _svc = ActiveRideService.instance;

  amap_map.AMapController? _mapController;
  bool _mapReady = false;

  bool _isPicking = false;
  LatLng? _pickedLocation;
  // Latest camera target reported by the SDK (in GCJ-02).
  amap.LatLng? _cameraCenter;

  // Self-avatar marker for the live position pin.
  amap_map.BitmapDescriptor? _meIcon;

  bool get _hasModule => widget.selectedBike.traxSerialNumber != null;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _svc.addListener(_onServiceUpdate);
    _initLocation();
    _warmMeIcon();
  }

  Future<void> _warmMeIcon() async {
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
    if (mounted) setState(() => _meIcon = icon);
  }

  void _onServiceUpdate() {
    if (!mounted) return;
    setState(() {});
    if (_mapReady &&
        _mapController != null &&
        _svc.rideStatus != 'idle' &&
        !_isPicking) {
      _mapController!.moveCamera(
        amap_map.CameraUpdate.newLatLng(AmapAdapter.toAmap(_svc.currentPos)),
      );
    }
  }

  Future<void> _initLocation() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      _svc.currentPos = LatLng(pos.latitude, pos.longitude);
      setState(() {});
      _animateToCurrentPos();
    } catch (_) {}
  }

  void _animateToCurrentPos() {
    if (_mapReady && _mapController != null) {
      _mapController!.moveCamera(
        amap_map.CameraUpdate.newLatLng(AmapAdapter.toAmap(_svc.currentPos)),
      );
    }
  }

  @override
  void dispose() {
    _svc.removeListener(_onServiceUpdate);
    WakelockPlus.disable();
    super.dispose();
  }

  static const double _bottomPanelHeight = 240.0;

  double get _mapCenterY {
    final screenH = MediaQuery.of(context).size.height;
    return (screenH - _bottomPanelHeight) / 2;
  }

  Future<void> _onPickLocationTap() async {
    if (_isPicking) {
      final amapCenter = _cameraCenter;
      if (amapCenter == null) return;
      final wgs = AmapAdapter.fromAmap(amapCenter);
      setState(() {
        _isPicking = false;
        _pickedLocation = wgs;
        _svc.currentPos = wgs;
      });
      _mapController?.moveCamera(amap_map.CameraUpdate.newLatLng(amapCenter));
    } else {
      setState(() {
        _isPicking = true;
        _pickedLocation = null;
      });
    }
  }

  void _clearPickedLocation() {
    setState(() {
      _pickedLocation = null;
      _isPicking = false;
    });
    _initLocation();
  }

  Future<void> _onStart() async {
    final ok = await _svc.startRide(widget.selectedBike);
    if (!mounted || !ok) return;
    setState(() {
      _pickedLocation = null;
      _isPicking = false;
    });
  }

  Future<void> _onPause() async => await _svc.pauseRide();
  Future<void> _onResume() async => await _svc.resumeRide();

  Future<void> _onStop() async {
    TraxDialog.showBottomTipsDialog(
      title: 'End Ride?',
      content: 'Your ride will be saved.',
      mainBtnText: 'End Ride',
      mainBtnOnPressed: () async {
        Get.back();
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
        Get.back();
        final resp = await TraxApi.deleteRide(rideId);
        if (!mounted) return;
        if (resp.isSuccess()) {
          _svc.clearCompleted();
          showTraxSnackBar(context, 'Ride deleted');
          Navigator.pop(context);
        } else {
          showTraxSnackBar(context, resp.message ?? 'Failed to delete ride',
              isError: true);
        }
      },
      subBtnText: 'Cancel',
    );
  }

  @override
  Widget build(BuildContext context) =>
      PageCodeBadge(code: '401A', child: _buildContent(context));

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
          amap_map.AMapWidget(
            privacyStatement: AmapAdapter.privacy(),
            apiKey: AmapAdapter.apiKey(),
            initialCameraPosition: amap_map.CameraPosition(
              target: AmapAdapter.toAmap(currentPos),
              zoom: 16,
            ),
            polylines: {
              if (route.length >= 2) AmapAdapter.routePolyline(route),
            },
            markers: {
              if (rideStatus == 'idle' &&
                  _pickedLocation != null &&
                  !_isPicking)
                amap_map.Marker(
                  position: AmapAdapter.toAmap(_pickedLocation!),
                  icon: amap_map.BitmapDescriptor.defaultMarker,
                ),
              if (rideStatus != 'idle' && route.isNotEmpty)
                amap_map.Marker(
                  position: AmapAdapter.toAmap(currentPos),
                  icon: _meIcon ?? amap_map.BitmapDescriptor.defaultMarker,
                  anchor: const Offset(0.5, 0.5),
                ),
            },
            scrollGesturesEnabled: true,
            zoomGesturesEnabled: true,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
            },
            onMapCreated: (c) {
              _mapController = c;
              setState(() => _mapReady = true);
              _animateToCurrentPos();
            },
            onCameraMove: (pos) => _cameraCenter = pos.target,
            onCameraMoveEnd: (pos) => _cameraCenter = pos.target,
          ),
          if (_isPicking)
            Positioned(
              left: 0,
              right: 0,
              top: _mapCenterY - 20,
              child: const IgnorePointer(
                child: Center(
                  child: Icon(Icons.add, size: 40, color: AppColors.error),
                ),
              ),
            ),
          Positioned(
            top: safeTop + 8,
            left: 16,
            child: CircleAvatar(
              backgroundColor: AppColors.surface,
              child: IconButton(
                icon: const Icon(Icons.arrow_back,
                    color: AppColors.textPrimary, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          if (rideStatus == 'idle')
            Positioned(
              top: safeTop + 8,
              left: 72,
              child: CircleAvatar(
                backgroundColor:
                    _isPicking ? AppColors.primary : AppColors.surface,
                child: IconButton(
                  icon: Icon(
                    _isPicking ? Icons.check : Icons.pin_drop,
                    color: _isPicking ? Colors.white : AppColors.textPrimary,
                    size: 20,
                  ),
                  onPressed: _onPickLocationTap,
                  tooltip: _isPicking ? 'Confirm Location' : 'Pick Location',
                ),
              ),
            ),
          if (_isPicking)
            Positioned(
              top: safeTop + 8,
              left: 120,
              right: 60,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8),
                  ],
                ),
                child: const Text(
                  'Move map, then tap ✓ to confirm',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          if (rideStatus == 'idle' && _pickedLocation != null && !_isPicking)
            Positioned(
              top: safeTop + 8,
              left: 120,
              right: 60,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pin_drop,
                        size: 16, color: AppColors.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${_pickedLocation!.latitude.toStringAsFixed(5)}, ${_pickedLocation!.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: _clearPickedLocation,
                      child: const Icon(Icons.close,
                          size: 16, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          if (!_isPicking && _pickedLocation == null)
            Positioned(
              top: safeTop + 8,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _GpsInfoChip(position: currentPos),
                  if (_hasModule && telemetry != null) ...[
                    const SizedBox(height: 8),
                    _ModuleInfoChip(telemetry: telemetry),
                  ],
                ],
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomPanel(
                rideStatus, stats, displayDuration, route.length),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(String rideStatus, dynamic stats,
      int displayDuration, int pointCount) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _StatTile('Duration', _formatDuration(displayDuration)),
              _StatTile('Distance',
                  '${(stats?.distanceKm ?? 0).toStringAsFixed(2)} km'),
              _StatTile('Avg Speed',
                  '${(stats?.avgSpeedKmh ?? 0).toStringAsFixed(1)} km/h'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatTile('Max Speed',
                  '${(stats?.maxSpeedKmh ?? 0).toStringAsFixed(1)} km/h'),
              _StatTile('Elevation',
                  '${(stats?.elevationMeters ?? 0).toStringAsFixed(0)} m'),
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
            label: const Text('Start Ride',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28)),
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
                  label: const Text('Pause',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side:
                        const BorderSide(color: AppColors.primary, width: 2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26)),
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
                child:
                    const Icon(Icons.stop, color: Colors.white, size: 24),
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
                  label: const Text('Resume',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26)),
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
                child:
                    const Icon(Icons.stop, color: Colors.white, size: 24),
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
                    MapRouter.openRideSummary(context,
                        rideId: rideId, replace: true);
                  } else {
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.check, size: 24),
                label: const Text('View Summary',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28)),
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
                label: const Text('Delete Ride',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error, width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
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

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

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
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.gps_fixed, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

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
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
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
            color: telemetry.batteryPercent > 20
                ? AppColors.success
                : AppColors.error,
          ),
          const SizedBox(width: 4),
          Text('${telemetry.batteryPercent}%',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(width: 10),
          Icon(Icons.signal_cellular_alt,
              size: 16,
              color: bars >= 3
                  ? AppColors.success
                  : bars >= 2
                      ? AppColors.primary
                      : AppColors.error),
          const SizedBox(width: 2),
          Text('$bars/4',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
