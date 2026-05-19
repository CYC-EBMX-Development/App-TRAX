import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:amap_flutter_map/amap_flutter_map.dart' as amap_map;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:geolocator/geolocator.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

import '../../../common/global/global_user_info.dart';
import '../../../common/network/trax_api.dart';
import '../../../common/utils/amap_adapter.dart';
import '../../../common/widgets/bike_picker.dart';
import '../../../common/widgets/trax_dialog.dart';
import '../../../models/race.dart';
import '../../../models/race_live_data.dart';
import '../../../models/user_checkpoint.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/lap_splits_grid.dart';
import '../race_detail_page.dart';

/// Native-AMap variant of `RaceTrackingPage`. Identical state machine and
/// behaviour, just renders the map with [amap_map.AMapWidget] so it works
/// inside mainland China without Google Maps tiles. Avatars-in-marker
/// bitmaps are still built with `ui.PictureRecorder`, then handed to AMap
/// via `BitmapDescriptor.fromBytes`.
///
/// Feature gap vs Google variant: the **pick start location** affordance
/// (drag-and-confirm a custom pre-race position) is hidden because AMap's
/// controller does not expose a screen→world coordinate API. Riders inside
/// mainland China who need that feature should report their position by
/// physically moving; everything else is preserved.
class RaceTrackingPageAmap extends StatefulWidget {
  final int raceId;
  const RaceTrackingPageAmap({super.key, required this.raceId});
  @override
  State<RaceTrackingPageAmap> createState() => _RaceTrackingPageAmapState();
}

