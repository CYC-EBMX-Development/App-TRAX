import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../../common/utils/map_gesture_recognizers.dart';
import '../../common/utils/start_end_marker_icons.dart';
import '../../common/utils/trail_thumbnail.dart';
import '../../common/network/trax_api.dart';
import '../../common/widgets/page_code_badge.dart';
import '../../models/ebike.dart';
import '../../models/trail.dart';
import '../../models/user_checkpoint.dart';
import '../../theme/app_theme.dart';
import 'lap_timer_page.dart';

/// Lap Timer Setup
///
/// Layout:
///   ┌──────────────────────────┐
///   │           MAP            │  ~ top 45%
///   │      (selected trail)    │
///   ├──────────────────────────┤
///   │  Selected Trail card     │  bottom panel (selected trail
///   │  Checkpoints (0/4) [Add] │   info + checkpoints + laps +
///   │  Target Laps  −  3  +    │   start session)
///   │  [ Start N-Lap Session ] │
///   └──────────────────────────┘
///
/// On first entry the trail selector bottom-sheet is automatically opened
/// (OK only — user must choose). Tapping the small "Change" button on the
/// trail card re-opens the same sheet with both Cancel and OK buttons.
///
/// Checkpoint placement uses a full-screen map with a centered drop pin
/// and a Cancel / "Add Checkpoint" action bar (max 4 per user-trail).
class LapTimerSetupPage extends StatefulWidget {
  final EBike selectedBike;
  const LapTimerSetupPage({super.key, required this.selectedBike});

  @override
  State<LapTimerSetupPage> createState() => _LapTimerSetupPageState();
}

class _LapTimerSetupPageState extends State<LapTimerSetupPage> {
  // ── Data ──────────────────────────────────────────────────
  List<Trail> _trails = [];
  bool _isLoadingTrails = true;
  Trail? _selectedTrail;
  int _targetLaps = 3;

  // Trail route preview
  List<LatLng> _trailRoute = [];
  bool _isLoadingRoute = false;
  int _trailPointCount = 0;

  // Map
  GoogleMapController? _mapController;
  bool _mapReady = false;
  LatLng? _userLocation;

  // Checkpoints
  List<UserCheckpoint> _checkpoints = [];
  bool _isPickingCheckpoint = false;
  bool _addingCheckpoint = false;

  // Custom start location picker
  bool _isPickingStart = false;
  LatLng? _pickedStart;

  // Cache of numbered checkpoint marker bitmaps, keyed by sequence index.
  final Map<int, BitmapDescriptor> _cpMarkerCache = {};

  bool _autoSelectorShown = false;

