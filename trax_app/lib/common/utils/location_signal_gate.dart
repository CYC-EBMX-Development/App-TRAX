import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/ebike.dart';
import '../../models/module_telemetry.dart';
import '../../services/active_ride_service.dart';
import '../network/trax_api.dart';
import '../widgets/trax_dialog.dart';

/// Shared pre-start signal check used by Lap Timer start, Free Ride start,
/// Host Race start, and Join Race ready buttons.
///
/// Returns `true` when the caller may proceed (signal OK, or user chose to
/// continue despite a stale module signal). Returns `false` when the action
/// should be cancelled (user declined, or phone GPS is unavailable).
class LocationSignalGate {
  LocationSignalGate._();

  /// Module telemetry is considered stale when its timestamp is older than
  /// this threshold.
  static const Duration moduleStaleAfter = Duration(seconds: 10);

  /// Convenience wrapper for callers that have a full [EBike] instance.
  static Future<bool> ensureSignalOrConfirm({
    required BuildContext context,
    required EBike bike,
  }) =>
      ensureSignalOrConfirmForSerial(
        context: context,
        traxSerial: bike.traxSerialNumber,
      );

  /// Core check. Pass [traxSerial] as the bike's TRAX module serial number
  /// (or `null` / empty for a phone-only bike).
  static Future<bool> ensureSignalOrConfirmForSerial({
    required BuildContext context,
    required String? traxSerial,
  }) async {
    final hasModule = traxSerial != null && traxSerial.isNotEmpty;
    if (hasModule) {
      return _checkModule(context, traxSerial);
    }
    return _checkPhone(context);
  }

  // ── Module path ───────────────────────────────────────────
  static Future<bool> _checkModule(BuildContext context, String serial) async {
    if (_telemetryFresh(ActiveRideService.instance.telemetry)) return true;

    // No fresh in-memory telemetry. Try a one-shot HTTP probe so the gate
    // can answer correctly before any WS subscription has been opened
    // (e.g. on the Lap Timer setup page).
    ModuleTelemetry? probed;
    try {
      final resp = await TraxApi.getModuleTelemetry(serial);
      if (resp.isSuccess() && resp.data is Map) {
        probed = ModuleTelemetry.fromJson(
            Map<String, dynamic>.from(resp.data as Map));
      }
    } catch (_) {
      probed = null;
    }
    if (_telemetryFresh(probed)) return true;

    if (!context.mounted) return false;
    final ok = await TraxDialog.confirm(
      context,
      title: 'Bike Signal Unavailable',
      message:
          'No recent signal from the bike module. Start anyway? Tracking will resume once the module reconnects.',
    );
    return ok == true;
  }

  static bool _telemetryFresh(ModuleTelemetry? t) {
    if (t == null) return false;
    final tsStr = t.timestamp;
    if (tsStr == null || tsStr.isEmpty) return false;
    final dt = DateTime.tryParse(tsStr);
    if (dt == null) return false;
    final ageMs =
        DateTime.now().millisecondsSinceEpoch - dt.millisecondsSinceEpoch;
    return ageMs >= 0 && ageMs <= moduleStaleAfter.inMilliseconds;
  }

  // ── Phone path ────────────────────────────────────────────
  static Future<bool> _checkPhone(BuildContext context) async {
    String? failure;
    try {
      final svcOn = await Geolocator.isLocationServiceEnabled();
      if (!svcOn) {
        failure = 'Location services are turned off on this device.';
      } else {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever) {
          failure = 'Location permission is required to use phone GPS.';
        } else {
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (_) {
      failure = 'Unable to acquire a GPS fix from the phone.';
    }

    if (failure == null) return true;
    if (!context.mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Phone GPS Unavailable',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Color(0xFF333333))),
        content: Text(
          '$failure\n\nResolve the issue before starting.',
          style: const TextStyle(fontSize: 14, color: Color(0xFF666666)),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK',
                style: TextStyle(
                    color: Color(0xFFFFB800), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    return false;
  }
}
