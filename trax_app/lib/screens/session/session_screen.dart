import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../common/network/trax_api.dart';
import '../../common/widgets/page_code_badge.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../models/ride_record.dart';
import '../../theme/app_theme.dart';
import '../ride/race_detail_page.dart';
import '../ride/ride_detail_page.dart';

/// Bottom-tab "Session" page: lists the current user's completed rides
/// using the same card style as the previous Trails › Rides tab.
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

enum _RideTypeFilter { all, freeRide, lapTimer, race, laps }

bool _isLapsRace(RideRecord r) =>
    r.source == 'race' && (r.gameType ?? 'RACE').toUpperCase() == 'LAPS';
bool _isPureRace(RideRecord r) =>
    r.source == 'race' && (r.gameType ?? 'RACE').toUpperCase() != 'LAPS';

class _SessionScreenState extends State<SessionScreen> {
  bool _isLoading = true;
  List<RideRecord> _rides = [];
  _RideTypeFilter _filter = _RideTypeFilter.all;

  List<RideRecord> get _filtered {
    switch (_filter) {
      case _RideTypeFilter.freeRide:
        return _rides
            .where((r) => r.source == 'free_ride' || (r.source == null && r.trailId == null))
            .toList();
      case _RideTypeFilter.lapTimer:
        return _rides
            .where((r) => r.source == 'lap_timer' || (r.source == null && r.trailId != null))
            .toList();
      case _RideTypeFilter.race:
        return _rides.where(_isPureRace).toList();
      case _RideTypeFilter.laps:
        return _rides.where(_isLapsRace).toList();
      case _RideTypeFilter.all:
        return _rides;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final resp = await TraxApi.getUserRides();
    if (!mounted) return;
    if (resp.isSuccess() && resp.data is List) {
      final all = (resp.data as List)
          .map((e) => RideRecord.fromJson(e as Map<String, dynamic>))
          .where((r) => r.status == 'completed')
          .toList();
      all.sort((a, b) {
        final at = a.startTime?.millisecondsSinceEpoch ?? 0;
        final bt = b.startTime?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });
      setState(() {
        _rides = all;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  String _filterLabel() {
    switch (_filter) {
      case _RideTypeFilter.freeRide:
        return 'Free Ride';
      case _RideTypeFilter.lapTimer:
        return 'Lap Timer';
      case _RideTypeFilter.race:
        return 'Race';
      case _RideTypeFilter.laps:
        return 'Laps';
      case _RideTypeFilter.all:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) =>
      PageCodeBadge(code: '500', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: traxTitle('Session')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    final freeCount = _rides
        .where((r) => r.source == 'free_ride' || (r.source == null && r.trailId == null))
        .length;
    final lapCount = _rides
        .where((r) => r.source == 'lap_timer' || (r.source == null && r.trailId != null))
        .length;
    final raceCount = _rides.where(_isPureRace).length;
    final lapsCount = _rides.where(_isLapsRace).length;
    final filtered = _filtered;

    return Column(
      children: [
        if (_rides.isNotEmpty)
          _buildFilterRow(freeCount, lapCount, raceCount, lapsCount),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _load,
            child: filtered.isEmpty
                ? ListView(
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                      Center(
                        child: Column(
                          children: [
                            const Icon(Icons.explore_off,
                                size: 64, color: AppColors.textSecondary),
                            const SizedBox(height: 12),
                            Text(
                              _rides.isEmpty
                                  ? 'No sessions yet'
                                  : 'No ${_filterLabel()} sessions',
                              style: const TextStyle(
                                  fontSize: 16, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Start a ride to see your history here',
                              style: TextStyle(
                                  fontSize: 13, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RideCard(
                        ride: filtered[index],
                        onTap: () => _openRide(filtered[index]),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _openRide(RideRecord ride) async {
    final rideId = int.tryParse(ride.id ?? '');
    if (ride.source == 'race' && ride.raceId != null) {
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
            builder: (_) => RaceDetailPage(raceId: ride.raceId!)),
      );
      if (changed == true) _load();
      return;
    }
    if (rideId != null) {
      final deleted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => RideDetailPage(rideId: rideId)),
      );
      if (deleted == true) _load();
    }
  }

  Widget _buildFilterRow(int freeCount, int lapCount, int raceCount, int lapsCount) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          _FilterChip(
            label: 'All',
            count: _rides.length,
            selected: _filter == _RideTypeFilter.all,
            onTap: () => setState(() => _filter = _RideTypeFilter.all),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Free Ride',
            icon: Icons.explore,
            count: freeCount,
            selected: _filter == _RideTypeFilter.freeRide,
            onTap: () => setState(() => _filter = _RideTypeFilter.freeRide),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Lap Timer',
            icon: Icons.timer,
            count: lapCount,
            selected: _filter == _RideTypeFilter.lapTimer,
            onTap: () => setState(() => _filter = _RideTypeFilter.lapTimer),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Race',
            icon: Icons.flag,
            count: raceCount,
            selected: _filter == _RideTypeFilter.race,
            onTap: () => setState(() => _filter = _RideTypeFilter.race),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Laps',
            icon: Icons.repeat,
            count: lapsCount,
            selected: _filter == _RideTypeFilter.laps,
            onTap: () => setState(() => _filter = _RideTypeFilter.laps),
          ),
        ],
      ),
    );
  }
}

// ── Ride Card ────────────────────────────────────────────

class _RideCard extends StatelessWidget {
  final RideRecord ride;
  final VoidCallback onTap;
  const _RideCard({required this.ride, required this.onTap});

  bool get _isLapTimer => ride.source == 'lap_timer' ||
      (ride.source == null && ride.trailId != null);
  bool get _isRaceLaps =>
      ride.source == 'race' && (ride.gameType ?? 'RACE').toUpperCase() == 'LAPS';
  bool get _isRacePure =>
      ride.source == 'race' && !_isRaceLaps;
  bool get _hasLapInfo => _isLapTimer || _isRaceLaps || _isRacePure;

  String get _typeLabel {
    if (_isRaceLaps) return 'Laps';
    if (_isRacePure) return 'Race';
    if (_isLapTimer) return 'Lap Timer';
    return 'Free Ride';
  }

  IconData get _typeIcon {
    if (_isRaceLaps) return Icons.repeat;
    if (_isRacePure) return Icons.flag;
    if (_isLapTimer) return Icons.timer;
    return Icons.explore;
  }

  Color get _accentColor {
    if (_isRacePure) return AppColors.error;
    if (_isRaceLaps) return AppColors.warning;
    if (_isLapTimer) return AppColors.primary;
    return AppColors.success;
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');
    final dateStr =
        ride.startTime != null ? dateFormat.format(ride.startTime!) : '--';
    final startStr =
        ride.startTime != null ? timeFormat.format(ride.startTime!) : '';
    final endStr =
        ride.endTime != null ? timeFormat.format(ride.endTime!) : '';
    final timeRange = startStr.isNotEmpty ? '$startStr — $endStr' : '';
    final duration = ride.durationSeconds;
    final durationStr = duration != null ? _formatDuration(duration) : '--';

    final typeColor = _accentColor;
    final typeIcon = _typeIcon;
    final typeLabel = _typeLabel;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border(
            left: BorderSide(
              color: _accentColor,
              width: 3,
            ),
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(typeIcon, color: typeColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(typeLabel,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                          if (_hasLapInfo && (ride.targetLaps != null || ride.completedLaps != null)) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: typeColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${ride.completedLaps ?? 0}/${ride.targetLaps ?? '?'} laps',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: typeColor),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _hasLapInfo && ride.trailName != null
                            ? '${ride.trailName} · ${ride.bicycleName ?? 'Unknown Bike'}'
                            : (ride.bicycleName ?? 'Unknown Bike'),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(dateStr,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                    if (timeRange.isNotEmpty)
                      Text(timeRange,
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.textSecondary)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _hasLapInfo
                  ? [
                      _MiniStat(Icons.access_time, durationStr),
                      _MiniStat(Icons.straighten,
                          '${(ride.distance ?? 0).toStringAsFixed(2)} km'),
                      _MiniStat(Icons.flag,
                          '${ride.completedLaps ?? 0}/${ride.targetLaps ?? '?'}'),
                      _MiniStat(Icons.flash_on,
                          '${(ride.maxSpeed ?? 0).toStringAsFixed(1)} km/h'),
                    ]
                  : [
                      _MiniStat(Icons.access_time, durationStr),
                      _MiniStat(Icons.straighten,
                          '${(ride.distance ?? 0).toStringAsFixed(2)} km'),
                      _MiniStat(Icons.speed,
                          '${(ride.avgSpeed ?? 0).toStringAsFixed(1)} km/h'),
                      _MiniStat(Icons.flash_on,
                          '${(ride.maxSpeed ?? 0).toStringAsFixed(1)} km/h'),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  const _MiniStat(this.icon, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(value,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary)),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    this.icon,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.textSecondary;
    final bg = selected ? AppColors.primary : AppColors.surface;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.25)
                    : AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
