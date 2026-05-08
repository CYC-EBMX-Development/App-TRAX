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
    final topInset = MediaQuery.of(context).padding.top;
    // Vertically center the badge within the standard AppBar toolbar row,
    // and place it just to the right of the leading area so it sits visually
    // next to the page title rather than at the far right corner.
    const badgeHeight = 18.0;
    final top = topInset + (kToolbarHeight - badgeHeight) / 2;
    // Standard AppBar leading width is ~56; sit just past it.
    const leftOffset = 60.0;
    return Stack(
      children: [
        child,
        Positioned(
          top: top,
          left: leftOffset,
          child: IgnorePointer(
            child: Container(
              height: badgeHeight,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                '#$code',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
