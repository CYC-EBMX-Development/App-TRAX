import 'dart:math';
import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import '../../../common/services/map_service.dart';
import '../../../common/network/trax_api.dart';
import '../../../common/utils/amap_adapter.dart';
import '../../../theme/app_theme.dart';

/// AMap variant of [TrailSavePage]. Visual UX parity with the Google
/// version; the only difference is the SliverAppBar background which uses
/// an AMap static-map image (with GCJ-02 conversion applied internally by
/// [MapService.staticMapUrl]) so the route lines up with mainland-China
/// tiles. Phase 3 will swap this for the native `AMapWidget`.
class TrailSavePageAmap extends StatefulWidget {
  final List<Map<String, dynamic>> points;
  final List<LatLng> route;
  const TrailSavePageAmap({super.key, required this.points, required this.route});

  @override
  State<TrailSavePageAmap> createState() => _TrailSavePageAmapState();
}

class _TrailSavePageAmapState extends State<TrailSavePageAmap> {
  final _nameController = TextEditingController();
  final _nameFocusNode = FocusNode();
  String _difficulty = 'medium';
  bool _isPublic = true;
  bool _isSaving = false;
  bool _nameFieldFocused = false;
  String? _location;

  final _difficulties = ['easy', 'medium', 'hard', 'extreme'];

  @override
  void initState() {
    super.initState();
    _nameFocusNode.addListener(() {
      setState(() => _nameFieldFocused = _nameFocusNode.hasFocus);
    });
    _fetchLocation();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    if (widget.route.isEmpty) return;
    final pt = widget.route.first;
    final address = await MapService.reverseGeocode(pt.latitude, pt.longitude);
    if (address != null && mounted) setState(() => _location = address);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showTraxSnackBar(context, 'Please enter a trail name', isError: true);
      return;
    }
    setState(() => _isSaving = true);
    final data = {
      'name': name,
      'difficulty': _difficulty,
      'location': _location,
      'isPublic': _isPublic,
      'points': widget.points,
    };
    final resp = await TraxApi.createTrail(data);
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (resp.isSuccess()) {
      Navigator.of(context).pop(true);
    } else {
      showTraxSnackBar(context, resp.message ?? 'Failed to save trail', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Save Trail')),
      body: Column(
        children: [
          SizedBox(height: 220, width: double.infinity, child: _buildAmapHeader()),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatsSummary(),
                  const SizedBox(height: 20),
                  _buildSectionTitle('TRAIL NAME'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    focusNode: _nameFocusNode,
                    decoration: InputDecoration(
                      hintText: _nameFieldFocused ? null : 'Enter trail name',
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildSectionTitle('TYPE'),
                  const SizedBox(height: 8),
                  _buildTypeDisplay(),
                  const SizedBox(height: 20),
                  _buildSectionTitle('DIFFICULTY'),
                  const SizedBox(height: 8),
                  _buildDifficultyPicker(),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SwitchListTile(
                      title: const Text('Public Trail', style: TextStyle(fontSize: 14)),
                      subtitle: const Text('Allow others to search and use this trail',
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      value: _isPublic,
                      onChanged: (v) => setState(() => _isPublic = v),
                      activeColor: AppColors.primary,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save, size: 24),
                      label: Text(
                        _isSaving ? 'Saving...' : 'Save Trail',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      ),
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmapHeader() {
    if (widget.route.isEmpty) {
      return Container(
        color: AppColors.background,
        child: const Center(child: Icon(Icons.map_outlined, size: 64, color: AppColors.textSecondary)),
      );
    }
    return AMapWidget(
      privacyStatement: AmapAdapter.privacy(),
      apiKey: AmapAdapter.apiKey(),
      initialCameraPosition: AmapAdapter.initialCamera(widget.route, zoom: 14),
      polylines: {AmapAdapter.routePolyline(widget.route)},
      markers: AmapAdapter.startFinishMarkers(widget.route),
      scrollGesturesEnabled: true,
      zoomGesturesEnabled: true,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      // The map lives inside a CustomScrollView's SliverAppBar; without
      // claiming gestures explicitly the outer scroll view eats vertical
      // pans and pinches.
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
      },
    );
  }

  bool get _isLap {
    if (widget.route.length < 2) return false;
    return _haversineKm(widget.route.first, widget.route.last) < 0.05;
  }

  Widget _buildTypeDisplay() {
    final isLap = _isLap;
    final label = isLap ? 'Lap' : 'Free Ride';
    final icon = isLap ? Icons.loop : Icons.explore;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const Spacer(),
        const Text('Auto-detected', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ]),
    );
  }

  Widget _buildStatsSummary() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _InfoItem(Icons.pin_drop, '${widget.points.length} pts'),
          _InfoItem(Icons.straighten, '${_calcRouteDistance().toStringAsFixed(2)} km'),
        ]),
        if (_location != null) ...[
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.location_on, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(_location!,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ],
      ]),
    );
  }

  Widget _buildSectionTitle(String t) => Text(t,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary, letterSpacing: 1.2));

  Widget _buildDifficultyPicker() {
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: _difficulties.map((d) {
          final selected = _difficulty == d;
          final color = _difficultyColor(d);
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _difficulty = d),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? color.withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: selected ? Border.all(color: color, width: 2) : null,
                ),
                child: Text(d[0].toUpperCase() + d.substring(1), textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: selected ? color : AppColors.textSecondary)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _difficultyColor(String d) {
    switch (d) {
      case 'easy': return AppColors.success;
      case 'medium': return AppColors.primary;
      case 'hard': return Colors.orange;
      case 'extreme': return AppColors.error;
      default: return AppColors.textSecondary;
    }
  }

  double _calcRouteDistance() {
    double total = 0;
    for (int i = 1; i < widget.route.length; i++) {
      total += _haversineKm(widget.route[i - 1], widget.route[i]);
    }
    return total;
  }

  double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final la = a.latitude * pi / 180;
    final lb = b.latitude * pi / 180;
    final h = sin(dLat / 2) * sin(dLat / 2) + cos(la) * cos(lb) * sin(dLng / 2) * sin(dLng / 2);
    return 2 * r * atan2(sqrt(h), sqrt(1 - h));
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoItem(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 18, color: AppColors.primary),
    const SizedBox(width: 6),
    Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
  ]);
}
