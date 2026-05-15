import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../common/network/trax_api.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../models/race.dart';
import '../../theme/app_theme.dart';
import 'race_detail_page.dart';
import '../../common/widgets/map_router.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class MyEventsPage extends StatefulWidget {
  const MyEventsPage({super.key});

  @override
  State<MyEventsPage> createState() => _MyEventsPageState();
}

class _MyEventsPageState extends State<MyEventsPage> {
  final List<Race> _events = [];
  bool _loading = true;
  bool _hasMore = true;
  int _page = 0;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadPage();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200 && !_loading && _hasMore) {
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    setState(() => _loading = true);
    final resp = await TraxApi.getMyEvents(page: _page, size: 20);
    if (!mounted) return;
    if (resp.isSuccess() && resp.data != null) {
      final pageData = resp.data as Map<String, dynamic>;
      final content = (pageData['content'] as List?) ?? [];
      final races = content.map((e) => Race.fromJson(e as Map<String, dynamic>)).toList();
      setState(() {
        _events.addAll(races);
        _hasMore = !(pageData['last'] as bool? ?? true);
        _page++;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '406', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: traxTitle('My Events')),
      body: _events.isEmpty && !_loading
          ? const Center(child: Text('No events yet', style: TextStyle(color: AppColors.textSecondary, fontSize: 15)))
          : ListView.builder(
              controller: _scrollCtrl,
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
              itemCount: _events.length + (_loading ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i >= _events.length) {
                  return const Center(child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ));
                }
                return _buildEventCard(_events[i]);
              },
            ),
    );
  }

  Widget _buildEventCard(Race race) {
    final statusColor = switch (race.status) {
      'waiting' => AppColors.primary,
      'preparing' => Colors.orange,
      'in_progress' => AppColors.success,
      'completed' => AppColors.textSecondary,
      'canceled' => AppColors.error,
      _ => AppColors.textSecondary,
    };
    final statusLabel = switch (race.status) {
      'waiting' => 'Upcoming',
      'preparing' => 'Preparing',
      'in_progress' => 'In Progress',
      'completed' => 'Completed',
      'canceled' => 'Canceled',
      _ => race.status,
    };

    final roleColor = switch (race.myRole) {
      'host' => AppColors.primary,
      'rider' => AppColors.success,
      'observer' => Colors.blueGrey,
      _ => AppColors.textSecondary,
    };
    final roleLabel = switch (race.myRole) {
      'host' => 'Hosted',
      'rider' => 'Joined',
      'observer' => 'Observe',
      _ => '',
    };

    return GestureDetector(
      onTap: () {
        if (race.isPreparing && (race.isHost || race.isRider)) {
          MapRouter.openRaceTracking(context, raceId: race.id);
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => RaceDetailPage(raceId: race.id)),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.emoji_events, color: statusColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(race.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    '${race.trailName ?? '-'} · ${race.targetLaps} laps',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  if (race.scheduledTime != null)
                    Text(
                      DateFormat('MMM d, yyyy · h:mm a').format(race.scheduledTime!),
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
                ),
                const SizedBox(height: 4),
                if (roleLabel.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: roleColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(roleLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: roleColor)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
