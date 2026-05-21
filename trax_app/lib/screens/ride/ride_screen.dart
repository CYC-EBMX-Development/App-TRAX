import 'package:flutter/material.dart';
import '../../models/ebike.dart';
import '../../models/race.dart';
import '../../common/network/trax_api.dart';
import '../../common/utils/trax_storage_util.dart';
import '../../common/widgets/map_router.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../services/active_ride_service.dart';
import '../../theme/app_theme.dart';
import '../garage/trax_module_inquiry_page.dart';
import 'host_laps_page.dart';
import 'host_race_page.dart';
import 'join_race_page.dart';
import 'my_events_page.dart';
import 'observe_race_page.dart';
import 'race_detail_page.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class RideScreen extends StatefulWidget {
  const RideScreen({super.key});

  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> {
  List<EBike> _bikes = [];
  EBike? _selectedBike;
  bool _isLoading = true;
  List<Race> _upcomingEvents = [];

  final _rideSvc = ActiveRideService.instance;

  @override
  void initState() {
    super.initState();
    _rideSvc.addListener(_onRideUpdate);
    _loadBikes();
    _loadUpcomingEvents();
    _rideSvc.checkActiveRide();
  }

  @override
  void dispose() {
    _rideSvc.removeListener(_onRideUpdate);
    super.dispose();
  }

  void _onRideUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _loadBikes() async {
    setState(() => _isLoading = true);
    final response = await TraxApi.getUserBikes();
    if (!mounted) return;
    if (response.isSuccess() && response.data is List) {
      final list = (response.data as List)
          .map((e) => EBike.fromJson(e as Map<String, dynamic>))
          .toList();
      // Restore saved bike selection
      final savedId = TraxStorageUtil.getSelectedBikeId();
      EBike? selected;
      if (savedId.isNotEmpty) {
        selected = list.where((b) => b.id == savedId).firstOrNull;
      }
      setState(() {
        _bikes = list;
        _selectedBike = selected ?? (list.isNotEmpty ? list.first : null);
        _isLoading = false;
      });
      // Persist auto-selected bike so other screens (race pages) can read it.
      if (selected == null && _selectedBike != null) {
        TraxStorageUtil.saveSelectedBikeId(_selectedBike!.id);
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  void _selectBike(EBike bike) {
    setState(() => _selectedBike = bike);
    TraxStorageUtil.saveSelectedBikeId(bike.id);
  }

  bool get _hasActiveRide => _rideSvc.isActive;
  bool get _showActiveRideBanner => _hasActiveRide && _rideSvc.source != 'race' && _activeRace == null;

  Future<void> _loadUpcomingEvents() async {
    final resp = await TraxApi.getUpcomingEvents();
    if (!mounted) return;
    if (resp.isSuccess() && resp.data is List) {
      setState(() {
        _upcomingEvents = (resp.data as List)
            .map((e) => Race.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    }
  }

  Race? get _activeRace {
    try {
      return _upcomingEvents.where((e) => e.isInProgress || e.isPreparing).firstOrNull;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '400', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: traxTitle('Ride'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async {
                await _loadBikes();
                await _loadUpcomingEvents();
              },
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                    16, 8, 16, 32 + MediaQuery.of(context).padding.bottom),
                children: [
                  _buildBikeSelector(),
                  const SizedBox(height: 16),
                  if (_showActiveRideBanner) ...[
                    _buildActiveRide(),
                    const SizedBox(height: 24),
                  ],
                  if (_activeRace != null) ...[
                    _buildActiveRaceCard(_activeRace!),
                    const SizedBox(height: 24),
                  ],
                  _buildRideModes(),
                  const SizedBox(height: 24),
                  _buildMyComingEvents(),
                ],
              ),
            ),
    );
  }

  // ── Bike Selector ──────────────────────────────────────────

  Widget _buildBikeSelector() {
    final hasBike = _selectedBike != null;
    final modelText = _selectedBike?.modelData != null
        ? '${_selectedBike!.modelData!.brand} ${_selectedBike!.modelData!.model}'
        : null;

    return GestureDetector(
      onTap: _bikes.isNotEmpty ? _showBikePicker : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.electric_bike, color: AppColors.primary, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: hasBike
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedBike!.name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (modelText != null)
                          Text(
                            modelText,
                            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    )
                  : const Text(
                      'No bikes yet — add one in Garage',
                      style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                    ),
            ),
            if (_bikes.length > 1)
              const Icon(Icons.unfold_more_rounded, color: AppColors.textSecondary, size: 22),
          ],
        ),
      ),
    );
  }

  void _showBikePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select Bike',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              ..._bikes.map((bike) {
                final isSelected = bike.id == _selectedBike?.id;
                final model = bike.modelData != null
                    ? '${bike.modelData!.brand} ${bike.modelData!.model}'
                    : '';
                return ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.electric_bike,
                      color: isSelected ? AppColors.primary : AppColors.textSecondary,
                      size: 22,
                    ),
                  ),
                  title: Text(
                    bike.name,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: model.isNotEmpty
                      ? Text(model, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))
                      : null,
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: AppColors.primary, size: 22)
                      : null,
                  onTap: () {
                    _selectBike(bike);
                    Navigator.pop(ctx);
                  },
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // ── Active Ride Banner ─────────────────────────────────────

  Widget _buildActiveRide() {
    final stats = _rideSvc.stats;
    final duration = _rideSvc.displayDuration;
    final distance = stats?.distanceKm ?? 0;
    final statusText = _rideSvc.rideStatus == 'paused' ? 'Paused' : 'In Progress';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.explore, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Free Ride',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 11,
                        color: _rideSvc.rideStatus == 'paused' ? AppColors.textSecondary : AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatDuration(duration)} · ${distance.toStringAsFixed(1)} km',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              if (_selectedBike == null) return;
              MapRouter.openFreeRide(
                context,
                selectedBike: _rideSvc.bike ?? _selectedBike!,
              );
            },
            style: TextButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Continue', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Ride Modes 2×2 Grid ────────────────────────────────────

  Widget _buildRideModes() {
    final noBike = _selectedBike == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ride Modes',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _RideModeCard(
                icon: Icons.explore,
                title: 'Free Ride',
                subtitle: 'Record your route',
                disabled: noBike || _hasActiveRide,
                onTap: () => _onRideModeTap('Free Ride', blockByActive: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _RideModeCard(
                icon: Icons.timer,
                title: 'Lap Timer',
                subtitle: 'Personal laps',
                disabled: noBike || _hasActiveRide,
                onTap: () => _onRideModeTap('Lap Timer', blockByActive: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _RideModeCard(
                icon: Icons.flag_circle,
                title: 'Host Laps',
                subtitle: 'Group lap challenge',
                disabled: noBike,
                onTap: () => _onRideModeTap('Host Laps'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _RideModeCard(
                icon: Icons.emoji_events,
                title: 'Host Race',
                subtitle: 'Create a group race',
                disabled: noBike,
                onTap: () => _onRideModeTap('Host Race'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _RideModeCard(
                icon: Icons.group_add,
                title: 'Join Game',
                subtitle: 'Join a race or laps',
                disabled: noBike,
                onTap: () => _onRideModeTap('Join Game'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _RideModeCard(
                icon: Icons.visibility,
                title: 'Watch Game',
                subtitle: 'Spectate a live game',
                disabled: false,
                onTap: () => _onRideModeTap('Watch Game'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _onRideModeTap(String mode, {bool blockByActive = false}) {
    // Watch Game is the only mode that doesn't require a bike.
    if (_selectedBike == null && mode != 'Watch Game' && mode != 'Watch Race') {
      _promptAddBike();
      return;
    }
    if (blockByActive && _hasActiveRide) {
      showTraxSnackBar(context, 'Finish your current ride first');
      return;
    }
    if (mode == 'Free Ride') {
      MapRouter.openFreeRide(context, selectedBike: _selectedBike!);
      return;
    }
    if (mode == 'Lap Timer') {
      _startLapTimerFlow();
      return;
    }
    if (mode == 'Host Race') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const HostRacePage()),
      ).then((_) => _loadUpcomingEvents());
      return;
    }
    if (mode == 'Host Laps') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const HostLapsPage()),
      ).then((_) => _loadUpcomingEvents());
      return;
    }
    if (mode == 'Join Race' || mode == 'Join Game') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const JoinRacePage()),
      ).then((_) => _loadUpcomingEvents());
      return;
    }
    if (mode == 'Watch Race' || mode == 'Watch Game') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ObserveRacePage()),
      ).then((_) => _loadUpcomingEvents());
      return;
    }
    showTraxSnackBar(context, '$mode — Coming soon');
  }

  /// Open Lap Timer setup page where user picks trail, laps, and start location.
  void _startLapTimerFlow() {
    MapRouter.openLapTimerSetup(context, selectedBike: _selectedBike!);
  }

  /// Show a confirm dialog when the user taps a ride mode but has no bike
  /// configured. On confirm, push the Add-a-new-bike flow and refresh on return.
  Future<void> _promptAddBike() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No bike configured'),
        content: const Text(
          'You need to add a bike before you can start riding. '
          'Would you like to configure one now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TraxModuleInquiryPage()),
    );
    if (!mounted) return;
    // Refresh bikes (and selected bike) after returning from the add-bike flow.
    await _loadBikes();
  }

  // ── Active Race Card ───────────────────────────────────────

  Widget _buildActiveRaceCard(Race race) {
    final canEnterTracking = race.isPreparing || race.isInProgress;
    final cardColor = race.isPreparing ? Colors.orange : AppColors.success;
    final statusText = race.isPreparing ? 'Preparing' : 'Racing';

    return GestureDetector(
      onTap: () {
        _openEventByStatus(race);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cardColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: cardColor.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(Icons.emoji_events, color: cardColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(race.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Text(statusText, style: TextStyle(fontSize: 11, color: cardColor)),
                  ]),
                  const SizedBox(height: 2),
                  Text('${race.trailName ?? '-'} · ${race.targetLaps} laps',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                _openEventByStatus(race);
              },
              style: TextButton.styleFrom(
                backgroundColor: cardColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(canEnterTracking ? 'Continue' : 'View', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  // ── My Coming Events ───────────────────────────────────────

  Widget _buildMyComingEvents() {
    // Show max 3 upcoming/in-progress events
    final events = _upcomingEvents.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('My Coming Events',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MyEventsPage()),
                ).then((_) => _loadUpcomingEvents());
              },
              child: const Text('More', style: TextStyle(color: AppColors.primary, fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (events.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('No upcoming events', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
          ),
        ...events.map(_buildEventCard),
      ],
    );
  }

  Widget _buildEventCard(Race race) {
    final isHosted = race.myRole == 'host';
    final isObserver = race.myRole == 'observer';

    String roleLabel;
    Color roleColor;
    if (isHosted) {
      if (race.isPreparing) {
        roleLabel = 'Preparing';
        roleColor = Colors.orange;
      } else if (race.isInProgress) {
        roleLabel = 'Racing';
        roleColor = AppColors.success;
      } else {
        roleLabel = 'Hosted';
        roleColor = AppColors.primary;
      }
    } else if (isObserver) {
      roleLabel = race.isInProgress ? 'Live' : race.isPreparing ? 'Preparing' : 'Booked';
      roleColor = race.isInProgress ? AppColors.success : race.isPreparing ? Colors.orange : Colors.blueGrey;
    } else {
      if (race.isPreparing) {
        roleLabel = 'Preparing';
        roleColor = Colors.orange;
      } else if (race.isInProgress) {
        roleLabel = 'Racing';
        roleColor = AppColors.success;
      } else {
        roleLabel = 'Joined';
        roleColor = AppColors.success;
      }
    }

    return GestureDetector(
      onTap: () {
        _openEventByStatus(race);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: roleColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isHosted ? Icons.emoji_events : isObserver ? Icons.visibility : Icons.group,
                color: roleColor, size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(race.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('${race.trailName ?? '-'} · ${race.targetLaps} laps',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: roleColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(roleLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: roleColor)),
                ),
                const SizedBox(height: 4),
                Text('${race.currentParticipants} riders',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _openEventByStatus(Race race) async {
    await MapRouter.openEventByStatus(context, race);
    if (!mounted) return;
    await _loadUpcomingEvents();
  }
}

// ── Ride Mode Card ─────────────────────────────────────────

class _RideModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool disabled;
  final VoidCallback onTap;

  const _RideModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: disabled ? 0.4 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.primary, size: 26),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
