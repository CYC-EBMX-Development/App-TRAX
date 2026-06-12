import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/coord_transform.dart';
import 'location_service.dart';

enum MapProvider { google, amap }

/// User-facing override mode. `auto` means "follow GPS location (default)";
/// `forceGoogle` / `forceAmap` pin the provider regardless of where the
/// device is.
enum MapProviderMode { auto, forceGoogle, forceAmap }

/// Lazily-determined map provider selection.
///
/// Decision is cached in SharedPreferences and re-evaluated only when
/// [refreshFromCurrentLocation] is invoked (e.g. at app startup or after the
/// user moves significantly). Pages should treat [current] as a hot value
/// that does not change mid-rendering.
class MapProviderService {
  MapProviderService._();

  static const String _prefsKey = 'map_provider_v1';
  static const String _modePrefsKey = 'map_provider_mode_v1';

  static MapProvider _auto = MapProvider.google;
  static MapProviderMode _mode = MapProviderMode.auto;

  /// Future that completes when the first GPS-based provider resolution
  /// finishes (success or failure). Used by [ensureResolved] so callers
  /// like the Trail Record / Ride entry routes can wait briefly before
  /// deciding which native map widget to open.
  static Future<void>? _firstResolveFuture;

  /// True once a real GPS fix (not just the cached pref) has been used to
  /// pick [_auto]. Background retries stop once this flips to true.
  static bool _resolvedFromGps = false;

  /// Resolved provider after applying the user's override.
  static MapProvider get current {
    switch (_mode) {
      case MapProviderMode.forceGoogle:
        return MapProvider.google;
      case MapProviderMode.forceAmap:
        return MapProvider.amap;
      case MapProviderMode.auto:
        return _auto;
    }
  }

  static bool get useAmap => current == MapProvider.amap;
  static MapProviderMode get mode => _mode;

  /// GPS-derived regional provider hint (ignores user override mode).
  /// Useful when we must ensure a map SDK is locally usable (e.g. observer
  /// watch mode in mainland China).
  static MapProvider get localRegionProvider => _auto;

  static bool get isMainlandRegion => _auto == MapProvider.amap;

  /// Resolve provider for a concrete client role.
  ///
  /// For rider/host flows, we keep the desired provider as-is.
  /// For observer flows, we force a mainland-safe fallback so Watch mode can
  /// still render when Google Maps is unreachable on the viewer device.
  static MapProvider resolveForClient({
    required bool isObserver,
    MapProvider? preferredProvider,
  }) {
    final desired = preferredProvider ?? current;
    if (!isObserver) return desired;
    if (desired == MapProvider.google && isMainlandRegion) {
      return MapProvider.amap;
    }
    return desired;
  }

  static bool observerFallbackApplied({MapProvider? preferredProvider}) {
    final desired = preferredProvider ?? current;
    return desired == MapProvider.google &&
        resolveForClient(isObserver: true, preferredProvider: desired) ==
            MapProvider.amap;
  }

  /// Notifies listeners when [current] changes. UI code can rebuild against
  /// this to reflect provider switches across app sessions.
  static final ValueNotifier<MapProvider> providerNotifier =
      ValueNotifier(MapProvider.google);

