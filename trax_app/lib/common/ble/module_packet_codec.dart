import 'dart:typed_data';

/// Wire codec for the TRA-X module command channel.
///
/// Mirrors the firmware framing in VESC-express
/// `components/PACKAGE/src/package.c` (landon branch). A frame is:
///
/// ```
/// [headLen:1][dataLen:1..3 big-endian][cmd:1][payload:N][crc16:2 big-endian][tail:0x03]
/// ```
///
/// * `dataLen` counts the command byte plus the payload (`payload.length + 1`).
/// * `headLen` is 2 when `dataLen <= 255`, 3 when `<= 65535`, otherwise 4.
/// * The CRC covers `[cmd] + payload` (i.e. `dataLen` bytes) and is
///   CRC-16/XMODEM (poly 0x1021, init 0x0000, no reflection, no xorout),
///   serialised big-endian.
/// * The frame is identical in both directions.
class ModulePacketCodec {
  ModulePacketCodec._();

  /// `MQTT_USERNAME_QUERY` — see `main/commands.h` (enum index 19).
  static const int cmdMqttUsernameQuery = 19;

  static const int _tail = 0x03;

  /// CRC-16/XMODEM over [data].
  static int crc16(List<int> data) {
    var crc = 0;
    for (final b in data) {
      crc ^= (b & 0xFF) << 8;
      for (var i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc & 0xFFFF;
  }

  /// Build a wire frame for [cmd] with an optional [payload].
  static Uint8List encode(int cmd, [List<int> payload = const []]) {
    final dataLen = payload.length + 1; // +1 for the command byte
    final int headLen = dataLen <= 0xFF
        ? 2
        : dataLen <= 0xFFFF
            ? 3
            : 4;

    final crcInput = <int>[cmd & 0xFF, ...payload.map((b) => b & 0xFF)];
    final crc = crc16(crcInput);

    final out = BytesBuilder();
    out.addByte(headLen);
    switch (headLen) {
      case 2:
        out.addByte(dataLen & 0xFF);
        break;
      case 3:
        out.addByte((dataLen >> 8) & 0xFF);
        out.addByte(dataLen & 0xFF);
        break;
      default:
        out.addByte((dataLen >> 16) & 0xFF);
        out.addByte((dataLen >> 8) & 0xFF);
        out.addByte(dataLen & 0xFF);
    }
    out.addByte(cmd & 0xFF);
    out.add(payload.map((b) => b & 0xFF).toList());
    out.addByte((crc >> 8) & 0xFF);
    out.addByte(crc & 0xFF);
    out.addByte(_tail);
    return out.toBytes();
  }

  /// Parse a wire frame. Returns null if the frame is malformed, the length
  /// is inconsistent, the CRC mismatches, or the tail byte is wrong.
  static ModulePacket? decode(List<int> packet) {
    if (packet.length < 6) return null;

    var offset = 0;
    final headLen = packet[offset++] & 0xFF;
    if (headLen < 2 || headLen > 4) return null;
    if (packet.length < headLen + 1) return null;

    int dataLen;
    switch (headLen) {
      case 2:
        dataLen = packet[offset++] & 0xFF;
        break;
      case 3:
        dataLen = ((packet[offset] & 0xFF) << 8) | (packet[offset + 1] & 0xFF);
        offset += 2;
        break;
      default:
        dataLen = ((packet[offset] & 0xFF) << 16) |
            ((packet[offset + 1] & 0xFF) << 8) |
            (packet[offset + 2] & 0xFF);
        offset += 3;
    }
    if (dataLen < 1) return null;

    final total = headLen + dataLen + 2 /*crc*/ + 1 /*tail*/;
    if (packet.length != total) return null;

    final cmd = packet[offset++] & 0xFF;
    final payloadLen = dataLen - 1;
    final payload = Uint8List(payloadLen);
    for (var i = 0; i < payloadLen; i++) {
      payload[i] = packet[offset++] & 0xFF;
    }

    final receivedCrc = ((packet[offset] & 0xFF) << 8) | (packet[offset + 1] & 0xFF);
    offset += 2;
    final calcCrc = crc16(packet.sublist(headLen, headLen + dataLen));
    if (receivedCrc != calcCrc) return null;

    if ((packet[offset] & 0xFF) != _tail) return null;

    return ModulePacket(cmd: cmd, payload: payload);
  }
}

/// A decoded module command frame.
class ModulePacket {
  final int cmd;
  final Uint8List payload;

  const ModulePacket({required this.cmd, required this.payload});
}