  // ── Lifecycle ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadTrails(), _fetchUserLocation()]);
    if (!mounted) return;
    // Auto-open the selector after first frame, only once.
    if (!_autoSelectorShown && _selectedTrail == null && _trails.isNotEmpty) {
      _autoSelectorShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openTrailSelector(initial: true);
      });
    }
  }

  Future<void> _loadTrails() async {
    final resp = await TraxApi.getTrails();
    if (!mounted) return;
    if (resp.isSuccess() && resp.data is List) {
      _trails = (resp.data as List)
          .map((e) => Trail.fromJson(e as Map<String, dynamic>))
          .where((t) => t.type == 'lap')
          .toList();
    }
    setState(() => _isLoadingTrails = false);
  }

  Future<void> _fetchUserLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      _userLocation = LatLng(pos.latitude, pos.longitude);
      if (_mapReady && _selectedTrail == null) {
        _mapController
            ?.animateCamera(CameraUpdate.newLatLngZoom(_userLocation!, 15));
      }
    } catch (_) {}
  }

  // ── Trail selection ───────────────────────────────────────
  Future<void> _openTrailSelector({required bool initial}) async {
    final picked = await showModalBottomSheet<Trail>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: !initial, // first time: must pick OK
      enableDrag: !initial,
      builder: (sheetCtx) => _TrailPickerSheet(
        trails: _trails,
        initialSelectedId: _selectedTrail?.id,
        showCancel: !initial,
      ),
    );
    if (!mounted) return;
    if (picked != null && picked.id != _selectedTrail?.id) {
      await _applySelectedTrail(picked);
    }
  }

  Future<void> _applySelectedTrail(Trail trail) async {
    setState(() {
      _selectedTrail = trail;
      _trailRoute = [];
      _trailPointCount = 0;
      _isLoadingRoute = true;
      _isPickingCheckpoint = false;
      _isPickingStart = false;
      _pickedStart = null;
      _checkpoints = [];
      _cpMarkerCache.clear();
    });

    final id = int.tryParse(trail.id ?? '');
    if (id == null) {
      setState(() => _isLoadingRoute = false);
      return;
    }

    // Load checkpoints in parallel.
    _loadCheckpoints(id);

    final resp = await TraxApi.getTrailPoints(id);
    if (!mounted) return;

    if (resp.isSuccess() && resp.data is List) {
      final pts = (resp.data as List).map((p) {
        final m = p as Map<String, dynamic>;
        return LatLng(
          (m['latitude'] as num).toDouble(),
          (m['longitude'] as num).toDouble(),
        );
      }).toList();
      setState(() {
        _trailRoute = pts;
        _trailPointCount = pts.length;
        _isLoadingRoute = false;
      });
      if (pts.isNotEmpty && _mapReady) _fitTrailBounds(pts);
    } else {
      setState(() => _isLoadingRoute = false);
    }
  }

  void _fitTrailBounds(List<LatLng> pts) {
    if (pts.isEmpty || _mapController == null) return;
    if (pts.length == 1) {
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 15));
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
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        50,
      ),
    );
  }

  // ── Checkpoints ───────────────────────────────────────────
  Future<void> _loadCheckpoints(int trailId) async {
    final resp = await TraxApi.getTrailCheckpoints(trailId);
    if (!mounted) return;
    if (resp.isSuccess() && resp.data is List) {
      setState(() {
        _checkpoints = (resp.data as List)
            .map((e) => UserCheckpoint.fromJson(e as Map<String, dynamic>))
            .toList();
      });
      _warmCpMarkers();
    }
  }

  Future<void> _warmCpMarkers() async {
    var changed = false;
    for (final cp in _checkpoints) {
      if (!_cpMarkerCache.containsKey(cp.sequenceIndex)) {
        _cpMarkerCache[cp.sequenceIndex] =
            await _buildNumberedMarker(cp.sequenceIndex);
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
  }

  Future<BitmapDescriptor> _buildNumberedMarker(int seq) async {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final r = 18.0 * dpr;
    final borderW = 3.0 * dpr;
    final size = (r + borderW) * 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
    final cx = size / 2;
    final cy = size / 2;
    // White outer ring
    canvas.drawCircle(
        Offset(cx, cy), r + borderW / 2, Paint()..color = Colors.white);
    // Primary fill
    canvas.drawCircle(
        Offset(cx, cy), r, Paint()..color = AppColors.primary);
    // Number
    final tp = TextPainter(
      text: TextSpan(
        text: '$seq',
        style: TextStyle(
          color: Colors.white,
          fontSize: 20 * dpr,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      byteData!.buffer.asUint8List(),
      width: size / dpr,
      height: size / dpr,
    );
  }

  BitmapDescriptor _cpIcon(int seq) {
    return _cpMarkerCache[seq] ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
  }

  void _enterCheckpointPickMode() {
    if (_selectedTrail == null) return;
    if (_checkpoints.length >= 4) {
      _toast('Max 4 checkpoints');
      return;
    }
    setState(() => _isPickingCheckpoint = true);
    // Re-fit so user sees the trail in the full-screen map.
    if (_trailRoute.isNotEmpty && _mapReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitTrailBounds(_trailRoute);
      });
    }
  }

  void _exitCheckpointPickMode() {
    setState(() => _isPickingCheckpoint = false);
    if (_trailRoute.isNotEmpty && _mapReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitTrailBounds(_trailRoute);
      });
    }
  }

  Future<void> _confirmCheckpointAtCenter() async {
    if (_selectedTrail == null || _mapController == null) return;
    final id = int.tryParse(_selectedTrail!.id ?? '');
    if (id == null) return;
    setState(() => _addingCheckpoint = true);
    try {
      final size = MediaQuery.of(context).size;
      final centerScreen = ScreenCoordinate(
        x: (size.width / 2).round(),
        y: ((size.height -
                    _checkpointBottomBarHeight() -
                    MediaQuery.of(context).padding.top) /
                2 +
            MediaQuery.of(context).padding.top).round(),
      );
      final center = await _mapController!.getLatLng(centerScreen);
      final resp = await TraxApi.addTrailCheckpoint(
          id, center.latitude, center.longitude);
      if (!mounted) return;
      if (resp.isSuccess() && resp.data is List) {
        setState(() {
          _checkpoints = (resp.data as List)
              .map((e) => UserCheckpoint.fromJson(e as Map<String, dynamic>))
              .toList();
        });
        _warmCpMarkers();
      } else {
        _toast(
            resp.message.isNotEmpty
                ? resp.message
                : 'Failed to add checkpoint',
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _addingCheckpoint = false);
    }
  }

  double _checkpointBottomBarHeight() =>
      120 + MediaQuery.of(context).padding.bottom;

  Future<void> _deleteCheckpoint(UserCheckpoint cp) async {
    final resp = await TraxApi.deleteTrailCheckpoint(cp.id);
    if (!mounted) return;
    if (resp.isSuccess() && resp.data is List) {
      setState(() {
        _checkpoints = (resp.data as List)
            .map((e) => UserCheckpoint.fromJson(e as Map<String, dynamic>))
            .toList();
      });
      _warmCpMarkers();
    } else {
      _toast(resp.message.isNotEmpty ? resp.message : 'Failed to delete',
          isError: true);
    }
  }

  // ── Start Location Picker ─────────────────────────────────
  void _enterStartPickMode() {
    if (_selectedTrail == null) return;
    setState(() => _isPickingStart = true);
  }

  Future<void> _confirmStartLocation() async {
    if (_mapController == null) return;
    final size = MediaQuery.of(context).size;
    final mapH = (size.height * 0.45).clamp(280.0, 460.0);
    final center = await _mapController!.getLatLng(
      ScreenCoordinate(
        x: (size.width / 2).round(),
        y: (mapH / 2).round(),
      ),
    );
    setState(() {
      _pickedStart = center;
      _isPickingStart = false;
    });
  }

  void _cancelStartPick() {
    setState(() => _isPickingStart = false);
  }

  // ── Start Session ─────────────────────────────────────────
  void _onStartSession() {
    if (_selectedTrail == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LapTimerPage(
          selectedBike: widget.selectedBike,
          trail: _selectedTrail!,
          targetLaps: _targetLaps,
          startLocation: _pickedStart,
          autoStart: true,
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────
  void _toast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.error : null,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) =>
      PageCodeBadge(code: '404', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isPickingCheckpoint
          ? _buildCheckpointPickView()
          : _buildMainView(),
    );
  }

  // ───────────────────────────────────────────────────────────
  // MAIN VIEW (Map top half + Bottom panel)
  // ───────────────────────────────────────────────────────────
  Widget _buildMainView() {
    final safeTop = MediaQuery.of(context).padding.top;
    final screenH = MediaQuery.of(context).size.height;
    final mapH = (screenH * 0.45).clamp(280.0, 460.0);

    LatLng mapCenter;
    if (_trailRoute.isNotEmpty) {
      mapCenter = _trailRoute[_trailRoute.length ~/ 2];
    } else if (_userLocation != null) {
      mapCenter = _userLocation!;
    } else {
      mapCenter = const LatLng(22.8956, 113.8739);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Map (top half)
        Positioned(
          top: 0, left: 0, right: 0,
          height: mapH,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: mapCenter, zoom: 15),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            gestureRecognizers: kMapGestureRecognizers,
            polylines: {
              if (_trailRoute.length >= 2)
                Polyline(
                  polylineId: const PolylineId('trail'),
                  points: _trailRoute,
                  color: AppColors.primary,
                  width: 4,
                ),
            },
            markers: {
              if (_trailRoute.isNotEmpty)
                Marker(
                  markerId: const MarkerId('start'),
                  position: _trailRoute.first,
                  icon: StartEndMarkerIcons.start,
                  infoWindow: const InfoWindow(title: 'Start / Finish'),
                ),
              for (final cp in _checkpoints)
                Marker(
                  markerId: MarkerId('cp_${cp.id}'),
                  position: LatLng(cp.latitude, cp.longitude),
                  icon: _cpIcon(cp.sequenceIndex),
                  anchor: const Offset(0.5, 0.5),
                  infoWindow:
                      InfoWindow(title: 'Checkpoint ${cp.sequenceIndex}'),
                ),
              if (_pickedStart != null)
                Marker(
                  markerId: const MarkerId('picked_start'),
                  position: _pickedStart!,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueRed),
                  infoWindow: const InfoWindow(title: 'Custom Start'),
                ),
            },
            onMapCreated: (c) {
              _mapController = c;
              _mapReady = true;
              if (_trailRoute.isNotEmpty) {
                _fitTrailBounds(_trailRoute);
              } else if (_userLocation != null) {
                c.animateCamera(
                    CameraUpdate.newLatLngZoom(_userLocation!, 15));
              }
            },
          ),
        ),

        if (_isLoadingRoute)
          Positioned(
            top: safeTop + 56, left: 0, right: 0,
            child: const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              ),
            ),
          ),

        // Bottom panel (hidden while picking start so the map is fully visible)
        if (!_isPickingStart)
          Positioned(
            left: 0, right: 0, top: mapH - 16, bottom: 0,
            child: _buildBottomPanel(),
          ),

        // Centered pin overlay while picking start (within top-half map)
        if (_isPickingStart)
          Positioned(
            left: 0, right: 0,
            top: mapH / 2 - 36,
            child: const IgnorePointer(
              child: Center(
                child: Icon(Icons.pin_drop,
                    size: 44, color: AppColors.error),
              ),
            ),
          ),

        // Picking hint banner (just above the bottom of the map)
        if (_isPickingStart)
          Positioned(
            left: 16, right: 16,
            top: mapH - 56,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.pin_drop,
                      size: 14, color: AppColors.error),
                  SizedBox(width: 6),
                  Text('Drag map, then tap ✓ to set start',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
          ),

        // Bottom action bar while picking start
        if (_isPickingStart)
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8, offset: Offset(0, -2)),
                ],
              ),
              padding: EdgeInsets.fromLTRB(16, 14, 16,
                  MediaQuery.of(context).padding.bottom + 14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _cancelStartPick,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: BorderSide(
                            color: AppColors.textSecondary
                                .withValues(alpha: 0.4)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _confirmStartLocation,
                      icon: const Icon(Icons.check,
                          size: 18, color: Colors.white),
                      label: const Text('Set Start',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Top bar
        Positioned(
          top: safeTop + 8, left: 12, right: 12,
          child: Row(
            children: [
              _circleBtn(
                  _isPickingStart ? Icons.close : Icons.arrow_back,
                  _isPickingStart
                      ? _cancelStartPick
                      : () => Navigator.of(context).pop()),
              const SizedBox(width: 8),
              // On-map pick-start toggle (free-ride style)
              if (_selectedTrail != null)
                Material(
                  color: _isPickingStart
                      ? AppColors.primary
                      : Colors.white,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _isPickingStart
                        ? _confirmStartLocation
                        : _enterStartPickMode,
                    child: SizedBox(
                      width: 40, height: 40,
                      child: Icon(
                        _isPickingStart ? Icons.check : Icons.pin_drop,
                        size: 20,
                        color: _isPickingStart
                            ? Colors.white
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              if (_selectedTrail != null) const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 6),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                          _isPickingStart
                              ? Icons.pin_drop
                              : Icons.timer,
                          size: 18,
                          color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                          _isPickingStart
                              ? 'Pick Start Location'
                              : 'Lap Timer Setup',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2)),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
          16, 14, 16, MediaQuery.of(context).padding.bottom + 12),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            if (_isLoadingTrails)
              const Center(
                  child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: AppColors.primary),
              ))
            else if (_selectedTrail == null)
              _buildPickPrompt()
            else ...[
              _buildSelectedTrailCard(_selectedTrail!),
              const SizedBox(height: 14),
              _buildCheckpointsSection(),
              const SizedBox(height: 14),
              _buildTargetLapsRow(),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _onStartSession,
                  icon: const Icon(Icons.play_arrow, size: 22),
                  label: Text('Start $_targetLaps-Lap Session',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPickPrompt() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            children: [
              Icon(Icons.explore_outlined,
                  size: 40, color: AppColors.textSecondary),
              SizedBox(height: 8),
              Text('No trail selected',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              SizedBox(height: 4),
              Text('Pick a lap trail to begin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _trails.isEmpty
                ? null
                : () => _openTrailSelector(initial: true),
            icon: const Icon(Icons.list, size: 20),
            label: Text(
                _trails.isEmpty ? 'No lap trails available' : 'Select Trail',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedTrailCard(Trail trail) {
    final id = int.tryParse(trail.id ?? '');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildTrailThumb(id),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.loop,
                            size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            trail.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _difficultyColor(trail.difficulty)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _difficultyLabel(trail.difficulty),
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: _difficultyColor(trail.difficulty)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(trail.distance ?? 0).toStringAsFixed(2)} km · ${trail.creatorName ?? ""}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: () => _openTrailSelector(initial: false),
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: const Text('Change',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _infoStat(Icons.straighten,
                      '${(trail.distance ?? 0).toStringAsFixed(2)} km')),
              Expanded(
                  child: _infoStat(Icons.trending_up,
                      '${(trail.elevation ?? 0).toStringAsFixed(0)} m')),
              Expanded(
                  child: _infoStat(
                      Icons.scatter_plot, '$_trailPointCount pts')),
            ],
          ),
          if (trail.location != null && trail.location!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.location_on,
                    size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    trail.location!,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCheckpointsSection() {
    final n = _checkpoints.length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text('Checkpoints ($n/4)',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const Spacer(),
              TextButton.icon(
                onPressed: n >= 4 ? null : _enterCheckpointPickMode,
                icon: const Icon(Icons.add_location_alt, size: 16),
                label: const Text('Add', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ],
          ),
          if (n == 0)
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 2),
              child: Text(
                'No personal checkpoints yet. Add up to 4 to split this lap.',
                style:
                    TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6, runSpacing: 6,
                children: _checkpoints
                    .map((cp) => Chip(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.08),
                          side: BorderSide(
                              color: AppColors.primary
                                  .withValues(alpha: 0.3)),
                          label: Text('CP ${cp.sequenceIndex}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary)),
                          deleteIcon: const Icon(Icons.close,
                              size: 14, color: AppColors.error),
                          onDeleted: () => _deleteCheckpoint(cp),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTargetLapsRow() {
    return Row(
      children: [
        const Text('Target Laps',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const Spacer(),
        _lapCountBtn(Icons.remove,
            _targetLaps > 1 ? () => setState(() => _targetLaps--) : null),
        Container(
          width: 56, alignment: Alignment.center,
          child: Text('$_targetLaps',
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary)),
        ),
        _lapCountBtn(Icons.add,
            _targetLaps < 50 ? () => setState(() => _targetLaps++) : null),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────
  // CHECKPOINT PICK VIEW (full-screen map + bottom action bar)
  // ───────────────────────────────────────────────────────────
  Widget _buildCheckpointPickView() {
    final safeTop = MediaQuery.of(context).padding.top;
    final size = MediaQuery.of(context).size;
    final bottomBarH = _checkpointBottomBarHeight();
    final mapVisibleH = size.height - bottomBarH;
    final pinTopOffset = safeTop + (mapVisibleH - safeTop) / 2 - 36;

    LatLng mapCenter;
    if (_trailRoute.isNotEmpty) {
      mapCenter = _trailRoute[_trailRoute.length ~/ 2];
    } else if (_userLocation != null) {
      mapCenter = _userLocation!;
    } else {
      mapCenter = const LatLng(22.8956, 113.8739);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: mapCenter, zoom: 16),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          gestureRecognizers: kMapGestureRecognizers,
          polylines: {
            if (_trailRoute.length >= 2)
              Polyline(
                polylineId: const PolylineId('trail'),
                points: _trailRoute,
                color: AppColors.primary,
                width: 4,
              ),
          },
          markers: {
            if (_trailRoute.isNotEmpty)
              Marker(
                markerId: const MarkerId('start'),
                position: _trailRoute.first,
                icon: StartEndMarkerIcons.start,
              ),
            for (final cp in _checkpoints)
              Marker(
                markerId: MarkerId('cp_${cp.id}'),
                position: LatLng(cp.latitude, cp.longitude),
                icon: _cpIcon(cp.sequenceIndex),
                anchor: const Offset(0.5, 0.5),
                infoWindow:
                    InfoWindow(title: 'Checkpoint ${cp.sequenceIndex}'),
              ),
          },
          onMapCreated: (c) {
            _mapController = c;
            _mapReady = true;
            if (_trailRoute.isNotEmpty) _fitTrailBounds(_trailRoute);
          },
        ),

        // Centered pin
        Positioned(
          left: 0, right: 0, top: pinTopOffset,
          child: const IgnorePointer(
            child: Center(
              child: Icon(Icons.location_pin,
                  size: 44, color: AppColors.error),
            ),
          ),
        ),

        // Top bar
        Positioned(
          top: safeTop + 8, left: 12, right: 12,
          child: Row(
            children: [
              _circleBtn(Icons.arrow_back, _exitCheckpointPickMode),
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
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 6),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.flag,
                          size: 18, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Add Checkpoint  ${_checkpoints.length}/4',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Bottom action bar
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8, offset: Offset(0, -2)),
              ],
            ),
            padding: EdgeInsets.fromLTRB(16, 14, 16,
                MediaQuery.of(context).padding.bottom + 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.location_pin,
                        color: AppColors.error, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Drag map to position the pin · ${_checkpoints.length}/4',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Existing checkpoint chips (so user can delete during placement)
                if (_checkpoints.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(
                      spacing: 6, runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: _checkpoints
                          .map((cp) => Chip(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4),
                                backgroundColor: AppColors.primary
                                    .withValues(alpha: 0.08),
                                side: BorderSide(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.3)),
                                label: Text('CP ${cp.sequenceIndex}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary)),
                                deleteIcon: const Icon(Icons.close,
                                    size: 14, color: AppColors.error),
                                onDeleted: () => _deleteCheckpoint(cp),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ))
                          .toList(),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _addingCheckpoint
                            ? null
                            : _exitCheckpointPickMode,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: BorderSide(
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Done'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed:
                            (_addingCheckpoint || _checkpoints.length >= 4)
                                ? null
                                : _confirmCheckpointAtCenter,
                        icon: _addingCheckpoint
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.add_location_alt,
                                size: 18, color: Colors.white),
                        label: Text(
                          _addingCheckpoint
                              ? 'Validating…'
                              : 'Add Checkpoint',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Small helpers ─────────────────────────────────────────
  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40, height: 40,
          child: Icon(icon, size: 20, color: AppColors.textPrimary),
        ),
      ),
    );
  }

  Widget _lapCountBtn(IconData icon, VoidCallback? onTap) {
    return Material(
      color: onTap != null
          ? AppColors.primary.withValues(alpha: 0.1)
          : AppColors.background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36, height: 36,
          child: Icon(icon,
              size: 20,
              color: onTap != null
                  ? AppColors.primary
                  : AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildTrailThumb(int? trailId) {
    if (trailId == null) {
      return Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.terrain,
            color: AppColors.textSecondary, size: 24),
      );
    }
    final cached = trailThumbCache[trailId];
    if (cached != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(cached, width: 64, height: 64, fit: BoxFit.cover),
      );
    }
    return FutureBuilder<TrailThumbnailResult>(
      future: loadTrailThumbnail(trailId),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final bytes = snap.data?.bytes;
        if (bytes != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(bytes,
                width: 64, height: 64, fit: BoxFit.cover),
          );
        }
        return Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.terrain,
              color: AppColors.textSecondary, size: 24),
        );
      },
    );
  }

  Color _difficultyColor(String d) {
    switch (d.toLowerCase()) {
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

  String _difficultyLabel(String d) {
    if (d.isEmpty) return 'Medium';
    return d[0].toUpperCase() + d.substring(1);
  }

  Widget _infoStat(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(value,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────
// Trail picker bottom-sheet
// ───────────────────────────────────────────────────────────────
class _TrailPickerSheet extends StatefulWidget {
  final List<Trail> trails;
  final String? initialSelectedId;
  final bool showCancel;

  const _TrailPickerSheet({
    required this.trails,
    required this.initialSelectedId,
    required this.showCancel,
  });

  @override
  State<_TrailPickerSheet> createState() => _TrailPickerSheetState();
}

class _TrailPickerSheetState extends State<_TrailPickerSheet> {
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialSelectedId;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxH = mq.size.height * 0.75;
    final hasSelection = _selectedId != null;

    return PopScope(
      canPop: widget.showCancel,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(0, 8, 0, mq.padding.bottom + 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.loop, size: 18, color: AppColors.primary),
                  SizedBox(width: 6),
                  Text('Select Trail',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: widget.trails.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No lap trails available.\nRecord one first in Trails tab.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: widget.trails.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final t = widget.trails[i];
                        final isSel = t.id == _selectedId;
                        return _TrailPickerRow(
                          trail: t,
                          selected: isSel,
                          onTap: () => setState(() => _selectedId = t.id),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  if (widget.showCancel) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: BorderSide(
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.4)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: widget.showCancel ? 2 : 1,
                    child: ElevatedButton(
                      onPressed: hasSelection
                          ? () {
                              final picked = widget.trails.firstWhere(
                                  (e) => e.id == _selectedId);
                              Navigator.of(context).pop(picked);
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hasSelection
                            ? AppColors.primary
                            : AppColors.divider,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                      ),
                      child: const Text('OK',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrailPickerRow extends StatelessWidget {
  final Trail trail;
  final bool selected;
  final VoidCallback onTap;

  const _TrailPickerRow({
    required this.trail,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final id = int.tryParse(trail.id ?? '');
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            _thumb(id),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.loop,
                          size: 14,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          trail.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? AppColors.primary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _diffColor(trail.difficulty)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _diffLabel(trail.difficulty),
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: _diffColor(trail.difficulty)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${(trail.distance ?? 0).toStringAsFixed(2)} km · ${trail.creatorName ?? ""}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (selected)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.check_circle,
                    color: AppColors.primary, size: 22),
              ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(int? trailId) {
    if (trailId == null) {
      return Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.terrain,
            color: AppColors.textSecondary, size: 22),
      );
    }
    final cached = trailThumbCache[trailId];
    if (cached != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(cached, width: 56, height: 56, fit: BoxFit.cover),
      );
    }
    return FutureBuilder<TrailThumbnailResult>(
      future: loadTrailThumbnail(trailId),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final bytes = snap.data?.bytes;
        if (bytes != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(bytes,
                width: 56, height: 56, fit: BoxFit.cover),
          );
        }
        return Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.terrain,
              color: AppColors.textSecondary, size: 22),
        );
      },
    );
  }

  Color _diffColor(String d) {
    switch (d.toLowerCase()) {
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

  String _diffLabel(String d) {
    if (d.isEmpty) return 'Medium';
    return d[0].toUpperCase() + d.substring(1);
  }
}
