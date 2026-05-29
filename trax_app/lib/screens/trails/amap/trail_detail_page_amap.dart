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
import '../../../common/utils/cp_marker_icons_amap.dart';
import '../../../common/utils/polyline_chaser.dart';
import '../../../common/utils/trax_storage_util.dart';
import '../../../common/widgets/trax_dialog.dart';
import '../../../models/ebike.dart';
import '../../../models/trail.dart';
import '../../../models/user_checkpoint.dart';
import '../../../theme/app_theme.dart';
import '../../../common/widgets/map_router.dart';
import '../../ride/host_laps_page.dart';
import '../../ride/host_race_page.dart';

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

  /// Per-user checkpoints loaded from the backend (WGS-84; converted to
  /// GCJ-02 when rendered on AMap).
  List<UserCheckpoint> _checkpoints = const [];

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
    _loadCheckpoints();
    if (_locationName == null || _locationName!.isEmpty) {
      _fetchLocationName();
    }
  }

  Future<void> _loadCheckpoints() async {
    final id = int.tryParse(trail.id ?? '');
    if (id == null) return;
    final resp = await TraxApi.getTrailCheckpoints(id);
    if (!mounted) return;
    if (resp.isSuccess() && resp.data is List) {
      final cps = (resp.data as List)
          .map((e) => UserCheckpoint.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.sequenceIndex.compareTo(b.sequenceIndex));
      setState(() => _checkpoints = cps);
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
              height: 180,
              width: double.infinity,
              child: _buildMap(isLap),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    12, 12, 12, 12 + MediaQuery.of(context).padding.bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderStrip(),
                    const SizedBox(height: 10),
                    _buildStatsStrip(),
                    const SizedBox(height: 10),
                    _buildLocationStrip(),
                    const SizedBox(height: 10),
                    _buildCheckpointsStrip(),
                    if (isLap) ...[
                      const SizedBox(height: 12),
                      _buildLapActionButtons(),
                    ],
                    if (_isOwner) ...[
                      const SizedBox(height: 10),
                      _buildVisibilityStrip(),
                    ],
                    SizedBox(
                        height: MediaQuery.of(context).padding.bottom + 8),
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
            width: 4, color: AppColors.primary.withValues(alpha: 0.9)),
      },
      markers: {
        ...AmapAdapter.startFinishMarkers(_route),
        ...CpMarkerIconsAmap.buildMarkers(
          context,
          {
            for (final cp in _checkpoints)
              cp.sequenceIndex: LatLng(cp.latitude, cp.longitude),
          },
          onWarmed: () { if (mounted) setState(() {}); },
        ),
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

  Widget _buildCheckpointsCard() {
    final id = int.tryParse(trail.id ?? '');
    if (id == null) return const SizedBox.shrink();
    final count = _checkpoints.length;
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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.flag, color: AppColors.warning, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('My Checkpoints',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text('$count / 4 placed along this trail',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              await MapRouter.openTrailCheckpoints(
                context,
                trailId: id,
                trailName: trail.name,
                trailStartLat: trail.startLatitude,
                trailStartLng: trail.startLongitude,
              );
              if (!mounted) return;
              await _loadCheckpoints();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: Text(count == 0 ? 'Configure' : 'Edit'),
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

  /// Three independent entry points for a lap-type trail. The user
  /// asked for them to be visually equal (no primary/secondary).
  Widget _buildLapActionButtons() {
    return Row(
      children: [
        Expanded(child: _lapActionBtn(
          icon: Icons.timer,
          label: 'Lap Timer',
          onTap: _startLapTimer,
        )),
        const SizedBox(width: 8),
        Expanded(child: _lapActionBtn(
          icon: Icons.groups_outlined,
          label: 'Host Laps',
          onTap: _onHostLaps,
        )),
        const SizedBox(width: 8),
        Expanded(child: _lapActionBtn(
          icon: Icons.emoji_events_outlined,
          label: 'Host Race',
          onTap: _onHostRace,
        )),
      ],
    );
  }

  Widget _lapActionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 64,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onHostLaps() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HostLapsPage(initialTrail: trail)),
    );
  }

  Future<void> _onHostRace() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HostRacePage(initialTrail: trail)),
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
  // ───── Compact one-screen strips (mirror Google variant) ─────────

  Widget _buildHeaderStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: _stripDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.terrain, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  trail.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
              ),
              _miniChip(
                label: _isOwner ? 'Owner' : 'Guest',
                color: _isOwner ? AppColors.primary : AppColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(_typeIcon(), size: 13, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(_typeLabel(),
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(width: 10),
              _miniChip(label: _difficultyLabel(), color: _difficultyColor()),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isOwner
                      ? 'Created by you'
                      : 'by ${trail.creatorName ?? "unknown"}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: _stripDecoration(),
      child: Row(
        children: [
          _miniStat(Icons.straighten, 'Distance',
              '${(trail.distance ?? 0).toStringAsFixed(2)} km'),
          _miniStat(Icons.trending_up, 'Elev',
              '${(trail.elevation ?? 0).toStringAsFixed(0)} m'),
          _miniStat(Icons.swap_vert, 'Elev Δ',
              trail.elevationDiff != null
                  ? '${trail.elevationDiff!.toStringAsFixed(0)} m'
                  : '—'),
          _miniStat(Icons.pin_drop, 'Points', '${_route.length}'),
        ],
      ),
    );
  }

  Widget _miniStat(IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          Text(label,
              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildLocationStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: _stripDecoration(),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _locationName ?? 'Loading…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckpointsStrip() {
    final id = int.tryParse(trail.id ?? '');
    if (id == null) return const SizedBox.shrink();
    final count = _checkpoints.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: _stripDecoration(),
      child: Row(
        children: [
          const Icon(Icons.flag, color: AppColors.warning, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'My Checkpoints  ·  $count / 4',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
          ),
          TextButton(
            onPressed: () async {
              await MapRouter.openTrailCheckpoints(
                context,
                trailId: id,
                trailName: trail.name,
                trailStartLat: trail.startLatitude,
                trailStartLng: trail.startLongitude,
              );
              if (!mounted) return;
              await _loadCheckpoints();
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            child: Text(count == 0 ? 'Configure' : 'Edit'),
          ),
        ],
      ),
    );
  }

  Widget _buildVisibilityStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: _stripDecoration(),
      child: Row(
        children: [
          Icon(
            _isPublic ? Icons.public : Icons.lock_outline,
            color: _isPublic ? AppColors.primary : AppColors.textSecondary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isPublic
                  ? 'Public · Anyone can search this trail'
                  : 'Private · Only you can see this trail',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500),
            ),
          ),
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: _isPublic,
              onChanged: _toggleVisibility,
              activeColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _stripDecoration() => BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      );

  Widget _miniChip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }}

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
