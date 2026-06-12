import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../common/network/trax_api.dart';
import '../../common/global/global_user_info.dart';
import '../../common/utils/trax_storage_util.dart';
import '../../common/widgets/bike_info_dialog.dart';
import '../../common/widgets/bike_picker.dart';
import '../../common/widgets/trax_dialog.dart';
import '../../common/widgets/trax_refresh_button.dart';
import '../../models/race.dart';
import '../../models/race_live_data.dart';
import '../../models/ride_lap.dart';
import '../../models/trail.dart';
import '../../theme/app_theme.dart';
import '../../widgets/lap_splits_grid.dart';
import '../../common/widgets/map_router.dart';
import '../../common/widgets/race_live_mini_map.dart';
import '../../common/widgets/route_preview_map.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'trail_picker_page.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

/// Unified Race Detail page for host, rider, and watcher.
class RaceDetailPage extends StatefulWidget {
  final int raceId;
  const RaceDetailPage({super.key, required this.raceId});

  @override
  State<RaceDetailPage> createState() => _RaceDetailPageState();
}

class _RaceDetailPageState extends State<RaceDetailPage> {
  Race? _race;
  RaceLiveData? _liveData;
  bool _loading = true;
  Timer? _pollTimer;
  int? _selectedBikeId;
  bool _bikePrefilled = false;
  bool _infoExpanded = true;
  bool _showMoreRanks = false;

  // LAPS-mode UI state
  _LapsTab _lapsTab = _LapsTab.leaderboard;
  bool _showMockRiders = false;
  List<RiderLiveInfo>? _mockRiders;

  // RACE-mode UI state
  _RaceTab _raceTab = _RaceTab.leaderboard;
  bool _showMockRaceRiders = false;
  List<RiderLiveInfo>? _mockRaceRiders;

  // Trail polyline shown above the lobby (waiting/preparing) so all
  // participants can see, drag and zoom the route while they wait.
  List<gmap.LatLng> _trailRoute = const [];
  int? _trailRouteForTrailId;

  // Rider colors for map markers / labels
  static const _riderColors = [
    Colors.blue, Colors.red, Colors.green, Colors.purple,
    Colors.orange, Colors.teal, Colors.pink, Colors.indigo,
  ];

  @override
  void initState() {
    super.initState();
    final savedId = TraxStorageUtil.getSelectedBikeId();
    if (savedId.isNotEmpty) {
      _selectedBikeId = int.tryParse(savedId);
    }
    _load();
    if (_selectedBikeId == null) _initBikeFallback();
  }