class _RaceTrackingPageAmapState extends State<RaceTrackingPageAmap>
    with TickerProviderStateMixin {
  Race? _race;
  RaceLiveData? _liveData;
  bool _initialLoading = true;
  Timer? _pollTimer;
  Timer? _locationTimer;
  amap_map.AMapController? _mapController;
  bool _mapReady = false;
  LatLng _myPos = const LatLng(0, 0);
  bool _hasLocation = false;
  List<LatLng> _trailRoute = [];
  List<UserCheckpoint> _myCheckpoints = [];
  final Map<int, bool> _riderVisibility = {};
  bool _showCheckpoints = true;
  final Map<int, amap_map.BitmapDescriptor> _markerIcons = {};
  final Map<int, Uint8List> _avatarBytes = {};
  final Map<int, String> _avatarUrlByUid = {};
  final Map<int, int> _riderColorIndex = {};
  int _nextColorIndex = 0;
  List<Map<String, dynamic>> _myBikes = [];
  int? _selectedBikeId;

  static const List<Color> _riderColors = [
    Color(0xFF4285F4), Color(0xFFEA4335), Color(0xFF34A853),
    Color(0xFFFBBC04), Color(0xFF9C27B0), Color(0xFFFF6D00),
    Color(0xFF00BCD4), Color(0xFFE91E63),
  ];

  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadRace();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _locationTimer?.cancel();
    _mapController?.disponse();
    _lapsTabCtrl?.dispose();
    super.dispose();
  }

  int _colorIdx(int userId) =>
      _riderColorIndex.putIfAbsent(userId, () => _nextColorIndex++);
  Color _colorFor(int userId) =>
      _riderColors[_colorIdx(userId) % _riderColors.length];

  Future<void> _initLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        _myPos = LatLng(pos.latitude, pos.longitude);
        _hasLocation = true;
      });
      _animateTo(_myPos);
    } catch (_) {}
  }

  void _startLocationReporting() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high),
        );
        if (!mounted) return;
        setState(() {
          _myPos = LatLng(pos.latitude, pos.longitude);
          _hasLocation = true;
        });
        TraxApi.reportLocation(widget.raceId, pos.latitude, pos.longitude);
      } catch (_) {}
    });
  }

  void _animateTo(LatLng pos) {
    if (_mapReady && _mapController != null) {
      _mapController!.moveCamera(
        amap_map.CameraUpdate.newLatLng(AmapAdapter.toAmap(pos)),
        animated: true,
      );
    }
  }

  Future<void> _goToMyLocation() async {
    if (_hasLocation) {
      _animateTo(_myPos);
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        _myPos = LatLng(pos.latitude, pos.longitude);
        _hasLocation = true;
      });
      _animateTo(_myPos);
    } catch (_) {}
  }

  Future<void> _loadRace() async {
    final resp = await TraxApi.getRace(widget.raceId);
    if (!mounted) return;
    if (resp.isSuccess() && resp.data != null) {
      final race = Race.fromJson(resp.data as Map<String, dynamic>);
      setState(() {
        _race = race;
        _initialLoading = false;
      });
      _loadMyBikes(race);
      _loadTrailRoute();
      _startPolling();
      if (race.isPreparing) _startLocationReporting();
    } else {
      setState(() => _initialLoading = false);
    }
  }

  Future<void> _loadMyBikes(Race race) async {
    final resp = await TraxApi.getUserBikes();
    if (!mounted || !resp.isSuccess()) return;
    final list = (resp.data as List?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList() ??
        [];
    final myPart =
        race.participants.where((p) => p.userId == _myId).firstOrNull;
    setState(() {
      _myBikes = list;
      _selectedBikeId = myPart?.bicycleId;
    });
  }

  Future<void> _onChangeBike(int? bikeId) async {
    final resp =
        await TraxApi.setRaceBike(widget.raceId, bicycleId: bikeId);
    if (!mounted) return;
    if (resp.isSuccess() && resp.data != null) {
      final race = Race.fromJson(resp.data as Map<String, dynamic>);
      setState(() {
        _race = race;
        _selectedBikeId = bikeId;
      });
    } else {
      showTraxSnackBar(context, resp.message, isError: true);
    }
  }

  Future<void> _loadTrailRoute() async {
    final trailId = _race?.trailId;
    if (trailId == null) return;
    final results = await Future.wait([
      TraxApi.getTrailPoints(trailId),
      TraxApi.getTrailCheckpoints(trailId),
    ]);
    if (!mounted) return;
    final pointsResp = results[0];
    final cpResp = results[1];
    List<LatLng> pts = const [];
    if (pointsResp.isSuccess() && pointsResp.data is List) {
      pts = (pointsResp.data as List).map((p) {
        final m = p as Map<String, dynamic>;
        return LatLng(
          (m['latitude'] as num).toDouble(),
          (m['longitude'] as num).toDouble(),
        );
      }).toList();
    }
    List<UserCheckpoint> cps = const [];
    if (cpResp.isSuccess() && cpResp.data is List) {
      cps = (cpResp.data as List)
          .map((e) => UserCheckpoint.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.sequenceIndex.compareTo(b.sequenceIndex));
    }
    setState(() {
      _trailRoute = pts;
      _myCheckpoints = cps;
    });
    if (pts.isNotEmpty && !_hasLocation) _animateTo(pts.first);
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    _poll();
  }

  Future<void> _poll() async {
    final results = await Future.wait([
      TraxApi.getRace(widget.raceId),
      TraxApi.getRaceLive(widget.raceId),
    ]);
    if (!mounted) return;
    final raceResp = results[0];
    final liveResp = results[1];

    if (raceResp.isSuccess() && raceResp.data != null) {
      final race = Race.fromJson(raceResp.data as Map<String, dynamic>);
      final wasNotInProgress = _race != null && !_race!.isInProgress;
      setState(() => _race = race);
      if (race.isInProgress && wasNotInProgress) _locationTimer?.cancel();
      if (race.isCompleted) {
        _pollTimer?.cancel();
        _locationTimer?.cancel();
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
                builder: (_) => RaceDetailPage(raceId: widget.raceId)),
          );
        }
        return;
      }
      if (race.isCanceled) {
        _pollTimer?.cancel();
        _locationTimer?.cancel();
        if (mounted) {
          showTraxSnackBar(context, 'Race has been canceled');
          Navigator.of(context).pop();
        }
        return;
      }
    }

    if (liveResp.isSuccess() && liveResp.data != null) {
      final live =
          RaceLiveData.fromJson(liveResp.data as Map<String, dynamic>);
      setState(() {
        _liveData = live;
        for (final r in live.riders) {
          _riderVisibility.putIfAbsent(r.userId, () => true);
          _colorIdx(r.userId);
        }
      });
      _ensureMarkerIcons(live.riders);
    }
  }

  Future<void> _ensureMarkerIcons(List<RiderLiveInfo> riders) async {
    bool anyNew = false;
    for (final r in riders) {
      final currentUrl = r.userAvatarUrl;
      final cachedUrl = _avatarUrlByUid[r.userId];
      if (cachedUrl != currentUrl) {
        _avatarBytes.remove(r.userId);
        _markerIcons.remove(r.userId);
        if (currentUrl == null) {
          _avatarUrlByUid.remove(r.userId);
        } else {
          _avatarUrlByUid[r.userId] = currentUrl;
        }
      }
      if (r.userAvatarUrl != null && !_avatarBytes.containsKey(r.userId)) {
        try {
          final resp = await Dio().get<List<int>>(
            r.userAvatarUrl!,
            options: Options(responseType: ResponseType.bytes),
          );
          if (resp.data != null) {
            _avatarBytes[r.userId] = Uint8List.fromList(resp.data!);
            _markerIcons.remove(r.userId);
          }
        } catch (_) {}
      }
      if (_markerIcons.containsKey(r.userId)) continue;
      anyNew = true;
      _markerIcons[r.userId] = await _createMarkerIcon(
        r.userName ?? 'Rider',
        _colorFor(r.userId),
        r.userId == _myId,
        _avatarBytes[r.userId],
      );
    }
    if (anyNew && mounted) setState(() {});
  }

  Future<amap_map.BitmapDescriptor> _createMarkerIcon(
      String name, Color color, bool isMe, Uint8List? avatarBytes) async {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final displayName = isMe ? 'You' : name.split(' ').first;
    final nameTp = TextPainter(
      text: TextSpan(
        text: displayName,
        style: TextStyle(
          color: Colors.black87,
          fontSize: 11 * dpr,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final circleR = 20 * dpr;
    final borderW = 3 * dpr;
    final gap = 4 * dpr;
    final nameH = nameTp.height;
    final nameBgPad = 4 * dpr;
    final w = (nameTp.width + nameBgPad * 2)
        .clamp(circleR * 2 + borderW * 2, 200 * dpr);
    final totalH = borderW +
        circleR * 2 +
        borderW +
        gap +
        nameH +
        nameBgPad * 2 +
        2 * dpr;
    final cx = w / 2;
    final cy = borderW + circleR;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, totalH));
    canvas.drawCircle(
      Offset(cx, cy),
      circleR + borderW / 2,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(Offset(cx, cy), circleR, Paint()..color = color);
    if (avatarBytes != null) {
      try {
        final codec = await ui.instantiateImageCodec(
          avatarBytes,
          targetWidth: (circleR * 2).toInt(),
          targetHeight: (circleR * 2).toInt(),
        );
        final frame = await codec.getNextFrame();
        final img = frame.image;
        canvas.save();
        final clipPath = Path()
          ..addOval(
              Rect.fromCircle(center: Offset(cx, cy), radius: circleR));
        canvas.clipPath(clipPath);
        final dst =
            Rect.fromCircle(center: Offset(cx, cy), radius: circleR);
        paintImage(
            canvas: canvas, rect: dst, image: img, fit: BoxFit.cover);
        canvas.restore();
        img.dispose();
      } catch (_) {}
    } else {
      final initialTp = TextPainter(
        text: TextSpan(
          text: displayName[0].toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontSize: 18 * dpr,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      initialTp.paint(canvas,
          Offset(cx - initialTp.width / 2, cy - initialTp.height / 2));
    }
    final nameY = cy + circleR + borderW + gap;
    final nameRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, nameY + nameH / 2 + nameBgPad),
        width: nameTp.width + nameBgPad * 2,
        height: nameH + nameBgPad,
      ),
      Radius.circular(4 * dpr),
    );
    canvas.drawRRect(nameRect, Paint()..color = Colors.white);
    canvas.drawRRect(
      nameRect,
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 * dpr,
    );
    nameTp.paint(
        canvas, Offset(cx - nameTp.width / 2, nameY + nameBgPad / 2));
    final picture = recorder.endRecording();
    final image = await picture.toImage(w.toInt(), totalH.toInt());
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    return amap_map.BitmapDescriptor.fromBytes(
        byteData!.buffer.asUint8List());
  }

  Future<void> _onReady() async {
    final resp = await TraxApi.readyForRace(widget.raceId);
    if (!mounted) return;
    if (resp.isSuccess()) {
      showTraxSnackBar(context, 'You are ready!');
    } else {
      showTraxSnackBar(context, resp.message, isError: true);
    }
  }

  Future<void> _onGoRace() async {
    final ok = await TraxDialog.confirm(context,
        title: 'Start Racing',
        message: 'Start the race for all riders?');
    if (ok != true || !mounted) return;
    final resp = await TraxApi.goRace(widget.raceId);
    if (!mounted) return;
    if (resp.isSuccess()) {
      showTraxSnackBar(context, 'Race started!');
    } else {
      showTraxSnackBar(context, resp.message, isError: true);
    }
  }

  Future<void> _onQuitRace() async {
    final ok = await TraxDialog.confirm(context,
        title: 'Quit Race', message: 'Leave this race?');
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

  Future<void> _onCancelRace() async {
    final ok = await TraxDialog.confirm(context,
        title: 'Cancel Race', message: 'Cancel for all?');
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

  Future<void> _onStopRace() async {
    final ok = await TraxDialog.confirm(context,
        title: 'Stop Race', message: 'End race for all?');
    if (ok != true || !mounted) return;
    final resp = await TraxApi.stopRaceEvent(widget.raceId);
    if (!mounted) return;
    if (resp.isSuccess()) {
      showTraxSnackBar(context, 'Race stopped');
    } else {
      showTraxSnackBar(context, resp.message, isError: true);
    }
  }

  int? get _myId => GlobalUserInfo.instance.id.value;

  bool get _amReady {
    if (_race == null) return false;
    final me =
        _race!.participants.where((p) => p.userId == _myId).firstOrNull;
    return me != null && (me.isReady || me.isHost);
  }

  bool _isHostUser(int userId) => _race?.hostId == userId;

  String _fmtDur(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) =>
      PageCodeBadge(code: '410', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    if (_initialLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (_race == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Race not found'),
            const SizedBox(height: 12),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back')),
          ]),
        ),
      );
    }

    final riders = _liveData?.riders ?? [];
    final mapTarget = _hasLocation
        ? _myPos
        : (_trailRoute.isNotEmpty
            ? _trailRoute[_trailRoute.length ~/ 2]
            : const LatLng(22.8956, 113.8739));

    return Scaffold(
      body: Stack(
        children: [
          amap_map.AMapWidget(
            privacyStatement: AmapAdapter.privacy(),
            apiKey: AmapAdapter.apiKey(),
            initialCameraPosition: amap_map.CameraPosition(
                target: AmapAdapter.toAmap(mapTarget), zoom: 15),
            polylines: _buildPolylines(riders),
            markers: _buildMarkers(riders),
            onMapCreated: (c) {
              _mapController = c;
              _mapReady = true;
              if (_hasLocation) _animateTo(_myPos);
            },
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: Row(
              children: [
                _circleBtn(Icons.arrow_back, () => Navigator.pop(context)),
                const SizedBox(width: 8),
                Expanded(child: _buildStatusPill()),
                const SizedBox(width: 8),
                if (_myCheckpoints.isNotEmpty) ...[
                  _cpToggleBtn(),
                  const SizedBox(width: 8),
                ],
                _circleBtn(Icons.my_location, _goToMyLocation),
              ],
            ),
          ),
          if (_race?.isInProgress == true && riders.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 64,
              right: 12,
              child: _buildLiveRankingOverlay(riders),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomPanel(riders),
          ),
        ],
      ),
    );
  }

  Set<amap_map.Polyline> _buildPolylines(List<RiderLiveInfo> riders) {
    final polylines = <amap_map.Polyline>{};
    if (_trailRoute.length >= 2) {
      polylines.add(amap_map.Polyline(
        points: AmapAdapter.toAmapList(_trailRoute),
        color: AppColors.primary.withValues(alpha: 0.35),
        width: 7,
      ));
    }
    for (final r in riders) {
      if (r.route.length >= 2) {
        polylines.add(amap_map.Polyline(
          points: AmapAdapter.toAmapList(r.route),
          color: _colorFor(r.userId),
          width: 6,
        ));
      }
    }
    return polylines;
  }

  Set<amap_map.Marker> _buildMarkers(List<RiderLiveInfo> riders) {
    final markers = <amap_map.Marker>{};
    if (_trailRoute.isNotEmpty) {
      markers.add(amap_map.Marker(
        position: AmapAdapter.toAmap(_trailRoute.first),
        infoWindow: const amap_map.InfoWindow(title: 'Start / Finish'),
      ));
    }
    if (_showCheckpoints && _myCheckpoints.isNotEmpty) {
      for (final cp in _myCheckpoints) {
        markers.add(amap_map.Marker(
          position: AmapAdapter.toAmap(
              LatLng(cp.latitude, cp.longitude)),
          infoWindow:
              amap_map.InfoWindow(title: 'CP${cp.sequenceIndex}'),
        ));
      }
    }
    for (final r in riders) {
      if (!(_riderVisibility[r.userId] ?? true)) continue;
      if (_race?.isPreparing == true) {
        final shouldShow = r.status == 'ready' || _isHostUser(r.userId);
        if (!shouldShow) continue;
      }
      if (r.latitude == 0 && r.longitude == 0) continue;
      markers.add(amap_map.Marker(
        position:
            AmapAdapter.toAmap(LatLng(r.latitude, r.longitude)),
        icon: _markerIcons[r.userId] ??
            amap_map.BitmapDescriptor.defaultMarker,
        anchor: const Offset(0.5, 0.5),
        zIndex: 10,
      ));
    }
    return markers;
  }

  Widget _buildStatusPill() {
    final race = _race!;
    final parts = race.participants
        .where((p) => p.role == 'host' || p.role == 'rider')
        .toList();
    final readyCount = parts.where((p) => p.isReady || p.isHost).length;
    String label;
    Color color;
    IconData icon;
    if (race.isPreparing) {
      label = 'Preparing \u00b7 $readyCount/${parts.length} ready';
      color = Colors.orange;
      icon = Icons.flag;
    } else if (race.isInProgress) {
      label =
          '${race.name} \u00b7 ${_fmtDur(_liveData?.elapsedSeconds ?? 0)}';
      color = AppColors.success;
      icon = Icons.directions_bike;
    } else {
      label = race.name;
      color = AppColors.textSecondary;
      icon = Icons.info;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.1), blurRadius: 6)
        ],
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color),
              overflow: TextOverflow.ellipsis),
        ),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('AMap',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary)),
        ),
      ]),
    );
  }

  Widget _buildBottomPanel(List<RiderLiveInfo> riders) {
    final isLapsInProgress =
        _race?.isLaps == true && _race?.isInProgress == true;
    Widget body;
    if (isLapsInProgress) {
      body = _buildLapsModeTabs(riders);
    } else {
      final lapBoard = _race?.isInProgress == true
          ? _buildLapLeaderboard(riders)
          : const SizedBox.shrink();
      body = lapBoard;
    }
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 14, 16, MediaQuery.of(context).padding.bottom + 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (riders.isNotEmpty) ...[
            SizedBox(
              height: 76,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: riders.length,
                itemBuilder: (_, i) => _riderChip(riders[i]),
              ),
            ),
            const SizedBox(height: 10),
          ],
          body,
          _buildActions(_race!),
        ],
      ),
    );
  }

  TabController? _lapsTabCtrl;

  Widget _buildLapsModeTabs(List<RiderLiveInfo> riders) {
    final showMine = _race?.isObserver != true;
    final tabsCount = showMine ? 2 : 1;
    if (_lapsTabCtrl == null || _lapsTabCtrl!.length != tabsCount) {
      _lapsTabCtrl?.dispose();
      _lapsTabCtrl = TabController(length: tabsCount, vsync: this);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TabBar(
            controller: _lapsTabCtrl,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700),
            tabs: [
              const Tab(text: 'Leaderboard', height: 32),
              if (showMine) const Tab(text: 'My Laps', height: 32),
            ],
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: TabBarView(
              controller: _lapsTabCtrl,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildBestLapLeaderboard(riders),
                if (showMine) _buildMyLapsPanel(riders),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtLap(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildBestLapLeaderboard(List<RiderLiveInfo> riders) {
    final sorted = [...riders];
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
    String fmtDiff(int? best) {
      if (best == null || leaderBest == null) return '—';
      final d = best - leaderBest!;
      if (d == 0) return '+0:00';
      final sign = d >= 0 ? '+' : '-';
      final abs = d.abs();
      final m = abs ~/ 60;
      final s = abs % 60;
      if (m > 0) return '$sign$m:${s.toString().padLeft(2, '0')}';
      return '${sign}0:${s.toString().padLeft(2, '0')}';
    }

    const headerStyle = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      color: AppColors.textSecondary,
      letterSpacing: 0.4,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          ...sorted.asMap().entries.map((e) {
            final rank = e.key + 1;
            final r = e.value;
            final isMe = r.userId == _myId;
            final color = _colorFor(r.userId);
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              decoration: BoxDecoration(
                color: isMe
                    ? AppColors.primary.withValues(alpha: 0.06)
                    : Colors.transparent,
                border: const Border(
                  bottom:
                      BorderSide(color: AppColors.divider, width: 0.5),
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
                          fontSize: 12,
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
                          ? _fmtLap(r.bestLapSeconds!)
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
                      rank == 1 && r.bestLapSeconds != null
                          ? '+0:00'
                          : fmtDiff(r.bestLapSeconds),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: rank == 1
                              ? AppColors.success
                              : AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMyLapsPanel(List<RiderLiveInfo> riders) {
    final me = riders.where((r) => r.userId == _myId).firstOrNull;
    if (me == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Waiting for your ride to start…',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
        ),
      );
    }
    final target = _race?.targetLaps ?? 0;
    final last = me.laps.isNotEmpty ? me.laps.last : null;

    final inProgress = me.laps.where((l) => l.endTime == null).toList();
    final currentLap = inProgress.isNotEmpty ? inProgress.first : null;
    final completedLaps =
        me.laps.where((l) => l.endTime != null).length;
    final currentLapNumber = currentLap?.lapNumber ?? (completedLaps + 1);
    int? currentLapElapsed;
    final liveStart = currentLap?.startTime;
    if (liveStart != null) {
      currentLapElapsed =
          DateTime.now().difference(liveStart).inSeconds.clamp(0, 1 << 30);
    }
    final currentLapPasses = currentLap == null
        ? <({int sequenceIndex, int secondsFromLapStart})>[]
        : currentLap.checkpointPasses
            .map((p) => (
                  sequenceIndex: p.sequenceIndex,
                  secondsFromLapStart: p.secondsFromLapStart,
                ))
            .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _statTile('Lap',
                  '${me.completedLaps}${target > 0 ? '/$target' : ''}'),
              const SizedBox(width: 8),
              _statTile('Last',
                  last != null ? _fmtLap(last.durationSeconds) : '—'),
              const SizedBox(width: 8),
              _statTile(
                  'Best',
                  me.bestLapSeconds != null
                      ? _fmtLap(me.bestLapSeconds!)
                      : '—'),
            ],
          ),
          const SizedBox(height: 10),
          LapSplitsGrid(
            laps: me.laps.where((l) => l.endTime != null).toList(),
            accentColor: AppColors.primary,
            targetLaps: target,
            checkpointCount: _myCheckpoints.length,
            currentLapNumber:
                _race?.isInProgress == true ? currentLapNumber : null,
            currentLapPasses: currentLapPasses,
            currentLapElapsed: currentLapElapsed,
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildLapLeaderboard(List<RiderLiveInfo> riders) {
    int maxLap = 0;
    for (final r in riders) {
      if (r.laps.length > maxLap) maxLap = r.laps.length;
    }
    if (maxLap == 0) return const SizedBox.shrink();

    String fmt(int sec) {
      final m = sec ~/ 60;
      final s = sec % 60;
      return '$m:${s.toString().padLeft(2, '0')}';
    }

    final lapWidgets = <Widget>[];
    for (int lap = 1; lap <= maxLap; lap++) {
      final entries = <MapEntry<RiderLiveInfo, dynamic>>[];
      for (final r in riders) {
        final l = r.laps.where((x) => x.lapNumber == lap).firstOrNull;
        if (l != null) entries.add(MapEntry(r, l));
      }
      if (entries.isEmpty) continue;
      entries.sort((a, b) {
        final ae = a.value.endTime as DateTime?;
        final be = b.value.endTime as DateTime?;
        if (ae == null && be == null) return 0;
        if (ae == null) return 1;
        if (be == null) return -1;
        return ae.compareTo(be);
      });

      lapWidgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 36,
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'L$lap',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: entries.asMap().entries.map((e) {
                    final rank = e.key + 1;
                    final rider = e.value.key as RiderLiveInfo;
                    final lap = e.value.value;
                    final isMe = rider.userId == _myId;
                    final color = _colorFor(rider.userId);
                    return Container(
                      margin: const EdgeInsets.only(right: 10),
                      child: Row(children: [
                        Text('$rank.',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary)),
                        const SizedBox(width: 4),
                        CircleAvatar(
                          radius: 10,
                          backgroundColor:
                              color.withValues(alpha: 0.18),
                          backgroundImage: rider.userAvatarUrl != null
                              ? NetworkImage(rider.userAvatarUrl!)
                              : null,
                          child: rider.userAvatarUrl == null
                              ? Text(
                                  (rider.userName ?? '?')[0]
                                      .toUpperCase(),
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: color),
                                )
                              : null,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isMe
                              ? 'You'
                              : (rider.userName ?? '').split(' ').first,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          fmt(lap.durationSeconds as int),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary),
                        ),
                      ]),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 2),
            child: Text('Lap Leaderboard',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary)),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 140),
            child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: lapWidgets),
            ),
          ),
        ],
      ),
    );
  }

  Widget _riderChip(RiderLiveInfo rider) {
    final visible = _riderVisibility[rider.userId] ?? true;
    final color = _colorFor(rider.userId);
    final isMe = rider.userId == _myId;
    return GestureDetector(
      onTap: () =>
          setState(() => _riderVisibility[rider.userId] = !visible),
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: visible ? color : Colors.grey.shade300,
                    width: 2.5,
                  ),
                ),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: visible
                      ? color.withValues(alpha: 0.15)
                      : Colors.grey.shade100,
                  backgroundImage: rider.userAvatarUrl != null
                      ? NetworkImage(rider.userAvatarUrl!)
                      : null,
                  child: rider.userAvatarUrl == null
                      ? Text(
                          (rider.userName ?? '?')[0].toUpperCase(),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: visible ? color : Colors.grey,
                          ),
                        )
                      : null,
                ),
              ),
              if (!visible)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                    child: const Icon(Icons.visibility_off,
                        size: 16, color: Colors.grey),
                  ),
                ),
              if (_race!.isPreparing)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: rider.status == 'ready' ||
                              _isHostUser(rider.userId)
                          ? AppColors.success
                          : Colors.orange,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Icon(
                      rider.status == 'ready' ||
                              _isHostUser(rider.userId)
                          ? Icons.check
                          : Icons.hourglass_top,
                      size: 8,
                      color: Colors.white,
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 3),
            Text(
              isMe ? 'You' : (rider.userName ?? '').split(' ').first,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color:
                    visible ? AppColors.textPrimary : Colors.grey,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            if (rider.bicycleName != null)
              Text(
                rider.bicycleName!,
                style: TextStyle(
                  fontSize: 8,
                  color: visible
                      ? AppColors.textSecondary
                      : Colors.grey.shade400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(Race race) {
    if (race.isObserver) return _buildObserverActions();
    if (race.isPreparing) return _buildPreparingActions(race);
    if (race.isInProgress) return _buildInProgressActions(race);
    return const SizedBox.shrink();
  }

  Widget _buildObserverActions() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _onQuitWatch,
        icon: const Icon(Icons.visibility_off, size: 18),
        label: const Text('Quit Watch',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Future<void> _onQuitWatch() async {
    final ok = await TraxDialog.confirm(context,
        title: 'Quit Watch', message: 'Stop watching this race?');
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

  Widget _buildBikeSelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BikePickerTile(
        selectedBikeId: _selectedBikeId,
        bikes: _myBikes,
        onSelected: _onChangeBike,
      ),
    );
  }

  Widget _buildPreparingActions(Race race) {
    final parts = race.participants
        .where((p) => p.role == 'host' || p.role == 'rider')
        .toList();
    final allReady = parts.every((p) => p.isReady || p.isHost);
    final bikeSelector = _buildBikeSelector();
    if (race.isHost) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        bikeSelector,
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _onGoRace,
            icon: const Icon(Icons.play_arrow, size: 22),
            label: const Text('Race!',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
          ),
        ),
        if (!allReady)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Some riders are not ready yet',
                style:
                    TextStyle(fontSize: 12, color: Colors.orange[700])),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 42,
          child: OutlinedButton.icon(
            onPressed: _onCancelRace,
            icon: const Icon(Icons.cancel, size: 16),
            label: const Text('Cancel Race',
                style: TextStyle(fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ]);
    } else {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        bikeSelector,
        if (!_amReady)
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _onReady,
              icon: const Icon(Icons.check_circle, size: 22),
              label: const Text("I'm Ready!",
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle,
                    color: AppColors.success, size: 22),
                SizedBox(width: 8),
                Text('Ready! Waiting for host...',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.success)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 42,
          child: OutlinedButton.icon(
            onPressed: _onQuitRace,
            icon: const Icon(Icons.exit_to_app, size: 16),
            label: const Text('Quit Race',
                style: TextStyle(fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ]);
    }
  }

  Widget _buildInProgressActions(Race race) {
    final myInfo =
        _liveData?.riders.where((r) => r.userId == _myId).firstOrNull;
    final statsRow = myInfo == null
        ? const SizedBox.shrink()
        : Row(children: [
            _miniStat('Distance',
                '${myInfo.distanceKm.toStringAsFixed(2)} km'),
            const SizedBox(width: 8),
            _miniStat(
                'Speed', '${myInfo.speed.toStringAsFixed(1)} km/h'),
            const SizedBox(width: 8),
            _miniStat('Laps',
                '${myInfo.completedLaps}/${_race?.targetLaps ?? 0}'),
          ]);

    if (race.isHost) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        statsRow,
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _onStopRace,
            icon: const Icon(Icons.stop, size: 22),
            label: const Text('Stop Race',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
          ),
        ),
      ]);
    }
    return statsRow;
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
            width: 40,
            height: 40,
            child:
                Icon(icon, size: 20, color: AppColors.textPrimary)),
      ),
    );
  }

  // ── Live ranking overlay (top-right of map) ───────────
  /// Builds a compact floating leaderboard showing the top 5 riders
  /// ranked by laps completed, then by distance, then by speed.
  /// Updates in real time as [_liveData] is polled.
  List<RiderLiveInfo> _rankedRiders(List<RiderLiveInfo> riders) {
    final list = [...riders];
    list.sort((a, b) {
      final aFin = a.status == 'finished' && a.finishRank != null;
      final bFin = b.status == 'finished' && b.finishRank != null;
      if (aFin && bFin) return a.finishRank!.compareTo(b.finishRank!);
      if (aFin) return -1;
      if (bFin) return 1;
      if (a.status == 'dnf' && b.status != 'dnf') return 1;
      if (b.status == 'dnf' && a.status != 'dnf') return -1;
      final lapCmp = b.completedLaps.compareTo(a.completedLaps);
      if (lapCmp != 0) return lapCmp;
      final distCmp = b.distanceKm.compareTo(a.distanceKm);
      if (distCmp != 0) return distCmp;
      return b.speed.compareTo(a.speed);
    });
    return list;
  }

  Widget _buildLiveRankingOverlay(List<RiderLiveInfo> riders) {
    final ranked = _rankedRiders(riders).take(5).toList();
    return Container(
      width: 168,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.12), blurRadius: 8),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.leaderboard, size: 14, color: AppColors.primary),
              SizedBox(width: 4),
              Text('Live Ranking',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 6),
          for (int i = 0; i < ranked.length; i++)
            _buildRankRow(i + 1, ranked[i]),
        ],
      ),
    );
  }

  Widget _buildRankRow(int rank, RiderLiveInfo r) {
    final isMe = r.userId == _myId;
    final rankColor = rank == 1
        ? const Color(0xFFFFC107)
        : rank == 2
            ? const Color(0xFFB0BEC5)
            : rank == 3
                ? const Color(0xFFCD7F32)
                : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: Text('$rank',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: rankColor)),
          ),
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: _colorFor(r.userId),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              r.userName ?? 'Rider',
              style: TextStyle(
                fontSize: 11,
                fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
                color: isMe ? AppColors.primary : AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            r.status == 'dnf' ? 'DNF' : 'L${r.completedLaps}',
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _cpToggleBtn() {
    final on = _showCheckpoints;
    return Material(
      color: on ? AppColors.primary : Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () =>
            setState(() => _showCheckpoints = !_showCheckpoints),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                on ? Icons.flag : Icons.flag_outlined,
                size: 16,
                color: on ? Colors.white : AppColors.textPrimary,
              ),
              const SizedBox(width: 4),
              Text(
                on ? 'Hide CP' : 'Show CP',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color:
                      on ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
