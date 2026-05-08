import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'trax_button.dart';

class TraxDialog {
  TraxDialog._();

  static void showLoading({String? msg}) {
    SmartDialog.showLoading(msg: msg ?? 'Loading...');
  }

  static void hideLoading() {
    SmartDialog.dismiss(status: SmartStatus.loading);
  }

  static void messageTopDialog(String message, bool flag) {
    OverlayState? overlayState = Overlay.of(Get.context!);
    OverlayEntry overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: flag ? Colors.blue : Colors.red,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Row(
              children: [
                if (flag) const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
              ],
            ),
          ),
        ),
      ),
    );
    overlayState.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 3), () {
      if (overlayEntry.mounted) overlayEntry.remove();
    });
  }

  static void showBottomTipsDialog({
    required String title,
    required String content,
    required String mainBtnText,
    required VoidCallback mainBtnOnPressed,
    String? subBtnText,
    VoidCallback? subBtnOnPressed,
  }) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Text(content, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFFA0A0A0))),
            const SizedBox(height: 32),
            TraxButton.filled(
              text: mainBtnText,
              padding: const EdgeInsets.symmetric(vertical: 12),
              backgroundColor: const Color(0xFFFFB800),
              overlayColor: const Color(0xFFFFD04D),
              onPressed: mainBtnOnPressed,
            ),
            if (subBtnText != null)
              TraxButton.text(
                text: subBtnText,
                textStyle: const TextStyle(color: Color(0xFFABABAB)),
                overlayColor: Colors.grey[200],
                borderRadius: 20,
                onPressed: () => subBtnOnPressed != null ? subBtnOnPressed() : Get.back(),
              ),
          ],
        ),
      ),
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
    );
  }

  /// Simple confirmation dialog returning true/false.
  static Future<bool?> confirm(BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
        content: Text(message, style: const TextStyle(fontSize: 14, color: Color(0xFF666666))),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF999999))),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm', style: TextStyle(color: Color(0xFFFFB800), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
