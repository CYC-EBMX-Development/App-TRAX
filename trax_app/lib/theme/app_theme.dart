import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFFFFB800);
  static const Color primaryDark = Color(0xFFF5A623);
  static const Color background = Color(0xFFEDEDED);
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF333333);
  static const Color textSecondary = Color(0xFF999999);
  static const Color divider = Color(0xFFE0E0E0);
  static const Color error = Color(0xFFE53935);
  static const Color success = Color(0xFF43A047);
  static const Color warning = Color(0xFFE69100);
  // Note: trail polyline colors (selected, non-selected, dimmed-under-rider,
  // halo) live in `MapStyles` (lib/common/utils/map_styles.dart) — they are
  // map-styling concerns, not brand/UI colors. AppColors.primary (#FFB800)
  // remains the brand golden-yellow used by buttons, icons, banners, and
  // start/finish markers; trails on the map render in MapStyles.trailColor
  // (deep warm orange #FF6B00) with optional halo for the Strava-style look.
}

OverlayEntry? _activeTraxBanner;
VoidCallback? _activeTraxBannerCancel;

/// App-wide styled top banner (formerly a SnackBar).
///
/// Renders just below the status/app bar via the root [Overlay] so the
/// notification appears in the same spot on Android and iOS, regardless
/// of which Scaffold is on screen. Tapping dismisses it; otherwise it
/// auto-dismisses after [duration].
void showTraxSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
  Duration duration = const Duration(seconds: 3),
}) {
  // Cancel any in-flight banner first so the latest message wins.
  _activeTraxBannerCancel?.call();
  _activeTraxBanner?.remove();
  _activeTraxBanner = null;
  _activeTraxBannerCancel = null;

  final overlay = Overlay.of(context, rootOverlay: true);
  final mq = MediaQuery.of(context);
  // Sit just below the topbar. `padding.top` covers the status bar; the
  // floating pill bar on map pages (~44h + ~10 margins) and a standard
  // AppBar (kToolbarHeight = 56) both end around `padding.top + 56`, so a
  // single offset works for both. SafeArea is intentionally NOT used here
  // — wrapping a Positioned with SafeArea would re-add padding.top and
  // push the banner far below the topbar.
  final topInset = mq.padding.top + kToolbarHeight + 4;

  late OverlayEntry entry;
  void dismiss() {
    if (_activeTraxBanner == entry) {
      _activeTraxBanner = null;
      _activeTraxBannerCancel = null;
    }
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      top: topInset,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: dismiss,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isError ? AppColors.error : const Color(0xFF333333),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.info_outline,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  _activeTraxBanner = entry;
  overlay.insert(entry);

  // Schedule auto-dismiss; cancellable so a follow-up call can shorten it.
  bool cancelled = false;
  _activeTraxBannerCancel = () => cancelled = true;
  Future<void>.delayed(duration).then((_) {
    if (!cancelled) dismiss();
  });
}
