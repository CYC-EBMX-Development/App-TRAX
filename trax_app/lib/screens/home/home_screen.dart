import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../common/global/global_user_info.dart';
import '../../common/network/trax_api.dart';
import '../../common/services/app_update_service.dart';
import '../../common/services/map_provider.dart';
import '../../common/widgets/app_update_prompt.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../models/ebike.dart';
import '../../models/race.dart';
import '../../models/ride_record.dart';
import '../../models/trail.dart';
import '../../theme/app_theme.dart';
import '../garage/trax_module_inquiry_page.dart';
import '../profile/profile_screen.dart';
import '../ride/host_race_page.dart';
import '../ride/my_events_page.dart';
import '../ride/ride_detail_page.dart';
import '../ride/ride_screen.dart';
import '../../common/widgets/map_router.dart';
// TrailRecordPage now routed via MapRouter (see ../common/widgets/map_router.dart)
import 'package:trax_app/common/widgets/page_code_badge.dart';

class HomeScreen extends StatefulWidget {
  /// Optional callback to switch the parent bottom-nav tab.
  /// Index matches `MainScreen._pages` (0=Home, 1=Session, 3=Trails, 4=Garage).
  final void Function(int index)? onSwitchTab;

  const HomeScreen({super.key, this.onSwitchTab});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  /// Public refresh hook invoked by the bottom-nav.
  Future<void> refresh() => _loadAll();

  static IconData _iconForMode(MapProviderMode m) => switch (m) {
        MapProviderMode.auto => Icons.auto_awesome,
        MapProviderMode.forceGoogle => Icons.public,
        MapProviderMode.forceAmap => Icons.map_outlined,
      };

  static String _labelForMode(MapProviderMode m) => switch (m) {
        MapProviderMode.auto => 'Default (auto)',
        MapProviderMode.forceGoogle => 'Google Maps',
        MapProviderMode.forceAmap => 'AMap (高德)',
      };

