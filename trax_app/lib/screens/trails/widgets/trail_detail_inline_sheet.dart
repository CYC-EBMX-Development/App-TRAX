import 'package:flutter/material.dart';

import '../../../common/global/global_user_info.dart';
import '../../../common/network/trax_api.dart';
import '../../../common/services/map_service.dart';
import '../../../common/utils/trax_storage_util.dart';
import '../../../common/widgets/map_router.dart';
import '../../../common/widgets/trax_dialog.dart';
import '../../../models/ebike.dart';
import '../../../models/trail.dart';
import '../../../models/user_checkpoint.dart';
import '../../../theme/app_theme.dart';
import '../../ride/host_laps_page.dart';
import '../../ride/host_race_page.dart';

/// Inline, scaffold-less version of the trail detail body used inside the
/// map screen's draggable bottom sheet. Unlike [TrailDetailPage] this
/// widget renders ONLY the data strips (header / stats / location /
/// checkpoints / lap actions / visibility) — no map header, no AppBar,
/// no PopScope. The host map already supplies the basemap and frame.
///
/// The widget self-loads the per-user checkpoints + reverse-geocoded
/// location for the current trail. When [trail] changes (user picks a
/// different trail in the carousel) it reloads automatically.
class TrailDetailInlineSheet extends StatefulWidget {
  const TrailDetailInlineSheet({
    super.key,
    required this.trail,
    required this.onChanged,
  });

  final Trail trail;

  /// Called when an action inside the sheet mutates server state
  /// (visibility toggled, trail deleted). The host can then refresh
  /// the trail list. Sheet does NOT close itself — the host owns the
  /// open/close state.
  final VoidCallback onChanged;

  @override
  State<TrailDetailInlineSheet> createState() => _TrailDetailInlineSheetState();
}

class _TrailDetailInlineSheetState extends State<TrailDetailInlineSheet> {
  List<UserCheckpoint> _checkpoints = const [];
  String? _locationName;
  late bool _isPublic;
  int? _pointsCount;

  Trail get trail => widget.trail;
  bool get _isOwner => trail.creatorId == GlobalUserInfo.instance.id.value;

  @override
  void initState() {
    super.initState();
    _isPublic = trail.isPublic;
    _locationName = trail.location;
    _loadAll();
  }

