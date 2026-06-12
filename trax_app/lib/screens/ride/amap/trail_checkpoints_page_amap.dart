import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:amap_flutter_base/amap_flutter_base.dart' as amap;
import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;

import '../../../common/network/trax_api.dart';
import '../../../common/utils/amap_adapter.dart';
import '../../../common/utils/map_styles.dart';
import '../../../common/utils/start_end_marker_icons_amap.dart';
import '../../../common/widgets/page_code_badge.dart';
import '../../../common/widgets/trax_refresh_button.dart';
import '../../../models/user_checkpoint.dart';
import '../../../theme/app_theme.dart';

/// AMap counterpart of [TrailCheckpointsPage]. Same slider-based UX:
/// drag the slider to move a draft pin along the trail polyline (arc-length
/// parameterised), tap "Add" to persist. Existing CPs render as numbered
/// markers and as ticks above the slider. Up to 4 personal CPs.
///
/// Coordinate model: [_trailRoute] is WGS-84 (backend); on-screen positions
/// go through [AmapAdapter.toAmap] to GCJ-02 for AMap. Slider-derived
/// positions are interpolated in WGS-84 then submitted as-is to the backend.
class TrailCheckpointsPageAmap extends StatefulWidget {
  final int trailId;
  final String? trailName;

  const TrailCheckpointsPageAmap({
    super.key,
    required this.trailId,
    this.trailName,
  });

  @override
  State<TrailCheckpointsPageAmap> createState() =>
      _TrailCheckpointsPageAmapState();
}

class _TrailCheckpointsPageAmapState extends State<TrailCheckpointsPageAmap> {
  AMapController? _mapController;
  bool _mapReady = false;

  List<gmap.LatLng> _trailRoute = const []; // WGS-84
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

  Future<void> _load() async {
    final results = await Future.wait([
      TraxApi.getTrailPoints(widget.trailId),
      TraxApi.getTrailCheckpoints(widget.trailId),
    ]);
    if (!mounted) return;
    final routeResp = results[0];
    final cpResp = results[1];

    final pts = <gmap.LatLng>[];
    if (routeResp.isSuccess() && routeResp.data is List) {
      for (final p in routeResp.data as List) {
        final m = p as Map<String, dynamic>;
        pts.add(gmap.LatLng(
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
    if (pts.isNotEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _fitTrailBounds(pts));
    }
  }

  // ── Polyline arc-length helpers (WGS-84) ──────────────────
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
        .map((cp) => _fractionOf(gmap.LatLng(cp.latitude, cp.longitude)))
        .toList();
  }

  gmap.LatLng _positionAtFraction(double t) {
    if (_trailRoute.isEmpty) return const gmap.LatLng(0, 0);
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
    return gmap.LatLng(
      a.latitude + (b.latitude - a.latitude) * f,
      a.longitude + (b.longitude - a.longitude) * f,
    );
  }

  double _fractionOf(gmap.LatLng p) {
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

  static double _haversineM(gmap.LatLng a, gmap.LatLng b) {
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

  Future<BitmapDescriptor> _buildNumberedMarker(int seq, Color fill) async {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final r = 14.0 * dpr;
    final borderW = 2.5 * dpr;
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
          fontSize: 16 * dpr,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }

  Future<BitmapDescriptor>? _draftIconFuture;
  BitmapDescriptor? _draftIcon;
  int? _draftIconForSeq;

  void _ensureDraftIcon() {
    final nextSeq = _checkpoints.length + 1;
    if (_draftIconForSeq == nextSeq && _draftIcon != null) return;
    if (_draftIconFuture != null) return;
    _draftIconFuture =
        _buildNumberedMarker(nextSeq, const Color(0xFF8E24AA));
    _draftIconFuture!.then((b) {
      if (!mounted) return;
      setState(() {
        _draftIcon = b;
        _draftIconForSeq = nextSeq;
        _draftIconFuture = null;
      });
    });
  }

  BitmapDescriptor _cpIcon(int seq) =>
      _cpMarkerCache[seq] ?? BitmapDescriptor.defaultMarker;

  Future<void> _fitTrailBounds(List<gmap.LatLng> pts) async {
    if (pts.isEmpty || _mapController == null) return;
    final amapPts = AmapAdapter.toAmapList(pts);
    if (amapPts.length == 1) {
      await _mapController!.moveCamera(
        CameraUpdate.newLatLngZoom(amapPts.first, 15),
      );
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
    await _mapController!.moveCamera(
      CameraUpdate.newLatLngBounds(
        amap.LatLngBounds(
          southwest: amap.LatLng(minLat, minLng),
          northeast: amap.LatLng(maxLat, maxLng),
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
      final p = _positionAtFraction(_sliderT); // WGS-84
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
    } else {
      showTraxSnackBar(context, resp.message, isError: true);
    }
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) =>
      PageCodeBadge(code: '411A', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    _ensureDraftIcon();
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
    final markers = <Marker>{};
    if (_trailRoute.isNotEmpty) {
      markers.add(Marker(
        position: AmapAdapter.toAmap(_trailRoute.first),
        icon: StartEndMarkerIconsAmap.start,
        anchor: const Offset(0.5, 0.5),
        zIndex: 0,
        infoWindow: const InfoWindow(title: 'Start'),
      ));
    }
    for (final cp in _checkpoints) {
      markers.add(Marker(
        position:
            AmapAdapter.toAmap(gmap.LatLng(cp.latitude, cp.longitude)),
        icon: _cpIcon(cp.sequenceIndex),
        anchor: const Offset(0.5, 0.5),
        clickable: true,
        zIndex: 5,
        onTap: (_) => _showDeleteSheet(cp),
      ));
    }
    if (_trailRoute.length >= 2 &&
        _checkpoints.length < 4 &&
        _draftIcon != null) {
      final draftWgs = _positionAtFraction(_sliderT);
      markers.add(Marker(
        position: AmapAdapter.toAmap(draftWgs),
        icon: _draftIcon!,
        anchor: const Offset(0.5, 0.5),
        zIndex: 10,
        infoWindow: InfoWindow(
            title: 'New Checkpoint ${_checkpoints.length + 1}'),
      ));
    }
    return AMapWidget(
      privacyStatement: AmapAdapter.privacy(),
      apiKey: AmapAdapter.apiKey(),
      initialCameraPosition: AmapAdapter.initialCamera(_trailRoute, zoom: 14),
      polylines: {
        if (_trailRoute.length >= 2) ...[
          AmapAdapter.routePolyline(_trailRoute,
              color: MapStyles.trailHaloColor,
              width: MapStyles.trailHaloWidth),
          AmapAdapter.routePolyline(_trailRoute, color: MapStyles.trailColor),
        ],
      },
      markers: markers,
      scrollGesturesEnabled: true,
      zoomGesturesEnabled: true,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      onMapCreated: (c) {
        _mapController = c;
        _mapReady = true;
        if (_trailRoute.isNotEmpty) _fitTrailBounds(_trailRoute);
      },
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
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
                        _mapController?.moveCamera(
                          CameraUpdate.newLatLng(
                              AmapAdapter.toAmap(_positionAtFraction(v))),
                        );
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
