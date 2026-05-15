import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/trail.dart';
import '../../common/network/trax_api.dart';
import '../../common/services/map_service.dart';
import '../../common/utils/trail_thumbnail.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../theme/app_theme.dart';
import '../../common/widgets/map_router.dart';
// TrailRecordPage now routed via MapRouter.
import 'package:trax_app/common/widgets/page_code_badge.dart';

class TrailsScreen extends StatefulWidget {
  const TrailsScreen({super.key});

  @override
  State<TrailsScreen> createState() => TrailsScreenState();
}

class TrailsScreenState extends State<TrailsScreen> {
  /// Public refresh hook invoked by the bottom-nav.
  Future<void> refresh() => _load();

  List<Trail> _trails = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final resp = await TraxApi.getTrails();
    if (!mounted) return;
    if (resp.isSuccess() && resp.data is List) {
      final trails = (resp.data as List)
          .map((e) => Trail.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _trails = trails;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _goToRecordTrail() async {
    final saved = await MapRouter.openTrailRecord(context);
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) =>
      PageCodeBadge(code: '600', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: traxTitle('Trails'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
            onPressed: _goToRecordTrail,
            tooltip: 'Record Trail',
          ),
        ],
      ),
      body: _buildTrailList(),
    );
  }

  Widget _buildTrailList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_trails.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
            const Center(
              child: Column(
                children: [
                  Icon(Icons.terrain, size: 64, color: AppColors.textSecondary),
                  SizedBox(height: 12),
                  Text('No trails yet',
                      style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
                  SizedBox(height: 4),
                  Text('Tap + to record a new trail',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _trails.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _TrailCard(
            trail: _trails[index],
            onTap: () async {
              final changed = await MapRouter.openTrailDetail(context, _trails[index]);
              if (changed == true) _load();
            },
          ),
        ),
      ),
    );
  }
}

// ── Trail Card ───────────────────────────────────────────

class _TrailCard extends StatefulWidget {
  final Trail trail;
  final VoidCallback onTap;
  const _TrailCard({required this.trail, required this.onTap});

  @override
  State<_TrailCard> createState() => _TrailCardState();
}

class _TrailCardState extends State<_TrailCard> {
  String? _location;
  Uint8List? _thumbBytes;
  bool _thumbFailed = false;

  Trail get trail => widget.trail;

  @override
  void initState() {
    super.initState();
    _location = trail.location;
    if (_location == null || _location!.isEmpty) {
      _geocode();
    }
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    final id = int.tryParse(trail.id ?? '');
    if (id == null) return;
    final result = await loadTrailThumbnail(id, serverImageUrl: trail.imageUrl);
    if (!mounted) return;
    if (result.bytes != null) {
      setState(() => _thumbBytes = result.bytes);
    } else if (result.failed) {
      setState(() => _thumbFailed = true);
    }
  }

  Future<void> _geocode() async {
    final lat = trail.startLatitude;
    final lng = trail.startLongitude;
    if (lat == null || lng == null) return;
    final address = await MapService.reverseGeocode(lat, lng);
    if (address != null && mounted) {
      setState(() => _location = address);
    }
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

  @override
  Widget build(BuildContext context) {
    final isLap = trail.type == 'lap';
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildThumbnail(),
            const SizedBox(width: 12),
            Expanded(child: _buildDetails(isLap)),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    Widget child;
    if (_thumbBytes != null) {
      child = Image.memory(
        _thumbBytes!,
        width: 88,
        height: 88,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } else if (_thumbFailed) {
      child = const Center(
        child: Icon(Icons.terrain, color: AppColors.primary, size: 28),
      );
    } else {
      child = const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.primary),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 88,
        height: 88,
        color: AppColors.primary.withValues(alpha: 0.08),
        child: child,
      ),
    );
  }

  Widget _buildDetails(bool isLap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Name + difficulty
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(trail.name,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(isLap ? 'Lap' : 'Free Ride',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _difficultyColor().withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_difficultyLabel(),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _difficultyColor())),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Divider(height: 1, color: AppColors.divider),
        const SizedBox(height: 8),
        // Stats row
        Row(
          children: [
            Expanded(
                child: _MiniStat(isLap ? Icons.loop : Icons.explore,
                    isLap ? 'Lap' : 'Free')),
            Expanded(
                child: _MiniStat(Icons.straighten,
                    '${(trail.distance ?? 0).toStringAsFixed(2)} km')),
            Expanded(
                child: _MiniStat(Icons.trending_up,
                    '${(trail.elevation ?? 0).toStringAsFixed(0)} m')),
          ],
        ),
        if (_location != null && _location!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.location_on,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _location!,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 6),
        Row(
          children: [
            CircleAvatar(
              radius: 10,
              backgroundImage: trail.creatorAvatarUrl != null &&
                      trail.creatorAvatarUrl!.isNotEmpty
                  ? NetworkImage(trail.creatorAvatarUrl!)
                  : null,
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              child: trail.creatorAvatarUrl == null ||
                      trail.creatorAvatarUrl!.isEmpty
                  ? const Icon(Icons.person,
                      size: 12, color: AppColors.primary)
                  : null,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                trail.creatorName ?? 'Unknown',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
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