  static PopupMenuItem<MapProviderMode> _mapModeItem(
      MapProviderMode item, MapProviderMode current, IconData icon, String label) {
    final selected = item == current;
    return PopupMenuItem<MapProviderMode>(
      value: item,
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textPrimary),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          if (selected) const Icon(Icons.check, size: 18, color: AppColors.primary),
        ],
      ),
    );
  }

  bool _loading = true;
  List<RideRecord> _rides = [];
  List<Trail> _trails = [];
  List<Race> _events = [];
  List<EBike> _bikes = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
    // Run the OTA check eagerly so the avatar badge reflects the real
    // server state from the moment the Home screen renders, instead of
    // only after the user taps the avatar. We also auto-prompt the user
    // once per process / per new build via AppUpdatePrompt.maybeShowOnHome.
    AppUpdateService.instance.checkForUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppUpdatePrompt.maybeShowOnHome(context);
    });
  }

  Future<void> _loadAll() async {
    if (mounted) setState(() => _loading = true);
    final results = await Future.wait([
      TraxApi.getUserRides(),
      TraxApi.getTrails(),
      TraxApi.getUpcomingEvents(),
      TraxApi.getUserBikes(),
    ]);
    if (!mounted) return;
    final ridesResp = results[0];
    final trailsResp = results[1];
    final eventsResp = results[2];
    final bikesResp = results[3];

    final rides = (ridesResp.isSuccess() && ridesResp.data is List)
        ? (ridesResp.data as List)
            .map((e) => RideRecord.fromJson(e as Map<String, dynamic>))
            .toList()
        : <RideRecord>[];
    rides.sort((a, b) {
      final at = a.startTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.startTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });

    final trails = (trailsResp.isSuccess() && trailsResp.data is List)
        ? (trailsResp.data as List)
            .map((e) => Trail.fromJson(e as Map<String, dynamic>))
            .toList()
        : <Trail>[];

    final events = (eventsResp.isSuccess() && eventsResp.data is List)
        ? (eventsResp.data as List)
            .map((e) => Race.fromJson(e as Map<String, dynamic>))
            .toList()
        : <Race>[];

    final bikes = (bikesResp.isSuccess() && bikesResp.data is List)
        ? (bikesResp.data as List)
            .map((e) => EBike.fromJson(e as Map<String, dynamic>))
            .toList()
        : <EBike>[];

    setState(() {
      _rides = rides;
      _trails = trails;
      _events = events;
      _bikes = bikes;
      _loading = false;
    });
  }

  // ── stats derived from rides ──
  int get _totalRides => _rides.where((r) => r.status == 'completed').length;

  double get _totalDistanceKm {
    double sum = 0;
    for (final r in _rides) {
      sum += r.distance ?? 0;
    }
    return sum;
  }

  int get _totalSeconds {
    int s = 0;
    for (final r in _rides) {
      s += r.durationSeconds ?? 0;
    }
    return s;
  }

  String get _distanceLabel {
    final km = _totalDistanceKm;
    if (km >= 100) return '${km.toStringAsFixed(0)} km';
    return '${km.toStringAsFixed(1)} km';
  }

  String get _timeLabel {
    final h = _totalSeconds / 3600;
    if (h >= 10) return '${h.toStringAsFixed(0)}h';
    if (h >= 1) return '${h.toStringAsFixed(1)}h';
    final m = (_totalSeconds / 60).round();
    return '${m}m';
  }

  // ── navigation handlers ──
  Future<void> _openRideTab() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RideScreen()),
    );
    if (mounted) _loadAll();
  }

  Future<void> _openMyEvents() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MyEventsPage()),
    );
    if (mounted) _loadAll();
  }

  Future<void> _startRide() async {
    if (_bikes.isEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TraxModuleInquiryPage()),
      );
      if (mounted) _loadAll();
      return;
    }
    await MapRouter.openFreeRide(context, selectedBike: _bikes.first);
    if (mounted) _loadAll();
  }

  Future<void> _createTrail() async {
    await MapRouter.openTrailRecord(context);
    if (mounted) _loadAll();
  }

  Future<void> _hostEvent() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HostRacePage()),
    );
    if (mounted) _loadAll();
  }

  Future<void> _openRideDetail(RideRecord r) async {
    final id = int.tryParse(r.id ?? '');
    if (id == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RideDetailPage(rideId: id)),
    );
    if (mounted) _loadAll();
  }

  void _openTrailDetail(Trail t) {
    MapRouter.openTrailDetail(context, t);
  }

  @override
  Widget build(BuildContext context) =>
      PageCodeBadge(code: '101', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              // Persist that the user has acknowledged the pending
              // update so the badge stays off after they return from
              // Profile, until the server publishes a newer release.
              await AppUpdateService.instance.markUpdateSeen();
              if (!context.mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
            child: Center(
              child: Obx(() {
                final avatar = GlobalUserInfo.instance.avatar.value;
                final hasAvatar = avatar.isNotEmpty &&
                    avatar != 'null' &&
                    Uri.tryParse(avatar)?.hasScheme == true;
                final name = GlobalUserInfo.instance.name.value;
                final letter = name.isNotEmpty ? name[0].toUpperCase() : 'T';
                return ValueListenableBuilder<bool>(
                  valueListenable:
                      AppUpdateService.instance.hasUpdateAvailable,
                  builder: (context, hasUpdate, _) {
                    final avatarWidget = CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.primary,
                      backgroundImage:
                          hasAvatar ? NetworkImage(avatar) : null,
                      child: !hasAvatar
                          ? Text(
                              letter,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white),
                            )
                          : null,
                    );
                    if (!hasUpdate) return avatarWidget;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        avatarWidget,
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Theme.of(context)
                                      .scaffoldBackgroundColor,
                                  width: 1.5),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              }),
            ),
          ),
        ),
        title: traxTitle('TRAX',
            style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 4)),
        actions: [
          ValueListenableBuilder<MapProvider>(
            valueListenable: MapProviderService.providerNotifier,
            builder: (context, _, __) {
              final mode = MapProviderService.mode;
              return PopupMenuButton<MapProviderMode>(
                tooltip: 'Map provider',
                icon: Icon(_iconForMode(mode), size: 22),
                onSelected: (m) async {
                  await MapProviderService.setMode(m);
                  if (!context.mounted) return;
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.clearSnackBars();
                  messenger.showSnackBar(
                    SnackBar(
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      content: Text('Map provider: ${_labelForMode(m)}'),
                    ),
                  );
                },
                itemBuilder: (context) => [
                  _mapModeItem(MapProviderMode.auto, mode,
                      Icons.auto_awesome, 'Default (auto)'),
                  _mapModeItem(MapProviderMode.forceGoogle, mode,
                      Icons.public, 'Google Maps'),
                  _mapModeItem(MapProviderMode.forceAmap, mode,
                      Icons.map_outlined, 'AMap (高德)'),
                ],
              );
            },
          ),
          IconButton(
              icon: const Icon(Icons.notifications_outlined), onPressed: () {}),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeBanner(),
              const SizedBox(height: 24),
              _SectionHeader(
                  title: 'Recent Rides',
                  onSeeAll: _rides.isEmpty ? null : () => widget.onSwitchTab?.call(1)),
              const SizedBox(height: 12),
              _buildRecentRides(),
              const SizedBox(height: 24),
              _SectionHeader(
                  title: 'Featured Trails',
                  onSeeAll: _trails.isEmpty ? null : () => widget.onSwitchTab?.call(3)),
              const SizedBox(height: 12),
              _buildFeaturedTrails(),
              const SizedBox(height: 24),
              _SectionHeader(
                  title: 'Upcoming Events',
                  onSeeAll: _events.isEmpty ? null : _openMyEvents),
              const SizedBox(height: 12),
              _buildUpcomingEvents(),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeBanner() {
    final name = GlobalUserInfo.instance.name.value;
    final greeting = name.isNotEmpty ? 'Welcome Back, $name!' : 'Welcome Back!';
    final subtitle = _totalRides == 0
        ? 'Start your first ride today.'
        : 'Ready for your next ride?';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(greeting,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(
                  fontSize: 14, color: Colors.white.withValues(alpha: 0.9))),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatItem(label: 'Rides', value: '$_totalRides'),
              const SizedBox(width: 32),
              _StatItem(label: 'Distance', value: _distanceLabel),
              const SizedBox(width: 32),
              _StatItem(label: 'Time', value: _timeLabel),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentRides() {
    if (_loading) {
      return const SizedBox(
          height: 160,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_rides.isEmpty) {
      return _EmptyStateCard(
        icon: Icons.directions_bike_outlined,
        message: 'No rides yet. Hit the road and create your first one!',
        ctaLabel: 'Start a Ride',
        onTap: _startRide,
      );
    }
    final items = _rides.take(5).toList();
    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) => _RideCard(
          ride: items[index],
          onTap: () => _openRideDetail(items[index]),
        ),
      ),
    );
  }

  Widget _buildFeaturedTrails() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_trails.isEmpty) {
      return _EmptyStateCard(
        icon: Icons.alt_route,
        message: 'No trails yet. Record one to share with the community.',
        ctaLabel: 'Create a Trail',
        onTap: _createTrail,
      );
    }
    final items = _trails.take(3).toList();
    return Column(
      children: [
        for (final t in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _TrailPreviewCard(
              trail: t,
              onTap: () => _openTrailDetail(t),
            ),
          ),
      ],
    );
  }

  Widget _buildUpcomingEvents() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_events.isEmpty) {
      return _EmptyStateCard(
        icon: Icons.emoji_events_outlined,
        message: 'No upcoming events. Host one and invite your friends.',
        ctaLabel: 'Host an Event',
        onTap: _hostEvent,
      );
    }
    return Column(
      children: [
        for (final r in _events.take(2))
          Card(
            child: ListTile(
              onTap: _openRideTab,
              leading: const CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Icon(Icons.flag, color: Colors.white),
              ),
              title: Text(r.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(_eventSubtitle(r)),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
      ],
    );
  }

  String _eventSubtitle(Race r) {
    final parts = <String>[];
    if (r.trailName != null && r.trailName!.isNotEmpty) parts.add(r.trailName!);
    if (r.scheduledTime != null) {
      parts.add(_formatScheduledTime(r.scheduledTime!));
    }
    parts.add('${r.currentParticipants}/${r.maxParticipants} riders');
    return parts.join(' · ');
  }

  String _formatScheduledTime(DateTime t) {
    final now = DateTime.now();
    final d = t.difference(now);
    if (d.inMinutes.abs() < 60) return 'In ${d.inMinutes}m';
    if (d.inHours.abs() < 24) return 'In ${d.inHours}h';
    return '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

// ── helpers ──────────────────────────────────────────

String _formatDistance(double? km) {
  if (km == null || km <= 0) return '—';
  if (km < 10) return '${km.toStringAsFixed(1)} km';
  return '${km.toStringAsFixed(0)} km';
}

String _formatDuration(int? seconds) {
  if (seconds == null || seconds <= 0) return '—';
  final m = seconds ~/ 60;
  if (m < 60) return '$m min';
  final h = m ~/ 60;
  final rm = m % 60;
  return rm == 0 ? '${h}h' : '${h}h ${rm}m';
}

String _formatRelativeDate(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(t.year, t.month, t.day);
  final days = today.difference(that).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  return '${t.month}/${t.day}';
}

IconData _trailIcon(Trail t) {
  switch (t.difficulty.toLowerCase()) {
    case 'easy':
      return Icons.water;
    case 'medium':
      return Icons.landscape;
    case 'hard':
    case 'extreme':
      return Icons.terrain;
    default:
      return Icons.alt_route;
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  const _SectionHeader({required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            child: const Text('See all',
                style: TextStyle(fontSize: 13, color: AppColors.primary)),
          ),
      ],
    );
  }
}

class _RideCard extends StatelessWidget {
  final RideRecord ride;
  final VoidCallback? onTap;
  const _RideCard({required this.ride, this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = (ride.trailName != null && ride.trailName!.isNotEmpty)
        ? ride.trailName!
        : (ride.source == 'lap_timer'
            ? 'Lap Session'
            : (ride.source == 'race' ? 'Race Ride' : 'Free Ride'));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.route, color: AppColors.primary, size: 28),
            const Spacer(),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 4),
            Text(
              '${_formatDistance(ride.distance)} · ${_formatDuration(ride.durationSeconds)}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 2),
            Text(_formatRelativeDate(ride.startTime),
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _TrailPreviewCard extends StatelessWidget {
  final Trail trail;
  final VoidCallback? onTap;
  const _TrailPreviewCard({required this.trail, this.onTap});

  @override
  Widget build(BuildContext context) {
    final difficulty = trail.difficulty.isEmpty
        ? 'Medium'
        : '${trail.difficulty[0].toUpperCase()}${trail.difficulty.substring(1)}';
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(_trailIcon(trail), color: AppColors.primary),
        ),
        title: Text(trail.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text('$difficulty · ${_formatDistance(trail.distance)}'),
        trailing: const Icon(Icons.chevron_right,
            color: AppColors.textSecondary),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String message;
  final String ctaLabel;
  final VoidCallback onTap;
  const _EmptyStateCard({
    required this.icon,
    required this.message,
    required this.ctaLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.15), width: 1),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.add, size: 18),
              label: Text(ctaLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
