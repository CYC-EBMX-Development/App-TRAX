import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../common/network/trax_api.dart';
import '../../common/utils/start_end_marker_icons.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../models/user_checkpoint.dart';
import '../../theme/app_theme.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

/// Standalone editor for the current user's checkpoints on a single trail.
/// Used by the Host Laps lobby (`RaceDetailPage` LAPS branch) so each rider
/// can configure up to 4 personal CPs without leaving the session.
class TrailCheckpointsPage extends StatefulWidget {
  final int trailId;
  final String? trailName;

  const TrailCheckpointsPage({
    super.key,
    required this.trailId,
    this.trailName,
  });

  @override
  State<TrailCheckpointsPage> createState() => _TrailCheckpointsPageState();
}

class _TrailCheckpointsPageState extends State<TrailCheckpointsPage> {
  GoogleMapController? _mapController;
  List<LatLng> _trailRoute = [];
  List<UserCheckpoint> _checkpoints = [];
  final Map<int, BitmapDescriptor> _cpMarkerCache = {};
  bool _loading = true;
  bool _isPicking = false;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      TraxApi.getTrailPoints(widget.trailId),
      TraxApi.getTrailCheckpoints(widget.trailId),
    ]);
    if (!mounted) return;
    final routeResp = results[0];
    final cpResp = results[1];
    final pts = <LatLng>[];
    if (routeResp.isSuccess() && routeResp.data is List) {
      for (final p in routeResp.data as List) {
        final m = p as Map<String, dynamic>;
        pts.add(LatLng(
          (m['latitude'] as num).toDouble(),
          (m['longitude'] as num).toDouble(),
        ));
      }
    }
    final cps = <UserCheckpoint>[];
    if (cpResp.isSuccess() && cpResp.data is List) {
      for (final e in cpResp.data as List) {
        cps.add(UserCheckpoint.fromJson(e as Map<String, dynamic>));
      }
    }
    setState(() {
      _trailRoute = pts;
      _checkpoints = cps;
      _loading = false;
    });
    _warmCpMarkers();
    if (pts.isNotEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _fitTrailBounds(pts));
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
    canvas.drawCircle(
        Offset(cx, cy), r + borderW / 2, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = AppColors.primary);
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
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      byteData!.buffer.asUint8List(),
      width: size / dpr,
      height: size / dpr,
    );
  }

  BitmapDescriptor _cpIcon(int seq) =>
      _cpMarkerCache[seq] ??
      BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);

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

  void _enterPickMode() {
    if (_checkpoints.length >= 4) {
      showTraxSnackBar(context, 'Max 4 checkpoints', isError: true);
      return;
    }
    setState(() => _isPicking = true);
  }

  Future<void> _confirmAtCenter() async {
    if (_mapController == null) return;
    setState(() => _adding = true);
    try {
      final size = MediaQuery.of(context).size;
      final cy = (size.height -
              (120 + MediaQuery.of(context).padding.bottom) -
              MediaQuery.of(context).padding.top) /
          2 +
          MediaQuery.of(context).padding.top;
      final centerScreen = ScreenCoordinate(
        x: (size.width / 2).round(),
        y: cy.round(),
      );
      final center = await _mapController!.getLatLng(centerScreen);
      final resp = await TraxApi.addTrailCheckpoint(
          widget.trailId, center.latitude, center.longitude);
      if (!mounted) return;
      if (resp.isSuccess() && resp.data is List) {
        setState(() {
          _checkpoints = (resp.data as List)
              .map((e) => UserCheckpoint.fromJson(e as Map<String, dynamic>))
              .toList();
          _isPicking = false;
        });
        _warmCpMarkers();
      } else {
        showTraxSnackBar(
            context,
            resp.message.isNotEmpty
                ? resp.message
                : 'Failed to add checkpoint',
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _delete(UserCheckpoint cp) async {
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
      showTraxSnackBar(context, resp.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) =>
      PageCodeBadge(code: '411', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: traxTitle('My Checkpoints'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : Stack(
              children: [
                _buildMap(),
                if (_isPicking) _buildPickerOverlay(),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildBottomBar(),
                ),
              ],
            ),
    );
  }

  Widget _buildMap() {
    final mapCenter = _trailRoute.isNotEmpty
        ? _trailRoute[_trailRoute.length ~/ 2]
        : const LatLng(0, 0);
    return GoogleMap(
      initialCameraPosition:
          CameraPosition(target: mapCenter, zoom: 14),
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      compassEnabled: false,
      mapToolbarEnabled: false,
      onMapCreated: (c) {
        _mapController = c;
        if (_trailRoute.isNotEmpty) _fitTrailBounds(_trailRoute);
      },
      polylines: {
        if (_trailRoute.length >= 2)
          Polyline(
            polylineId: const PolylineId('trail'),
            color: AppColors.primary,
            width: 4,
            points: _trailRoute,
          ),
      },
      markers: {
        if (_trailRoute.isNotEmpty)
          Marker(
            markerId: const MarkerId('start'),
            position: _trailRoute.first,
            icon: StartEndMarkerIcons.start,
            anchor: const Offset(0.5, 0.5),
            zIndex: 0,
          ),
        for (final cp in _checkpoints)
          Marker(
            markerId: MarkerId('cp${cp.sequenceIndex}'),
            position: LatLng(cp.latitude, cp.longitude),
            icon: _cpIcon(cp.sequenceIndex),
            anchor: const Offset(0.5, 0.5),
            consumeTapEvents: true,
            onTap: () => _showDeleteSheet(cp),
          ),
      },
    );
  }

  Widget _buildPickerOverlay() {
    return IgnorePointer(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Icon(
            Icons.location_pin,
            size: 44,
            color: AppColors.primary,
            shadows: [
              Shadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 16 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                widget.trailName ?? 'Trail',
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text('${_checkpoints.length}/4',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          if (_isPicking)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _adding
                        ? null
                        : () => setState(() => _isPicking = false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _adding ? null : _confirmAtCenter,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: _adding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Add Checkpoint'),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    _checkpoints.length >= 4 ? null : _enterPickMode,
                icon: const Icon(Icons.add_location_alt, size: 18),
                label: Text(_checkpoints.length >= 4
                    ? 'Maximum 4 checkpoints'
                    : 'Add Checkpoint'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showDeleteSheet(UserCheckpoint cp) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.flag, color: AppColors.primary),
              title: Text('Checkpoint ${cp.sequenceIndex}'),
              subtitle: Text(
                  '${cp.latitude.toStringAsFixed(5)}, ${cp.longitude.toStringAsFixed(5)}'),
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: AppColors.error),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await _delete(cp);
  }
}