  /// Load the cached provider choice and (best-effort) refresh it from the
  /// current GPS reading. Safe to call before runApp.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == 'amap') {
      _auto = MapProvider.amap;
    } else if (raw == null) {
      // First-launch hint: no GPS yet, no cached choice. Bias the
      // default towards AMap when the device locale + timezone look
      // Chinese mainland — otherwise testers in CN see Google Maps
      // render first, then a jarring ~10s swap after the GPS fix
      // arrives. This is only a default; a real GPS fix later via
      // [applyForCoordinate] still wins.
      if (_looksLikeChinaByDeviceLocale()) {
        _auto = MapProvider.amap;
      }
    }
    final modeRaw = prefs.getString(_modePrefsKey);
    switch (modeRaw) {
      case 'google':
        _mode = MapProviderMode.forceGoogle;
        break;
      case 'amap':
        _mode = MapProviderMode.forceAmap;
        break;
      default:
        _mode = MapProviderMode.auto;
    }
    providerNotifier.value = current;
    // Silently resolve the provider from GPS in the background. We expose
    // the future via [_firstResolveFuture] so navigation entry points can
    // wait briefly (see [ensureResolved]).
    _firstResolveFuture = _silentResolveLoop();
  }

  /// Heuristic: device locale starts with `zh` AND timezone offset is
  /// UTC+8. Matches mainland China, HK, Macau, Taiwan, Singapore (close
  /// enough — worst case Singapore users see AMap initially then flip to
  /// Google once GPS resolves, which is the SAME behaviour CN users had
  /// before this hint, just inverted).
  static bool _looksLikeChinaByDeviceLocale() {
    try {
      final locale = Platform.localeName.toLowerCase();
      final isChineseLocale = locale.startsWith('zh');
      final isUtc8 = DateTime.now().timeZoneOffset == const Duration(hours: 8);
      return isChineseLocale && isUtc8;
    } catch (_) {
      return false;
    }
  }

  /// Run a sequence of background location fixes until one succeeds.
  /// First attempt is fast (last-known + low-accuracy current); if that
  /// returns nothing (e.g. permission still being granted, or no cached
  /// fix on iOS cold start), we retry with longer delays so the auto
  /// provider snaps to the right basemap soon after the user finishes the
  /// permission dialog — even if they haven't opened a map yet.
  static Future<void> _silentResolveLoop() async {
    // Sequence of attempts (cumulative wait ≈ 0 + 2 + 4 + 8 = 14s).
    const delaysSec = <int>[0, 2, 4, 8];
    for (final d in delaysSec) {
      if (d > 0) await Future<void>.delayed(Duration(seconds: d));
      if (_resolvedFromGps) return;
      final ok = await _attemptResolveFromGps();
      if (ok) {
        _resolvedFromGps = true;
        return;
      }
    }
  }

  /// Wait (up to [timeout]) for the first location-based provider
  /// resolution to complete. No-op when the user has pinned a provider
  /// via [setMode]. Safe to call repeatedly — only the first resolution
  /// is awaited; subsequent calls return immediately.
  ///
  /// Use this from navigation entry points that branch on the user's
  /// current location (Trail Record, Free Ride, …) so that opening the
  /// page right after app launch on a slow GPS fix doesn't fall back to
  /// the cached/default Google provider.
  static Future<void> ensureResolved({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (_mode != MapProviderMode.auto) return;
    final f = _firstResolveFuture;
    if (f == null) return;
    try {
      await f.timeout(timeout, onTimeout: () {});
    } catch (_) {}
  }

  /// Set the user-facing override mode and persist it.
  static Future<void> setMode(MapProviderMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _modePrefsKey,
      switch (mode) {
        MapProviderMode.forceGoogle => 'google',
        MapProviderMode.forceAmap => 'amap',
        MapProviderMode.auto => 'auto',
      },
    );
    providerNotifier.value = current;
  }

  /// Read the latest known GPS reading and update [current] if the device is
  /// now in (or out of) Chinese mainland. Failures are silently ignored.
  static Future<void> refreshFromCurrentLocation() async {
    final ok = await _attemptResolveFromGps();
    if (ok) _resolvedFromGps = true;
  }

  /// One attempt at resolving [_auto] from a real GPS fix. Returns true
  /// only when a coordinate was actually read and applied.
  static Future<bool> _attemptResolveFromGps() async {
    try {
      // Dual-source fix (Geolocator + AMap, first wins). AMap is what lets
      // the provider resolve correctly indoors in mainland China, where the
      // GMS network-location server is unreachable. Returns WGS-84.
      final fix = await LocationService.getFix(
        timeout: const Duration(seconds: 8),
      );
      if (fix == null) return false;
      await applyForCoordinate(fix.latitude, fix.longitude);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Apply provider selection based on an arbitrary WGS-84 coordinate.
  /// Persists the choice to SharedPreferences.
  static Future<void> applyForCoordinate(double lat, double lng) async {
    final next = CoordTransform.isInChinaMainland(lat, lng)
        ? MapProvider.amap
        : MapProvider.google;
    if (next == _auto) return;
    _auto = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, next == MapProvider.amap ? 'amap' : 'google');
    if (_mode == MapProviderMode.auto) {
      providerNotifier.value = current;
    }
  }
}
