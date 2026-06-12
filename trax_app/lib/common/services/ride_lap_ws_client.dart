import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../network/trax_api.dart';
import '../utils/trax_storage_util.dart';

/// Subscribes to backend `/ws/rides/{rideId}/laps` and emits each lap
/// event as a JSON map. Sink-only — clients fan messages into their own
/// state container.
///
/// Server pushes two event types:
///   • `{type:"lap", rideId, lapNumber, completedLaps, targetLaps, status, endTime}`
///   • `{type:"completed", rideId, completedLaps, targetLaps, endTime}`
///
/// The server force-closes the session after the `completed` event;
/// the auto-reconnect loop is therefore short-circuited via [dispose].
class RideLapWsClient {
  RideLapWsClient({required this.rideId});

  final int rideId;

  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  WebSocket? _socket;
  bool _closed = false;
  int _backoffMs = 1000;
  Timer? _reconnectTimer;

  Stream<Map<String, dynamic>> get stream => _controller.stream;
  bool get isConnected =>
      _socket != null && _socket!.readyState == WebSocket.open;

  /// Build the WS URL by reusing TraxApi's base URL (http→ws, https→wss).
  String _wsUrl() {
    final base = TraxApi.activeBaseUrl;
    final uri = Uri.parse(base);
    final wsScheme = (uri.scheme == 'https') ? 'wss' : 'ws';
    final basePath = uri.path.endsWith('/api')
        ? uri.path.substring(0, uri.path.length - 4)
        : uri.path;
    return Uri(
      scheme: wsScheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '$basePath/ws/rides/$rideId/laps',
    ).toString();
  }

  Future<void> connect() async {
    if (_closed) return;
    _reconnectTimer?.cancel();
    try {
      final token = TraxStorageUtil.getToken();
      final headers = <String, dynamic>{};
      if (token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
      _socket = await WebSocket.connect(_wsUrl(), headers: headers)
          .timeout(const Duration(seconds: 8));
      _backoffMs = 1000;
      _socket!.listen(
        _onMessage,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) _controller.add(json);
    } catch (_) {/* ignore malformed */}
  }

  void _scheduleReconnect() {
    _socket = null;
    if (_closed) return;
    final delay = Duration(milliseconds: _backoffMs);
    _backoffMs = (_backoffMs * 2).clamp(1000, 30000);
    _reconnectTimer = Timer(delay, connect);
  }

  Future<void> dispose() async {
    _closed = true;
    _reconnectTimer?.cancel();
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    await _controller.close();
  }
}
