import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'module_packet_codec.dart';

/// Result of a [TraxModuleCommandClient.queryMqttUsername] call.
class ModuleUsernameResult {
  final String? username;
  final String? error;

  const ModuleUsernameResult._({this.username, this.error});

  factory ModuleUsernameResult.success(String username) =>
      ModuleUsernameResult._(username: username);

  factory ModuleUsernameResult.failure(String error) =>
      ModuleUsernameResult._(error: error);

  bool get isSuccess => username != null && username!.isNotEmpty;
}

/// One-shot BLE command client for the TRA-X module.
///
/// Connects, issues a single command over the SPP write characteristic,
/// awaits the matching reply on the notify characteristic, then always
/// disconnects. The module's MQTT username (= its certificate CN / deviceId,
/// the prefix every telemetry topic is keyed by) cannot be guessed, so it is
/// read live from the module rather than typed by the user.
class TraxModuleCommandClient {
  TraxModuleCommandClient._();

  static final TraxModuleCommandClient instance = TraxModuleCommandClient._();

  // SPP service + characteristics — must match the firmware GATT table
  // (see trax_ble_scanner.dart and VESC-express landon BLE component).
  static const _uuidService = 'ebccabf0-12e2-4315-90fb-eeb6690f04f2';
  static const _uuidCharWrite = 'ebccabf3-12e2-4315-90fb-eeb6690f04f2';
  static const _uuidCharNotify = 'ebccabf2-12e2-4315-90fb-eeb6690f04f2';

  /// Connect to [deviceId], read the module's MQTT username and disconnect.
  ///
  /// Returns a [ModuleUsernameResult]; on any failure the result carries a
  /// short, English, user-facing [ModuleUsernameResult.error].
  Future<ModuleUsernameResult> queryMqttUsername(
    String deviceId, {
    Duration connectTimeout = const Duration(seconds: 8),
    Duration replyTimeout = const Duration(seconds: 5),
  }) async {
    // `onValueChange` is a global, setter-only handler in universal_ble. No
    // other screen installs one (scanning uses `onScanResult`), so we own it
    // for the duration of this call and clear it in `finally`.
    var didConnect = false;
    final completer = Completer<ModuleUsernameResult>();

    void complete(ModuleUsernameResult r) {
      if (!completer.isCompleted) completer.complete(r);
    }

    try {
      try {
        await UniversalBle.connect(deviceId, connectionTimeout: connectTimeout)
            .timeout(connectTimeout);
      } on TimeoutException {
        return ModuleUsernameResult.failure(
            'Connect timed out. Move closer and try again.');
      } catch (e) {
        return ModuleUsernameResult.failure('Connect failed: $e');
      }
      didConnect = true;

      // Locate the write + notify characteristics.
      final services = await UniversalBle.discoverServices(deviceId);
      BleCharacteristic? writeChar;
      var hasNotify = false;
      for (final s in services) {
        if (s.uuid.toLowerCase() != _uuidService) continue;
        for (final c in s.characteristics) {
          final u = c.uuid.toLowerCase();
          if (u == _uuidCharWrite) writeChar = c;
          if (u == _uuidCharNotify) hasNotify = true;
        }
      }
      if (writeChar == null || !hasNotify) {
        return ModuleUsernameResult.failure(
            'TRA-X service incomplete — firmware may be out of date.');
      }

      // Listen for the reply before writing the request.
      UniversalBle.onValueChange = (id, characteristic, value) {
        if (id != deviceId) return;
        if (characteristic.toLowerCase() != _uuidCharNotify) return;
        final packet = ModulePacketCodec.decode(value);
        if (packet == null ||
            packet.cmd != ModulePacketCodec.cmdMqttUsernameQuery) {
          return;
        }
        // RE_FAIL is a single 0x00 byte; a real username is a non-empty,
        // non-null string.
        final p = packet.payload;
        if (p.isEmpty || (p.length == 1 && p[0] == 0x00)) {
          complete(ModuleUsernameResult.failure(
              'Module could not provide its cloud username.'));
          return;
        }
        try {
          complete(ModuleUsernameResult.success(utf8.decode(p)));
        } catch (_) {
          complete(ModuleUsernameResult.failure(
              'Received a malformed username from the module.'));
        }
      };

      await UniversalBle.setNotifiable(
        deviceId,
        _uuidService,
        _uuidCharNotify,
        BleInputProperty.notification,
      );

      final request =
          ModulePacketCodec.encode(ModulePacketCodec.cmdMqttUsernameQuery);
      final supportsNoResponse =
          writeChar.properties.contains(CharacteristicProperty.writeWithoutResponse);
      await UniversalBle.writeValue(
        deviceId,
        _uuidService,
        _uuidCharWrite,
        Uint8List.fromList(request),
        supportsNoResponse
            ? BleOutputProperty.withoutResponse
            : BleOutputProperty.withResponse,
      );

      return await completer.future.timeout(
        replyTimeout,
        onTimeout: () => ModuleUsernameResult.failure(
            'No reply from the module. Try again closer to it.'),
      );
    } catch (e) {
      return ModuleUsernameResult.failure('Read failed: $e');
    } finally {
      UniversalBle.onValueChange = null;
      if (didConnect) {
        try {
          await UniversalBle.setNotifiable(
            deviceId,
            _uuidService,
            _uuidCharNotify,
            BleInputProperty.disabled,
          );
        } catch (_) {}
        try {
          await UniversalBle.disconnect(deviceId);
        } catch (_) {}
      }
    }
  }
}
