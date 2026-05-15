import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../common/network/trax_api.dart';
import '../../common/utils/trax_storage_util.dart';
import '../../common/widgets/bike_picker.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../models/race.dart';
import '../../models/trail.dart';
import '../../theme/app_theme.dart';
import 'race_detail_page.dart';
import 'trail_picker_page.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class HostRacePage extends StatefulWidget {
  const HostRacePage({super.key});

  @override
  State<HostRacePage> createState() => _HostRacePageState();
}

class _HostRacePageState extends State<HostRacePage> {
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  int _maxParticipants = 10;
  int _targetLaps = 1;
  bool _isPublic = true;
  DateTime? _scheduledTime;
  Trail? _selectedTrail;
  List<Trail> _trails = [];
  int? _selectedBikeId;
  bool _loading = true;
  double? _userLat;
  double? _userLng;

  @override
  void initState() {
    super.initState();
    _loadTrails();
    _loadUserLocation();
    _initBike();
  }

  Future<void> _initBike() async {
    final savedId = TraxStorageUtil.getSelectedBikeId();
    if (savedId.isNotEmpty) {
      final id = int.tryParse(savedId);
      if (id != null && mounted) setState(() => _selectedBikeId = id);
      return;
    }
    final resp = await TraxApi.getUserBikes();
    if (!mounted || !resp.isSuccess() || resp.data is! List) return;
    final list = resp.data as List;
    if (list.isEmpty) return;
    final firstId = (list.first as Map)['id'];
    if (firstId == null) return;
    final id = (firstId as num).toInt();
    setState(() => _selectedBikeId = id);
    TraxStorageUtil.saveSelectedBikeId(id.toString());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTrails() async {
    final resp = await TraxApi.getTrails();
    if (!mounted) return;
    if (resp.isSuccess() && resp.data is List) {
      final list = (resp.data as List)
          .map((e) => Trail.fromJson(e as Map<String, dynamic>))
          .where((t) => t.type == 'lap')
          .toList();
      setState(() {
        _trails = list;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadUserLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
        );
        if (mounted) {
          setState(() {
            _userLat = pos.latitude;
            _userLng = pos.longitude;
          });
        }
      }
    } catch (_) {}
  }

  double _distanceToTrail(Trail t) {
    if (_userLat == null || _userLng == null || t.startLatitude == null || t.startLongitude == null) {
      return double.infinity;
    }
    return Geolocator.distanceBetween(_userLat!, _userLng!, t.startLatitude!, t.startLongitude!) / 1000;
  }

  String _formatDistance(double km) {
    if (km == double.infinity) return '-';
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1)} km';
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null || !mounted) return;

    setState(() {
      _scheduledTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _onCreate() async {
    if (_nameCtrl.text.trim().isEmpty) {
      showTraxSnackBar(context, 'Please enter a race name', isError: true);
      return;
    }
    if (_selectedTrail == null) {
      showTraxSnackBar(context, 'Please select a trail', isError: true);
      return;
    }

    final data = {
      'name': _nameCtrl.text.trim(),
      'trailId': int.parse(_selectedTrail!.id!),
      'maxParticipants': _maxParticipants,
      'targetLaps': _targetLaps,
      'isPublic': _isPublic,
      if (_selectedBikeId != null) 'bicycleId': _selectedBikeId,
      if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
      if (_scheduledTime != null) 'scheduledTime': _scheduledTime!.toIso8601String(),
    };

    final resp = await TraxApi.createRace(data);
    if (!mounted) return;
    if (resp.isSuccess() && resp.data != null) {
      final race = Race.fromJson(resp.data as Map<String, dynamic>);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RaceDetailPage(raceId: race.id)),
      );
    } else {
      showTraxSnackBar(context, resp.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '402', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: traxTitle('Host Race')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
              children: [
                _buildTextField('Race Name', _nameCtrl, 'e.g. Sunday Sprint'),
                const SizedBox(height: 16),
                _buildTrailPicker(),
                const SizedBox(height: 16),
                const Text('Your Bike',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                BikePickerTile(
                  selectedBikeId: _selectedBikeId,
                  onSelected: (id) => setState(() => _selectedBikeId = id),
                ),
                const SizedBox(height: 16),
                _buildScheduleRow(),
                const SizedBox(height: 16),
                _buildCounterRow('Max Participants', _maxParticipants, 2, 50, (v) {
                  setState(() => _maxParticipants = v);
                }),
                const SizedBox(height: 16),
                _buildCounterRow('Target Laps', _targetLaps, 1, 100, (v) {
                  setState(() => _targetLaps = v);
                }),
                const SizedBox(height: 16),
                _buildToggleRow(),
                const SizedBox(height: 16),
                _buildTextField('Notes (optional)', _notesCtrl, 'Any extra info…',
                    maxLines: 3),
                const SizedBox(height: 32),
                _buildCreateButton(),
              ],
            ),
    );
  }

  Widget _buildTextField(String label, TextEditingController ctrl, String hint,
      {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildTrailPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Trail', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _showTrailPicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedTrail?.name ?? 'Select a trail',
                    style: TextStyle(
                      fontSize: 14,
                      color: _selectedTrail != null ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                ),
                if (_selectedTrail != null)
                  Text(
                    '${_selectedTrail!.distance?.toStringAsFixed(1) ?? '-'} km',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showTrailPicker() async {
    final result = await Navigator.push<Trail>(
      context,
      MaterialPageRoute(
        builder: (_) => TrailPickerPage(
          trails: _trails,
          initialSelection: _selectedTrail,
          userLat: _userLat,
          userLng: _userLng,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _selectedTrail = result);
    }
  }

  Widget _buildScheduleRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Scheduled Time', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _pickDateTime,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.event, color: AppColors.primary, size: 20),
                const SizedBox(width: 10),
                Text(
                  _scheduledTime != null
                      ? DateFormat('MMM d, yyyy · h:mm a').format(_scheduledTime!)
                      : 'Pick date & time',
                  style: TextStyle(
                    fontSize: 14,
                    color: _scheduledTime != null ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCounterRow(String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
        Container(
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove, size: 18),
                onPressed: value > min ? () => onChanged(value - 1) : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              SizedBox(
                width: 36,
                child: Text('$value', textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                onPressed: value < max ? () => onChanged(value + 1) : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToggleRow() {
    return Row(
      children: [
        const Expanded(child: Text('Public Race', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
        Switch.adaptive(
          value: _isPublic,
          activeColor: AppColors.primary,
          onChanged: (v) => setState(() => _isPublic = v),
        ),
      ],
    );
  }

  Widget _buildCreateButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _onCreate,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: const Text('Create Race', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
