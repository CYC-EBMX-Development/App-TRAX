import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common/global/global_user_info.dart';
import '../../common/network/trax_api.dart';
import '../../common/services/app_update_service.dart';
import '../../common/utils/trax_storage_util.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../models/ebike.dart';
import '../../models/ride_record.dart';
import '../../routers/trax_router.dart';
import '../../theme/app_theme.dart';
import '../garage/garage_screen.dart';
import '../session/session_screen.dart';
import 'change_password_screen.dart';
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
  AppUpdateStatus? _updateStatus;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    final s = await AppUpdateService.instance.checkForUpdate();
    if (mounted) setState(() => _updateStatus = s);
    // Opening the Profile counts as "user has seen the update" — persist
    // this so the home avatar badge stays off until a *newer* release
    // appears. Done after the check completes so the service knows which
    // release code to remember.
    await AppUpdateService.instance.markUpdateSeen();
  }

  String _versionTileSubtitle() {
    final s = _updateStatus;
    if (s == null) return 'Checking…';
    if (s.hasUpdate) {
      final code = s.release!.latestCode;
      return '${s.displayCurrent} → $code';
    }
    return s.displayCurrent;
  }

  Future<void> _onTapVersionTile() async {
    final s = _updateStatus;
    if (s == null) {
      await _checkForUpdate();
      return;
    }
    if (!s.hasUpdate) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('App Version'),
          content: Text(
              'You are on the latest version.\n\nCurrent: ${s.displayCurrent}'
              '${s.release != null ? "\nServer:  ${s.release!.latestCode}" : ""}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                setState(() => _updateStatus = null);
                await _checkForUpdate();
              },
              child: const Text('Check Again'),
            ),
          ],
        ),
      );
      return;
    }
    await _showUpdateDialog(s.release!);
  }

  Future<void> _showUpdateDialog(AppReleaseInfo release) async {
    // iOS distributes via TestFlight; we cannot side-load an IPA, so just
    // tell the user to open TestFlight and update from there.
    if (Platform.isIOS) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Update Available'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'A new version is available on TestFlight.\n\n'
                  'Please open the TestFlight app to update to the latest build.',
                  style: TextStyle(fontSize: 14)),
              const SizedBox(height: 12),
              Text('Latest:   ${release.latestCode}',
                  style: const TextStyle(fontSize: 13)),
              if (release.releasedAt.isNotEmpty)
                Text('Released: ${release.releasedAt}',
                    style: const TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      return;
    }

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('A new version is ready to install.',
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            Text('Build:    ${release.latestCode}',
                style: const TextStyle(fontSize: 13)),
            Text('File:     ${release.filename}',
                style: const TextStyle(fontSize: 13)),
            Text('Size:     ${release.sizeMb} MB',
                style: const TextStyle(fontSize: 13)),
            if (release.releasedAt.isNotEmpty)
              Text('Released: ${release.releasedAt}',
                  style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Update Now'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    await _runDownloadAndInstall(release);
  }

  Future<void> _runDownloadAndInstall(AppReleaseInfo release) async {
    final progress = ValueNotifier<double>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Downloading…'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, p, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: p > 0 ? p : null),
              const SizedBox(height: 12),
              Text('${(p * 100).toStringAsFixed(0)}%'),
            ],
          ),
        ),
      ),
    );
    try {
      await AppUpdateService.instance.downloadAndInstall(
        release,
        onProgress: (recv, total) {
          if (total > 0) progress.value = recv / total;
        },
      );
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      progress.dispose();
    }
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

  Future<void> _openChangePassword() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
    );
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
    showTraxSnackBar(context, '$feature coming soon');
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
                _MenuItem(Icons.lock_outline, 'Change Password', '',
                    onTap: _openChangePassword),
                _MenuItem(Icons.language, 'Language', 'English',
                    onTap: () => _comingSoon('Language settings')),
                _MenuItem(Icons.notifications_outlined, 'Notifications', '',
                    onTap: () => _comingSoon('Notification settings')),
                _MenuItem(Icons.help_outline, 'Help & Support', '',
                    onTap: () => _comingSoon('Help & Support')),
              ]),
              const SizedBox(height: 8),
              _buildSection('About', [
                _MenuItem(
                  Icons.system_update_alt,
                  _updateStatus?.hasUpdate == true
                      ? 'Update Available'
                      : 'App Version',
                  _versionTileSubtitle(),
                  onTap: _onTapVersionTile,
                  highlight: _updateStatus?.hasUpdate == true,
                ),
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
                    leading: Icon(item.icon,
                        color: item.highlight
                            ? AppColors.error
                            : AppColors.primary,
                        size: 22),
                    title: Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: item.highlight
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: item.highlight
                              ? AppColors.error
                              : AppColors.textPrimary,
                        )),
                    subtitle: (item.highlight && item.subtitle.isNotEmpty)
                        ? Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(item.subtitle,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                          )
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.highlight)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: const BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                        if (!item.highlight && item.subtitle.isNotEmpty)
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
  final bool highlight;
  _MenuItem(this.icon, this.title, this.subtitle,
      {this.onTap, this.highlight = false});
}
