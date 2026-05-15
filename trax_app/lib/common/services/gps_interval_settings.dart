import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-selectable GPS sampling cadence used by the trail-recorder and
/// active-ride services. Persisted in SharedPreferences and surfaced in
/// Profile → Settings.
///
/// The selected value is the *base* interval; existing adaptive-sampling
/// code may still drop further (e.g. 100 ms near a lap boundary).
class GpsIntervalSettings {
  GpsIntervalSettings._();

  static const String _prefsKey = 'gps_interval_ms_v1';
  static const int defaultIntervalMs = 100;
  static const List<int> options = [100, 200, 500, 1000];

  static int _baseIntervalMs = defaultIntervalMs;

  /// Notifies listeners when the selection changes.
  static final ValueNotifier<int> notifier = ValueNotifier(defaultIntervalMs);

  static int get baseIntervalMs => _baseIntervalMs;

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt(_prefsKey);
      if (v != null && options.contains(v)) {
        _baseIntervalMs = v;
        notifier.value = v;
      }
    } catch (_) {
      // Keep default on any failure.
    }
  }

  static Future<void> set(int ms) async {
    if (!options.contains(ms) || ms == _baseIntervalMs) return;
    _baseIntervalMs = ms;
    notifier.value = ms;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKey, ms);
    } catch (_) {
      // ignore persistence failures
    }
  }

  static String labelFor(int ms) {
    if (ms >= 1000 && ms % 1000 == 0) {
      final s = ms ~/ 1000;
      return '$s s / fix';
    }
    return '$ms ms / fix';
  }
}