  @override
  void didUpdateWidget(covariant TrailDetailInlineSheet old) {
    super.didUpdateWidget(old);
    if (old.trail.id != widget.trail.id) {
      setState(() {
        _isPublic = trail.isPublic;
        _locationName = trail.location;
        _checkpoints = const [];
        _pointsCount = null;
      });
      _loadAll();
    }
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadCheckpoints(),
      _loadPointsCount(),
      _ensureLocationName(),
    ]);
  }

  Future<void> _loadCheckpoints() async {
    final id = int.tryParse(trail.id ?? '');
    if (id == null) return;
    final resp = await TraxApi.getTrailCheckpoints(id);
    if (!mounted) return;
    if (resp.isSuccess() && resp.data is List) {
      final cps = (resp.data as List)
          .map((e) => UserCheckpoint.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.sequenceIndex.compareTo(b.sequenceIndex));
      setState(() => _checkpoints = cps);
    }
  }

  /// Used only to populate the "Points" mini-stat. Failures fall back to
  /// hiding the count rather than blocking the sheet.
  Future<void> _loadPointsCount() async {
    final id = int.tryParse(trail.id ?? '');
    if (id == null) return;
    final resp = await TraxApi.getTrailPoints(id);
    if (!mounted) return;
    if (resp.isSuccess() && resp.data is List) {
      setState(() => _pointsCount = (resp.data as List).length);
    }
  }

  Future<void> _ensureLocationName() async {
    if (_locationName != null && _locationName!.isNotEmpty) return;
    final lat = trail.startLatitude;
    final lng = trail.startLongitude;
    if (lat == null || lng == null) return;
    final addr = await MapService.reverseGeocode(lat, lng);
    if (!mounted) return;
    setState(() {
      _locationName = addr ??
          '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    });
  }

  Future<void> _toggleVisibility(bool value) async {
    final id = int.tryParse(trail.id ?? '');
    if (id == null) return;
    setState(() => _isPublic = value);
    final resp = await TraxApi.updateTrailVisibility(id, value);
    if (!mounted) return;
    if (!resp.isSuccess()) {
      setState(() => _isPublic = !value);
      showTraxSnackBar(context, resp.message ?? 'Failed to update', isError: true);
    } else {
      widget.onChanged();
    }
  }

  Future<void> _confirmDelete() async {
    final id = int.tryParse(trail.id ?? '');
    if (id == null) return;
    TraxDialog.showBottomTipsDialog(
      title: 'Delete Trail',
      content: 'This trail will be permanently removed.',
      mainBtnText: 'Delete',
      mainBtnOnPressed: () async {
        Navigator.of(context).pop();
        final resp = await TraxApi.deleteTrail(id);
        if (!mounted) return;
        if (resp.isSuccess()) {
          widget.onChanged();
        } else {
          showTraxSnackBar(
              context, resp.message ?? 'Failed to delete trail', isError: true);
        }
      },
      subBtnText: 'Cancel',
    );
  }

  // ───── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isLap = trail.type == 'lap';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeaderStrip(),
          const SizedBox(height: 10),
          _buildStatsStrip(),
          const SizedBox(height: 10),
          _buildLocationStrip(),
          const SizedBox(height: 10),
          _buildCheckpointsStrip(),
          if (isLap) ...[
            const SizedBox(height: 12),
            _buildLapActionButtons(),
          ],
          if (_isOwner) ...[
            const SizedBox(height: 10),
            _buildVisibilityStrip(),
          ],
        ],
      ),
    );
  }

  // ───── Strips ───────────────────────────────────────────────────────

  Widget _buildHeaderStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: _stripDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.terrain,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  trail.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
              ),
              _chip(
                label: _isOwner ? 'Owner' : 'Guest',
                color: _isOwner ? AppColors.primary : AppColors.textSecondary,
              ),
              if (_isOwner) ...[
                const SizedBox(width: 4),
                InkResponse(
                  radius: 20,
                  onTap: _confirmDelete,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.delete_outline,
                        color: AppColors.error, size: 20),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(_typeIcon(), size: 13, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(_typeLabel(),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(width: 10),
              _chip(label: _difficultyLabel(), color: _difficultyColor()),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isOwner
                      ? 'Created by you'
                      : 'by ${trail.creatorName ?? "unknown"}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: _stripDecoration(),
      child: Row(
        children: [
          _miniStat(Icons.straighten, 'Distance',
              '${(trail.distance ?? 0).toStringAsFixed(2)} km'),
          _miniStat(Icons.trending_up, 'Elev',
              '${(trail.elevation ?? 0).toStringAsFixed(0)} m'),
          _miniStat(
              Icons.swap_vert,
              'Elev Δ',
              trail.elevationDiff != null
                  ? '${trail.elevationDiff!.toStringAsFixed(0)} m'
                  : '—'),
          _miniStat(Icons.pin_drop, 'Points',
              _pointsCount == null ? '—' : '${_pointsCount!}'),
        ],
      ),
    );
  }

  Widget _miniStat(IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildLocationStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: _stripDecoration(),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _locationName ?? 'Loading…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckpointsStrip() {
    final id = int.tryParse(trail.id ?? '');
    if (id == null) return const SizedBox.shrink();
    final count = _checkpoints.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: _stripDecoration(),
      child: Row(
        children: [
          const Icon(Icons.flag, color: AppColors.warning, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'My Checkpoints  ·  $count / 4',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
          ),
          TextButton(
            onPressed: () async {
              await MapRouter.openTrailCheckpoints(
                context,
                trailId: id,
                trailName: trail.name,
                trailStartLat: trail.startLatitude,
                trailStartLng: trail.startLongitude,
              );
              if (!mounted) return;
              await _loadCheckpoints();
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            child: Text(count == 0 ? 'Configure' : 'Edit'),
          ),
        ],
      ),
    );
  }

  Widget _buildLapActionButtons() {
    return Row(
      children: [
        Expanded(
            child: _lapActionBtn(
                icon: Icons.timer,
                label: 'Lap Timer',
                onTap: _onStartLapTimer)),
        const SizedBox(width: 8),
        Expanded(
            child: _lapActionBtn(
                icon: Icons.groups_outlined,
                label: 'Host Laps',
                onTap: _onHostLaps)),
        const SizedBox(width: 8),
        Expanded(
            child: _lapActionBtn(
                icon: Icons.emoji_events_outlined,
                label: 'Host Race',
                onTap: _onHostRace)),
      ],
    );
  }

  Widget _lapActionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 64,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisibilityStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: _stripDecoration(),
      child: Row(
        children: [
          Icon(
            _isPublic ? Icons.public : Icons.lock_outline,
            color: _isPublic ? AppColors.primary : AppColors.textSecondary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isPublic
                  ? 'Public · Anyone can search this trail'
                  : 'Private · Only you can see this trail',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500),
            ),
          ),
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: _isPublic,
              onChanged: _toggleVisibility,
              activeColor: AppColors.primary,
              activeTrackColor: AppColors.primary.withValues(alpha: 0.5),
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: Colors.grey.shade400,
              trackOutlineColor:
                  WidgetStatePropertyAll(Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }

  // ───── Helpers ──────────────────────────────────────────────────────

  BoxDecoration _stripDecoration() => BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      );

  Widget _chip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  Color _difficultyColor() {
    switch (trail.difficulty.toLowerCase()) {
      case 'easy':
        return AppColors.success;
      case 'medium':
        return AppColors.primary;
      case 'hard':
        return Colors.orange;
      case 'extreme':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  String _difficultyLabel() {
    final d = trail.difficulty;
    if (d.isEmpty) return 'Medium';
    return d[0].toUpperCase() + d.substring(1);
  }

  String _typeLabel() => trail.type == 'lap' ? 'Lap' : 'Free Ride';
  IconData _typeIcon() => trail.type == 'lap' ? Icons.loop : Icons.explore;

  // ───── Lap actions (kept identical to TrailDetailPage) ──────────────

  Future<void> _onHostLaps() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HostLapsPage(initialTrail: trail)),
    );
  }

  Future<void> _onHostRace() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HostRacePage(initialTrail: trail)),
    );
  }

  Future<void> _onStartLapTimer() async {
    final bikesResp = await TraxApi.getUserBikes();
    if (!mounted) return;
    if (!bikesResp.isSuccess() || bikesResp.data is! List) {
      showTraxSnackBar(context, 'Could not load your bikes', isError: true);
      return;
    }
    final bikes = (bikesResp.data as List)
        .map((e) => EBike.fromJson(e as Map<String, dynamic>))
        .toList();
    if (bikes.isEmpty) {
      showTraxSnackBar(context, 'Add a bike in Garage first', isError: true);
      return;
    }
    final bike = await _showBikePickerDialog(bikes);
    if (bike == null || !mounted) return;
    final targetLaps = await _showLapCountDialog();
    if (targetLaps == null || targetLaps <= 0 || !mounted) return;
    MapRouter.openLapTimer(
      context,
      selectedBike: bike,
      trail: trail,
      targetLaps: targetLaps,
    );
  }

  Future<EBike?> _showBikePickerDialog(List<EBike> bikes) {
    final savedId = TraxStorageUtil.getSelectedBikeId();
    final defaultBike = bikes.firstWhere(
      (b) => b.id == savedId,
      orElse: () => bikes.firstWhere(
        (b) => b.traxSerialNumber != null && b.isConnected,
        orElse: () => bikes.first,
      ),
    );
    return showModalBottomSheet<EBike>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).padding.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Select Bike',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            ...bikes.map((b) {
              final hasModule = b.traxSerialNumber != null;
              final isDefault = b.id == defaultBike.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(ctx).pop(b),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isDefault
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDefault
                            ? AppColors.primary
                            : AppColors.textSecondary.withValues(alpha: 0.2),
                        width: isDefault ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.electric_bike,
                            color: hasModule
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(b.name,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary)),
                              Text(
                                hasModule
                                    ? 'TRAX Module: ${b.traxSerialNumber}${b.isConnected ? " · Connected" : ""}'
                                    : 'No TRAX Module (uses phone GPS)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: hasModule
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<int?> _showLapCountDialog() async {
    int laps = 3;
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).padding.bottom + 20),
        child: StatefulBuilder(
          builder: (ctx, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('How many laps?',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              const Text(
                'Your ride will auto-finish after the target is reached.',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _lapCountBtn(
                      icon: Icons.remove,
                      onPressed: laps > 1 ? () => setS(() => laps--) : null),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 28),
                    width: 60,
                    alignment: Alignment.center,
                    child: Text('$laps',
                        style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary)),
                  ),
                  _lapCountBtn(
                      icon: Icons.add,
                      onPressed: laps < 50 ? () => setS(() => laps++) : null),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(laps),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25)),
                  ),
                  child: Text(
                      'Continue with $laps lap${laps == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lapCountBtn({required IconData icon, VoidCallback? onPressed}) {
    final enabled = onPressed != null;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: enabled ? AppColors.primary : AppColors.background,
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled
                ? AppColors.primary
                : AppColors.textSecondary.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(icon,
            size: 24,
            color: enabled ? Colors.white : AppColors.textSecondary),
      ),
    );
  }
}
