import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../common/network/trax_api.dart';
import '../../common/utils/map_gesture_recognizers.dart';
import '../../common/utils/start_end_marker_icons.dart';
import '../../common/widgets/page_code_badge.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../models/user_checkpoint.dart';
import '../../common/utils/map_styles.dart';
import '../../theme/app_theme.dart';

/// Standalone editor for the current user's checkpoints on a single trail.
///
/// Operation model: a slider beneath the map maps to arc-length along the
/// trail polyline. The user drags the slider to position a draft pin and
/// taps "Add" to persist. Existing checkpoints render as numbered markers
/// on the map and as ticks above the slider so the user can see which
/// spots are already occupied. Up to 4 personal CPs are allowed.
///
/// This page is the single source of truth for the CP-configuration UX
/// across the app — open it via `MapRouter.openTrailCheckpoints` from any
/// caller (e.g. the Host Laps lobby).
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
  bool _mapReady = false;

  List<LatLng> _trailRoute = const [];
  List<UserCheckpoint> _checkpoints = const [];
  final Map<int, BitmapDescriptor> _cpMarkerCache = {};

  bool _loading = true;
  bool _adding = false;

  // Slider state (arc-length along [_trailRoute], normalised 0..1).
  double _sliderT = 0.5;
  List<double> _cumDistM = const [];
  double _trailLengthM = 0;
  List<double> _checkpointTicks = const [];

  // ── Lifecycle ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
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
      _recomputeArcLengths();
      _recomputeCheckpointTicks();
    });
    _warmCpMarkers();
    _warmDraftIcon();
    if (pts.isNotEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _fitTrailBounds(pts));
    }
  }

  // ── Polyline arc-length helpers ───────────────────────────
  void _recomputeArcLengths() {
    if (_trailRoute.length < 2) {
      _cumDistM = const [];
      _trailLengthM = 0;
      return;
    }
    final cum = <double>[0];
    double total = 0;
    for (var i = 1; i < _trailRoute.length; i++) {
      total += _haversineM(_trailRoute[i - 1], _trailRoute[i]);
      cum.add(total);
    }
    _cumDistM = cum;
    _trailLengthM = total;
  }

  void _recomputeCheckpointTicks() {
    if (_trailRoute.length < 2 || _trailLengthM <= 0) {
      _checkpointTicks = const [];
      return;
    }
    _checkpointTicks = _checkpoints
        .map((cp) => _fractionOf(LatLng(cp.latitude, cp.longitude)))
        .toList();
  }

  LatLng _positionAtFraction(double t) {
    if (_trailRoute.isEmpty) return const LatLng(0, 0);
    if (_trailRoute.length == 1) return _trailRoute.first;
    final target = (t.clamp(0.0, 1.0)) * _trailLengthM;
    var lo = 0, hi = _cumDistM.length - 1;
    while (lo < hi - 1) {
      final mid = (lo + hi) >> 1;
      if (_cumDistM[mid] <= target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final segStart = _cumDistM[lo];
    final segEnd = _cumDistM[hi];
    final segLen = (segEnd - segStart).abs();
    final f = segLen > 0 ? (target - segStart) / segLen : 0.0;
    final a = _trailRoute[lo];
    final b = _trailRoute[hi];
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * f,
      a.longitude + (b.longitude - a.longitude) * f,
    );
  }

  double _fractionOf(LatLng p) {
    if (_trailRoute.length < 2 || _trailLengthM <= 0) return 0;
    var bestDist = double.infinity;
    double bestArc = 0;
    for (var i = 0; i < _trailRoute.length - 1; i++) {
      final a = _trailRoute[i];
      final b = _trailRoute[i + 1];
      final segLen = _haversineM(a, b);
      if (segLen <= 0) continue;
      final cosLat = math.cos(a.latitude * math.pi / 180);
      final bx = (b.longitude - a.longitude) * cosLat;
      final by = b.latitude - a.latitude;
      final px = (p.longitude - a.longitude) * cosLat;
      final py = p.latitude - a.latitude;
      final l2 = bx * bx + by * by;
      var u = l2 > 0 ? (px * bx + py * by) / l2 : 0.0;
      u = u.clamp(0.0, 1.0);
      final cx = u * bx;
      final cy = u * by;
      final dx = px - cx;
      final dy = py - cy;
      final approxM = math.sqrt(dx * dx + dy * dy) * 111320.0;
      if (approxM < bestDist) {
        bestDist = approxM;
        bestArc = _cumDistM[i] + segLen * u;
      }
    }
    return (bestArc / _trailLengthM).clamp(0.0, 1.0);
  }

  static double _haversineM(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final s1 = math.sin(dLat / 2);
    final s2 = math.sin(dLng / 2);
    final h = s1 * s1 +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            s2 *
            s2;
    return 2 * r * math.asin(math.sqrt(h));
  }

  // ── Marker rendering ──────────────────────────────────────
  Future<void> _warmCpMarkers() async {
    var changed = false;
    for (final cp in _checkpoints) {
      if (!_cpMarkerCache.containsKey(cp.sequenceIndex)) {
        _cpMarkerCache[cp.sequenceIndex] =
            await _buildNumberedMarker(cp.sequenceIndex, AppColors.primary);
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
  }

  // Numbered violet draft icon for the next CP about to be added.
  BitmapDescriptor? _draftCpIcon;
  int? _draftCpIconForSeq;
  Future<void> _warmDraftIcon() async {
    final nextSeq = _checkpoints.length + 1;
    if (_draftCpIconForSeq == nextSeq && _draftCpIcon != null) return;
    final icon =
        await _buildNumberedMarker(nextSeq, const Color(0xFF8E24AA));
    if (!mounted) return;
    setState(() {
      _draftCpIcon = icon;
      _draftCpIconForSeq = nextSeq;
    });
  }

  Future<BitmapDescriptor> _buildNumberedMarker(int seq, Color fill) async {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final r = 11.0 * dpr;
    final borderW = 2.0 * dpr;
    final size = (r + borderW) * 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
    final cx = size / 2;
    final cy = size / 2;
    canvas.drawCircle(
        Offset(cx, cy), r + borderW / 2, Paint()..color = Colors.white);
    canvas.drawCircle(
        Offset(cx, cy), r, Paint()..color = fill);
    final tp = TextPainter(
      text: TextSpan(
        text: '$seq',
        style: TextStyle(
          color: Colors.white,
          fontSize: 13 * dpr,
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

  // ── Add / Delete ──────────────────────────────────────────
  Future<void> _addAtSlider() async {
    if (_trailRoute.length < 2) {
      showTraxSnackBar(context, 'Trail has no path', isError: true);
      return;
    }
    if (_checkpoints.length >= 4) {
      showTraxSnackBar(context, 'Max 4 checkpoints', isError: true);
      return;
    }
    setState(() => _adding = true);
    try {
      final p = _positionAtFraction(_sliderT);
      final resp = await TraxApi.addTrailCheckpoint(
          widget.trailId, p.latitude, p.longitude);
      if (!mounted) return;
      if (resp.isSuccess() && resp.data is List) {
        setState(() {
          _checkpoints = (resp.data as List)
              .map((e) => UserCheckpoint.fromJson(e as Map<String, dynamic>))
              .toList();
          _recomputeCheckpointTicks();
        });
        _warmCpMarkers();
        _warmDraftIcon();
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
        _recomputeCheckpointTicks();
      });
      _warmCpMarkers();
      _warmDraftIcon();
    } else {
      showTraxSnackBar(context, resp.message, isError: true);
    }
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) =>
      PageCodeBadge(code: '411', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: traxTitle('My Checkpoints')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                Expanded(child: _buildMap()),
                _buildBottomBar(),
              ],
            ),
    );
  }

  Widget _buildMap() {
    final mapCenter = _trailRoute.isNotEmpty
        ? _trailRoute[_trailRoute.length ~/ 2]
        : const LatLng(0, 0);
    final draftPos = _trailRoute.length >= 2
        ? _positionAtFraction(_sliderT)
        : (_trailRoute.isNotEmpty ? _trailRoute.first : mapCenter);

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: mapCenter, zoom: 14),
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      compassEnabled: false,
      mapToolbarEnabled: false,
      gestureRecognizers: kMapGestureRecognizers,
      onMapCreated: (c) {
        _mapController = c;
        _mapReady = true;
        if (_trailRoute.isNotEmpty) _fitTrailBounds(_trailRoute);
      },
      polylines: {
        if (_trailRoute.length >= 2) ...[
          Polyline(
            polylineId: const PolylineId('trail_halo'),
            color: MapStyles.trailHaloColor,
            width: MapStyles.trailHaloWidth,
            points: _trailRoute,
          ),
          Polyline(
            polylineId: const PolylineId('trail'),
            color: MapStyles.trailColor,
            width: MapStyles.trailWidth,
            points: _trailRoute,
          ),
        ],
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
        if (_trailRoute.length >= 2 && _checkpoints.length < 4)
          Marker(
            markerId: const MarkerId('cp_draft'),
            position: draftPos,
            icon: _draftCpIcon ??
                BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueViolet),
            anchor: const Offset(0.5, 0.5),
            zIndex: 5,
            infoWindow: InfoWindow(
                title: 'New Checkpoint ${_checkpoints.length + 1}'),
          ),
      },
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
              color: Colors.black12, blurRadius: 8, offset: Offset(0, -2)),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
          16, 14, 16, MediaQuery.of(context).padding.bottom + 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.trailName != null && widget.trailName!.isNotEmpty
                      ? widget.trailName!
                      : 'Drag to position the new checkpoint',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${_checkpoints.length}/4',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          _buildSlider(),
          if (_checkpoints.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: _checkpoints
                  .map((cp) => Chip(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.08),
                        side: BorderSide(
                            color:
                                AppColors.primary.withValues(alpha: 0.3)),
                        label: Text('CP ${cp.sequenceIndex}',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary)),
                        deleteIcon: const Icon(Icons.close,
                            size: 14, color: AppColors.error),
                        onDeleted: () => _delete(cp),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_adding || _checkpoints.length >= 4)
                  ? null
                  : _addAtSlider,
              icon: _adding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add_location_alt,
                      size: 18, color: Colors.white),
              label: Text(
                _adding
                    ? 'Adding…'
                    : (_checkpoints.length >= 4
                        ? 'Maximum 4 checkpoints'
                        : 'Add Checkpoint'),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tick marks for existing checkpoints.
          SizedBox(
            height: 18,
            child: LayoutBuilder(
              builder: (ctx, c) {
                return Stack(
                  children: [
                    for (var i = 0; i < _checkpointTicks.length; i++)
                      Positioned(
                        left: (c.maxWidth - 10) * _checkpointTicks[i] + 5,
                        top: 2,
                        child: Container(
                          width: 2,
                          height: 14,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: AppColors.primary,
              inactiveTrackColor:
                  AppColors.primary.withValues(alpha: 0.25),
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.18),
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 9),
            ),
            child: Slider(
              value: _sliderT,
              min: 0,
              max: 1,
              onChanged: (_trailRoute.length < 2 || _adding)
                  ? null
                  : (v) {
                      setState(() => _sliderT = v);
                      if (_mapReady && _trailRoute.length >= 2) {
                        _mapController?.animateCamera(
                            CameraUpdate.newLatLng(_positionAtFraction(v)));
                      }
                    },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('Start',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600)),
              Text('End',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600)),
            ],
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
              leading: const Icon(Icons.flag, color: AppColors.primary),
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
