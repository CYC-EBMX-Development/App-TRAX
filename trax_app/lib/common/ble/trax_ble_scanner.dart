import 'package:universal_ble/universal_ble.dart';

/// Lightweight BLE scanner for TRAX module discovery.
///
/// Only handles scanning – connection/command management is out of scope
/// for the device-picker page.
class TraxBleScanner {
  TraxBleScanner._();

  static final TraxBleScanner instance = TraxBleScanner._();

  // TRA-X modules advertise the Nordic UART Service (NUS).
  static const _uuidService = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';

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
      seen[device.deviceId] = device;

      if (isNew || _betterResult(existing, device)) {
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
}
