import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../common/services/map_service.dart';
import '../../common/utils/chaser_dot_icon.dart';
import '../../common/utils/polyline_chaser.dart';
import '../../common/utils/start_end_marker_icons.dart';
import 'package:intl/intl.dart';
import '../../models/trail.dart';
import '../../models/ebike.dart';
import '../../common/network/trax_api.dart';
import '../../common/global/global_user_info.dart';
import '../../common/utils/trax_storage_util.dart';
import '../../common/utils/map_gesture_recognizers.dart';
import '../../common/widgets/trax_dialog.dart';
import '../../theme/app_theme.dart';
import '../../common/widgets/map_router.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class TrailDetailPage extends StatefulWidget {
  final Trail trail;
  const TrailDetailPage({super.key, required this.trail});

  @override
  State<TrailDetailPage> createState() => _TrailDetailPageState();
}

class _TrailDetailPageState extends State<TrailDetailPage> {
  List<LatLng> _route = [];
  bool _isLoading = true;
  String? _locationName;
  late bool _isPublic;
  bool _changed = false;

  GoogleMapController? _mapController;

  // Direction-of-travel hint: a small blue dot slides along the route
  // on a repeating timer, similar to an indeterminate progress bar.
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
    // Use stored location first, geocode as fallback
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
    final icon = await ChaserDotIcon.bitmap(dpr);
    if (!mounted) return;
    setState(() => _chaserDot = icon);
  }

  void _startChaser() {
    _chaserTimer?.cancel();
    if (_route.length < 3) return;
    _chaser = PolylineChaser(_route);
    // ~20fps, full loop every ~22.5s.
    _chaserTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      setState(() => _chaserPhase = (_chaserPhase + 0.00222) % 1.0);
    });
  }

  /// Frame the whole route in the 240 px-tall map header so a long
  /// trail isn't shown as a tiny squiggle next to the centre pin. Runs
  /// once the map controller is available and the route has loaded.
  void _fitRouteBounds() {
    final ctrl = _mapController;
    if (ctrl == null || _route.isEmpty) return;
    if (_route.length == 1) {
      ctrl.animateCamera(CameraUpdate.newLatLngZoom(_route.first, 16));
      return;
    }
    double minLat = _route.first.latitude, maxLat = _route.first.latitude;
    double minLng = _route.first.longitude, maxLng = _route.first.longitude;
    for (final p in _route) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    ctrl.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
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

    // Only geocode if location not already stored in DB
    if (_locationName == null || _locationName!.isEmpty) {
      _fetchLocationName();
    }
  }

  Future<void> _fetchLocationName() async {
    final lat = trail.startLatitude ?? (_route.isNotEmpty ? _route.first.latitude : null);
    final lng = trail.startLongitude ?? (_route.isNotEmpty ? _route.first.longitude : null);
    if (lat == null || lng == null) return;

    final address = await MapService.reverseGeocode(lat, lng);
    if (address != null) {
      if (mounted) setState(() => _locationName = address);
      return;
    }
    // Fallback: show coordinates so the UI doesn't stay stuck on "Loading..."
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
      setState(() => _isPublic = !value); // revert on failure
      showTraxSnackBar(context, resp.message ?? 'Failed to update', isError: true);
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
        Navigator.of(context).pop(); // dismiss dialog
        final resp = await TraxApi.deleteTrail(id);
        if (!mounted) return;
        if (resp.isSuccess()) {
          _changed = true;
          Navigator.of(context).pop(_changed);
        } else {
          showTraxSnackBar(context, resp.message ?? 'Failed to delete trail', isError: true);
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

  String _typeLabel() {
    return trail.type == 'lap' ? 'Lap' : 'Free Ride';
  }

  IconData _typeIcon() {
    return trail.type == 'lap' ? Icons.loop : Icons.explore;
  }

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '601', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
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
          // Fixed-height map header — using a SliverAppBar/FlexibleSpaceBar
          // here would let the surrounding scroll view steal the map's
          // pan/pinch gestures.
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
                        polylineId: const PolylineId('trail'),
                        points: _route,
                        color: AppColors.primary.withValues(alpha: 0.9),
                        width: 2,
                      ),
                    },
                    markers: {
                      Marker(
                        markerId: const MarkerId('start'),
                        position: _route.first,
                        icon: StartEndMarkerIcons.start,
                      ),
                      if (!isLap && _route.length > 1)
                        Marker(
                          markerId: const MarkerId('end'),
                          position: _route.last,
                          icon: StartEndMarkerIcons.finish,
                        ),
                      if (_chaserDot != null && (_chaser?.canRender ?? false))
                        Marker(
                          markerId: const MarkerId('trail_chaser'),
                          position: _chaser!.headAt(_chaserPhase),
                          icon: _chaserDot!,
                          anchor: const Offset(0.5, 0.5),
                          flat: true,
                          zIndex: 6,
                        ),
                    },
                    myLocationEnabled: false,
                    zoomControlsEnabled: false,
                    gestureRecognizers: kMapGestureRecognizers,
                    onMapCreated: (c) {
                      _mapController = c;
                      // Trail points may already be loaded by the time the
                      // GoogleMap is ready; fit now so the whole route is
                      // framed inside the 240 px header instead of being
                      // shown at the initial fixed zoom-14.
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => _fitRouteBounds());
                    },
                  )
                : Container(
                    color: AppColors.background,
                    child: const Center(
                      child: Icon(Icons.map_outlined, size: 64, color: AppColors.textSecondary),
                    ),
                  ),
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
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildTrailInfo() {
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
            child: const Icon(Icons.terrain, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trail.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(_typeIcon(), size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(_typeLabel(), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _difficultyColor().withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _difficultyLabel(),
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _difficultyColor()),
                      ),
                    ),
                  ],
                ),
                if (trail.createdAt != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        'Created ${DateFormat('MMM d, yyyy').format(trail.createdAt!)}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(_isOwner ? Icons.person : Icons.person_outline,
                        size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _isOwner
                            ? 'Created by you'
                            : 'Created by ${trail.creatorName ?? "unknown"}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: (_isOwner ? AppColors.primary : AppColors.textSecondary)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _isOwner ? 'Owner' : 'Guest',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _isOwner ? AppColors.primary : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
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
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.location_on, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Location', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(
                  _locationName ?? 'Loading...',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisibilityToggle() {
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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (_isPublic ? AppColors.primary : AppColors.textSecondary)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _isPublic ? Icons.public : Icons.lock_outline,
              color: _isPublic ? AppColors.primary : AppColors.textSecondary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isPublic ? 'Public' : 'Private',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  _isPublic
                      ? 'Anyone can search and use this trail'
                      : 'Only you can see and use this trail',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Switch(
            value: _isPublic,
            onChanged: _toggleVisibility,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildStartLapTimerButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _onStartLapTimer,
        icon: const Icon(Icons.timer, size: 22),
        label: const Text(
          'Start Lap Timer',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        ),
      ),
    );
  }

  Future<void> _onStartLapTimer() async {
    final bikesResp = await TraxApi.getUserBikes();
    if (!mounted) return;
    if (!bikesResp.isSuccess() || bikesResp.data is! List) {
      showTraxSnackBar(context, 'Could not load your bikes', isError: true);
      return;
    }
    final bikes = (bikesResp.data as List)
        .map((e) => EBike.fromJson(e as Map<String, dynamic>))
        .toList();
    if (bikes.isEmpty) {
      showTraxSnackBar(context, 'Add a bike in Garage first', isError: true);
      return;
    }

    // Let user pick a bike
    final bike = await _showBikePickerDialog(bikes);
    if (bike == null || !mounted) return;

    final targetLaps = await _showLapCountDialog();
    if (targetLaps == null || targetLaps <= 0) return;
    if (!mounted) return;

    MapRouter.openLapTimer(
      context,
      selectedBike: bike,
      trail: trail,
      targetLaps: targetLaps,
    );
  }

  Future<EBike?> _showBikePickerDialog(List<EBike> bikes) {
    // Pre-select: prefer saved bike, else first connected module bike
    final savedId = TraxStorageUtil.getSelectedBikeId();
    final defaultBike = bikes.firstWhere(
      (b) => b.id == savedId,
      orElse: () => bikes.firstWhere(
        (b) => b.traxSerialNumber != null && b.isConnected,
        orElse: () => bikes.first,
      ),
    );

    return showModalBottomSheet<EBike>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).padding.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Select Bike',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 12),
              ...bikes.map((b) {
                final hasModule = b.traxSerialNumber != null;
                final isDefault = b.id == defaultBike.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.of(ctx).pop(b),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isDefault ? AppColors.primary.withValues(alpha: 0.1) : AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDefault ? AppColors.primary : AppColors.textSecondary.withValues(alpha: 0.2),
                          width: isDefault ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.electric_bike,
                            color: hasModule ? AppColors.primary : AppColors.textSecondary,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.name,
                                  style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  hasModule
                                      ? 'TRAX Module: ${b.traxSerialNumber}${b.isConnected ? " · Connected" : ""}'
                                      : 'No TRAX Module (uses phone GPS)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: hasModule ? AppColors.primary : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (b.isConnected && hasModule)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Online',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Future<int?> _showLapCountDialog() async {
    int laps = 3;
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).padding.bottom + 20,
          ),
          child: StatefulBuilder(
            builder: (ctx, setS) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'How many laps?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Your ride will auto-finish after the target is reached.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _lapCountBtn(
                      icon: Icons.remove,
                      onPressed: laps > 1 ? () => setS(() => laps--) : null,
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 28),
                      width: 60,
                      alignment: Alignment.center,
                      child: Text(
                        '$laps',
                        style: const TextStyle(
                            fontSize: 40, fontWeight: FontWeight.w800, color: AppColors.primary),
                      ),
                    ),
                    _lapCountBtn(
                      icon: Icons.add,
                      onPressed: laps < 50 ? () => setS(() => laps++) : null,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [1, 3, 5, 10].map((n) {
                    final selected = laps == n;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: GestureDetector(
                        onTap: () => setS(() => laps = n),
                        child: Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: selected ? AppColors.primary : AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected ? AppColors.primary : AppColors.textSecondary.withValues(alpha: 0.3),
                              width: selected ? 2 : 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$n',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: selected ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(laps),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    ),
                    child: Text('Continue with $laps lap${laps == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _lapCountBtn({required IconData icon, VoidCallback? onPressed}) {
    final enabled = onPressed != null;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: enabled ? AppColors.primary : AppColors.background,
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled ? AppColors.primary : AppColors.textSecondary.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 24, color: enabled ? Colors.white : AppColors.textSecondary),
      ),
    );
  }

  Widget _buildStatsGrid() {
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
          const Text('Trail Info', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatItem(Icons.straighten, 'Distance', '${(trail.distance ?? 0).toStringAsFixed(2)} km'),
              _StatItem(Icons.trending_up, 'Elevation', '${(trail.elevation ?? 0).toStringAsFixed(0)} m'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatItem(
                  Icons.swap_vert,
                  'Elevation Diff',
                  trail.elevationDiff != null
                      ? '${trail.elevationDiff!.toStringAsFixed(0)} m'
                      : '\u2014'),
              _StatItem(_typeIcon(), 'Type', _typeLabel()),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatItem(Icons.pin_drop, 'Points', '${_route.length}'),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
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
