import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../common/utils/map_gesture_recognizers.dart';
import '../../common/utils/map_styles.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../theme/app_theme.dart';
import 'ride_analysis_shared.dart';

class RideAnalysisPage extends StatefulWidget {
  final List<Map<String, dynamic>> points;
  final String rideName;

  const RideAnalysisPage({
    super.key,
    required this.points,
    required this.rideName,
  });

  @override
  State<RideAnalysisPage> createState() => _RideAnalysisPageState();
}

class _RideAnalysisPageState extends State<RideAnalysisPage> {
  GoogleMapController? _mapController;
  late final List<RideAnalysisSample> _samples;
  late final List<double> _distanceKm;
  late final List<LatLng> _positions;

  int _cursor = 0;
  int _windowStart = 0;
  int _windowEnd = 0;
  RideAnalysisMetric _metric = RideAnalysisMetric.speed;

  @override
  void initState() {
    super.initState();
    _samples = buildAnalysisSamples(widget.points);
    _distanceKm = buildCumulativeDistanceKm(_samples);
    _positions = _samples.map((s) => s.position).toList(growable: false);
    if (_samples.isNotEmpty) {
      _windowEnd = _samples.length - 1;
      _cursor = ((_samples.length - 1) * 0.5).round();
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  bool get _hasData => _samples.length >= 2;

  RideAnalysisSample get _current => _samples[_cursor];

  void _setCursor(int idx) {
    if (_samples.isEmpty) return;
    final next = idx.clamp(0, _samples.length - 1);
    setState(() => _cursor = next);
  }

  void _setWindow(int start, int end) {
    if (_samples.isEmpty) return;
    int s = start.clamp(0, _samples.length - 1);
    int e = end.clamp(0, _samples.length - 1);
    if (e < s) {
      final t = s;
      s = e;
      e = t;
    }
    int c = _cursor;
    if (c < s) c = s;
    if (c > e) c = e;
    setState(() {
      _windowStart = s;
      _windowEnd = e;
      _cursor = c;
    });
  }

  void _zoom(bool zoomIn) {
    if (_samples.length <= 10) return;
    final span = _windowEnd - _windowStart + 1;
    final target = zoomIn ? (span * 0.65).round() : (span * 1.6).round();
    final minSpan = 10;
    final nextSpan = target.clamp(minSpan, _samples.length);
    final frac = span <= 1 ? 0.5 : (_cursor - _windowStart) / (span - 1);
    int start = (_cursor - frac * (nextSpan - 1)).round();
    final maxStart = _samples.length - nextSpan;
    if (start < 0) start = 0;
    if (start > maxStart) start = maxStart;
    _setWindow(start, start + nextSpan - 1);
  }

  void _fitToTrack() {
    final ctrl = _mapController;
    if (ctrl == null || _samples.isEmpty) return;

    double minLat = _samples.first.position.latitude;
    double maxLat = _samples.first.position.latitude;
    double minLng = _samples.first.position.longitude;
    double maxLng = _samples.first.position.longitude;
    for (final s in _samples) {
      final p = s.position;
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    ctrl.moveCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        48,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasData) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: traxTitle('Ride Analysis')),
        body: const Center(child: Text('No ride data available')),
      );
    }

    final elapsed = _current.timestamp.difference(_samples.first.timestamp);
    final total = _samples.last.timestamp.difference(_samples.first.timestamp);
    final metricValue = _metric.valueOf(_current);

    // Cheap reference slices over the precomputed positions — no
    // per-frame re-projection of the whole sample list while scrubbing.
    final traversed = _positions.sublist(0, _cursor + 1);
    final remaining = _positions.sublist(_cursor);

    final currentPos = _current.position;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(target: currentPos, zoom: 14),
                    onMapCreated: (c) {
                      _mapController = c;
                      WidgetsBinding.instance.addPostFrameCallback((_) => _fitToTrack());
                    },
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    compassEnabled: false,
                    mapToolbarEnabled: false,
                    gestureRecognizers: kMapGestureRecognizers,
                    polylines: {
                      Polyline(
                        polylineId: const PolylineId('remaining'),
                        points: remaining,
                        color: MapStyles.trailColor.withValues(alpha: 0.3),
                        width: 5,
                      ),
                      Polyline(
                        polylineId: const PolylineId('traversed'),
                        points: traversed,
                        color: MapStyles.trailColor,
                        width: 5,
                      ),
                    },
                    markers: {
                      Marker(
                        markerId: const MarkerId('start'),
                        position: _samples.first.position,
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                      ),
                      Marker(
                        markerId: const MarkerId('finish'),
                        position: _samples.last.position,
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                      ),
                      Marker(
                        markerId: const MarkerId('cursor'),
                        position: currentPos,
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
                      ),
                    },
                  ),
                  Positioned(
                    top: 14,
                    left: 56,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: Text(
                        'Distance ${_distanceKm[_cursor].toStringAsFixed(2)} km  ·  Time ${formatElapsed(elapsed)}',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _circleBtn(
                      Icons.arrow_back,
                      () => Navigator.of(context).pop(),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 12,
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(formatElapsed(Duration.zero), style: const TextStyle(color: Colors.white70)),
                            Text(
                              'Current ${formatElapsed(elapsed)}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                            Text(formatElapsed(total), style: const TextStyle(color: Colors.white70)),
                          ],
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppColors.primary,
                            inactiveTrackColor: Colors.white38,
                            thumbColor: AppColors.primary,
                            overlayColor: AppColors.primary.withValues(alpha: 0.2),
                          ),
                          child: Slider(
                            min: 0,
                            max: (_samples.length - 1).toDouble(),
                            value: _cursor.toDouble(),
                            onChanged: (v) => _setCursor(v.round()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2)),
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: Row(
                        children: [
                          _metricChip(RideAnalysisMetric.speed),
                          const SizedBox(width: 8),
                          _metricChip(RideAnalysisMetric.altitude),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                      child: Row(
                        children: [
                          Text(
                            metricValue.toStringAsFixed(1),
                            style: TextStyle(
                              color: _metric.color,
                              fontSize: 42,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _metric.unit,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 20, fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Zoom Out',
                            onPressed: () => _zoom(false),
                            icon: const Icon(Icons.remove, color: AppColors.textPrimary),
                          ),
                          IconButton(
                            tooltip: 'Zoom In',
                            onPressed: () => _zoom(true),
                            icon: const Icon(Icons.add, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: RideAnalysisChart(
                          samples: _samples,
                          metric: _metric,
                          cursor: _cursor,
                          windowStart: _windowStart,
                          windowEnd: _windowEnd,
                          onCursorChanged: _setCursor,
                          onWindowChanged: _setWindow,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricChip(RideAnalysisMetric metric) {
    final on = _metric == metric;
    return GestureDetector(
      onTap: () => setState(() => _metric = metric),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: on ? metric.color.withValues(alpha: 0.12) : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? metric.color : AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.circle, size: 10, color: on ? metric.color : AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              metric.label,
              style: TextStyle(
                color: on ? metric.color : AppColors.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}
