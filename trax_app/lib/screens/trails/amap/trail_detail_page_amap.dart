import 'dart:async';

import 'package:amap_flutter_base/amap_flutter_base.dart' as amap;
import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:intl/intl.dart';

import '../../../common/global/global_user_info.dart';
import '../../../common/network/trax_api.dart';
import '../../../common/services/map_service.dart';
import '../../../common/utils/amap_adapter.dart';
import '../../../common/utils/chaser_dot_icon.dart';
import '../../../common/utils/polyline_chaser.dart';
import '../../../common/utils/trax_storage_util.dart';
import '../../../common/widgets/trax_dialog.dart';
import '../../../models/ebike.dart';
import '../../../models/trail.dart';
import '../../../theme/app_theme.dart';
import '../../../common/widgets/map_router.dart';

/// AMap variant of [TrailDetailPage] used when the trail's start point falls
/// inside Chinese mainland.
///
/// Behavioural parity goals with the Google variant:
///   * Same Sliver-driven layout (map header + info / location / stats).
///   * Same back-button + delete + visibility-toggle interactions.
///   * Same "Start Lap Timer" CTA for lap trails.
///   * Reverse-geocode via [MapService.reverseGeocode] (which already routes
///     to the AMap REST endpoint when the user is in China).
///
/// Phase 1 implementation: the map header is rendered as a **static AMap
/// image** (via [MapService.staticMapUrl]) which already does WGS-84 →
/// GCJ-02 conversion and uses the AMap key. The route polyline is overlaid
/// in PNG form by AMap's `staticmap` endpoint so users see the correct
/// alignment over Chinese road tiles.
///
/// Phase 2 will replace this with the native `AMapWidget` from
/// `amap_flutter_map` once an AMap Android/iOS SDK Key is provisioned.
class TrailDetailPageAmap extends StatefulWidget {
  final Trail trail;
  const TrailDetailPageAmap({super.key, required this.trail});

  @override
  State<TrailDetailPageAmap> createState() => _TrailDetailPageAmapState();
}

class _TrailDetailPageAmapState extends State<TrailDetailPageAmap> {
  List<LatLng> _route = [];
  bool _isLoading = true;
  String? _locationName;
  late bool _isPublic;
  bool _changed = false;

  AMapController? _mapController;

  // Direction-of-travel hint: a small blue dot slides along the route
  // on a repeating timer.
  PolylineChaser? _chaser;
  BitmapDescriptor? _chaserDot;
  Timer? _chaserTimer;
  double _chaserPhase = 0;

  Trail get trail => widget.trail;
  bool get _isOwner => trail.creatorId == GlobalUserInfo.instance.id.value;

  @override
  void initState() {
    super.initState();
    _isPublic = trail.isPublic;
    _locationName = trail.location;
    _loadChaserDot();
    _loadPoints();
  }

