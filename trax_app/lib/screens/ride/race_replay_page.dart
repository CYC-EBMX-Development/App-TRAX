import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../common/utils/map_gesture_recognizers.dart';
import '../../common/utils/cp_marker_icons.dart';
import '../../common/utils/start_end_marker_icons.dart';
import '../../common/utils/ride_checkpoints.dart';

import '../../common/network/trax_api.dart';
import '../../common/global/global_user_info.dart';
import '../../models/race_live_data.dart';
import '../../models/user_checkpoint.dart';
import '../../theme/app_theme.dart';
import '../../widgets/lap_splits_grid.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class RaceReplayPage extends StatefulWidget {
  final String raceName;
  final int targetLaps;
  final List<RiderLiveInfo> riders;
  final bool isLaps;
  /// Optional trail id — when supplied, the actual trail checkpoints are
  /// drawn on the map (matching what the riders raced on) instead of
  /// being inferred from completed laps.
  final int? trailId;

  const RaceReplayPage({
    super.key,
    required this.raceName,
    required this.targetLaps,
    required this.riders,
    this.isLaps = false,
    this.trailId,
  });

  @override
  State<RaceReplayPage> createState() => _RaceReplayPageState();
}

class _ReplayRiderData {
  final RiderLiveInfo rider;
  final List<LatLng> route;
  final List<DateTime>? timestamps;
  final List<double> speeds; // km/h, length matches route when available

  const _ReplayRiderData({
    required this.rider,
    required this.route,
    required this.timestamps,
    required this.speeds,
  });
}

class _RaceReplayPageState extends State<RaceReplayPage> {
  GoogleMapController? _mapController;
  bool _mapReady = false;
  bool _loading = true;

  List<_ReplayRiderData> _riders = [];
  final Map<int, bool> _visibility = {};

  /// Trail checkpoints (loaded from the trail when [widget.trailId] is set).
  List<UserCheckpoint> _trailCheckpoints = const [];

  int _step = 0;
  int _maxSteps = 1;
  bool _playing = false;
  Timer? _timer;
  double _speed = 1.0;

  static const _riderColors = [
    // Curated multi-rider palette. Avoid orange/yellow hues so the
    // riders never collide with the trail color (AppColors.primary,
    // #FFB800). Matches the live race tracking palette.
    Color(0xFF4285F4), // blue
    Color(0xFFEA4335), // red
    Color(0xFF34A853), // green
    Color(0xFF9C27B0), // purple
    Color(0xFF00BCD4), // cyan
    Color(0xFFE91E63), // pink
    Color(0xFF3F51B5), // indigo
    Color(0xFF8BC34A), // light green
  ];

  @override
  void initState() {
    super.initState();
    _loadReplayData();
    _loadTrailCheckpoints();
  }