  Future<void> _initBikeFallback() async {
    final resp = await TraxApi.getUserBikes();
    if (!mounted || !resp.isSuccess() || resp.data is! List) return;
    final list = resp.data as List;
    if (list.isEmpty) return;
    final firstId = (list.first as Map)['id'];
    if (firstId == null) return;
    final id = (firstId as num).toInt();
    if (_selectedBikeId == null) {
      setState(() => _selectedBikeId = id);
      TraxStorageUtil.saveSelectedBikeId(id.toString());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final resp = await TraxApi.getRace(widget.raceId);
    if (!mounted) return;
    if (!resp.isSuccess() || resp.data == null) {
      setState(() => _loading = false);
      return;
    }
    final race = Race.fromJson(resp.data as Map<String, dynamic>);

    // For in_progress / completed races, fetch live data BEFORE first paint
    // to avoid flashing a half-loaded layout (no map markers, no leaderboard).
    RaceLiveData? live;
    if (race.isInProgress || race.isCompleted) {
      final lResp = await TraxApi.getRaceLive(widget.raceId);
      if (!mounted) return;
      if (lResp.isSuccess() && lResp.data != null) {
        live = RaceLiveData.fromJson(lResp.data as Map<String, dynamic>);
      }
    }

    setState(() {
      _race = race;
      if (live != null) _liveData = live;
      _loading = false;
    });
    _prefillBikeIfNeeded();
    _ensureTrailRouteLoaded();
    _startPolling();
  }

  void _prefillBikeIfNeeded() {
    if (_bikePrefilled || _race == null) return;
    final myId = GlobalUserInfo.instance.id.value;
    if (myId == null) return;
    final me = _race!.participants
        .where((p) => p.userId == myId)
        .firstOrNull;
    if (me?.bicycleId != null) {
      _selectedBikeId = me!.bicycleId;
      _bikePrefilled = true;
    }
  }

  Future<void> _onChangeBike(int? bikeId) async {
    setState(() => _selectedBikeId = bikeId);
    final resp =
        await TraxApi.setRaceBike(widget.raceId, bicycleId: bikeId);
    if (!mounted) return;
    if (resp.isSuccess()) {
      showTraxSnackBar(context, bikeId == null ? 'Bike cleared' : 'Bike updated');
      _load();
    } else {
      showTraxSnackBar(context, resp.message, isError: true);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  Future<void> _poll() async {
    // Always refresh race metadata
    final rResp = await TraxApi.getRace(widget.raceId);
    if (!mounted) return;
    if (rResp.isSuccess() && rResp.data != null) {
      setState(() => _race = Race.fromJson(rResp.data as Map<String, dynamic>));
      _prefillBikeIfNeeded();
      _ensureTrailRouteLoaded();
    }

    // If in_progress or completed, fetch live data
    if (_race != null && (_race!.isInProgress || _race!.isCompleted)) {
      final lResp = await TraxApi.getRaceLive(widget.raceId);
      if (!mounted) return;
      if (lResp.isSuccess() && lResp.data != null) {
        setState(() => _liveData = RaceLiveData.fromJson(lResp.data as Map<String, dynamic>));
      }
    }

    // Stop polling if completed or canceled
    if (_race != null && (_race!.isCompleted || _race!.isCanceled)) {
      _pollTimer?.cancel();
    }
  }

  // ── Actions ────────────────────────────────────────────

  Future<void> _onStartRace() async {
    final ok = await TraxDialog.confirm(context,
        title: 'Start Race',
        message: 'Enter the preparation phase. Riders will be asked to ready up.');
    if (ok != true || !mounted) return;
    final resp = await TraxApi.startRaceEvent(widget.raceId);
    if (!mounted) return;
    if (resp.isSuccess()) {
      MapRouter.openRaceTracking(
        context,
        raceId: widget.raceId,
        isObserver: _race?.isObserver ?? false,
        replace: true,
      );
    } else {
      showTraxSnackBar(context, resp.message, isError: true);
    }
  }

  Future<void> _onStopRace() async {
    final ok = await TraxDialog.confirm(context,
        title: 'Stop Race',
        message: 'This will end the race. Riders with incomplete laps will be marked DNF.');
    if (ok != true || !mounted) return;
    final resp = await TraxApi.stopRaceEvent(widget.raceId);
    if (!mounted) return;
    if (resp.isSuccess()) {
      showTraxSnackBar(context, 'Race stopped');
    } else {
      showTraxSnackBar(context, resp.message, isError: true);
    }
  }

  Future<void> _onCancelRace() async {
    final ok = await TraxDialog.confirm(context,
        title: 'Cancel Race',
        message: 'This will cancel the race for all participants.');
    if (ok != true || !mounted) return;
    final resp = await TraxApi.cancelRaceEvent(widget.raceId);
    if (!mounted) return;
    if (resp.isSuccess()) {
      showTraxSnackBar(context, 'Race canceled');
      Navigator.of(context).pop();
    } else {
      showTraxSnackBar(context, resp.message, isError: true);
    }
  }

  Future<void> _onQuitRace() async {
    final ok = await TraxDialog.confirm(context,
        title: 'Quit Race',
        message: 'You will leave this race.');
    if (ok != true || !mounted) return;
    final resp = await TraxApi.quitRace(widget.raceId);
    if (!mounted) return;
    if (resp.isSuccess()) {
      showTraxSnackBar(context, 'Left the race');
      Navigator.of(context).pop();
    } else {
      showTraxSnackBar(context, resp.message, isError: true);
    }
  }

  /// Returns my own rideId for this race (if any), so I can delete just my record.
  int? get _myRideId {
    final myId = GlobalUserInfo.instance.id.value;
    if (myId == null || _race == null) return null;
    for (final p in _race!.participants) {
      if (p.userId == myId && p.rideId != null) return p.rideId;
    }
    return null;
  }

  Future<void> _onDeleteMyRecord() async {
    final rideId = _myRideId;
    if (rideId == null) return;
    final ok = await TraxDialog.confirm(context,
        title: 'Delete My Race Record',
        message:
            'This removes only your own ride record from this race. Other riders\u2019 records will not be affected.');
    if (ok != true || !mounted) return;
    final resp = await TraxApi.deleteRide(rideId);
    if (!mounted) return;
    if (resp.isSuccess()) {
      showTraxSnackBar(context, 'Your race record was deleted');
      Navigator.of(context).pop(true);
      return;
    } else {
      showTraxSnackBar(context, resp.message, isError: true);
    }
  }

  Future<void> _onJoinRace() async {
    final resp = await TraxApi.joinRace(widget.raceId, bicycleId: _selectedBikeId);
    if (!mounted) return;
    if (resp.isSuccess()) {
      showTraxSnackBar(context, 'Joined the race!');
      _load();
    } else {
      showTraxSnackBar(context, resp.message, isError: true);
    }
  }

  void _copyJoinCode() {
    if (_race == null) return;
    Clipboard.setData(ClipboardData(text: _race!.joinCode));
    showTraxSnackBar(context, 'Join code copied: ${_race!.joinCode}');
  }

  Future<void> _onToggleType(bool newValue) async {
    // Optimistic update for instant UI feedback
    if (_race != null) {
      setState(() => _race = _race!.copyWith(isPublic: newValue));
    }
    final resp = await TraxApi.updateRaceType(widget.raceId, newValue);
    if (!mounted) return;
    if (!resp.isSuccess()) {
      // Revert on failure
      setState(() => _race = _race!.copyWith(isPublic: !newValue));
      showTraxSnackBar(context, resp.message, isError: true);
    }
  }

  Widget _buildTypeToggle(Race race) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(race.isPublic ? Icons.public : Icons.lock, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          const Text('Type: ', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          GestureDetector(
            onTap: () => _onToggleType(!race.isPublic),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: race.isPublic
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : Colors.grey.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: race.isPublic ? AppColors.primary : Colors.grey,
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    race.isPublic ? 'Public' : 'Private',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: race.isPublic ? AppColors.primaryDark : Colors.grey[700],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.swap_horiz, size: 14,
                      color: race.isPublic ? AppColors.primaryDark : Colors.grey[700]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '408', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: traxTitle(_race?.name ?? 'Race Detail'),
        actions: _buildAppBarActions(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _race == null
              ? const Center(child: Text('Race not found'))
              : _buildBody(),
    );
  }

  /// Compact top-right actions for the Race Detail AppBar. Mirrors the
  /// Ride Detail layout (circular Play + Delete buttons) so Replay Race
  /// and Delete My Race Record live in the same spot across screens.
  List<Widget> _buildAppBarActions() {
    final race = _race;
    if (race == null || !race.isCompleted) return const [];
    final canReplay = _liveData != null && _liveData!.riders.isNotEmpty;
    final canAnalyze = _myRideId != null;
    final canDelete = _myRideId != null;
    return [
      if (canReplay)
        Container(
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.play_circle_outline, color: AppColors.primary),
            tooltip: 'Replay Race',
            onPressed: _onReplayRace,
          ),
        ),
      if (canAnalyze)
        Container(
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.insights_outlined, color: AppColors.primary),
            tooltip: 'Analyze My Ride',
            onPressed: _onAnalyzeMyRide,
          ),
        ),
      if (canDelete)
        Container(
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.error),
            tooltip: 'Delete My Race Record',
            onPressed: _onDeleteMyRecord,
          ),
        ),
    ];
  }

  Widget _buildBody() {
    final race = _race!;
    return Column(
      children: [
        // Map area:
        //  - waiting/preparing: trail preview (drag + zoom)
        //  - in_progress/completed: live race mini-map
        if (race.isInProgress || race.isCompleted)
          _buildMap()
        else if (race.trailId != null)
          _buildLobbyTrailMap(race),
        // Bottom scrollable content
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildInfoCard(race),
              if (race.isLaps && race.trailId != null &&
                  (race.isHost || race.isRider) &&
                  (race.isWaiting || race.isPreparing)) ...[
                const SizedBox(height: 12),
                _buildMyCheckpointsCard(race),
              ],
              if (!race.isCompleted) ...[
                const SizedBox(height: 12),
                _buildJoinCodeCard(race),
              ],
              // Suppress the Results podium card on completion for both
              // LAPS and RACE modes — the tabbed Leaderboard below already
              // surfaces the top 3.
              if (!race.isCompleted) ...[
                const SizedBox(height: 12),
                _buildParticipantsCard(race),
              ],
              if (_liveData != null && _liveData!.riders.isNotEmpty) ...[
                const SizedBox(height: 12),
                if (race.isLaps)
                  _buildLapsTabbedCard()
                else
                  _buildLeaderboard(),
              ],
              const SizedBox(height: 16),
              _buildActionButtons(race),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }

  // ── Map ────────────────────────────────────────────────

  Widget _buildMap() {
    final riders = <RaceLiveRider>[];
    if (_liveData != null) {
      final latestAligned = _liveData!.alignedFrames.isNotEmpty
          ? _liveData!.alignedFrames.last
          : null;
      final alignedPos = <int, List<double>>{
        if (latestAligned != null)
          for (final p in latestAligned.riders) p.userId: [p.latitude, p.longitude],
      };
      for (int i = 0; i < _liveData!.riders.length; i++) {
        final r = _liveData!.riders[i];
        final pos = alignedPos[r.userId];
        riders.add(RaceLiveRider(
          userId: r.userId,
          name: r.userName ?? 'Rider ${i + 1}',
          latitude: pos?[0] ?? r.latitude,
          longitude: pos?[1] ?? r.longitude,
          completedLaps: r.completedLaps,
          distanceKm: r.distanceKm,
          color: _riderColors[i % _riderColors.length],
        ));
      }
    }
    return RaceLiveMiniMap(
      riders: riders,
      targetLaps: _race?.targetLaps ?? 0,
    );
  }

  /// Trail preview shown above the lobby (waiting / preparing). Drag-able
  /// and zoom-able so participants can inspect the route while they wait.
  Widget _buildLobbyTrailMap(Race race) {
    if (_trailRoute.isEmpty) {
      return Container(
        height: 220,
        color: AppColors.surface,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
              strokeWidth: 2.4, color: AppColors.primary),
        ),
      );
    }
    return SizedBox(
      height: 240,
      child: RoutePreviewMap(
        route: _trailRoute,
        gesturesEnabled: true,
      ),
    );
  }

  Future<void> _ensureTrailRouteLoaded() async {
    final race = _race;
    if (race == null) return;
    final tid = race.trailId;
    if (tid == null) return;
    if (_trailRouteForTrailId == tid && _trailRoute.isNotEmpty) return;
    final resp = await TraxApi.getTrailPoints(tid);
    if (!mounted) return;
    if (!resp.isSuccess() || resp.data is! List) return;
    final pts = <gmap.LatLng>[];
    for (final p in resp.data as List) {
      final m = p as Map<String, dynamic>;
      pts.add(gmap.LatLng(
        (m['latitude'] as num).toDouble(),
        (m['longitude'] as num).toDouble(),
      ));
    }
    setState(() {
      _trailRoute = pts;
      _trailRouteForTrailId = tid;
    });
  }

  // ── Info Card ──────────────────────────────────────────

  Widget _buildInfoCard(Race race) {
    final statusColor = switch (race.status) {
      'waiting' => AppColors.primary,
      'preparing' => Colors.orange,
      'in_progress' => AppColors.success,
      'completed' => AppColors.textSecondary,
      'canceled' => AppColors.error,
      _ => AppColors.textSecondary,
    };
    final statusLabel = switch (race.status) {
      'waiting' => 'Waiting',
      'preparing' => 'Preparing',
      'in_progress' => 'In Progress',
      'completed' => 'Completed',
      'canceled' => 'Canceled',
      _ => race.status,
    };

    final canCollapse = race.isCompleted;
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
          InkWell(
            onTap: canCollapse
                ? () => setState(() => _infoExpanded = !_infoExpanded)
                : null,
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(race.name,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (race.isLaps) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                          ),
                          child: const Text('LAPS',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.warning)),
                        ),
                      ] else ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                          ),
                          child: const Text('RACE',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.primary)),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor)),
                ),
                if (canCollapse) ...[
                  const SizedBox(width: 6),
                  Icon(
                    _infoExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary,
                  ),
                ],
              ],
            ),
          ),
          if (canCollapse && !_infoExpanded)
            const SizedBox.shrink()
          else ...[
            const SizedBox(height: 10),
          _infoRow(Icons.person, 'Host', race.hostName ?? 'Unknown'),
          _editableRow(
            Icons.route,
            'Trail',
            '${race.trailName ?? '-'} (${race.trailDistance?.toStringAsFixed(1) ?? '-'} km)',
            editable: _canEditSettings(race),
            onTap: _editTrail,
          ),
          _editableRow(
            Icons.flag,
            'Laps',
            '${race.targetLaps}',
            editable: _canEditSettings(race),
            onTap: () => _editIntField(
                title: 'Target Laps',
                current: race.targetLaps,
                min: 1,
                max: 100,
                save: (v) => TraxApi.updateRaceSettings(widget.raceId,
                    targetLaps: v)),
          ),
          _editableRow(
            Icons.group,
            'Riders',
            '${race.currentParticipants}/${race.maxParticipants}',
            editable: _canEditSettings(race),
            onTap: () => _editIntField(
                title: 'Max Riders',
                current: race.maxParticipants,
                min: race.currentParticipants < 2 ? 2 : race.currentParticipants,
                max: 50,
                save: (v) => TraxApi.updateRaceSettings(widget.raceId,
                    maxParticipants: v)),
          ),
          if ((race.isHost && race.isWaiting) || (race.isHost && race.isPreparing))
            _buildTypeToggle(race)
          else
            _infoRow(race.isPublic ? Icons.public : Icons.lock, 'Type', race.isPublic ? 'Public' : 'Private'),
          if (_canEditSettings(race))
            _editableRow(
              Icons.event,
              'Scheduled',
              race.scheduledTime != null
                  ? DateFormat('MMM d, yyyy · h:mm a').format(race.scheduledTime!)
                  : 'Not scheduled',
              editable: true,
              onTap: _editSchedule,
            )
          else if (race.scheduledTime != null)
            _infoRow(Icons.event, 'Scheduled', DateFormat('MMM d, yyyy · h:mm a').format(race.scheduledTime!)),
          if (race.notes != null && race.notes!.isNotEmpty)
            _infoRow(Icons.notes, 'Notes', race.notes!),
          if (_liveData != null && _liveData!.elapsedSeconds > 0)
            _infoRow(Icons.timer, 'Elapsed', _fmtDuration(_liveData!.elapsedSeconds)),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary))),
        ],
      ),
    );
  }

  bool _canEditSettings(Race race) =>
      race.isHost && (race.isWaiting || race.isPreparing);

  Widget _editableRow(IconData icon, String label, String value,
      {required bool editable, required VoidCallback onTap}) {
    if (!editable) return _infoRow(icon, label, value);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text('$label: ',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textPrimary)),
            ),
            const Icon(Icons.edit, size: 14, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  Future<void> _applySettings(
      Future<dynamic> Function() fn, String successMsg) async {
    final resp = await fn();
    if (!mounted) return;
    if (resp.isSuccess()) {
      showTraxSnackBar(context, successMsg);
      _load();
    } else {
      showTraxSnackBar(context, resp.message, isError: true);
    }
  }

  Future<void> _editIntField({
    required String title,
    required int current,
    required int min,
    required int max,
    required Future<dynamic> Function(int value) save,
  }) async {
    int value = current.clamp(min, max);
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(title),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                color: AppColors.primary,
                onPressed: value > min
                    ? () => setSt(() => value--)
                    : null,
              ),
              SizedBox(
                width: 60,
                child: Text('$value',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                color: AppColors.primary,
                onPressed: value < max
                    ? () => setSt(() => value++)
                    : null,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, value),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (result == null || result == current) return;
    await _applySettings(() => save(result), '$title updated');
  }

  Future<void> _editTrail() async {
    final resp = await TraxApi.getTrails();
    if (!mounted) return;
    if (!resp.isSuccess() || resp.data is! List) {
      showTraxSnackBar(context, resp.message, isError: true);
      return;
    }
    final trails = (resp.data as List)
        .map((e) => Trail.fromJson(e as Map<String, dynamic>))
        .toList();
    Trail? current;
    if (_race?.trailId != null) {
      current = trails
          .where((t) => t.id == _race!.trailId.toString())
          .firstOrNull;
    }
    final picked = await Navigator.push<Trail>(
      context,
      MaterialPageRoute(
        builder: (_) => TrailPickerPage(
          trails: trails,
          initialSelection: current,
        ),
      ),
    );
    if (picked == null || picked.id == null) return;
    final newId = int.tryParse(picked.id!);
    if (newId == null || newId == _race?.trailId) return;
    await _applySettings(
        () => TraxApi.updateRaceSettings(widget.raceId, trailId: newId),
        'Trail updated');
  }

  Future<void> _editSchedule() async {
    final initialDate = _race?.scheduledTime ??
        DateTime.now().add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (time == null || !mounted) return;
    final dt = DateTime(
        date.year, date.month, date.day, time.hour, time.minute);
    await _applySettings(
        () => TraxApi.updateRaceSettings(widget.raceId,
            scheduledTime: dt.toIso8601String()),
        'Schedule updated');
  }

  // ── My Checkpoints (LAPS lobby) ─────────────────────────

  Widget _buildMyCheckpointsCard(Race race) {
    return Container(
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
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.flag, color: AppColors.warning, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My Checkpoints',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                SizedBox(height: 2),
                Text('Place up to 4 personal CPs along this trail',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => MapRouter.openTrailCheckpoints(
              context,
              trailId: race.trailId!,
              trailName: race.trailName,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: const Text('Configure'),
          ),
        ],
      ),
    );
  }

  // ── Join Code Card ─────────────────────────────────────

  Widget _buildJoinCodeCard(Race race) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.key, color: AppColors.primary, size: 22),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Join Code', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              Text(race.joinCode,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primary, letterSpacing: 4)),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.copy, color: AppColors.primary),
            onPressed: _copyJoinCode,
            tooltip: 'Copy',
          ),
        ],
      ),
    );
  }

  // ── Participants Card ──────────────────────────────────

  Widget _buildParticipantsCard(Race race) {
    if (race.isCompleted && _liveData != null && _liveData!.riders.isNotEmpty) {
      return _buildCompletedPodiumCard(_liveData!.riders);
    }
    final riders = race.participants.where((p) => p.role == 'host' || p.role == 'rider').toList();
    final watchers = race.participants.where((p) => p.role == 'observer').toList();

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
          Text('Participants (${riders.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (riders.isEmpty)
            const Text('No riders yet', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ...riders.map((p) => _participantTile(p)),
          if (watchers.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Spectators (${watchers.length})',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            ...watchers.map((p) => _participantTile(p, isSpectator: true)),
          ],
        ],
      ),
    );
  }

  Widget _buildCompletedPodiumCard(List<RiderLiveInfo> riders) {
    final ranked = List<RiderLiveInfo>.from(riders);
    final top3 = ranked.take(3).toList();
    final others = ranked.length > 3 ? ranked.sublist(3) : <RiderLiveInfo>[];

    Widget podiumTile(RiderLiveInfo r, int rank) {
      final medalColor = switch (rank) {
        1 => const Color(0xFFFFC107),
        2 => const Color(0xFFB0BEC5),
        3 => const Color(0xFFCD7F32),
        _ => AppColors.textSecondary,
      };
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: medalColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: rank == 1 ? 20 : 16,
                backgroundColor: Colors.white,
                backgroundImage:
                    r.userAvatarUrl != null ? NetworkImage(r.userAvatarUrl!) : null,
                child: r.userAvatarUrl == null
                    ? Text((r.userName ?? '?')[0].toUpperCase(),
                        style: TextStyle(
                            color: medalColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 14))
                    : null,
              ),
              const SizedBox(height: 6),
              Text('P$rank',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: medalColor)),
              const SizedBox(height: 2),
              Text(
                (r.userName ?? 'Rider').split(' ').first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
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
          const Text('Results',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Row(children: [
            for (int i = 0; i < top3.length; i++) podiumTile(top3[i], i + 1),
          ]),
          if (others.isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => setState(() => _showMoreRanks = !_showMoreRanks),
              child: Row(
                children: [
                  Text(
                    _showMoreRanks
                        ? 'Hide Rank 4+'
                        : 'Show Rank 4+ (${others.length})',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary),
                  ),
                  const Spacer(),
                  Icon(
                    _showMoreRanks ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
            if (_showMoreRanks) ...[
              const SizedBox(height: 6),
              ...others.asMap().entries.map((e) {
                final rank = e.key + 4;
                final r = e.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 30,
                        child: Text(
                          '$rank',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary),
                        ),
                      ),
                      CircleAvatar(
                        radius: 12,
                        backgroundImage: r.userAvatarUrl != null
                            ? NetworkImage(r.userAvatarUrl!)
                            : null,
                        child: r.userAvatarUrl == null
                            ? Text((r.userName ?? '?')[0].toUpperCase(),
                                style: const TextStyle(fontSize: 11))
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(r.userName ?? 'Rider',
                            style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ],
      ),
    );
  }

  Widget _participantTile(RaceParticipant p, {bool isSpectator = false}) {
    final isHostRole = p.role == 'host';
    final myId = GlobalUserInfo.instance.id.value;
    final isMe = myId != null && p.userId == myId;
    final canEditBike = !isSpectator && isMe && _race != null && (_race!.isWaiting || _race!.isPreparing);
    final tappable = !isSpectator && (p.bicycleId != null || canEditBike);
    return InkWell(
      onTap: !tappable
          ? null
          : () {
              if (p.bicycleId != null) {
                BikeInfoDialog.show(
                  context,
                  participant: p,
                  onChange: canEditBike ? _onChangeBike : null,
                );
              } else if (canEditBike) {
                showBikePickerSheet(
                  context,
                  selectedBikeId: _selectedBikeId,
                  onSelected: _onChangeBike,
                );
              }
            },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            backgroundImage: p.userAvatarUrl != null ? NetworkImage(p.userAvatarUrl!) : null,
            child: p.userAvatarUrl == null
                ? Text(
                    (p.userName ?? '?')[0].toUpperCase(),
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 14),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.userName ?? 'User ${p.userId}',
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                ),
                if (p.bicycleName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Row(children: [
                      const Icon(Icons.two_wheeler, size: 11, color: AppColors.textSecondary),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          p.bicycleName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ),
                    ]),
                  ),
              ],
            ),
          ),
          if (isHostRole)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
              child: const Text('Host', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
            ),
          if (p.isReady) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
              child: const Text('Ready', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.success)),
            ),
          ],
          if (p.status == 'finished' && p.finishRank != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
              child: Text('#${p.finishRank}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.success)),
            ),
          ],
          if (p.status == 'dnf') ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
              child: const Text('DNF', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.error)),
            ),
          ],
        ],
      ),
      ),
    );
  }

  // ── Leaderboard ────────────────────────────────────────

  /// LAPS-mode tabbed card: Leaderboard / My Laps + mock-data toggle.
  Widget _buildLapsTabbedCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
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
          // Tab header row (full width).
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _buildTabBtn('Leaderboard', _LapsTab.leaderboard),
                _buildTabBtn('My Laps', _LapsTab.myLaps),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_lapsTab == _LapsTab.leaderboard)
            _buildLapsBestLeaderboardBody()
          else
            _buildMyLapsBody(),
        ],
      ),
    );
  }

  Widget _buildTabBtn(String label, _LapsTab tab) {
    final selected = _lapsTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _lapsTab = tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4)
                  ]
                : null,
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? AppColors.primary
                      : AppColors.textSecondary)),
        ),
      ),
    );
  }

  Widget _buildMockToggleBtn() {
    final on = _showMockRiders;
    return Material(
      color: on ? AppColors.primary : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _showMockRiders = !on),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                on ? Icons.science : Icons.science_outlined,
                size: 14,
                color: on ? Colors.white : AppColors.textPrimary,
              ),
              const SizedBox(width: 4),
              Text(
                on ? 'Hide Mock' : 'Show Mock',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Generates 7 mock riders (positions 4–10) with plausible best-lap times.
  /// Cached so toggling doesn't reshuffle ranks.
  List<RiderLiveInfo> _ensureMockRiders() {
    if (_mockRiders != null) return _mockRiders!;
    // Anchor mock best-lap times around the current real leader so they
    // slot into positions 4–10 even if the real leader is fast.
    int anchor = 90; // default seed (1:30)
    for (final r in _liveData?.riders ?? const <RiderLiveInfo>[]) {
      if (r.bestLapSeconds != null) {
        anchor = r.bestLapSeconds!;
        break;
      }
    }
    const names = [
      'Alex',
      'Jordan',
      'Casey',
      'Morgan',
      'Riley',
      'Quinn',
      'Sam'
    ];
    // Offsets in seconds added to anchor for ranks 4–10.
    const offsets = [3, 5, 8, 12, 16, 22, 30];
    final list = <RiderLiveInfo>[];
    for (int i = 0; i < names.length; i++) {
      list.add(RiderLiveInfo(
        userId: -(1000 + i), // negative IDs to avoid clash with real users
        userName: names[i],
        status: 'finished',
        bestLapSeconds: anchor + offsets[i],
        completedLaps: _race?.targetLaps ?? 0,
      ));
    }
    _mockRiders = list;
    return list;
  }

  /// Returns the leaderboard rider list (real + optional mock).
  List<RiderLiveInfo> _leaderboardRiders() {
    final real = _liveData!.riders;
    if (!_showMockRiders) return real;
    return [...real, ..._ensureMockRiders()];
  }

  /// LAPS-mode leaderboard body — top 3 podium-style + 4-N grid rows.
  Widget _buildLapsBestLeaderboardBody() {
    final myId = GlobalUserInfo.instance.id.value;
    final sorted = [..._leaderboardRiders()];
    sorted.sort((a, b) {
      final ba = a.bestLapSeconds;
      final bb = b.bestLapSeconds;
      if (ba == null && bb == null) {
        return b.completedLaps.compareTo(a.completedLaps);
      }
      if (ba == null) return 1;
      if (bb == null) return -1;
      return ba.compareTo(bb);
    });
    int? leaderBest;
    for (final r in sorted) {
      if (r.bestLapSeconds != null) {
        leaderBest = r.bestLapSeconds;
        break;
      }
    }

    String fmtLap(int s) {
      final m = s ~/ 60;
      final ss = s % 60;
      return '$m:${ss.toString().padLeft(2, '0')}';
    }

    String fmtDiff(int? best, {bool signed = true}) {
      if (best == null || leaderBest == null) return '—';
      final d = best - leaderBest!;
      final sign = d >= 0 ? '+' : '-';
      final abs = d.abs();
      final m = abs ~/ 60;
      final s = abs % 60;
      final core = m > 0
          ? '$m:${s.toString().padLeft(2, '0')}'
          : '0:${s.toString().padLeft(2, '0')}';
      return signed ? '$sign$core' : core;
    }

    final top = sorted.take(3).toList();
    final rest = sorted.skip(3).toList();

    const headerStyle = TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: AppColors.textSecondary,
        letterSpacing: 0.4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mock-data toggle (Leaderboard tab only) — sits above the podium
        // so it lives inside the Leaderboard content.
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildMockToggleBtn(),
            ],
          ),
        ),
        // Podium for top 3
        if (top.isNotEmpty)
          _buildPodium(top, leaderBest, fmtLap, fmtDiff, myId),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: const [
                SizedBox(width: 28, child: Text('POS', style: headerStyle)),
                Expanded(child: Text('RIDER', style: headerStyle)),
                SizedBox(
                    width: 60,
                    child: Text('BEST',
                        textAlign: TextAlign.right, style: headerStyle)),
                SizedBox(
                    width: 56,
                    child: Text('DIFF',
                        textAlign: TextAlign.right, style: headerStyle)),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          ...rest.asMap().entries.map((e) {
            final rank = e.key + 4;
            final r = e.value;
            final isMe = r.userId == myId;
            final color = _riderColors[(rank - 1) % _riderColors.length];
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: isMe
                    ? AppColors.primary.withValues(alpha: 0.06)
                    : Colors.transparent,
                border: const Border(
                  bottom: BorderSide(color: AppColors.divider, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text('$rank',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                  ),
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: color.withValues(alpha: 0.18),
                    backgroundImage: r.userAvatarUrl != null
                        ? NetworkImage(r.userAvatarUrl!)
                        : null,
                    child: r.userAvatarUrl == null
                        ? Text(
                            (r.userName ?? '?')[0].toUpperCase(),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: color),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isMe ? 'You' : (r.userName ?? '—'),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isMe
                              ? AppColors.primary
                              : AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      r.bestLapSeconds != null
                          ? fmtLap(r.bestLapSeconds!)
                          : '—',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      fmtDiff(r.bestLapSeconds),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  /// Top-3 podium row — 2nd | 1st | 3rd, with medal-tinted avatars and
  /// best-lap times. 2nd/3rd show "+m:ss" diff under their best time.
  Widget _buildPodium(
    List<RiderLiveInfo> top,
    int? leaderBest,
    String Function(int s) fmtLap,
    String Function(int? best, {bool signed}) fmtDiff,
    int? myId,
  ) {
    Widget podiumCol(int rank, RiderLiveInfo r) {
      final isMe = myId != null && r.userId == myId;
      // Medal tints: gold / silver / bronze
      final medal = rank == 1
          ? const Color(0xFFFFC107)
          : rank == 2
              ? const Color(0xFFB0BEC5)
              : const Color(0xFFCD7F32);
      final radius = rank == 1 ? 30.0 : 24.0;
      final podiumHeight = rank == 1 ? 56.0 : (rank == 2 ? 42.0 : 32.0);

      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: medal, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: radius,
                    backgroundColor: medal.withValues(alpha: 0.18),
                    backgroundImage: r.userAvatarUrl != null
                        ? NetworkImage(r.userAvatarUrl!)
                        : null,
                    child: r.userAvatarUrl == null
                        ? Text(
                            (r.userName ?? '?')[0].toUpperCase(),
                            style: TextStyle(
                                fontSize: rank == 1 ? 22 : 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary),
                          )
                        : null,
                  ),
                ),
                Positioned(
                  bottom: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: medal,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 3)
                      ],
                    ),
                    child: Text('$rank',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              isMe ? 'You' : (r.userName ?? '—'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isMe ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              r.bestLapSeconds != null ? fmtLap(r.bestLapSeconds!) : '—',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              rank == 1
                  ? 'Best'
                  : fmtDiff(r.bestLapSeconds, signed: true),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: rank == 1
                    ? AppColors.success
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            // Podium block
            Container(
              height: podiumHeight,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: medal.withValues(alpha: 0.18),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(8)),
                border: Border(
                  top: BorderSide(color: medal, width: 2),
                ),
              ),
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: rank == 1 ? 18 : 14,
                  fontWeight: FontWeight.w900,
                  color: medal,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Order: 2nd | 1st | 3rd
    final r1 = top.isNotEmpty ? top[0] : null;
    final r2 = top.length >= 2 ? top[1] : null;
    final r3 = top.length >= 3 ? top[2] : null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (r2 != null) podiumCol(2, r2) else const Expanded(child: SizedBox()),
          if (r1 != null) podiumCol(1, r1) else const Expanded(child: SizedBox()),
          if (r3 != null) podiumCol(3, r3) else const Expanded(child: SizedBox()),
        ],
      ),
    );
  }

  /// LAPS-mode "My Laps" body — lap-by-checkpoint splits for the viewer.
  Widget _buildMyLapsBody() {
    final myId = GlobalUserInfo.instance.id.value;
    final me = _liveData!.riders
        .where((r) => r.userId == myId)
        .firstOrNull;
    if (me == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
            'You are not riding in this race — join to record your laps.',
            style: TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
      );
    }
    final completed = me.laps.where((l) => l.endTime != null).toList();
    if (completed.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No completed laps yet.',
            style: TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
      );
    }
    return LapSplitsGrid(
      laps: completed,
      accentColor: AppColors.primary,
      targetLaps: _race?.targetLaps ?? 0,
    );
  }

  Widget _buildLeaderboard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tab header (full width)
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _buildRaceTabBtn('Leaderboard', _RaceTab.leaderboard),
                _buildRaceTabBtn('Lap board', _RaceTab.lapTimes),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_raceTab == _RaceTab.leaderboard)
            _buildRaceLeaderboardBody()
          else
            _buildRaceLapTimesBody(),
        ],
      ),
    );
  }

  Widget _buildRaceTabBtn(String label, _RaceTab tab) {
    final selected = _raceTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _raceTab = tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4),
                  ]
                : null,
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? AppColors.primary
                      : AppColors.textSecondary)),
        ),
      ),
    );
  }

  Widget _buildRaceMockToggleBtn() {
    final on = _showMockRaceRiders;
    return Material(
      color: on ? AppColors.primary : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _showMockRaceRiders = !on),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(on ? Icons.science : Icons.science_outlined,
                  size: 14,
                  color: on ? Colors.white : AppColors.textPrimary),
              const SizedBox(width: 4),
              Text(
                on ? 'Hide Mock' : 'Show Mock',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Generates 7 mock race riders (positions 4–10) with plausible totals
  /// and per-lap times, anchored to the current real leader. Cached so
  /// toggling doesn't reshuffle ranks.
  List<RiderLiveInfo> _ensureMockRaceRiders() {
    if (_mockRaceRiders != null) return _mockRaceRiders!;
    final realRiders = _liveData?.riders ?? const <RiderLiveInfo>[];
    final targetLaps = _race?.targetLaps ?? 0;

    // Anchor: leader's avg lap time (fall back to 90s).
    int leaderTotal = 0;
    int leaderLaps = 0;
    double leaderDist = 0;
    for (final r in realRiders) {
      if (r.completedLaps > leaderLaps ||
          (r.completedLaps == leaderLaps && r.durationSeconds < leaderTotal)) {
        leaderLaps = r.completedLaps;
        leaderTotal = r.durationSeconds;
        leaderDist = r.distanceKm;
      }
    }
    final anchorLapSec = (leaderLaps > 0 && leaderTotal > 0)
        ? (leaderTotal / leaderLaps).round()
        : 90;
    final lapKm = (leaderLaps > 0 && leaderDist > 0)
        ? (leaderDist / leaderLaps)
        : 0.5;
    final laps = targetLaps > 0 ? targetLaps : (leaderLaps > 0 ? leaderLaps : 1);

    const names = [
      'Alex',
      'Jordan',
      'Casey',
      'Morgan',
      'Riley',
      'Quinn',
      'Sam'
    ];
    // Per-lap second offsets above the anchor for ranks 4..10.
    const lapOffsets = [3, 5, 8, 12, 16, 22, 30];
    final list = <RiderLiveInfo>[];
    for (int i = 0; i < names.length; i++) {
      final perLap = anchorLapSec + lapOffsets[i];
      final lapList = <RideLap>[
        for (int n = 1; n <= laps; n++)
          RideLap(
              lapNumber: n,
              durationSeconds: perLap,
              distanceKm: lapKm),
      ];
      list.add(RiderLiveInfo(
        userId: -(2000 + i),
        userName: names[i],
        status: 'finished',
        completedLaps: laps,
        durationSeconds: perLap * laps,
        distanceKm: lapKm * laps,
        bestLapSeconds: perLap,
        laps: lapList,
      ));
    }
    _mockRaceRiders = list;
    return list;
  }

  List<RiderLiveInfo> _raceLeaderboardRiders() {
    final real = _liveData!.riders;
    if (!_showMockRaceRiders) return real;
    return [...real, ..._ensureMockRaceRiders()];
  }

  Widget _buildRaceLeaderboardBody() {
    final myId = GlobalUserInfo.instance.id.value;
    final riders = _raceLeaderboardRiders();

    String fmtTotal(int s) => _fmtDuration(s);

    String fmtGap(int totalSec, int? leaderTotalSec) {
      if (leaderTotalSec == null) return '—';
      final d = totalSec - leaderTotalSec;
      if (d == 0) return 'Leader';
      final sign = d >= 0 ? '+' : '-';
      final abs = d.abs();
      final h = abs ~/ 3600;
      final m = (abs % 3600) ~/ 60;
      final s = abs % 60;
      if (h > 0) {
        return '$sign$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      }
      if (m > 0) return '$sign$m:${s.toString().padLeft(2, '0')}';
      return '${sign}0:${s.toString().padLeft(2, '0')}';
    }

    final top = riders.take(3).toList();
    final rest = riders.skip(3).toList();
    final leaderTotal = riders.isNotEmpty ? riders.first.durationSeconds : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Show Mock toggle (right-aligned)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [_buildRaceMockToggleBtn()],
          ),
        ),
        if (top.isNotEmpty)
          _buildRacePodium(top, leaderTotal, fmtTotal, fmtGap, myId),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 14),
          // Header for ranks 4+
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text('POS',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.4)),
                ),
                Expanded(
                    child: Text('RIDER',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.4))),
                SizedBox(
                    width: 44,
                    child: Text('LAPS',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.4))),
                SizedBox(
                    width: 64,
                    child: Text('TIME',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.4))),
                SizedBox(
                    width: 60,
                    child: Text('GAP',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.4))),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          ...rest.asMap().entries.map((entry) {
            final rank = entry.key + 4;
            final r = entry.value;
            final isMe = myId != null && r.userId == myId;
            final color = _riderColors[(rank - 1) % _riderColors.length];
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: isMe
                    ? AppColors.primary.withValues(alpha: 0.06)
                    : Colors.transparent,
                border: const Border(
                  bottom: BorderSide(color: AppColors.divider, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text('$rank',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                  ),
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: color.withValues(alpha: 0.18),
                    backgroundImage: r.userAvatarUrl != null
                        ? NetworkImage(r.userAvatarUrl!)
                        : null,
                    child: r.userAvatarUrl == null
                        ? Text(
                            (r.userName ?? '?')[0].toUpperCase(),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: color),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isMe ? 'You' : (r.userName ?? '—'),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isMe
                              ? AppColors.primary
                              : AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text('${r.completedLaps}/${_race?.targetLaps ?? 0}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(fmtTotal(r.durationSeconds),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            fontFeatures: [FontFeature.tabularFigures()])),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      fmtGap(r.durationSeconds, leaderTotal),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                          fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  /// Race-mode top-3 podium row: 2 | 1 | 3 with medal-tinted avatars.
  /// Shows the winner's total race time and signed gap (+m:ss) for 2nd/3rd.
  Widget _buildRacePodium(
    List<RiderLiveInfo> top,
    int? leaderTotal,
    String Function(int) fmtTotal,
    String Function(int totalSec, int? leaderTotalSec) fmtGap,
    int? myId,
  ) {
    Widget podiumCol(int rank, RiderLiveInfo r) {
      final isMe = myId != null && r.userId == myId;
      final medal = rank == 1
          ? const Color(0xFFFFC107)
          : rank == 2
              ? const Color(0xFFB0BEC5)
              : const Color(0xFFCD7F32);
      final radius = rank == 1 ? 30.0 : 24.0;
      final podiumHeight = rank == 1 ? 56.0 : (rank == 2 ? 42.0 : 32.0);

      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: medal, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: radius,
                    backgroundColor: medal.withValues(alpha: 0.18),
                    backgroundImage: r.userAvatarUrl != null
                        ? NetworkImage(r.userAvatarUrl!)
                        : null,
                    child: r.userAvatarUrl == null
                        ? Text(
                            (r.userName ?? '?')[0].toUpperCase(),
                            style: TextStyle(
                                fontSize: rank == 1 ? 22 : 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary),
                          )
                        : null,
                  ),
                ),
                Positioned(
                  bottom: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: medal,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 3),
                      ],
                    ),
                    child: Text('$rank',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              isMe ? 'You' : (r.userName ?? '—'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isMe ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              fmtTotal(r.durationSeconds),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              rank == 1 ? 'Winner' : fmtGap(r.durationSeconds, leaderTotal),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: rank == 1
                    ? AppColors.success
                    : AppColors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: podiumHeight,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: medal.withValues(alpha: 0.18),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(8)),
                border: Border(top: BorderSide(color: medal, width: 2)),
              ),
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 4),
              child: Text('$rank',
                  style: TextStyle(
                      fontSize: rank == 1 ? 18 : 14,
                      fontWeight: FontWeight.w900,
                      color: medal)),
            ),
          ],
        ),
      );
    }

    final r1 = top.isNotEmpty ? top[0] : null;
    final r2 = top.length >= 2 ? top[1] : null;
    final r3 = top.length >= 3 ? top[2] : null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (r2 != null)
            podiumCol(2, r2)
          else
            const Expanded(child: SizedBox()),
          if (r1 != null)
            podiumCol(1, r1)
          else
            const Expanded(child: SizedBox()),
          if (r3 != null)
            podiumCol(3, r3)
          else
            const Expanded(child: SizedBox()),
        ],
      ),
    );
  }

  /// F1-inspired lap timing chart.
  ///
  /// Rows are laps (L1..LmaxLap). Columns are finishing positions for that
  /// individual lap (Pos1..PosN). Each cell renders:
  ///   • Rider avatar + first name
  ///   • Lap time, color-coded F1-style:
  ///       - **Purple** ⇒ overall fastest lap of the race
  ///       - **Green**  ⇒ that rider's personal best lap
  ///       - Default    ⇒ neutral
  ///   • Interval to that lap's winner (P1 shows the absolute time, P2+
  ///     show "+m:ss.ms" gap).
  ///
  /// Lap board.
  ///
  /// Rows are laps (L1..LmaxLap). Each row's columns are the riders sorted
  /// by **who completed lap N first overall** (cumulative race time at
  /// lap N, ascending). Each cell shows:
  ///   • Rider avatar + first name
  ///   • Cumulative race time at the end of lap N
  ///   • For Pos2+: gap (`+m:ss`) vs. that lap's Pos1
  ///
  /// "Race start" is the earliest lap-1 startTime across all riders (so a
  /// rider's cumulative time naturally includes any late-start delay).
  Widget _buildRaceLapTimesBody() {
    final riders = _raceLeaderboardRiders();
    int maxLap = 0;
    for (final r in riders) {
      if (r.laps.length > maxLap) maxLap = r.laps.length;
    }
    if (maxLap == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No lap data yet.',
            style:
                TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      );
    }

    String fmt(int s) {
      final m = s ~/ 60;
      final ss = s % 60;
      return '$m:${ss.toString().padLeft(2, '0')}';
    }

    String fmtGap(int d) {
      if (d <= 0) return '+0:00';
      final m = d ~/ 60;
      final s = d % 60;
      if (m > 0) return '+$m:${s.toString().padLeft(2, '0')}';
      return '+0:${s.toString().padLeft(2, '0')}';
    }

    // Race origin: earliest lap-1 startTime across all riders. Falls back
    // to the earliest lap's endTime - duration if startTime is missing.
    DateTime? raceOrigin;
    for (final r in riders) {
      for (final l in r.laps) {
        if (l.lapNumber != 1) continue;
        final st = l.startTime ??
            (l.endTime != null
                ? l.endTime!.subtract(Duration(seconds: l.durationSeconds))
                : null);
        if (st == null) continue;
        if (raceOrigin == null || st.isBefore(raceOrigin)) raceOrigin = st;
      }
    }

    /// Cumulative race time (in seconds) for [rider] at the end of lap [n].
    /// Returns null when that lap is missing or has no end time.
    int? cumAtLap(RiderLiveInfo rider, int n) {
      final lap = rider.laps.where((l) => l.lapNumber == n).firstOrNull;
      if (lap == null) return null;
      if (raceOrigin != null && lap.endTime != null) {
        return lap.endTime!.difference(raceOrigin).inSeconds;
      }
      // Fallback: sum durations from lap 1..n.
      int sum = 0;
      for (int i = 1; i <= n; i++) {
        final li = rider.laps.where((l) => l.lapNumber == i).firstOrNull;
        if (li == null) return null;
        sum += li.durationSeconds;
      }
      return sum;
    }

    // Per-lap entries (rider + cumulative race time at end of lap N),
    // sorted ascending by cumulative time → reflects "who completed lap N
    // first overall".
    final perLap = <int, List<MapEntry<RiderLiveInfo, int>>>{};
    int posCount = 0;
    for (int n = 1; n <= maxLap; n++) {
      final entries = <MapEntry<RiderLiveInfo, int>>[];
      for (final r in riders) {
        final cum = cumAtLap(r, n);
        if (cum != null) entries.add(MapEntry(r, cum));
      }
      entries.sort((a, b) => a.value.compareTo(b.value));
      perLap[n] = entries;
      if (entries.length > posCount) posCount = entries.length;
    }
    if (posCount == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No completed laps yet.',
            style:
                TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      );
    }

    // ── Grid ───────────────────────────────────────────────────────
    const double labelColWidth = 36;
    const double cellWidth = 104;
    const double headerHeight = 28;
    const double rowHeight = 64;

    Widget headerCell(String text, {required double width}) {
      return Container(
        width: width,
        height: headerHeight,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(
            right: BorderSide(color: AppColors.divider, width: 0.5),
            bottom: BorderSide(color: AppColors.divider, width: 0.5),
          ),
        ),
        child: Text(text,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
                letterSpacing: 0.4)),
      );
    }

    Widget lapLabelCell(int lap) {
      return Container(
        width: labelColWidth,
        height: rowHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          border: const Border(
            right: BorderSide(color: AppColors.divider, width: 0.5),
            bottom: BorderSide(color: AppColors.divider, width: 0.5),
          ),
        ),
        child: Text('L$lap',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.primary)),
      );
    }

    Widget dataCell({
      required RiderLiveInfo? rider,
      required int? cumSec,
      required int? leaderCumSec,
      required bool isP1,
    }) {
      if (rider == null || cumSec == null) {
        return Container(
          width: cellWidth,
          height: rowHeight,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            border: Border(
              right: BorderSide(color: AppColors.divider, width: 0.5),
              bottom: BorderSide(color: AppColors.divider, width: 0.5),
            ),
          ),
          child: const Text('—',
              style: TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
        );
      }

      final cellBg = isP1
          ? AppColors.primary.withValues(alpha: 0.06)
          : Colors.transparent;
      final color = AppColors.primary;

      return Container(
        width: cellWidth,
        height: rowHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cellBg,
          border: const Border(
            right: BorderSide(color: AppColors.divider, width: 0.5),
            bottom: BorderSide(color: AppColors.divider, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 9,
                  backgroundColor: color.withValues(alpha: 0.18),
                  backgroundImage: rider.userAvatarUrl != null
                      ? NetworkImage(rider.userAvatarUrl!)
                      : null,
                  child: rider.userAvatarUrl == null
                      ? Text(
                          (rider.userName ?? '?')[0].toUpperCase(),
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: color),
                        )
                      : null,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    (rider.userName ?? 'Rider').split(' ').first,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              fmt(cumSec),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 1),
            Text(
              isP1
                  ? 'Leader'
                  : fmtGap(cumSec - (leaderCumSec ?? cumSec)),
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: isP1 ? AppColors.success : AppColors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                headerCell('Lap', width: labelColWidth),
                for (int p = 1; p <= posCount; p++)
                  headerCell('Pos$p', width: cellWidth),
              ],
            ),
            // Data rows
            for (int n = 1; n <= maxLap; n++)
              Row(
                children: [
                  lapLabelCell(n),
                  for (int p = 1; p <= posCount; p++)
                    Builder(builder: (_) {
                      final entries = perLap[n] ?? const [];
                      final entry = (p - 1) < entries.length
                          ? entries[p - 1]
                          : null;
                      final leaderCum = entries.isNotEmpty
                          ? entries.first.value
                          : null;
                      return dataCell(
                        rider: entry?.key,
                        cumSec: entry?.value,
                        leaderCumSec: leaderCum,
                        isP1: p == 1,
                      );
                    }),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ── Action Buttons ─────────────────────────────────────

  Future<void> _onWatchRace() async {
    final resp = await TraxApi.observeRace(widget.raceId);
    if (!mounted) return;
    if (resp.isSuccess()) {
      showTraxSnackBar(context, 'Now watching this race');
      _load();
    } else {
      showTraxSnackBar(context, resp.message, isError: true);
    }
  }

  Future<void> _onQuitWatch() async {
    final ok = await TraxDialog.confirm(context,
        title: 'Quit Watch',
        message: 'You will stop watching this race.');
    if (ok != true || !mounted) return;
    final resp = await TraxApi.quitRace(widget.raceId);
    if (!mounted) return;
    if (resp.isSuccess()) {
      showTraxSnackBar(context, 'Stopped watching');
      Navigator.of(context).pop();
    } else {
      showTraxSnackBar(context, resp.message, isError: true);
    }
  }

  void _onEnterTracking() {
    MapRouter.openRaceTracking(
      context,
      raceId: widget.raceId,
      isObserver: _race?.isObserver ?? false,
      replace: true,
    );
  }

  void _onReplayRace() async {
    // Refetch live data so any final laps that were detected on the backend
    // after the race auto-completed (late finishers) are included.
    final lResp = await TraxApi.getRaceLive(widget.raceId);
    if (!mounted) return;
    if (lResp.isSuccess() && lResp.data != null) {
      _liveData = RaceLiveData.fromJson(lResp.data as Map<String, dynamic>);
    }
    if (_liveData == null) return;
    MapRouter.openRaceReplay(
      context,
      raceName: _race?.name ?? 'Race Replay',
      targetLaps: _race?.targetLaps ?? 0,
      riders: _liveData!.riders,
      isLaps: _race?.isLaps ?? false,
      trailId: _race?.trailId,
      isObserver: _race?.isObserver ?? false,
    );
  }

  void _onAnalyzeMyRide() async {
    final rideId = _myRideId;
    if (rideId == null) return;

    final ptsResp = await TraxApi.getRidePoints(rideId);
    if (!mounted) return;

    if (!ptsResp.isSuccess() || ptsResp.data is! List) {
      showTraxSnackBar(context, ptsResp.message, isError: true);
      return;
    }

    final points = (ptsResp.data as List).cast<Map<String, dynamic>>();
    if (points.length < 2) {
      showTraxSnackBar(context, 'Not enough ride points for analysis', isError: true);
      return;
    }

    MapRouter.openRideAnalysis(
      context,
      points: points,
      rideName: '${_race?.name ?? 'Race'} · You',
    );
  }

  Widget _buildActionButtons(Race race) {
    final isHost = race.isHost;
    final isGuest = race.isRider || race.isObserver;
    final isNotParticipant = race.myRole == null;
    return Column(
      children: [
        if (isHost && race.isWaiting)
          _actionBtn('Start Race', Icons.play_arrow, AppColors.success, _onStartRace),
        if (isHost && race.isPreparing)
          _actionBtn('Enter Race Tracking', Icons.flag, AppColors.success, _onEnterTracking),
        if (isHost && race.isInProgress)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _actionBtn('Enter Race Tracking', Icons.flag, AppColors.success, _onEnterTracking),
          ),
        if (isHost && race.isInProgress)
          _actionBtn('Stop Race', Icons.stop, AppColors.error, _onStopRace),
        if (isHost && race.isWaiting)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _actionBtn('Cancel Race', Icons.cancel, AppColors.error, _onCancelRace, outlined: true),
          ),
        if (!isHost && race.isRider && race.isPreparing)
          _actionBtn('Enter Race Tracking', Icons.flag, AppColors.success, _onEnterTracking),
        if (!isHost && race.isRider && race.isInProgress)
          _actionBtn('Enter Race Tracking', Icons.flag, AppColors.success, _onEnterTracking),
        if (race.isObserver && race.isInProgress)
          _actionBtn('Enter Race', Icons.flag, AppColors.success, _onEnterTracking),
        if (!isHost && race.isRider && race.isWaiting)
          _actionBtn('Quit Race', Icons.exit_to_app, AppColors.error, _onQuitRace, outlined: true),
        if (race.isObserver && !race.isInProgress)
          _actionBtn('Quit Watch', Icons.visibility_off, AppColors.error, _onQuitWatch, outlined: true),
        if (isNotParticipant && race.isWaiting)
          _actionBtn('Join Race', Icons.group_add, AppColors.primary, _onJoinRace),
        if (isNotParticipant)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _actionBtn('Watch', Icons.visibility, AppColors.primary, _onWatchRace),
          ),
        // Replay Race + Delete My Record buttons are surfaced in the
        // top-right of the AppBar (see _buildAppBarActions) when the
        // race is completed, mirroring the Ride Detail page layout.
      ],
    );
  }

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback onTap, {bool outlined = false}) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: outlined
          ? OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 20),
              label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            )
          : ElevatedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 20),
              label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
    );
  }

  String _fmtDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

enum _LapsTab { leaderboard, myLaps }

enum _RaceTab { leaderboard, lapTimes }
