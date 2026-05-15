import 'dart:io';

import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

/// Whether to route Google APIs through the local dev HTTP proxy.
///
/// Set at build/run time via `--dart-define=USE_DEV_PROXY=true` when working on
/// a Mac/simulator where direct access to maps.googleapis.com is blocked and
/// Clash/Surge is running on 127.0.0.1:7897. On real devices (or any host
/// that doesn't have the local proxy) this MUST be false, otherwise every
/// request to Google APIs (static maps, geocoding) will fail.
const bool kUseDevProxy =
    bool.fromEnvironment('USE_DEV_PROXY', defaultValue: false);

/// Host:port of the local dev proxy. Override via
/// `--dart-define=DEV_PROXY_HOST=127.0.0.1:7897`.
const String kDevProxyHost =
    String.fromEnvironment('DEV_PROXY_HOST', defaultValue: '127.0.0.1:7897');

/// Apply the local dev proxy to [adapter] when [kUseDevProxy] is enabled in
/// debug builds. No-op on release builds and on real-device debug builds.
void applyDevProxy(IOHttpClientAdapter adapter) {
  if (!kDebugMode || !kUseDevProxy) return;
  adapter.createHttpClient = () {
    final client = HttpClient();
    client.findProxy = (uri) => 'PROXY $kDevProxyHost';
    client.badCertificateCallback = (cert, host, port) => true;
    return client;
  };
}
