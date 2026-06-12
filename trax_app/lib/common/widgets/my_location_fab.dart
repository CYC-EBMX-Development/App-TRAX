import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Canonical "My Location" floating button used across the app
/// (Map tab, in-ride 地图s like Free Ride and Lap Timer Setup, etc.).
///
/// Style is the one defined in the Map tab (`trails_screen.dart`'s
/// `_roundControlBtn`): 44x44 white circle, elevation 3, neutral
/// text-primary icon, with a tooltip.
class MyLocationFab extends StatelessWidget {
  final VoidCallback onTap;
  final String tooltip;

  const MyLocationFab({
    super.key,
    required this.onTap,
    this.tooltip = 'My Location',
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              Icons.my_location,
              color: AppColors.textPrimary,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}
