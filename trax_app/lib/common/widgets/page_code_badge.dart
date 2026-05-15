import 'package:flutter/material.dart';

/// Wraps [child] (typically a Scaffold) with a small 3-digit page code badge
/// pinned to the top-right corner. Used for design/QA communication so we can
/// reference each page by a stable code (e.g. "408").
class PageCodeBadge extends StatelessWidget {
  final String code;
  final Widget child;

  const PageCodeBadge({super.key, required this.code, required this.child});

  @override
  Widget build(BuildContext context) {
    // Page code overlays are disabled in production; this is a no-op wrapper
    // so existing call sites compile unchanged.
    return child;
  }
}
