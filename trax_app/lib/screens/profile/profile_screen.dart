import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common/global/global_user_info.dart';
import '../../common/network/trax_api.dart';
import '../../common/utils/trax_storage_util.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../models/ebike.dart';
import '../../models/ride_record.dart';
import '../../routers/trax_router.dart';
import '../../theme/app_theme.dart';
import '../garage/garage_screen.dart';
import '../session/session_screen.dart';
import 'edit_profile_screen.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  List<RideRecord> _rides = [];
  List<EBike> _bikes = [];
  int _rewardPoints = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      TraxApi.getCurrentUser(),
      TraxApi.getUserRides(),
      TraxApi.getUserBikes(),
    ]);
    if (!mounted) return;

    final meResp = results[0];
    if (meResp.isSuccess() && meResp.data is Map) {
      final m = meResp.data as Map<String, dynamic>;
      GlobalUserInfo.instance.setUserInfo(
        id: (m['id'] as num?)?.toInt(),
        name: (m['username'] as String?) ?? '',
        email: (m['email'] as String?) ?? '',
        avatar: (m['avatarUrl'] as String?) ?? '',
      );
      _rewardPoints = (m['rewardPoints'] as num?)?.toInt() ?? 0;
      // Persist for app-restart restore.
      TraxStorageUtil.saveUserInfo(
        '{"avatarUrl":"${m['avatarUrl'] ?? ''}",'
        '"id":${m['id'] ?? 'null'},'
        '"email":"${m['email'] ?? ''}",'
        '"username":"${m['username'] ?? ''}"}',
      );
    }

    final ridesResp = results[1];
    final rides = (ridesResp.isSuccess() && ridesResp.data is List)
        ? (ridesResp.data as List)
            .map((e) => RideRecord.fromJson(e as Map<String, dynamic>))
            .toList()
        : <RideRecord>[];

    final bikesResp = results[2];
    final bikes = (bikesResp.isSuccess() && bikesResp.data is List)
        ? (bikesResp.data as List)
            .map((e) => EBike.fromJson(e as Map<String, dynamic>))
            .toList()
        : <EBike>[];

    setState(() {
      _rides = rides;
      _bikes = bikes;
      _loading = false;
    });
  }

  // ── derived stats ──
  int get _totalRides => _rides.where((r) => r.status == 'completed').length;

  double get _totalDistanceKm {
    double s = 0;
    for (final r in _rides) {
      s += r.distance ?? 0;
    }
    return s;
  }

  double get _bestSpeedKmh {
    double m = 0;
    for (final r in _rides) {
      if ((r.maxSpeed ?? 0) > m) m = r.maxSpeed!;
    }
    return m;
  }

  String get _distanceLabel {
    final km = _totalDistanceKm;
    if (km >= 100) return '${km.toStringAsFixed(0)} km';
    return '${km.toStringAsFixed(1)} km';
  }

  String get _bestSpeedLabel {
    final v = _bestSpeedKmh;
    if (v <= 0) return '—';
    return '${v.toStringAsFixed(0)} km/h';
  }

  Future<void> _openEditProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const EditProfileScreen()),
    );
    if (mounted) setState(() {}); // GlobalUserInfo updated; rebuild header
  }

  Future<void> _openGarage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GarageScreen()),
    );
    if (mounted) _loadAll();
  }

  Future<void> _openRideHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SessionScreen()),
    );
    if (mounted) _loadAll();
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature coming soon'), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) =>
      PageCodeBadge(code: '300', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: traxTitle('Profile'),
        actions: [
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () {})
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Center(child: _buildHeader()),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ProfileStat('Rides', '$_totalRides'),
                    Container(height: 30, width: 1, color: AppColors.divider),
                    _ProfileStat('Distance', _distanceLabel),
                    Container(height: 30, width: 1, color: AppColors.divider),
                    _ProfileStat('Best', _bestSpeedLabel),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSection('My Gear', [
                _MenuItem(Icons.electric_bike, 'My Bicycles',
                    _bikes.isEmpty ? 'None' : '${_bikes.length} bike${_bikes.length == 1 ? '' : 's'}',
                    onTap: _openGarage),
              ]),
              const SizedBox(height: 8),
              _buildSection('Activity', [
                _MenuItem(Icons.history, 'Ride History',
                    _loading ? '—' : '$_totalRides rides',
                    onTap: _openRideHistory),
                _MenuItem(Icons.star_outline, 'Rewards', '$_rewardPoints pts',
                    onTap: () => _comingSoon('Rewards')),
              ]),
              const SizedBox(height: 8),
              _buildSection('Settings', [
                _MenuItem(Icons.person_outline, 'Edit Profile', '',
                    onTap: _openEditProfile),
                _MenuItem(Icons.language, 'Language', 'English',
                    onTap: () => _comingSoon('Language settings')),
                _MenuItem(Icons.notifications_outlined, 'Notifications', '',
                    onTap: () => _comingSoon('Notification settings')),
                _MenuItem(Icons.help_outline, 'Help & Support', '',
                    onTap: () => _comingSoon('Help & Support')),
              ]),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      TraxStorageUtil.clearAll();
                      GlobalUserInfo.instance.clear();
                      TraxRouter.toWelcomePageOffAll();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                    child: const Text('Log Out',
                        style: TextStyle(fontWeight: FontWeight.w500)),
                  ),
                ),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Obx(() {
      final info = GlobalUserInfo.instance;
      final avatar = info.avatar.value;
      final hasAvatar = avatar.isNotEmpty &&
          Uri.tryParse(avatar)?.hasScheme == true;
      final name = info.name.value.isEmpty ? 'TRAX Rider' : info.name.value;
      final email = info.email.value;
      final letter = name.isNotEmpty ? name[0].toUpperCase() : 'T';
      return Column(
        children: [
          CircleAvatar(
            radius: 48,
            backgroundColor: AppColors.primary,
            backgroundImage: hasAvatar ? NetworkImage(avatar) : null,
            child: !hasAvatar
                ? Text(letter,
                    style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: Colors.white))
                : null,
          ),
          const SizedBox(height: 12),
          Text(name,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(email,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
        ],
      );
    });
  }

  Widget _buildSection(String title, List<_MenuItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: items.map((item) {
              return Column(
                children: [
                  ListTile(
                    leading:
                        Icon(item.icon, color: AppColors.primary, size: 22),
                    title: Text(item.title,
                        style: const TextStyle(fontSize: 14)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.subtitle.isNotEmpty)
                          Text(item.subtitle,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right,
                            size: 18, color: AppColors.textSecondary),
                      ],
                    ),
                    onTap: item.onTap ?? () {},
                  ),
                  if (item != items.last)
                    const Divider(height: 1, indent: 56),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final String label, value;
  const _ProfileStat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  _MenuItem(this.icon, this.title, this.subtitle, {this.onTap});
}
