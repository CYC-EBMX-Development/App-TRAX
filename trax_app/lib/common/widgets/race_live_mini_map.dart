import 'dart:ui' as ui;

import 'package:amap_flutter_map/amap_flutter_map.dart' as amap_map;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;

import '../utils/amap_adapter.dart';
import '../utils/map_gesture_recognizers.dart';
import '../utils/map_region.dart';
import '../services/map_provider.dart';

/// One rider entry for [RaceLiveMiniMap].
class RaceLiveRider {
  final int userId;
  final String? name;
  final double latitude;
  final double longitude;
  final int completedLaps;
  final double distanceKm;
  final Color color;

  const RaceLiveRider({
    required this.userId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.completedLaps,
    required this.distanceKm,
    required this.color,
  });
}

/// A compact, read-only map used inside the race-detail header to show
/// where each rider currently is. Renders Google Maps or AMap based on
/// the global provider preference, using small colored-circle markers
/// (one per rider) so each colour stays distinct across providers.
class RaceLiveMiniMap extends StatefulWidget {
  final List<RaceLiveRider> riders;
  final int targetLaps;
  final double height;
  final gmap.LatLng fallbackCenter;

  const RaceLiveMiniMap({
    super.key,
    required this.riders,
    required this.targetLaps,
    this.height = 250,
    this.fallbackCenter = const gmap.LatLng(22.89810, 113.86990),
  });

  @override
  State<RaceLiveMiniMap> createState() => _RaceLiveMiniMapState();
}

class _RaceLiveMiniMapState extends State<RaceLiveMiniMap> {
  final Map<int, amap_map.BitmapDescriptor> _amapDots = {};
  final Set<int> _amapPending = <int>{};

  MapProvider get _provider {
    final fromCoord = widget.riders.isNotEmpty
        ? MapRegion.providerForCoord(
            widget.riders.first.latitude, widget.riders.first.longitude)
        : null;
    return fromCoord ?? MapProviderService.current;
  }

  Future<void> _ensureAmapDot(int userId, Color color) async {
    if (_amapDots.containsKey(userId) || _amapPending.contains(userId)) return;
    _amapPending.add(userId);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final r = 9.0 * dpr;
    final borderW = 2.0 * dpr;
    final size = (r + borderW) * 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
    final c = Offset(size / 2, size / 2);
    canvas.drawCircle(c, r + borderW / 2, Paint()..color = Colors.white);
    canvas.drawCircle(c, r, Paint()..color = color);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted) return;
    setState(() {
      _amapDots[userId] =
          amap_map.BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
      _amapPending.remove(userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child:
          _provider == MapProvider.amap ? _buildAmap() : _buildGoogle(),
    );
  }

  Widget _buildGoogle() {
    final markers = <gmap.Marker>{};
    for (final r in widget.riders) {
      if (r.latitude == 0 && r.longitude == 0) continue;
      markers.add(gmap.Marker(
        markerId: gmap.MarkerId('rider_${r.userId}'),
        position: gmap.LatLng(r.latitude, r.longitude),
        icon:
            gmap.BitmapDescriptor.defaultMarkerWithHue(_hueFromColor(r.color)),
        infoWindow: gmap.InfoWindow(
          title: r.name ?? 'Rider',
          snippet:
              'Lap ${r.completedLaps}/${widget.targetLaps} · ${r.distanceKm.toStringAsFixed(1)} km',
        ),
      ));
    }
    final initialPos = markers.isNotEmpty
        ? markers.first.position
        : widget.fallbackCenter;
    return gmap.GoogleMap(
      initialCameraPosition: gmap.CameraPosition(target: initialPos, zoom: 15),
      markers: markers,
      myLocationEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      gestureRecognizers: kMapGestureRecognizers,
    );
  }

  Widget _buildAmap() {
    final markers = <amap_map.Marker>{};
    for (final r in widget.riders) {
      if (r.latitude == 0 && r.longitude == 0) continue;
      _ensureAmapDot(r.userId, r.color);
      markers.add(amap_map.Marker(
        position:
            AmapAdapter.toAmap(gmap.LatLng(r.latitude, r.longitude)),
        icon: _amapDots[r.userId] ??
            amap_map.BitmapDescriptor.defaultMarker,
        anchor: const Offset(0.5, 0.5),
        infoWindow: amap_map.InfoWindow(
          title: r.name ?? 'Rider',
          snippet:
              'Lap ${r.completedLaps}/${widget.targetLaps} · ${r.distanceKm.toStringAsFixed(1)} km',
        ),
      ));
    }
    final firstRider = widget.riders.firstWhere(
      (r) => r.latitude != 0 || r.longitude != 0,
      orElse: () => RaceLiveRider(
        userId: -1,
        name: null,
        latitude: widget.fallbackCenter.latitude,
        longitude: widget.fallbackCenter.longitude,
        completedLaps: 0,
        distanceKm: 0,
        color: Colors.red,
      ),
    );
    return amap_map.AMapWidget(
      privacyStatement: AmapAdapter.privacy(),
      apiKey: AmapAdapter.apiKey(),
      initialCameraPosition: amap_map.CameraPosition(
        target: AmapAdapter.toAmap(
            gmap.LatLng(firstRider.latitude, firstRider.longitude)),
        zoom: 15,
      ),
      markers: markers,
      scrollGesturesEnabled: true,
      zoomGesturesEnabled: true,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
      },
    );
  }

  static double _hueFromColor(Color c) {
    if (c == Colors.blue) return gmap.BitmapDescriptor.hueBlue;
    if (c == Colors.red) return gmap.BitmapDescriptor.hueRed;
    if (c == Colors.green) return gmap.BitmapDescriptor.hueGreen;
    if (c == Colors.purple) return gmap.BitmapDescriptor.hueViolet;
    if (c == Colors.orange) return gmap.BitmapDescriptor.hueOrange;
    if (c == Colors.teal) return gmap.BitmapDescriptor.hueCyan;
    if (c == Colors.pink) return gmap.BitmapDescriptor.hueRose;
    if (c == Colors.indigo) return gmap.BitmapDescriptor.hueBlue;
    return gmap.BitmapDescriptor.hueRed;
  }
}
