import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:install_plugin/install_plugin.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// One snapshot of `version.json` published on the OTA server.
///
/// Server JSON shape (kept stable):
/// ```json
/// {
///   "latest":      "260513-01",
///   "filename":    "trax-test-260513-01.apk",
///   "url":         "/apk/trax-latest.apk",
///   "sha1":        "....",
///   "size_mb":     58,
///   "released_at": "2026-05-13T12:00:00+08:00"
/// }
/// ```
class AppReleaseInfo {
  /// Build code in the canonical `YYMMDD-NN` format.
  final String latestCode;
  final String filename;

  /// Path on the OTA host (or absolute http(s) URL).
  final String url;
  final String sha1;
  final int sizeMb;
  final String releasedAt;

  const AppReleaseInfo({
    required this.latestCode,
    required this.filename,
    required this.url,
    required this.sha1,
    required this.sizeMb,
    required this.releasedAt,
  });

  /// `260513-01` → `26051301`. Returns null if the format is unexpected.
  int? get buildNumber {
    final parts = latestCode.split('-');
    if (parts.length != 2) return null;
    final n = int.tryParse('${parts[0]}${parts[1].padLeft(2, '0')}');
    return n;
  }

  factory AppReleaseInfo.fromJson(Map<String, dynamic> j) => AppReleaseInfo(
        latestCode: (j['latest'] ?? '').toString(),
        filename: (j['filename'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
        sha1: (j['sha1'] ?? '').toString(),
        sizeMb: (j['size_mb'] is num) ? (j['size_mb'] as num).toInt() : 0,
        releasedAt: (j['released_at'] ?? '').toString(),
      );
}

/// Result of [AppUpdateService.checkForUpdate].
class AppUpdateStatus {
  final String currentVersion; // "1.0.0"
  final int currentBuildNumber; // 26051301 (parsed from PackageInfo.buildNumber)
  final AppReleaseInfo? release;

  const AppUpdateStatus({
    required this.currentVersion,
    required this.currentBuildNumber,
    required this.release,
  });

  bool get hasUpdate {
    final r = release?.buildNumber;
    if (r == null) return false;
    return r > currentBuildNumber;
  }

  /// Pretty current version, e.g. `1.0.0 (260513-01)`.
  String get displayCurrent {
    final code = _formatCode(currentBuildNumber);
    return code.isEmpty
        ? currentVersion
        : '$currentVersion ($code)';
  }

  static String _formatCode(int n) {
    if (n <= 0) return '';
    final s = n.toString();
    if (s.length < 8) return s;
    final date = s.substring(0, 6);
    final ctr = s.substring(6);
    return '$date-$ctr';
  }
}

/// Self-update service for Android OTA installs.
///
/// Flow:
/// 1. [checkForUpdate]   → fetch `version.json` and compare build numbers.
/// 2. [downloadAndInstall] → stream the APK to the app's cache dir, hand
///    the path to the system package installer via `install_plugin`.
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  /// Reactive flag indicating whether the most recent [checkForUpdate]
  /// found a newer build than the one installed. UI surfaces (e.g. the
  /// home-screen avatar badge) listen to this so they can show an
  /// unobtrusive "new update" hint without re-checking themselves.
  ///
  /// Cleared via [markUpdateSeen] when the user opens the Profile page
  /// where the full update tile lives.
  final ValueNotifier<bool> hasUpdateAvailable = ValueNotifier<bool>(false);

  void markUpdateSeen() {
    if (hasUpdateAvailable.value) hasUpdateAvailable.value = false;
  }

  /// Base URL of the OTA host. The Android OTA pipeline publishes both
  /// `version.json` and the APK under this prefix.
  ///
  /// NOTE: keep in sync with `scripts/upload_apk.sh`.
  static const String otaHost = 'http://43.99.48.204';
  static const String _versionUrlAndroid = '$otaHost/download/version.json';

  /// iOS uses a separate manifest because TestFlight builds are not
  /// downloaded directly: the file is updated manually whenever a new
  /// build is uploaded to App Store Connect (see
  /// `scripts/update_ios_version.sh`).
  static const String _versionUrlIos = '$otaHost/download/version-ios.json';

  static String get _versionUrl =>
      Platform.isIOS ? _versionUrlIos : _versionUrlAndroid;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(minutes: 5),
  ));

  /// Parse a build code like `260513-17` or `260513.17` (or with a
  /// trailing `.0` patch as Flutter produces on iOS) into the canonical
  /// `YYMMDDNN` integer used for comparison.
  static int _parseCode(String s) {
    // Accept: 260513-17, 260513.17, 260513.17.0, 260513-17.0
    final m = RegExp(r'^(\d{6})[-.](\d{1,3})').firstMatch(s);
    if (m == null) return 0;
    final date = m.group(1)!;
    final seq = m.group(2)!.padLeft(2, '0');
    return int.tryParse('$date$seq') ?? 0;
  }

  Future<AppUpdateStatus> checkForUpdate() async {
    final pkg = await PackageInfo.fromPlatform();
    // Android: buildNumber is already YYMMDDNN (e.g. 26051317).
    // iOS:     buildNumber is an epoch second for ASC monotonicity, so
    //          fall back to parsing the version string (CFBundleShort
    //          VersionString) which is `YYMMDD.NN[.0]`.
    int currentBuild = int.tryParse(pkg.buildNumber) ?? 0;
    if (Platform.isIOS || currentBuild < 20000000) {
      final fromVersion = _parseCode(pkg.version);
      if (fromVersion > 0) currentBuild = fromVersion;
    }
    AppReleaseInfo? release;
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        _versionUrl,
        options: Options(responseType: ResponseType.json),
      );
      if (resp.statusCode == 200 && resp.data != null) {
        release = AppReleaseInfo.fromJson(resp.data!);
      }
    } catch (_) {
      release = null;
    }
    final status = AppUpdateStatus(
      currentVersion: pkg.version,
      currentBuildNumber: currentBuild,
      release: release,
    );
    hasUpdateAvailable.value = status.hasUpdate;
    return status;
  }

  /// Streams the APK named in [release] into the app's cache dir, calling
  /// [onProgress] (received, total) as bytes arrive. On completion the
  /// system installer is launched and the future resolves with the
  /// installer's [InstallResult].
  ///
  /// Android only. iOS callers should redirect the user to a download
  /// page instead.
  Future<void> downloadAndInstall(
    AppReleaseInfo release, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (!Platform.isAndroid) {
      throw StateError('OTA install is supported on Android only');
    }
    final url = release.url.startsWith('http')
        ? release.url
        : '$otaHost${release.url}';

    final dir = await getExternalCacheDirectories();
    final cacheDir = (dir != null && dir.isNotEmpty)
        ? dir.first
        : await getApplicationCacheDirectory();
    final filename = release.filename.isNotEmpty
        ? release.filename
        : 'trax-update.apk';
    final apkPath = '${cacheDir.path}/$filename';

    // Wipe stale partials so we always end up with the right size.
    final f = File(apkPath);
    if (await f.exists()) {
      await f.delete();
    }

    await _dio.download(
      url,
      apkPath,
      onReceiveProgress: onProgress,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        receiveTimeout: const Duration(minutes: 10),
      ),
    );

    await InstallPlugin.installApk(apkPath);
  }
}
