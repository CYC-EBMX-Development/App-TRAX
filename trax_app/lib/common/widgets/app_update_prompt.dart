import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_update_service.dart';
import '../../theme/app_theme.dart';

/// One-shot helper that surfaces the "Update Available" dialog flow.
///
/// Used by:
/// - Home screen: auto-prompt on first frame after [AppUpdateService.checkForUpdate]
///   resolves a newer build.
/// - Profile screen "App Version" tile: re-uses the same dialogs to keep
///   the UX consistent.
///
/// De-duplication rules (Home auto-prompt only — Profile always shows on tap):
/// 1. Shown at most once per app process (in-memory flag).
/// 2. If the user picks "Later" we persist the dismissed build code so the
///    same version never re-prompts, until a newer one is published.
class AppUpdatePrompt {
  AppUpdatePrompt._();

  static const String _prefsKeyDismissedCode = 'ota_dismissed_code_v1';
  static bool _shownThisSession = false;

  /// Auto-prompt entry-point for Home. Safe to call multiple times — it
  /// no-ops after the first invocation per process or if the user already
  /// dismissed this exact build.
  static Future<void> maybeShowOnHome(BuildContext context) async {
    if (_shownThisSession) return;
    final status = await AppUpdateService.instance.checkForUpdate();
    if (!status.hasUpdate || status.release == null) return;

    final release = status.release!;
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getString(_prefsKeyDismissedCode) ?? '';
    if (dismissed == release.latestCode) return;

    if (!context.mounted) return;
    _shownThisSession = true;
    await showUpdateDialog(context, release, dismissable: true);
  }

  /// Show the "Update Available" dialog. When [dismissable] is true and the
  /// user hits "Later" we remember the build code so the auto-prompt won't
  /// nag again for this same version.
  static Future<void> showUpdateDialog(
    BuildContext context,
    AppReleaseInfo release, {
    bool dismissable = false,
  }) async {
    if (Platform.isIOS) {
      await _showIosTestFlightDialog(context, release);
      return;
    }

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('A new version is ready to install.',
                style: TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            Text('Build:    ${release.latestCode}',
                style: const TextStyle(fontSize: 13)),
            Text('File:     ${release.filename}',
                style: const TextStyle(fontSize: 13)),
            Text('Size:     ${release.sizeMb} MB',
                style: const TextStyle(fontSize: 13)),
            if (release.releasedAt.isNotEmpty)
              Text('Released: ${release.releasedAt}',
                  style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Update Now'),
          ),
        ],
      ),
    );

    if (go == true) {
      if (!context.mounted) return;
      await _runDownloadAndInstall(context, release);
    } else if (dismissable) {
      // Remember this exact build code so the Home auto-prompt won't
      // re-show it on the next launch.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyDismissedCode, release.latestCode);
    }
  }

  static Future<void> _showIosTestFlightDialog(
      BuildContext context, AppReleaseInfo release) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'A new version is available on TestFlight.\n\n'
                'Please open the TestFlight app to update to the latest build.',
                style: TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            Text('Latest:   ${release.latestCode}',
                style: const TextStyle(fontSize: 13)),
            if (release.releasedAt.isNotEmpty)
              Text('Released: ${release.releasedAt}',
                  style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  static Future<void> _runDownloadAndInstall(
      BuildContext context, AppReleaseInfo release) async {
    final progress = ValueNotifier<double>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Downloading…'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, p, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: p > 0 ? p : null),
              const SizedBox(height: 12),
              Text('${(p * 100).toStringAsFixed(0)}%'),
            ],
          ),
        ),
      ),
    );
    try {
      await AppUpdateService.instance.downloadAndInstall(
        release,
        onProgress: (recv, total) {
          if (total > 0) progress.value = recv / total;
        },
      );
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      progress.dispose();
    }
  }
}
