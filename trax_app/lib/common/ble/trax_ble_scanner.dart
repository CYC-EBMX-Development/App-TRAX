import 'dart:async';

import 'package:universal_ble/universal_ble.dart';

/// Lightweight BLE scanner for TRAX module discovery.
///
/// Scans for advertisements and, on demand, performs a one-shot GATT
/// connect + service-discovery handshake via [verifyConnect] to prove the
/// module is reachable. Long-lived command/control sessions are still out
/// of scope.
class TraxBleScanner {
  TraxBleScanner._();

  static final TraxBleScanner instance = TraxBleScanner._();

  // TRA-X modules advertise the CYC SPP service. The firmware declares it
  // as a 128-bit UUID in little-endian byte order (ESP-IDF convention):
  //   { 0xf2,0x04,0x0f,0x69, 0xb6,0xee,0xfb,0x90,
  //     0x15,0x43,0xe2,0x12, 0xf0,0xab,0xcc,0xeb }
  // Reversed to canonical big-endian → ebccabf0-12e2-4315-90fb-eeb6690f04f2.
  static const _uuidService = 'ebccabf0-12e2-4315-90fb-eeb6690f04f2';
  // Write + notify characteristics under the SPP service. Presence of BOTH
  // is our handshake — confirms this really is a TRA-X module and that the
  // GATT link came up, not just that the device advertised the right UUID.
  static const _uuidCharWrite  = 'ebccabf3-12e2-4315-90fb-eeb6690f04f2';
  static const _uuidCharNotify = 'ebccabf2-12e2-4315-90fb-eeb6690f04f2';

  bool _isScanning = false;

  bool get isScanning => _isScanning;

  /// Start a BLE scan.
  ///
  /// [onDeviceFound] is called each time a new device is discovered (or an
  /// existing one is updated with a stronger RSSI / a non-null name).
  /// [scanDuration] controls how long to keep the scanner running before
  /// automatically stopping (default 10 s).
  Future<void> startScan({
    required void Function(BleDevice device, bool isNew) onDeviceFound,
    Duration scanDuration = const Duration(seconds: 10),
  }) async {
    if (_isScanning) await stopScan();

    final seen = <String, BleDevice>{};
    _isScanning = true;

    UniversalBle.onScanResult = (BleDevice device) {
      final existing = seen[device.deviceId];
      final isNew = existing == null;

      // Keep the name if the new advertisement doesn't carry one.
      if (!isNew && device.name == null && existing.name != null) {
        device.name = existing.name;
      }
      // Detect a name that just arrived (iOS often omits Local Name in the
      // first ad packet — the next packet supplies it). We must surface that
      // to the UI so the cards stop showing the raw deviceId.
      final nameJustArrived = !isNew &&
          (existing.name == null || existing.name!.isEmpty) &&
          (device.name != null && device.name!.isNotEmpty);
      seen[device.deviceId] = device;

      if (isNew || nameJustArrived || _betterResult(existing, device)) {
        onDeviceFound(device, isNew);
      }
    };

    try {
      await UniversalBle.startScan(
        scanFilter: ScanFilter(withServices: [_uuidService]),
      );
    } catch (e) {
      _isScanning = false;
      return;
    }

    await Future.delayed(scanDuration);
    await stopScan();
  }

  Future<void> stopScan() async {
    if (!_isScanning) return;
    _isScanning = false;
    try {
      await UniversalBle.stopScan();
    } catch (_) {}
    UniversalBle.onScanResult = null;
  }

  /// Returns true when [updated] has a meaningfully better RSSI than [old].
  bool _betterResult(BleDevice? old, BleDevice updated) {
    final oldRssi = old?.rssi ?? -100;
    final newRssi = updated.rssi ?? -100;
    return newRssi > oldRssi + 3;
  }

  /// Try a real GATT connect + service discovery against [deviceId].
  ///
  /// Returns `null` on success. On failure returns a short, user-facing
  /// reason (already English). Always best-effort disconnects before
  /// returning so we don't hold the link.
  ///
  /// We deliberately do NOT read/write any value — presence of the SPP
  /// service + both write/notify characteristics is enough to prove this
  /// is a real TRA-X module that the phone could actually talk to. Anything
  /// further (firmware version, SIM state) belongs in a follow-up.
  Future<String?> verifyConnect(
    String deviceId, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    bool didConnect = false;
    try {
      var connectErr;
      var timedOut = false;
      await UniversalBle.connect(deviceId, connectionTimeout: timeout)
          .catchError((e) {
            if (e is TimeoutException) {
              timedOut = true;
            } else {
              connectErr = e;
            }
          })
          .timeout(timeout, onTimeout: () => timedOut = true);
      if (timedOut) return 'Connect timed out. Move closer and try again.';
      if (connectErr != null) return 'Connect failed: $connectErr';
      didConnect = true;

      final services = await UniversalBle.discoverServices(deviceId);
      var hasService = false;
      var hasWrite = false;
      var hasNotify = false;
      for (final s in services) {
        if (s.uuid.toLowerCase() != _uuidService) continue;
        hasService = true;
        for (final c in s.characteristics) {
          final u = c.uuid.toLowerCase();
          if (u == _uuidCharWrite) hasWrite = true;
          if (u == _uuidCharNotify) hasNotify = true;
        }
      }
      if (!hasService) return 'Not a TRA-X module (service missing).';
      if (!hasWrite || !hasNotify) {
        return 'TRA-X service incomplete — firmware may be out of date.';
      }
      return null;
    } catch (e) {
      return 'Connect error: $e';
    } finally {
      if (didConnect) {
        try {
          await UniversalBle.disconnect(deviceId);
        } catch (_) {}
      }
    }
  }
}