  @override
  void dispose() {
    _chaserTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadChaserDot() async {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final dpr = views.isNotEmpty ? views.first.devicePixelRatio : 3.0;
    final bytes = await ChaserDotIcon.bytes(dpr);
    if (!mounted) return;
    setState(() => _chaserDot = BitmapDescriptor.fromBytes(bytes));
  }

  void _startChaser() {
    _chaserTimer?.cancel();
    if (_route.length < 3) return;
    _chaser = PolylineChaser(_route);
    _chaserTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      setState(() => _chaserPhase = (_chaserPhase + 0.00222) % 1.0);
    });
  }

  /// Frame the whole route in the 240 px-tall map header so a long
  /// trail isn't shown as a tiny squiggle next to the centre pin.
  void _fitRouteBounds() {
    final ctrl = _mapController;
    if (ctrl == null || _route.isEmpty) return;
    final amapPts = AmapAdapter.toAmapList(_route);
    if (amapPts.length == 1) {
      ctrl.moveCamera(CameraUpdate.newLatLngZoom(amapPts.first, 16));
      return;
    }
    double minLat = amapPts.first.latitude, maxLat = amapPts.first.latitude;
    double minLng = amapPts.first.longitude, maxLng = amapPts.first.longitude;
    for (final p in amapPts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    ctrl.moveCamera(
      CameraUpdate.newLatLngBounds(
        amap.LatLngBounds(
          southwest: amap.LatLng(minLat, minLng),
          northeast: amap.LatLng(maxLat, maxLng),
        ),
        40,
      ),
    );
  }

  Future<void> _loadPoints() async {
    final id = int.tryParse(trail.id ?? '');
    if (id == null) {
      setState(() => _isLoading = false);
      return;
    }
    final resp = await TraxApi.getTrailPoints(id);
    if (!mounted) return;
    List<LatLng> route = [];
    if (resp.isSuccess() && resp.data is List) {
      route = (resp.data as List).map((p) {
        final m = p as Map<String, dynamic>;
        return LatLng(
          (m['latitude'] as num).toDouble(),
          (m['longitude'] as num).toDouble(),
        );
      }).toList();
    }
    setState(() {
      _route = route;
      _isLoading = false;
    });
    _startChaser();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitRouteBounds());
    if (_locationName == null || _locationName!.isEmpty) {
      _fetchLocationName();
    }
  }

  Future<void> _fetchLocationName() async {
    final lat = trail.startLatitude ??
        (_route.isNotEmpty ? _route.first.latitude : null);
    final lng = trail.startLongitude ??
        (_route.isNotEmpty ? _route.first.longitude : null);
    if (lat == null || lng == null) return;
    final address = await MapService.reverseGeocode(lat, lng);
    if (address != null) {
      if (mounted) setState(() => _locationName = address);
      return;
    }
    if (mounted) {
      setState(() => _locationName =
          '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}');
    }
  }

  Future<void> _toggleVisibility(bool value) async {
    final id = int.tryParse(trail.id ?? '');
    if (id == null) return;
    setState(() => _isPublic = value);
    final resp = await TraxApi.updateTrailVisibility(id, value);
    if (!mounted) return;
    if (!resp.isSuccess()) {
      setState(() => _isPublic = !value);
      showTraxSnackBar(context, resp.message ?? 'Failed to update',
          isError: true);
    } else {
      _changed = true;
    }
  }

  void _confirmDelete() {
    final id = int.tryParse(trail.id ?? '');
    if (id == null) return;
    TraxDialog.showBottomTipsDialog(
      title: 'Delete Trail',
      content: 'This trail will be permanently removed.',
      mainBtnText: 'Delete',
      mainBtnOnPressed: () async {
        Navigator.of(context).pop();
        final resp = await TraxApi.deleteTrail(id);
        if (!mounted) return;
        if (resp.isSuccess()) {
          _changed = true;
          Navigator.of(context).pop(_changed);
        } else {
          showTraxSnackBar(
              context, resp.message ?? 'Failed to delete trail',
              isError: true);
        }
      },
      subBtnText: 'Cancel',
    );
  }

  Color _difficultyColor() {
    switch (trail.difficulty.toLowerCase()) {
      case 'easy':
        return AppColors.success;
      case 'medium':
        return AppColors.primary;
      case 'hard':
        return Colors.orange;
      case 'extreme':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  String _difficultyLabel() {
    final d = trail.difficulty;
    if (d.isEmpty) return 'Medium';
    return d[0].toUpperCase() + d.substring(1);
  }

  String _typeLabel() => trail.type == 'lap' ? 'Lap' : 'Free Ride';
  IconData _typeIcon() => trail.type == 'lap' ? Icons.loop : Icons.explore;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(),
        body: const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    final isLap = trail.type == 'lap';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
          actions: [
            if (_isOwner)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                onPressed: _confirmDelete,
              ),
          ],
        ),
        body: Column(
          children: [
            SizedBox(
              height: 240,
              width: double.infinity,
              child: _buildMap(isLap),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTrailInfo(),
                    const SizedBox(height: 16),
                    _buildLocationInfo(),
                    if (_isOwner) ...[
                      const SizedBox(height: 16),
                      _buildVisibilityToggle(),
                    ],
                    if (isLap) ...[
                      const SizedBox(height: 16),
                      _buildStartLapTimerButton(),
                    ],
                    const SizedBox(height: 16),
                    _buildStatsGrid(),
                    SizedBox(
                        height: MediaQuery.of(context).padding.bottom + 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Map (native AMapWidget — Phase 3) ──
  Widget _buildMap(bool isLap) {
    if (_route.isEmpty) {
      return Container(
        color: AppColors.background,
        child: const Center(
          child: Icon(Icons.map_outlined,
              size: 64, color: AppColors.textSecondary),
        ),
      );
    }
    return AMapWidget(
      privacyStatement: AmapAdapter.privacy(),
      apiKey: AmapAdapter.apiKey(),
      initialCameraPosition: AmapAdapter.initialCamera(_route, zoom: 14),
      polylines: {
        AmapAdapter.routePolyline(_route,
            width: 2, color: AppColors.primary.withValues(alpha: 0.9)),
      },
      markers: {
        ...AmapAdapter.startFinishMarkers(_route),
        if (_chaserDot != null && (_chaser?.canRender ?? false))
          Marker(
            position: AmapAdapter.toAmap(_chaser!.headAt(_chaserPhase)),
            icon: _chaserDot!,
            anchor: const Offset(0.5, 0.5),
            zIndex: 6,
          ),
      },
      scrollGesturesEnabled: true,
      zoomGesturesEnabled: true,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      // The map sits inside a CustomScrollView's SliverAppBar; without
      // claiming the gestures explicitly the outer scroll view wins all
      // vertical pans and pinches. Hand horizontal+vertical drags and
      // pinch to the map's native view.
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
      },
      onMapCreated: (c) {
        _mapController = c;
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _fitRouteBounds());
      },
    );
  }

  // ── Info / Location / Toggle / Stats — visually identical to Google variant.

  Widget _buildTrailInfo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _difficultyColor().withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_typeIcon(), color: _difficultyColor(), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trail.name,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Row(children: [
                  _Pill(label: _typeLabel(), color: AppColors.primary),
                  const SizedBox(width: 6),
                  _Pill(
                      label: _difficultyLabel(), color: _difficultyColor()),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationInfo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_outlined,
              color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _locationName ?? 'Loading…',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisibilityToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.public, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Make public',
                style:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          Switch(
            value: _isPublic,
            activeColor: AppColors.primary,
            onChanged: _toggleVisibility,
          ),
        ],
      ),
    );
  }

  Widget _buildStartLapTimerButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _startLapTimer,
        icon: const Icon(Icons.timer_outlined),
        label: const Text('Start Lap Timer'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Future<void> _startLapTimer() async {
    // Pick the currently-selected bike (same logic as Google variant).
    final selectedBikeId = TraxStorageUtil.getSelectedBikeId();
    EBike? selected;
    if (selectedBikeId != null) {
      final resp = await TraxApi.getBike(selectedBikeId.toString());
      if (resp.isSuccess() && resp.data is Map) {
        selected = EBike.fromJson(resp.data as Map<String, dynamic>);
      }
    }
    if (!mounted || selected == null) return;
    final start = trail.startLatitude != null && trail.startLongitude != null
        ? LatLng(trail.startLatitude!, trail.startLongitude!)
        : null;
    await MapRouter.openLapTimer(
      context,
      selectedBike: selected,
      trail: trail,
      targetLaps: 3,
      startLocation: start,
    );
  }

  Widget _buildStatsGrid() {
    final distance = trail.distance ?? 0;
    final elevation = trail.elevation ?? 0;
    final elevDiff = trail.elevationDiff;
    final created = trail.createdAt;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.6,
      children: [
        _StatTile(
            icon: Icons.straighten,
            label: 'Distance',
            value: '${distance.toStringAsFixed(2)} km'),
        _StatTile(
            icon: Icons.height,
            label: 'Elevation',
            value: '${elevation.toStringAsFixed(0)} m'),
        _StatTile(
            icon: Icons.swap_vert,
            label: 'Elevation Diff',
            value: elevDiff != null
                ? '${elevDiff.toStringAsFixed(0)} m'
                : '\u2014'),
        _StatTile(
            icon: Icons.event,
            label: 'Created',
            value: created != null
                ? DateFormat('yyyy-MM-dd').format(created)
                : '\u2014'),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
