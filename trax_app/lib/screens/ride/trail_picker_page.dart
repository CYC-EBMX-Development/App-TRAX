import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../common/utils/map_gesture_recognizers.dart';
import '../../common/utils/start_end_marker_icons.dart';
import '../../common/utils/trail_thumbnail.dart';

import '../../common/network/trax_api.dart';
import '../../models/trail.dart';
import '../../theme/app_theme.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class TrailPickerPage extends StatefulWidget {
  final List<Trail> trails;
  final Trail? initialSelection;
  final double? userLat;
  final double? userLng;

  const TrailPickerPage({
    super.key,
    required this.trails,
    this.initialSelection,
    this.userLat,
    this.userLng,
  });

  @override
  State<TrailPickerPage> createState() => _TrailPickerPageState();
}

class _TrailPickerPageState extends State<TrailPickerPage> {
  Trail? _selected;
  List<LatLng> _route = [];
  bool _loadingRoute = false;
  GoogleMapController? _mapController;
  late List<Trail> _sorted;

  static const LatLng _defaultPos = LatLng(22.89810, 113.86990);

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelection;
    _sorted = List<Trail>.from(widget.trails)
      ..sort((a, b) => _distanceToTrail(a).compareTo(_distanceToTrail(b)));

    if (_selected != null) {
      _loadRouteForTrail(_selected!);
    }
  }

  double _distanceToTrail(Trail t) {
    if (widget.userLat == null || widget.userLng == null ||
        t.startLatitude == null || t.startLongitude == null) {
      return double.infinity;
    }
    return Geolocator.distanceBetween(
            widget.userLat!, widget.userLng!, t.startLatitude!, t.startLongitude!) /
        1000;
  }

  String _formatDistance(double km) {
    if (km == double.infinity) return '-';
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1)} km';
  }

  Future<void> _loadRouteForTrail(Trail t) async {
    final id = int.tryParse(t.id ?? '');
    if (id == null) return;

    setState(() => _loadingRoute = true);

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
      _loadingRoute = false;
    });

    _animateToTrail(t, route);
  }

  void _animateToTrail(Trail t, List<LatLng> route) {
    if (_mapController == null) return;

    if (route.length >= 2) {
      double minLat = route.first.latitude, maxLat = route.first.latitude;
      double minLng = route.first.longitude, maxLng = route.first.longitude;
      for (final p in route) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60,
      ));
    } else if (t.startLatitude != null && t.startLongitude != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(t.startLatitude!, t.startLongitude!), 15),
      );
    }
  }

  void _onTrailTap(Trail t) {
    setState(() => _selected = t);
    _loadRouteForTrail(t);
  }

  LatLng get _initialTarget {
    if (_selected?.startLatitude != null && _selected?.startLongitude != null) {
      return LatLng(_selected!.startLatitude!, _selected!.startLongitude!);
    }
    if (widget.userLat != null && widget.userLng != null) {
      return LatLng(widget.userLat!, widget.userLng!);
    }
    if (_sorted.isNotEmpty && _sorted.first.startLatitude != null && _sorted.first.startLongitude != null) {
      return LatLng(_sorted.first.startLatitude!, _sorted.first.startLongitude!);
    }
    return _defaultPos;
  }

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '414', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Select Trail'),
        actions: [
          TextButton(
            onPressed: _selected != null
                ? () => Navigator.pop(context, _selected)
                : null,
            child: Text(
              'Done',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _selected != null ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Map area
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(target: _initialTarget, zoom: 14),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  gestureRecognizers: kMapGestureRecognizers,
                  polylines: _route.length >= 2
                      ? {
                          Polyline(
                            polylineId: const PolylineId('trail'),
                            points: _route,
                            color: AppColors.primary,
                            width: 4,
                          ),
                        }
                      : {},
                  markers: {
                    if (_route.isNotEmpty)
                      Marker(
                        markerId: const MarkerId('start'),
                        position: _route.first,
                        icon: StartEndMarkerIcons.start,
                      ),
                  },
                  onMapCreated: (c) {
                    _mapController = c;
                    if (_selected != null && _route.isNotEmpty) {
                      Future.delayed(const Duration(milliseconds: 300), () {
                        _animateToTrail(_selected!, _route);
                      });
                    }
                  },
                ),
                if (_loadingRoute)
                  const Positioned(
                    top: 16,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
                      ),
                    ),
                  ),
                // Selected trail info overlay
                if (_selected != null)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2))],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.route, size: 16, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Text(
                            _selected!.name,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          if (_selected!.distance != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              '${_selected!.distance!.toStringAsFixed(1)} km',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Trail list
          Expanded(
            flex: 4,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Text(
                          '${_sorted.length} Trails',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                        const Spacer(),
                        if (_selected != null)
                          Text(
                            'Selected: ${_selected!.name}',
                            style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _sorted.isEmpty
                        ? const Center(child: Text('No lap trails available', style: TextStyle(color: AppColors.textSecondary)))
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _sorted.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final t = _sorted[i];
                              return _TrailPickerItem(
                                trail: t,
                                isSelected: _selected?.id == t.id,
                                distanceKm: _distanceToTrail(t),
                                onTap: () => _onTrailTap(t),
                                difficultyColor: _difficultyColor(t.difficulty),
                                formatDistance: _formatDistance,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrailItemBody(
    Trail t, {
    required bool isSelected,
    required double dist,
    required VoidCallback onTap,
    required Widget thumbnail,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            thumbnail,
            const SizedBox(width: 12),
            // Trail info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? AppColors.primaryDark : AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        '${t.distance?.toStringAsFixed(1) ?? '-'} km',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: _difficultyColor(t.difficulty).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          t.difficulty,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _difficultyColor(t.difficulty)),
                        ),
                      ),
                      if (t.location != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t.location!,
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Distance + check
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (dist != double.infinity)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _formatDistance(dist),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primaryDark),
                    ),
                  ),
                if (isSelected) ...[
                  const SizedBox(height: 4),
                  const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _difficultyColor(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'hard':
        return Colors.red;
      case 'extreme':
        return Colors.purple;
      default:
        return AppColors.textSecondary;
    }
  }
}

class _TrailPickerItem extends StatefulWidget {
  final Trail trail;
  final bool isSelected;
  final double distanceKm;
  final VoidCallback onTap;
  final Color difficultyColor;
  final String Function(double) formatDistance;

  const _TrailPickerItem({
    required this.trail,
    required this.isSelected,
    required this.distanceKm,
    required this.onTap,
    required this.difficultyColor,
    required this.formatDistance,
  });

  @override
  State<_TrailPickerItem> createState() => _TrailPickerItemState();
}

class _TrailPickerItemState extends State<_TrailPickerItem> {
  Uint8List? _thumbBytes;
  bool _thumbFailed = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    final id = int.tryParse(widget.trail.id ?? '');
    if (id == null) {
      if (mounted) setState(() => _thumbFailed = true);
      return;
    }
    final result = await loadTrailThumbnail(id);
    if (!mounted) return;
    if (result.bytes != null) {
      setState(() => _thumbBytes = result.bytes);
    } else if (result.failed) {
      setState(() => _thumbFailed = true);
    }
  }

  Widget _buildThumb() {
    Widget child;
    if (_thumbBytes != null) {
      child = Image.memory(
        _thumbBytes!,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } else if (_thumbFailed) {
      child = Icon(
        Icons.route,
        size: 22,
        color: widget.isSelected ? AppColors.primary : AppColors.textSecondary,
      );
    } else {
      child = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
            strokeWidth: 2, color: AppColors.primary),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        color: widget.isSelected
            ? AppColors.primary.withValues(alpha: 0.15)
            : AppColors.background,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final picker =
        context.findAncestorStateOfType<_TrailPickerPageState>();
    if (picker == null) return const SizedBox.shrink();
    return picker._buildTrailItemBody(
      widget.trail,
      isSelected: widget.isSelected,
      dist: widget.distanceKm,
      onTap: widget.onTap,
      thumbnail: _buildThumb(),
    );
  }
}
