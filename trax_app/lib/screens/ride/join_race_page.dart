import 'package:flutter/material.dart';

import '../../common/network/trax_api.dart';
import '../../common/utils/trax_storage_util.dart';
import '../../common/widgets/bike_picker.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../models/race.dart';
import '../../theme/app_theme.dart';
import 'race_detail_page.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class JoinRacePage extends StatefulWidget {
  const JoinRacePage({super.key});

  @override
  State<JoinRacePage> createState() => _JoinRacePageState();
}

class _JoinRacePageState extends State<JoinRacePage> {
  List<Race> _races = [];
  bool _loading = true;
  int? _selectedBikeId;
  final _codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
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
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final resp = await TraxApi.getPublicRaces();
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

  Future<void> _joinByCode() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      showTraxSnackBar(context, 'Enter a join code', isError: true);
      return;
    }
    final resp = await TraxApi.joinByCode(code, role: 'rider', bicycleId: _selectedBikeId);
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
  Widget build(BuildContext context) => PageCodeBadge(code: '403', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: traxTitle('Join Game')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
        children: [
          _buildCodeInput(),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text('Public Games',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
              GestureDetector(
                onTap: () {
                  setState(() => _loading = true);
                  _load();
                },
                child: const Icon(Icons.refresh, size: 22, color: AppColors.textSecondary),
              ),
            ],
          ),
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
          const Text('Join by Code', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
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
                onPressed: _joinByCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                child: const Text('Join', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRaceCard(Race race) {
    return GestureDetector(
      onTap: () async {
        final resp = await TraxApi.getRace(race.id);
        if (!mounted) return;
        if (!resp.isSuccess() || resp.data == null) {
          showTraxSnackBar(context, resp.message, isError: true);
          return;
        }
        final latest = Race.fromJson(resp.data as Map<String, dynamic>);
        if (!latest.isPublic) {
          showTraxSnackBar(context, 'This game is now private', isError: true);
          _load();
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RaceDetailPage(raceId: race.id)),
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
                color: (race.isLaps ? AppColors.warning : AppColors.primary).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                race.isLaps ? Icons.flag_circle : Icons.emoji_events,
                color: race.isLaps ? AppColors.warning : AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(race.name,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      _gameTypePill(race.isLaps),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${race.trailName ?? '-'} · ${race.targetLaps} laps · ${race.currentParticipants}/${race.maxParticipants} riders',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  if (race.hostName != null)
                    Text('by ${race.hostName}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _gameTypePill(bool isLaps) {
    final color = isLaps ? AppColors.warning : AppColors.primary;
    final label = isLaps ? 'LAPS' : 'RACE';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w800, color: color)),
    );
  }
}
