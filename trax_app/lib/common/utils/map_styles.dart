import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Globally unified styling for trail- and ride-track polylines.
///
/// Single source of truth for polyline widths and colors so the look
/// stays identical across Google Maps and AMap. Multi-rider colors
/// (used in race tracking / replay screens) are intentionally NOT
/// defined here — they are computed per rider and remain owned by
/// those screens.
///
/// Style spec (Strava-inspired, build 26060507+):
///   * Trail base color [trailColor] is a deep warm orange `#FF6B00`,
///     used for all trail roles (selected, multi-list non-selected,
///     dimmed-under-rider, replay traversed/remaining). Only alpha and
///     the optional [trailHaloColor] outline distinguish the roles.
///   * Selected / focal trail screens render a dark-brown halo polyline
///     ([trailHaloColor], width [trailHaloWidth]) BELOW the main line
///     so the orange reads as outlined on light AMap basemap tiles.
///   * Multi-list non-selected trails and dimmed-under-rider trails
///     do NOT render the halo (it would clutter / show through the
///     rider polyline on top).
///   * [AppColors.primary] (`#FFB800` golden yellow) remains the brand /
///     UI color (buttons, icons, start/finish markers, banners) and is
///     intentionally NOT used for trail polylines anymore.
class MapStyles {
  MapStyles._();

  /// Trail polyline width (the predefined route the rider follows).
  /// Applies to both Google Maps and AMap. Typed as [int] because
  /// `google_maps_flutter`'s `Polyline.width` is int; AMap call sites
  /// pass `.toDouble()` (or rely on [AmapAdapter.routePolyline] which
  /// does the conversion).
  ///
  /// Used for selected trails, single-trail screens, replay
  /// traversed/remaining segments, and the dimmed-under-rider trail
  /// during lap-timer / race-tracking rides — width is unified at 5
  /// across all trail roles; only alpha (and the optional halo)
  /// distinguishes them.
  static const int trailWidth = 5;

  /// Halo polyline width — drawn UNDER [trailWidth] to give the trail
  /// a dark outline on light basemap tiles. = [trailWidth] + 2.
  static const int trailHaloWidth = 7;

  /// Trail polyline width when shown as a non-selected option in a
  /// multi-trail listing (e.g. nearby-trails picker on the Trails tab).
  /// The selected trail still uses [trailWidth].
  static const int trailUnselectedWidth = 2;

  /// Ride-track polyline width (the rider's traveled path).
  /// Applies to solo rides, lap-timer rides, and replays — both Google
  /// Maps and AMap.
  static const int rideTrackWidth = 2;

  /// Trail polyline base color — deep warm orange `#FF6B00`. Used by
  /// every trail polyline regardless of role; alpha + halo encode the
  /// role differences. NOT the same as [AppColors.primary] (brand
  /// golden yellow) — that color stays reserved for UI / markers.
  static const Color trailColor = Color(0xFFFF6B00);

  /// Halo / outline color drawn under [trailColor] for selected trails
  /// to mimic the Strava look. Dark brown `#5C2C00` at ~35% alpha
  /// (`0x59`) so the outline reads as a soft drop-shadow rather than
  /// a hard black border.
  static const Color trailHaloColor = Color(0x595C2C00);

  /// Trail polyline color used for non-selected entries in a multi-trail
  /// listing. Same hue as [trailColor] but at ~55% alpha so the selected
  /// trail still pops above its dimmed siblings.
  static const Color trailUnselectedColor = Color(0x8CFF6B00);

  /// Trail polyline color used as the background trail under a live
  /// rider polyline (lap-timer, race tracking). Same hue at ~40% alpha
  /// so the rider's red/coloured track stays the visual focus.
  static const Color trailDimmedColor = Color(0x66FF6B00);

  /// Solo ride-track polyline color.
  static const Color rideTrackColor = Colors.red;
}

