import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../common/services/map_service.dart';
import '../../common/utils/map_gesture_recognizers.dart';
import '../../common/utils/start_end_marker_icons.dart';
import '../../common/network/trax_api.dart';
import '../../theme/app_theme.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class TrailSavePage extends StatefulWidget {
  final List<Map<String, dynamic>> points;
  final List<LatLng> route;

  const TrailSavePage({super.key, required this.points, required this.route});

  @override
  State<TrailSavePage> createState() => _TrailSavePageState();
}

class _TrailSavePageState extends State<TrailSavePage> {
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
    if (address != null && mounted) {
      setState(() => _location = address);
    }
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
      Navigator.of(context).pop(true); // pop with saved=true
    } else {
      showTraxSnackBar(context, resp.message ?? 'Failed to save trail', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '603', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Save Trail')),
      body: Column(
        children: [
          SizedBox(
            height: 220,
            width: double.infinity,
            child: widget.route.isNotEmpty
                ? GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: widget.route[widget.route.length ~/ 2],
                      zoom: 14,
                    ),
                    polylines: {
                      Polyline(
                        polylineId: const PolylineId('trail'),
                        points: widget.route,
                        color: AppColors.primary,
                        width: 2,
                      ),
                    },
                    markers: {
                      Marker(
                        markerId: const MarkerId('start'),
                        position: widget.route.first,
                        icon: StartEndMarkerIcons.start,
                      ),
                      if (widget.route.length > 1)
                        Marker(
                          markerId: const MarkerId('end'),
                          position: widget.route.last,
                          icon: StartEndMarkerIcons.finish,
                        ),
                    },
                    myLocationEnabled: false,
                    zoomControlsEnabled: false,
                    gestureRecognizers: kMapGestureRecognizers,
                  )
                : Container(
                    color: AppColors.background,
                    child: const Center(child: Icon(Icons.map_outlined, size: 64, color: AppColors.textSecondary)),
                  ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats summary
                  _buildStatsSummary(),
                  const SizedBox(height: 20),
                  // Trail name
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
                  // Type (auto-detected, read-only)
                  _buildSectionTitle('TYPE'),
                  const SizedBox(height: 8),
                  _buildTypeDisplay(),
                  const SizedBox(height: 20),
                  // Difficulty
                  _buildSectionTitle('DIFFICULTY'),
                  const SizedBox(height: 8),
                  _buildDifficultyPicker(),
                  const SizedBox(height: 20),
                  // Public trail
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
                  // Save button
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

  bool get _isLap {
    if (widget.route.length < 2) return false;
    final d = _haversineKm(widget.route.first, widget.route.last);
    return d < 0.05; // 50m threshold, same as backend
  }

  Widget _buildTypeDisplay() {
    final isLap = _isLap;
    final label = isLap ? 'Lap' : 'Free Ride';
    final icon = isLap ? Icons.loop : Icons.explore;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const Spacer(),
          const Text('Auto-detected', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildStatsSummary() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _InfoItem(Icons.pin_drop, '${widget.points.length} pts'),
              _InfoItem(Icons.straighten, '${_calcRouteDistance().toStringAsFixed(2)} km'),
            ],
          ),
          if (_location != null) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.location_on, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_location!,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: AppColors.textSecondary, letterSpacing: 1.2));
  }

  Widget _buildDifficultyPicker() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
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
                child: Text(
                  d[0].toUpperCase() + d.substring(1),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: selected ? color : AppColors.textSecondary,
                  ),
                ),
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
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(la) * cos(lb) * sin(dLng / 2) * sin(dLng / 2);
    return 2 * r * atan2(sqrt(h), sqrt(1 - h));
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoItem(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      ],
    );
  }
}
