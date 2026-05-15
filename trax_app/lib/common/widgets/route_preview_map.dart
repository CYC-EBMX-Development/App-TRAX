import 'package:amap_flutter_base/amap_flutter_base.dart' as amap;
import 'package:amap_flutter_map/amap_flutter_map.dart' as amap_map;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;

import '../services/map_provider.dart';
import '../utils/amap_adapter.dart';
import '../utils/map_gesture_recognizers.dart';
import '../utils/map_region.dart';
import '../utils/start_end_marker_icons.dart';
import '../utils/start_end_marker_icons_amap.dart';
import '../../theme/app_theme.dart';

/// Provider-agnostic preview map that renders a single WGS-84 route as a
/// polyline with optional start / finish markers. Internally chooses
/// `GoogleMap` or `AMapWidget` based on the route's region (or the user's
/// current map provider preference for empty routes).
///
/// Use this for any read-only / "summary" map block (ride detail header,
/// race detail thumbnail, trail-pick preview, etc.). For interactive maps
/// (live recording, multi-rider replay) create a dedicated AMap variant
/// instead.
class RoutePreviewMap extends StatefulWidget {
  final List<gmap.LatLng> route;
  final bool showStart;
  final bool showFinish;
  final bool gesturesEnabled;
  final bool myLocationEnabled;
  final double padding;
  final MapProvider? providerOverride;

  const RoutePreviewMap({
    super.key,
    required this.route,
    this.showStart = true,
    this.showFinish = true,
    this.gesturesEnabled = true,
    this.myLocationEnabled = false,
    this.padding = 50,
    this.providerOverride,
  });

  @override
  State<RoutePreviewMap> createState() => _RoutePreviewMapState();
}

class _RoutePreviewMapState extends State<RoutePreviewMap> {
  gmap.GoogleMapController? _gController;
  amap_map.AMapController? _aController;

  MapProvider get _provider {
    if (widget.providerOverride != null) return widget.providerOverride!;
    if (widget.route.isNotEmpty) {
      return MapRegion.providerForRoute(widget.route);
    }
    return MapProviderService.current;
  }

  @override
  void didUpdateWidget(covariant RoutePreviewMap old) {
    super.didUpdateWidget(old);
    if (old.route != widget.route) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
    }
  }

  Future<void> _fitBounds() async {
    final pts = widget.route;
    if (pts.isEmpty) return;
    if (_provider == MapProvider.amap) {
      if (_aController == null) return;
      final amapPts = AmapAdapter.toAmapList(pts);
      if (amapPts.length == 1) {
        await _aController!
            .moveCamera(amap_map.CameraUpdate.newLatLngZoom(amapPts.first, 15));
        return;
      }
      double minLat = amapPts.first.latitude, maxLat = amapPts.first.latitude;
      double minLng = amapPts.first.longitude, maxLng = amapPts.first.longitude;
      for (final p in amapPts) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      await _aController!.moveCamera(amap_map.CameraUpdate.newLatLngBounds(
        amap.LatLngBounds(
          southwest: amap.LatLng(minLat, minLng),
          northeast: amap.LatLng(maxLat, maxLng),
        ),
        widget.padding,
      ));
    } else {
      if (_gController == null) return;
      if (pts.length == 1) {
        await _gController!
            .animateCamera(gmap.CameraUpdate.newLatLngZoom(pts.first, 15));
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
      await _gController!.animateCamera(gmap.CameraUpdate.newLatLngBounds(
        gmap.LatLngBounds(
          southwest: gmap.LatLng(minLat, minLng),
          northeast: gmap.LatLng(maxLat, maxLng),
        ),
        widget.padding,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.route.isEmpty) {
      return Container(
        color: AppColors.background,
        child: const Center(
          child: Icon(Icons.map_outlined,
              size: 64, color: AppColors.textSecondary),
        ),
      );
    }
    return _provider == MapProvider.amap ? _buildAmap() : _buildGoogle();
  }

  Widget _buildGoogle() {
    final pts = widget.route;
    final markers = <gmap.Marker>{};
    if (widget.showStart) {
      markers.add(gmap.Marker(
        markerId: const gmap.MarkerId('start'),
        position: pts.first,
        icon: StartEndMarkerIcons.start,
        anchor: const Offset(0.5, 0.5),
      ));
    }
    if (widget.showFinish && pts.length > 1) {
      markers.add(gmap.Marker(
        markerId: const gmap.MarkerId('finish'),
        position: pts.last,
        icon: StartEndMarkerIcons.finish,
        anchor: const Offset(0.5, 0.5),
      ));
    }
    return gmap.GoogleMap(
      initialCameraPosition: gmap.CameraPosition(
        target: pts[pts.length ~/ 2],
        zoom: 14,
      ),
      polylines: {
        if (pts.length >= 2)
          gmap.Polyline(
            polylineId: const gmap.PolylineId('route'),
            points: pts,
            color: AppColors.primary,
            width: 4,
          ),
      },
      markers: markers,
      myLocationEnabled: widget.myLocationEnabled,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      compassEnabled: false,
      mapToolbarEnabled: false,
      gestureRecognizers:
          widget.gesturesEnabled ? kMapGestureRecognizers : const {},
      onMapCreated: (c) {
        _gController = c;
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
      },
    );
  }

  Widget _buildAmap() {
    final pts = widget.route;
    final markers = <amap_map.Marker>{};
    if (widget.showStart) {
      markers.add(amap_map.Marker(
        position: AmapAdapter.toAmap(pts.first),
        icon: StartEndMarkerIconsAmap.start,
        anchor: const Offset(0.5, 0.5),
      ));
    }
    if (widget.showFinish && pts.length > 1) {
      markers.add(amap_map.Marker(
        position: AmapAdapter.toAmap(pts.last),
        icon: StartEndMarkerIconsAmap.finish,
        anchor: const Offset(0.5, 0.5),
      ));
    }
    return amap_map.AMapWidget(
      privacyStatement: AmapAdapter.privacy(),
      apiKey: AmapAdapter.apiKey(),
      initialCameraPosition: AmapAdapter.initialCamera(pts, zoom: 14),
      polylines: {
        if (pts.length >= 2) AmapAdapter.routePolyline(pts),
      },
      markers: markers,
      scrollGesturesEnabled: widget.gesturesEnabled,
      zoomGesturesEnabled: widget.gesturesEnabled,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      gestureRecognizers: widget.gesturesEnabled
          ? <Factory<OneSequenceGestureRecognizer>>{
              Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
            }
          : const {},
      onMapCreated: (c) {
        _aController = c;
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
      },
    );
  }
}