  Future<void> _loadTrailCheckpoints() async {
    final trailId = widget.trailId;
    if (trailId == null) return;
    final resp = await TraxApi.getTrailCheckpoints(trailId);
    if (!mounted) return;
    if (resp.isSuccess() && resp.data is List) {
      final cps = (resp.data as List)
          .map((e) => UserCheckpoint.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.sequenceIndex.compareTo(b.sequenceIndex));
      setState(() => _trailCheckpoints = cps);
      if (cps.isNotEmpty) {
        // ignore: use_build_context_synchronously
        CpMarkerIcons.warm(context, cps.map((c) => c.sequenceIndex))
            .then((built) {
          if (built && mounted) setState(() {});
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadReplayData() async {
    final list = <_ReplayRiderData>[];

    for (final r in widget.riders) {
      List<LatLng> route = List<LatLng>.from(r.route);
      List<DateTime>? times;
      List<double> speeds = [];
      if (r.rideId != null) {
        final resp = await TraxApi.getRidePoints(r.rideId!);
        if (resp.isSuccess() && resp.data is List) {
          final pts = (resp.data as List)
              .map((e) => e as Map<String, dynamic>)
              .toList();
          if (pts.isNotEmpty) {
            route = pts
                .map((p) => LatLng(
                      (p['latitude'] as num).toDouble(),
                      (p['longitude'] as num).toDouble(),
                    ))
                .toList();
            speeds = pts
                .map((p) => (p['speed'] as num?)?.toDouble() ?? 0.0)
                .toList();
            times = pts
                .map((p) => DateTime.tryParse(p['timestamp']?.toString() ?? ''))
                .whereType<DateTime>()
                .toList();
            if (times.length != route.length) times = null;
          }
        }
      }

      if (route.isEmpty && r.latitude != 0 && r.longitude != 0) {
        route = [LatLng(r.latitude, r.longitude)];
      }
      if (speeds.length != route.length) {
        speeds = List<double>.filled(route.length, 0.0);
      }

      // Trim arrays 5 seconds after the rider's final-lap end time so each
      // rider's marker/trail stops shortly after they complete all required
      // laps (avoids replaying extra distance traveled before their ride was
      // auto-ended).
      DateTime? trimAt;
      if (r.laps.isNotEmpty && widget.targetLaps > 0) {
        final finalLap = r.laps
            .where((l) => l.endTime != null && l.lapNumber >= widget.targetLaps)
            .toList();
        if (finalLap.isNotEmpty) {
          trimAt = finalLap.first.endTime!.add(const Duration(seconds: 5));
        }
      }
      if (trimAt != null && times != null) {
        int cut = times.length;
        for (int i = 0; i < times.length; i++) {
          if (times[i].isAfter(trimAt)) {
            cut = i;
            break;
          }
        }
        if (cut > 0 && cut < times.length) {
          route = route.sublist(0, cut);
          times = times.sublist(0, cut);
          speeds = speeds.sublist(0, cut);
        }
      }

      list.add(_ReplayRiderData(
        rider: r,
        route: route,
        timestamps: times,
        speeds: speeds,
      ));
      _visibility[r.userId] = true;
    }

    int maxSteps = 1;
    for (final r in list) {
      if (r.route.length > maxSteps) maxSteps = r.route.length;
    }

    if (!mounted) return;
    setState(() {
      _riders = list;
      _maxSteps = maxSteps;
      _loading = false;
    });
    _ensureMarkerIcons();
    _fitReplayBounds();
  }

  /// Fit the camera so the entire replay (all rider routes + checkpoints)
  /// fits on screen. Called once on map ready and again once rider data
  /// finishes loading (whichever happens last).
  void _fitReplayBounds() {
    if (!_mapReady || _mapController == null) return;
    final pts = <LatLng>[
      for (final r in _riders) ...r.route,
      for (final cp in _trailCheckpoints) LatLng(cp.latitude, cp.longitude),
    ];
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(pts.first, 16),
      );
      return;
    }
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60,
      ),
    );
  }

  int? get _myId => GlobalUserInfo.instance.id.value;

  /// Display name for a rider — shows "You" if it's the current user.
  String _displayName(RiderLiveInfo r) {
    if (_myId != null && r.userId == _myId) return 'You';
    return (r.userName ?? 'Rider').split(' ').first;
  }

  final Map<int, BitmapDescriptor> _markerIcons = {};
  // Track the avatar URL used to build each cached marker so a new ?v=<...>
  // cache-buster from the backend forces a fresh bitmap.
  final Map<int, String?> _markerAvatarUrls = {};

  Future<void> _ensureMarkerIcons() async {
    bool anyNew = false;
    for (final r in _riders) {
      final uid = r.rider.userId;
      final url = r.rider.userAvatarUrl;
      if (_markerIcons.containsKey(uid) && _markerAvatarUrls[uid] == url) {
        continue;
      }
      anyNew = true;
      _markerIcons[uid] = await _createMarkerIcon(
        r.rider.userName ?? 'Rider',
        _colorFor(uid),
        uid == _myId,
        url,
      );
      _markerAvatarUrls[uid] = url;
    }
    if (anyNew && mounted) setState(() {});
  }

  /// Resolve a network image URL into a [ui.Image] using Flutter's image
  /// pipeline. Returns null on any failure (network error, decode error,
  /// missing URL).
  Future<ui.Image?> _loadNetworkImage(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final completer = Completer<ui.Image>();
      final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) completer.complete(info.image);
          stream.removeListener(listener);
        },
        onError: (e, st) {
          if (!completer.isCompleted) completer.completeError(e);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);
      return await completer.future;
    } catch (_) {
      return null;
    }
  }

  Future<BitmapDescriptor> _createMarkerIcon(
      String name, Color color, bool isMe, String? avatarUrl) async {
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
    final totalH =
        borderW + circleR * 2 + borderW + gap + nameH + nameBgPad * 2 + 2 * dpr;
    final cx = w / 2;
    final cy = borderW + circleR;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, totalH));
    // White outer ring
    canvas.drawCircle(
      Offset(cx, cy),
      circleR + borderW / 2,
      Paint()..color = Colors.white,
    );
    // Avatar (real account photo) or color-filled fallback circle.
    final avatarImg = await _loadNetworkImage(avatarUrl);
    if (avatarImg != null) {
      // Clip to a circle and draw the avatar image scaled to fit.
      canvas.save();
      final clipPath = Path()
        ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: circleR));
      canvas.clipPath(clipPath);
      final srcRect = Rect.fromLTWH(
          0, 0, avatarImg.width.toDouble(), avatarImg.height.toDouble());
      final dstRect = Rect.fromCircle(center: Offset(cx, cy), radius: circleR);
      canvas.drawImageRect(avatarImg, srcRect, dstRect, Paint());
      canvas.restore();
      // Colored ring on top of the avatar so each rider stays identifiable.
      canvas.drawCircle(
        Offset(cx, cy),
        circleR,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderW,
      );
    } else {
      canvas.drawCircle(Offset(cx, cy), circleR, Paint()..color = color);
      final initialTp = TextPainter(
        text: TextSpan(
          text: displayName.isEmpty ? '?' : displayName[0].toUpperCase(),
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
    nameTp.paint(canvas, Offset(cx - nameTp.width / 2, nameY + nameBgPad / 2));
    final picture = recorder.endRecording();
    final image = await picture.toImage(w.toInt(), totalH.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      byteData!.buffer.asUint8List(),
      width: w / dpr,
      height: totalH / dpr,
    );
  }

  void _playPause() {
    if (_playing) {
      _timer?.cancel();
      setState(() => _playing = false);
      return;
    }
    if (_step >= _maxSteps - 1) {
      setState(() => _step = 0);
    }
    setState(() => _playing = true);
    _tick();
  }

  void _tick() {
    _timer?.cancel();
    if (!_playing) return;
    final ms = (650 / _speed).clamp(60, 2000).toInt();
    _timer = Timer(Duration(milliseconds: ms), () {
      if (!mounted || !_playing) return;
      if (_step >= _maxSteps - 1) {
        setState(() => _playing = false);
        return;
      }
      setState(() => _step++);
      _tick();
    });
  }

  Color _colorFor(int userId) {
    final idx = widget.riders.indexWhere((r) => r.userId == userId);
    final i = idx < 0 ? 0 : idx;
    return _riderColors[i % _riderColors.length];
  }

  LatLng? _currentPos(_ReplayRiderData r) {
    if (r.route.isEmpty) return null;
    final i = _step.clamp(0, r.route.length - 1);
    return r.route[i];
  }

  DateTime? _currentReplayTime() {
    final stamps = _riders
        .where((r) => r.timestamps != null && r.timestamps!.isNotEmpty)
        .map((r) {
          final i = _step.clamp(0, r.timestamps!.length - 1);
          return r.timestamps![i];
        })
        .toList();
    if (stamps.isEmpty) return null;
    stamps.sort();
    return stamps.last;
  }

  int _completedLapsAtStep(_ReplayRiderData r, DateTime? currentTs) {
    if (r.rider.laps.isEmpty) return 0;
    if (currentTs == null) {
      final ratio = _maxSteps <= 1 ? 0 : (_step / (_maxSteps - 1));
      return (r.rider.laps.length * ratio).floor().clamp(0, r.rider.laps.length);
    }
    int c = 0;
    for (final l in r.rider.laps) {
      if (l.endTime != null && !currentTs.isBefore(l.endTime!)) c++;
    }
    return c;
  }

  double _distanceAtStep(_ReplayRiderData r) {
    if (r.route.length < 2) return 0;
    final end = _step.clamp(1, r.route.length - 1);
    double km = 0;
    for (int i = 1; i <= end; i++) {
      km += Geolocator.distanceBetween(
              r.route[i - 1].latitude,
              r.route[i - 1].longitude,
              r.route[i].latitude,
              r.route[i].longitude) /
          1000;
    }
    return km;
  }

  double _currentSpeed(_ReplayRiderData r) {
    if (r.speeds.isEmpty) return 0;
    final i = _step.clamp(0, r.speeds.length - 1);
    return r.speeds[i];
  }

  /// Origin (earliest) timestamp across all riders.
  DateTime? _replayOrigin() {
    DateTime? earliest;
    for (final r in _riders) {
      final ts = r.timestamps;
      if (ts == null || ts.isEmpty) continue;
      if (earliest == null || ts.first.isBefore(earliest)) earliest = ts.first;
    }
    return earliest;
  }

  /// Total replay duration in seconds (max minus origin).
  int _totalDurationSec() {
    final origin = _replayOrigin();
    if (origin == null) return 0;
    DateTime? latest;
    for (final r in _riders) {
      final ts = r.timestamps;
      if (ts == null || ts.isEmpty) continue;
      if (latest == null || ts.last.isAfter(latest)) latest = ts.last;
    }
    if (latest == null) return 0;
    return latest.difference(origin).inSeconds;
  }

  int _elapsedSecAtStep() {
    final origin = _replayOrigin();
    final ts = _currentReplayTime();
    if (origin == null || ts == null) return 0;
    return ts.difference(origin).inSeconds.clamp(0, 1 << 30);
  }

  String _fmtTime(int seconds) {
    if (seconds < 0) seconds = 0;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  List<_ReplayRiderData> _rankedRiders() {
    final ts = _currentReplayTime();
    final list = List<_ReplayRiderData>.from(_riders);
    list.sort((a, b) {
      final aL = _completedLapsAtStep(a, ts);
      final bL = _completedLapsAtStep(b, ts);
      if (aL != bL) return bL.compareTo(aL);
      final aD = _distanceAtStep(a);
      final bD = _distanceAtStep(b);
      return bD.compareTo(aD);
    });
    return list;
  }

  Set<Polyline> _buildPolylines() {
    final set = <Polyline>{};
    // Req 4: later riders overlay earlier ones via increasing zIndex.
    var z = 1;
    for (final r in _riders) {
      if (!(_visibility[r.rider.userId] ?? true)) continue;
      if (r.route.length < 2) continue;
      final end = _step.clamp(1, r.route.length - 1);
      set.add(
        Polyline(
          polylineId: PolylineId('r_${r.rider.userId}'),
          points: r.route.sublist(0, end + 1),
          color: _colorFor(r.rider.userId),
          width: 4,
          zIndex: z++,
        ),
      );
    }
    return set;
  }

  Set<Marker> _buildMarkers() {
    final set = <Marker>{};
    // Prefer the actual trail checkpoints (matches what the riders raced
    // through). Fall back to per-pass aggregation if no trail was provided.
    final cpAgg = <int, LatLng>{};
    if (_trailCheckpoints.isNotEmpty) {
      for (final cp in _trailCheckpoints) {
        cpAgg[cp.sequenceIndex] = LatLng(cp.latitude, cp.longitude);
      }
    } else {
      for (final r in _riders) {
        for (final entry in rideCheckpointPositions(r.rider.laps).entries) {
          cpAgg.putIfAbsent(entry.key, () => entry.value);
        }
      }
    }
    set.addAll(CpMarkerIcons.buildMarkers(
      context,
      cpAgg,
      onWarmed: () { if (mounted) setState(() {}); },
    ));
    // Start / finish marker: first point of any rider's route.
    final startPos = _riders
        .map((r) => r.route.isNotEmpty ? r.route.first : null)
        .whereType<LatLng>()
        .firstOrNull;
    if (startPos != null) {
      set.add(
        Marker(
          markerId: const MarkerId('start_finish'),
          position: startPos,
          icon: StartEndMarkerIcons.start,
          anchor: const Offset(0.5, 0.5),
          zIndex: 5,
          infoWindow: const InfoWindow(title: 'Start / Finish'),
        ),
      );
    }
    for (final r in _riders) {
      if (!(_visibility[r.rider.userId] ?? true)) continue;
      final pos = _currentPos(r);
      if (pos == null) continue;
      set.add(
        Marker(
          markerId: MarkerId('m_${r.rider.userId}'),
          position: pos,
          icon: _markerIcons[r.rider.userId] ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 0.32),
          // Riders always above CP pins.
          zIndex: 10,
          infoWindow: InfoWindow(
            title: _displayName(r.rider),
            snippet: '${_distanceAtStep(r).toStringAsFixed(2)} km',
          ),
        ),
      );
    }
    return set;
  }

  /// Per-lap leaderboard for the bottom panel — like race_tracking but only
  /// includes laps whose endTime is <= the current replay timestamp. Each
  /// entry shows finish rank, name, and lap time.
  Widget _buildLapLeaderboard() {
    final ts = _currentReplayTime();
    int maxLap = 0;
    for (final r in _riders) {
      for (final l in r.rider.laps) {
        if (l.endTime == null) continue;
        if (ts != null && l.endTime!.isAfter(ts)) continue;
        if (l.lapNumber > maxLap) maxLap = l.lapNumber;
      }
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
      for (final r in _riders) {
        final l = r.rider.laps
            .where((x) =>
                x.lapNumber == lap &&
                x.endTime != null &&
                (ts == null || !x.endTime!.isAfter(ts)))
            .firstOrNull;
        if (l != null) entries.add(MapEntry(r.rider, l));
      }
      if (entries.isEmpty) continue;
      entries.sort((a, b) =>
          (a.value.endTime as DateTime).compareTo(b.value.endTime as DateTime));

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
                    final lapDto = e.value.value;
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
                          backgroundColor: color.withValues(alpha: 0.18),
                          backgroundImage: rider.userAvatarUrl != null
                              ? NetworkImage(rider.userAvatarUrl!)
                              : null,
                          child: rider.userAvatarUrl == null
                              ? Text(
                                  (rider.userName ?? '?')[0].toUpperCase(),
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: color),
                                )
                              : null,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _displayName(rider),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          fmt(lapDto.durationSeconds as int),
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

    if (lapWidgets.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
          child: Icon(icon, size: 20, color: AppColors.textPrimary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '409', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final firstPos = _riders
            .map(_currentPos)
            .whereType<LatLng>()
            .cast<LatLng?>()
            .firstOrNull ??
        const LatLng(22.8956, 113.8739);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          // ── Map area (fixed: bottom panel never overlaps) ──
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition:
                      CameraPosition(target: firstPos, zoom: 15),
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  gestureRecognizers: kMapGestureRecognizers,
                  polylines: _buildPolylines(),
                  markers: _buildMarkers(),
                  onMapCreated: (c) {
                    _mapController = c;
                    _mapReady = true;
                    _fitReplayBounds();
                  },
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 12,
                  right: 12,
                  child: Row(
                    children: [
                      _circleBtn(
                          Icons.arrow_back, () => Navigator.pop(context)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                  color:
                                      Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 6)
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.replay,
                                  size: 18, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${widget.raceName} · Replay',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Live ranking overlay (right side) — animates when
                // positions change. LAPS-mode ranks by best lap; otherwise
                // by completed laps + distance.
                if (_riders.length >= 2)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 64,
                    right: 10,
                    child: _buildMapRankingOverlay(),
                  ),
              ],
            ),
          ),
          // ── Bottom control panel (fixed; never overlaps map) ──
          Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 12,
                    offset: Offset(0, -2)),
              ],
            ),
            padding: EdgeInsets.fromLTRB(
                16, 14, 16, MediaQuery.of(context).padding.bottom + 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isLaps)
                  _buildLapsTabbedCardReplay()
                else
                  _buildLapLeaderboard(),
                const SizedBox(height: 10),
                _buildPlayerHeader(),
                const SizedBox(height: 8),
                _buildSeekRow(),
                const SizedBox(height: 6),
                _buildLapRow(),
                const SizedBox(height: 8),
                _buildPlaybackButtons(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----- Player UI helpers (#409) -----

  /// Lead rider used to surface a single km/h on the player header.
  _ReplayRiderData? _leaderForHeader() {
    final ranked = _rankedRiders();
    if (ranked.isEmpty) return null;
    // Prefer "me" if visible and present, otherwise the current leader.
    final myId = _myId;
    if (myId != null) {
      final me = ranked.firstWhere(
        (r) => r.rider.userId == myId,
        orElse: () => ranked.first,
      );
      return me;
    }
    return ranked.first;
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerHeader() {
    final leader = _leaderForHeader();
    final speed = leader == null ? 0.0 : _currentSpeed(leader);
    final elapsed = _elapsedSecAtStep();
    // Speed label:
    //   • 1×, 2×, 4×, 8×        (real-time + fast-forward)
    //   • 0.5×, 0.25×           (slow-motion)
    final String speedLabel;
    if (_speed >= 1) {
      speedLabel = '${_speed.toInt()}x';
    } else if ((_speed - 0.5).abs() < 0.01) {
      speedLabel = '0.5x';
    } else {
      speedLabel = '0.25x';
    }
    return Row(
      children: [
        _infoChip(Icons.bolt, '${speed.toStringAsFixed(1)} km/h'),
        const SizedBox(width: 8),
        _infoChip(Icons.timer, _fmtTime(elapsed)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            speedLabel,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSeekRow() {
    final elapsed = _elapsedSecAtStep();
    final total = _totalDurationSec();
    // Drive the slider from wall-clock time (elapsed/total) so the thumb
    // tracks the time labels exactly. Going by sample index (_step /
    // _maxSteps) makes the bar lag because riders have very different
    // numbers of GPS samples.
    final canScrub = total > 0 && _maxSteps > 1;
    final sliderValue =
        canScrub ? elapsed.toDouble().clamp(0, total.toDouble()) : 0.0;
    return Row(
      children: [
        Text(
          _fmtTime(elapsed),
          style: const TextStyle(
              fontSize: 11, color: AppColors.textSecondary),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor:
                  AppColors.primary.withValues(alpha: 0.2),
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.1),
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: sliderValue.toDouble(),
              min: 0,
              max: total > 0 ? total.toDouble() : 1,
              onChanged: !canScrub
                  ? null
                  : (v) => _seekToSeconds(v.round()),
            ),
          ),
        ),
        Text(
          _fmtTime(total),
          style: const TextStyle(
              fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  /// Seek the replay to the sample whose timestamp is closest to
  /// `originSeconds` from the replay origin. Used by the time-based scrub
  /// bar so dragging the thumb actually moves time linearly.
  void _seekToSeconds(int originSeconds) {
    final origin = _replayOrigin();
    if (origin == null || _maxSteps <= 1) return;
    final target = origin.add(Duration(seconds: originSeconds));
    // Pick the step whose currentReplayTime is closest to target.
    int bestStep = 0;
    int bestDiff = 1 << 30;
    final stamps = _riders
        .where((r) => r.timestamps != null && r.timestamps!.isNotEmpty)
        .toList();
    if (stamps.isEmpty) {
      setState(() => _step =
          ((_maxSteps - 1) * (originSeconds / _totalDurationSec()))
              .round()
              .clamp(0, _maxSteps - 1));
      return;
    }
    for (int s = 0; s < _maxSteps; s++) {
      DateTime? ts;
      for (final r in stamps) {
        final i = s.clamp(0, r.timestamps!.length - 1);
        final t = r.timestamps![i];
        if (ts == null || t.isAfter(ts)) ts = t;
      }
      if (ts == null) continue;
      final diff = ts.difference(target).inSeconds.abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestStep = s;
      }
    }
    setState(() => _step = bestStep);
  }

  // ── LAPS-mode tabbed card (Leaderboard / My Laps) ─────

  /// Rank riders by **best lap so far** (used by the LAPS-mode map
  /// ranking overlay). Riders with no completed lap fall to the bottom in
  /// their original order.
  List<_ReplayRiderData> _rankedByBestLap() {
    final ts = _currentReplayTime();
    int? best(_ReplayRiderData r) {
      int? b;
      for (final l in r.rider.laps) {
        if (l.endTime == null) continue;
        if (ts != null && l.endTime!.isAfter(ts)) continue;
        if (b == null || l.durationSeconds < b) b = l.durationSeconds;
      }
      return b;
    }

    final list = List<_ReplayRiderData>.from(_riders);
    list.sort((a, b) {
      final ba = best(a);
      final bb = best(b);
      if (ba == null && bb == null) return 0;
      if (ba == null) return 1;
      if (bb == null) return -1;
      return ba.compareTo(bb);
    });
    return list;
  }

  /// Live ranking overlay shown on the right edge of the map.
  ///
  /// LAPS-mode races are ranked by **best lap so far**; other races fall
  /// back to the lap-count + distance ordering used elsewhere. When the
  /// ranking changes the rows animate to their new vertical position via
  /// AnimatedPositioned.
  Widget _buildMapRankingOverlay() {
    final ranked =
        widget.isLaps ? _rankedByBestLap() : _rankedRiders();
    if (ranked.isEmpty) return const SizedBox.shrink();

    final ts = _currentReplayTime();
    int? bestForRider(_ReplayRiderData r) {
      int? b;
      for (final l in r.rider.laps) {
        if (l.endTime == null) continue;
        if (ts != null && l.endTime!.isAfter(ts)) continue;
        if (b == null || l.durationSeconds < b) b = l.durationSeconds;
      }
      return b;
    }

    String fmtLap(int s) {
      final m = s ~/ 60;
      final ss = s % 60;
      return '$m:${ss.toString().padLeft(2, '0')}';
    }

    const double rowHeight = 30;
    const double rowGap = 4;
    const double width = 116;
    final stackHeight =
        ranked.length * rowHeight + (ranked.length - 1) * rowGap;

    return SizedBox(
      width: width,
      height: stackHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < ranked.length; i++)
            AnimatedPositioned(
              key: ValueKey('rank_${ranked[i].rider.userId}'),
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              top: i * (rowHeight + rowGap),
              left: 0,
              right: 0,
              height: rowHeight,
              child: _RankingRow(
                rank: i + 1,
                rider: ranked[i].rider,
                color: _colorFor(ranked[i].rider.userId),
                isMe: _myId != null && ranked[i].rider.userId == _myId,
                bestLapText: widget.isLaps
                    ? (() {
                        final b = bestForRider(ranked[i]);
                        return b == null ? '—' : fmtLap(b);
                      })()
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  /// Returns the in-progress lap (if any) for [r] at replay timestamp [ts],
  /// the lap number (1-based), checkpoint passes already recorded by [ts],
  /// and the elapsed seconds since lap start.
  ({
    int lapNumber,
    List<({int sequenceIndex, int secondsFromLapStart})> passes,
    int elapsedSeconds,
  })? _inProgressLapAtTs(_ReplayRiderData r, DateTime? ts) {
    if (ts == null) return null;
    for (final l in r.rider.laps) {
      final st = l.startTime;
      if (st == null) continue;
      if (st.isAfter(ts)) continue;
      // Lap is in-progress at ts when no end yet, or end is after ts.
      final ended = l.endTime != null && !l.endTime!.isAfter(ts);
      if (ended) continue;
      final elapsed = ts.difference(st).inSeconds.clamp(0, 1 << 30);
      final passes = <({int sequenceIndex, int secondsFromLapStart})>[];
      for (final p in l.checkpointPasses) {
        if (p.secondsFromLapStart <= elapsed) {
          passes.add((
            sequenceIndex: p.sequenceIndex,
            secondsFromLapStart: p.secondsFromLapStart,
          ));
        }
      }
      passes.sort((a, b) => a.sequenceIndex.compareTo(b.sequenceIndex));
      return (
        lapNumber: l.lapNumber,
        passes: passes,
        elapsedSeconds: elapsed,
      );
    }
    return null;
  }

  Widget _buildLapsTabbedCardReplay() {
    // Per request: drop the Leaderboard tab, keep only My Laps splits.
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: const [
              Icon(Icons.view_timeline_outlined,
                  size: 16, color: AppColors.primary),
              SizedBox(width: 6),
              Text('My Laps',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 8),
          _buildReplayMyLapsBody(),
        ],
      ),
    );
  }

  /// "My Laps" body — pre-loaded skeleton from targetLaps; fills cells live
  /// as the replay progresses. Includes the in-progress lap row when "me"
  /// is mid-lap at the current replay timestamp.
  Widget _buildReplayMyLapsBody() {
    final ts = _currentReplayTime();
    final myId = _myId;
    _ReplayRiderData? me;
    if (myId != null) {
      for (final d in _riders) {
        if (d.rider.userId == myId) {
          me = d;
          break;
        }
      }
    }
    me ??= _leaderForHeader();
    if (me == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No rider data available.',
            style:
                TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      );
    }

    final completed = me.rider.laps
        .where((l) =>
            l.endTime != null &&
            (ts == null || !l.endTime!.isAfter(ts)))
        .toList()
      ..sort((a, b) => a.lapNumber.compareTo(b.lapNumber));

    final inProgress = _inProgressLapAtTs(me, ts);

    // Checkpoint count for skeleton: prefer the trail CPs, otherwise the
    // longest known checkpoint sequence we've seen across this rider.
    int cpCount = _trailCheckpoints.length;
    if (cpCount == 0) {
      for (final l in me.rider.laps) {
        if (l.checkpointPasses.length > cpCount) {
          cpCount = l.checkpointPasses.length;
        }
      }
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: SingleChildScrollView(
        child: LapSplitsGrid(
          laps: completed,
          accentColor: AppColors.primary,
          targetLaps: widget.targetLaps,
          checkpointCount: cpCount,
          currentLapNumber: inProgress?.lapNumber,
          currentLapPasses: inProgress?.passes,
          currentLapElapsed: inProgress?.elapsedSeconds,
        ),
      ),
    );
  }

  Widget _buildLapRow() {
    final leader = _leaderForHeader();
    final ts = _currentReplayTime();
    final laps = leader == null ? 0 : _completedLapsAtStep(leader, ts);
    final total = widget.targetLaps;
    final currentLapNum = (laps + 1).clamp(1, total == 0 ? 99 : total);
    int currentLapElapsed = 0;
    if (leader != null && ts != null) {
      DateTime? lapStart;
      if (laps == 0) {
        lapStart = leader.timestamps?.firstOrNull ?? _replayOrigin();
      } else {
        final prev = leader.rider.laps
            .where((l) => l.lapNumber == laps && l.endTime != null)
            .firstOrNull;
        lapStart = prev?.endTime;
      }
      if (lapStart != null) {
        currentLapElapsed =
            ts.difference(lapStart).inSeconds.clamp(0, 1 << 30);
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(
            total > 0 ? 'Lap $currentLapNum / $total' : 'Lap $currentLapNum',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const Spacer(),
          Text(
            _fmtTime(currentLapElapsed),
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _playerSideBtn(
          Icons.fast_rewind,
          _speed > 0.25
              ? () => setState(() {
                    _speed /= 2;
                    if (_playing) _tick();
                  })
              : null,
        ),
        const SizedBox(width: 22),
        SizedBox(
          width: 56,
          height: 56,
          child: ElevatedButton(
            onPressed: _playPause,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
              elevation: 2,
            ),
            child: Icon(
              _playing ? Icons.pause : Icons.play_arrow,
              size: 30,
            ),
          ),
        ),
        const SizedBox(width: 22),
        _playerSideBtn(
          Icons.fast_forward,
          _speed < 8
              ? () => setState(() {
                    _speed *= 2;
                    if (_playing) _tick();
                  })
              : null,
        ),
      ],
    );
  }

  Widget _playerSideBtn(IconData icon, VoidCallback? onTap) {
    return Material(
      color: onTap != null
          ? AppColors.background
          : AppColors.background.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            size: 24,
            color: onTap != null
                ? AppColors.textPrimary
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}



/// One row in the live ranking overlay shown on the map.
///
/// Contains the rank pill, rider avatar, first name and (LAPS-mode only)
/// the rider's best lap time. Rendered inside an [AnimatedPositioned] so
/// the row slides smoothly when its rank changes.
class _RankingRow extends StatelessWidget {
  final int rank;
  final RiderLiveInfo rider;
  final Color color;
  final bool isMe;
  final String? bestLapText;

  const _RankingRow({
    required this.rank,
    required this.rider,
    required this.color,
    required this.isMe,
    this.bestLapText,
  });

  @override
  Widget build(BuildContext context) {
    final medal = rank == 1
        ? const Color(0xFFFFC107)
        : rank == 2
            ? const Color(0xFFB0BEC5)
            : rank == 3
                ? const Color(0xFFCD7F32)
                : null;
    final name = (rider.userName ?? 'Rider').split(' ').first;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isMe
              ? AppColors.primary
              : (medal ?? Colors.black.withValues(alpha: 0.06)),
          width: isMe ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: medal ?? AppColors.textSecondary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: medal != null ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          CircleAvatar(
            radius: 9,
            backgroundColor: color.withValues(alpha: 0.18),
            backgroundImage:
                rider.userAvatarUrl != null ? NetworkImage(rider.userAvatarUrl!) : null,
            child: rider.userAvatarUrl == null
                ? Text(
                    name.isEmpty ? '?' : name[0].toUpperCase(),
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
              isMe ? 'You' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: isMe ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
          ),
          if (bestLapText != null) ...[
            const SizedBox(width: 4),
            Text(
              bestLapText!,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
