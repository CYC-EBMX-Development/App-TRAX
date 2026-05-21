import 'package:flutter/material.dart';

import '../../common/network/trax_api.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../models/race.dart';
import '../../theme/app_theme.dart';
import 'race_detail_page.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class ObserveRacePage extends StatefulWidget {
  const ObserveRacePage({super.key});

  @override
  State<ObserveRacePage> createState() => _ObserveRacePageState();
}

class _ObserveRacePageState extends State<ObserveRacePage> {
  List<Race> _races = [];
  bool _loading = true;
  final _codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final resp = await TraxApi.getPublicRacesForObserver();
    if (!mounted) return;
    if (resp.isSuccess() && resp.data is List) {
      setState(() {
        _races = (resp.data as List)
            .map((e) => Race.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _observeByCode() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      showTraxSnackBar(context, 'Enter a join code', isError: true);
      return;
    }
    final resp = await TraxApi.joinByCode(code, role: 'observer');
    if (!mounted) return;
    if (resp.isSuccess() && resp.data != null) {
      final race = Race.fromJson(resp.data as Map<String, dynamic>);
      Navigator.of(context).pushReplacement(
        // Unified event navigation
        MapRouter.openEventByStatus(context, race),
      );
    } else {
      showTraxSnackBar(context, resp.message, isError: true);
    }
  }

  Future<void> _observeRace(Race race) async {
    final resp = await TraxApi.observeRace(race.id);
    if (!mounted) return;
    if (resp.isSuccess()) {
      Navigator.of(context).pushReplacement(
        // Unified event navigation
        MapRouter.openEventByStatus(context, race),
      );
    } else {
      showTraxSnackBar(context, resp.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '407', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: traxTitle('Watch Game')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
        children: [
          _buildCodeInput(),
          const SizedBox(height: 24),
          const Text('Public Games',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: AppColors.primary),
            )),
          if (!_loading && _races.isEmpty)
            const Center(child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('No public games available', style: TextStyle(color: AppColors.textSecondary)),
            )),
          ..._races.map(_buildRaceCard),
        ],
      ),
    );
  }

  Widget _buildCodeInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Watch by Code', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 4),
                  decoration: InputDecoration(
                    hintText: '',
                    counterText: '',
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _observeByCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                child: const Text('Watch', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRaceCard(Race race) {
    final statusColor = race.isInProgress ? AppColors.success : AppColors.primary;
    final statusLabel = race.isInProgress ? 'Live' : 'Waiting';

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          // Unified event navigation
          MapRouter.openEventByStatus(context, race),
        ).then((_) => _load());
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
              child: Icon(
                race.isInProgress ? Icons.live_tv : Icons.emoji_events,
                color: statusColor, size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(race.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (race.isLaps ? AppColors.warning : AppColors.primary).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: (race.isLaps ? AppColors.warning : AppColors.primary).withValues(alpha: 0.4)),
                        ),
                        child: Text(race.isLaps ? 'LAPS' : 'RACE',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: race.isLaps ? AppColors.warning : AppColors.primary)),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                        child: Text(statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${race.trailName ?? '-'} · ${race.targetLaps} laps · ${race.currentParticipants} riders',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 22),
          ],
        ),
      ),
    );
  }
}
