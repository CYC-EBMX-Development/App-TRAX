# TRAX App — Design System (single source of truth)

> Every new page MUST use these. Do NOT invent a one-off style. If a need
> truly isn't covered, add the new canonical widget here first, then use
> it. Keep this doc short.

Last updated: 2026-06-03

---

## 1. Errors / toasts / notifications

**Canonical:** `showTraxSnackBar(context, msg, isError: true|false)`
- Defined in: `lib/theme/app_theme.dart`
- Renders just **below the topbar** via the root `Overlay` (consistent on
  Android + iOS, regardless of which `Scaffold` is on screen).
- Icon: `Icons.error_outline` (error) / `Icons.info_outline` (info).
- Bg: `AppColors.error` (error) / `0xFF333333` (info).
- Tap to dismiss; auto-dismiss after 3s (configurable).
- **Do not use** `ScaffoldMessenger.of(context).showSnackBar(...)` for
  user-facing errors anymore — bottom snackbars are inconsistent with
  the rest of the app.

Local convenience helpers inside a page are fine **as long as they
delegate to `showTraxSnackBar`**, e.g.:
```dart
void _toast(String msg, {bool isError = false}) =>
    showTraxSnackBar(context, msg, isError: isError);
```

## 2. Dialogs / confirmations

**Canonical:** `TraxDialog.showBottomTipsDialog(...)`
- Defined in: `lib/common/widgets/trax_dialog.dart`
- Use for any "Are you sure?" / two-button confirmation.
- Pattern: `title`, `content`, `mainBtnText`, `mainBtnOnPressed`, `subBtnText`.

## 3. My-location FAB (on ride/map pages)

**Canonical:** `MyLocationFab(onTap: ...)`
- Defined in: `lib/common/widgets/my_location_fab.dart`
- 44×44 white Material circle, elevation 3, `Icons.my_location` in
  `AppColors.textPrimary`. Placed at `right: 14, bottom: <sheet-collapsed-height> + 12`.
- Handler convention (mirrors Free Ride): if `_hasModule` and module
  telemetry is null → `_toast('Unable to get bike module signal', isError: true)`
  and **return** (no silent fallback). Phone-only path → Geolocator;
  on failure → `_toast('Unable to get phone GPS signal', isError: true)`.

## 4. Buttons

**Primary action:**
```dart
ElevatedButton.icon(
  style: ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
    disabledForegroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
  ),
  ...
)
```
Height: 50 for main CTAs (Start, Save), 48 for secondary CTAs.
Text: `fontSize: 15, fontWeight: FontWeight.w700` (main); 14/w700 (secondary).

**Small circle button** (back, close on map overlay): see `_circleBtn` in
ride pages — 36×36 white circle, light shadow, `Icons.x` 18px.

## 5. Cards / surfaces

- Surface bg: `AppColors.surface`. Soft bg (e.g. pick-prompt): `AppColors.background`.
- Radius: `BorderRadius.circular(12)` for content cards;
  `BorderRadius.vertical(top: Radius.circular(20))` for bottom sheets.
- Shadow on overlays: `BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))` (top of sheet)
  or `Colors.black.withValues(alpha: 0.1), blurRadius: 6` (floating cards).

## 6. Bottom DraggableScrollableSheet (lap timer / race setup style)

Three pinned regions, **handle on top and action button at the bottom
are always visible**, content scrolls between them.

```dart
final _sheetCtl = DraggableScrollableController();
// ...
DraggableScrollableSheet(
  controller: _sheetCtl,
  initialChildSize: minSize, minChildSize: minSize, maxChildSize: maxSize,
  snap: true, snapSizes: [maxSize],
  builder: (ctx, scrollController) => Container(
    decoration: const BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      _PinnedHandle(controller: _sheetCtl, min: minSize, max: maxSize),
      Flexible(child: SingleChildScrollView(
        controller: scrollController,
        physics: const ClampingScrollPhysics(),
        child: /* content */,
      )),
      /* pinned action button with safe-area bottom padding */,
    ]),
  ),
);
```

Rules:
- Two snap states only (`minChildSize == initialChildSize`, `snapSizes: [maxSize]`).
- Compute `maxChildSize` from a tuned content-height heuristic so the
  card stops exactly at content end (no empty space below).
- The pinned handle is a `GestureDetector` that drives `_sheetCtl`:
  vertical drag → `jumpTo`, drag end → `animateTo` nearest snap, tap →
  `animateTo` opposite snap. **Do not** use `reverse: true` with the
  handle inside the scroll view — the handle becomes invisible when
  collapsed and there is no surface to drag.
- `collapsedPx ≈ handle (~26) + button height (50) + paddings (~24) + safeBottom`.

## 7. Colors / typography

All colors live in `AppColors` (`lib/theme/app_theme.dart`). Never hard-code
hex except shadows. Text styles:
- Title 14 / w700 / `textPrimary`
- Subtitle 12 / w400 / `textSecondary`
- Stat number 28+ / w800 / `textPrimary`

## 8. Map provider parity

Every ride/map screen has a Google variant under `lib/screens/ride/...`
and an AMap mirror under `lib/screens/ride/amap/...`. **Any visual or
behavior change MUST be applied to both.** AMap-specific gotchas:
- Use `AmapAdapter.toAmap(LatLng)` for coordinate conversion.
- Set `myLocationStyleOptions: MyLocationStyleOptions(!_hasModule, ...)`
  — AMap does NOT draw the blue dot otherwise.
- `Marker` has no `markerId`; never call `dispose()` on `AMapController`.

---

## 9. Satellite badge (live GPS satellite count)

**Canonical:** `SatelliteBadge(count: <int?>)`
- Defined in: `lib/common/widgets/satellite_badge.dart`
- Rounded pill (`AppColors.surface`, radius 20, subtle shadow) with
  `Icons.satellite_alt` + label. States by count:
  - `null` → grey “Searching…” (module connected, no fix yet)
  - `<= 3` → amber “N sat(s)” (weak / acquiring)
  - `>= 4` → green “N sats” (good 3D fix)
- Data source: `ModuleTelemetry.satellites` (from `$PCYCGPS` NMEA field
  [10] → backend `module_telemetry.satellites` → WS JSON). Show only for
  module bikes (`_hasModule` / `_selectedBikeHasModule` / serial != null).
- Placement: top-right of the map overlay, below the top bar
  (`top: safeTop + 56, right: 12–16`). On race pages it sits where the
  live-ranking overlay goes and is hidden while ranking is shown.
- Surfaced on: free ride, lap-timer setup (both maps), race tracking,
  trail record (both providers), and the module-detail GPS card.

---

## How to extend this doc

1. Find/build the canonical widget in `lib/common/widgets/` or `lib/theme/`.
2. Add a short section here with: name, file path, when to use, one
   minimal usage snippet.
3. Replace any drift in existing pages in the same PR (grep for the old
   pattern).
