# AGENTS.md — Rules for AI coding assistants in this repo

This file is read automatically by Copilot, Claude Code, Cursor, Codex,
Aider, and most other AI dev tools. Anything you add here becomes a
hard rule for those tools.

## ⛔ HARD RULES — read before doing anything in this repo

1. **No simulators, no emulators, no `dartvm`, no hot reload, no `flutter run`.**
   The user develops against a real iPhone only. Never ask for terminal
   IDs, never suggest hot-reload `r`/`R`, never spin up a simulator.
2. **"安装到手机" / "install to phone" = iPhone by default.** Command:
   `cd trax_app && source ~/trax-deploy.env && ./scripts/install_ios.sh --device-id 00008120-000249060AF1A01E`
   Switch to Android only if the user explicitly says "安卓" / "android".
3. **Validation flow after editing anything under `trax_app/lib/**`:**
   `get_errors` (clean) → install to iPhone (unless user said skip or
   the change is docs/memory-only). No other "done" criterion is valid.
4. **All user-facing UI strings must be English.** Chinese allowed only
   in comments/logs.
5. Backend Java edits: `cd backend && mvn -q -DskipTests compile` must
   be green before declaring done.

## TL;DR for any AI agent

- Frontend lives in `trax_app/` (Flutter, dual map provider: Google + AMap).
- Backend lives in `backend/` (Spring Boot, `mvn -q -DskipTests compile`).
- **Never run `flutter build apk` / `flutter build ipa` directly.**
  Use the project's release scripts — see "Release builds" below.

## Release builds (Android APK & iOS IPA)

Versioning rule: `versionCode = YYMMDDNN` (8-digit int, Asia/Shanghai
date + 2-digit per-day sequence). See header comment in
`trax_app/pubspec.yaml`.

The only sanctioned entry points are:

| Target | Command | What it does |
|---|---|---|
| Android, local | `./trax_app/scripts/build_apk.sh` | Allocates next `YYMMDDNN`, builds `--split-per-abi`, copies arm64-v8a slice to `build/dist/trax-test-YYMMDD-NN.apk`. |
| Android, deploy | `./trax_app/scripts/build_apk.sh --deploy` | Same, then rsyncs to the OTA server. |
| iOS, local | `./trax_app/scripts/build_ipa.sh` | Same naming/numbering scheme for IPA. |
| iOS, version bump only | `./trax_app/scripts/update_ios_version.sh [YYMMDD-NN] ["release note"]` | Updates `pubspec.yaml` + `Info.plist` versions. |

Why scripts and not raw `flutter build`:

1. They call `scripts/release_naming.sh` to allocate the next sequence
   for today, also dedup'd against the OTA server's existing files.
2. They inject `--build-name` / `--build-number` so the produced
   binary's `versionCode` is monotonically newer than what testers
   already have. Skipping this causes
   `INSTALL_FAILED_VERSION_DOWNGRADE` on `adb install -r`.
3. They route AMap / Google Maps SDK keys from `~/trax-deploy.env`
   into `--dart-define` so the build is actually usable in mainland
   China.

There is also a hard guard in `trax_app/android/app/build.gradle.kts`
that aborts any `*Release` Gradle task whose `versionCode` prefix
doesn't match today's `YYMMDD` (Asia/Shanghai). The error message
points back to this file. Do not weaken or remove that guard. The
emergency bypass (`TRAX_SKIP_RELEASE_VERSION_GUARD=1`) is only for
debugging Gradle itself — never for shipping an APK.

After a build, install to a connected Android device with:

```bash
adb -s <serial> install -r trax_app/build/dist/trax-test-YYMMDD-NN.apk
```

## Map provider rules

- `trax_app/lib/common/services/map_provider.dart` resolves Google vs
  AMap from the user's GPS (`CoordTransform.isInChinaMainland`).
- Screens that render a map MUST:
  1. Call `MapProviderService.ensureResolved()` **after** the GPS
     permission has been granted (or after a `getCurrentPosition()`
     fix in the screen itself). Calling it before a fix exists on a
     cold start in CN will silently fall back to Google.
  2. Subscribe to `MapProviderService.providerNotifier` and rebuild
     when it fires, so the basemap swaps when the user crosses the
     border or toggles the override.
- AMap `Marker` has **no** `markerId` field and there is no public
  `MarkerId` class. Use only `position` / `icon` / `anchor` / `zIndex`
  / `infoWindow` / `clickable` / `draggable`.
- Do NOT manually call `dispose()` on `AMapController` — `AMapWidget`
  handles it (the SDK method is also misspelled `disponse` upstream).

## Backend (Spring Boot)

- Verify compilation with `cd backend && mvn -q -DskipTests compile`
  after any Java edit. Tests are slow; only run when touching the
  related package.

## Flutter API drift to watch out for

- `SearchDelegate.notifyListeners()` is no longer accessible — drive
  rebuilds through a `ValueNotifier` + `ValueListenableBuilder` you
  own (see `_PlaceSearchDelegate` in
  `trax_app/lib/screens/trails/trails_screen.dart`).
- `_` is no longer a valid identifier in lambda parameter lists when
  you actually need the value — name it `ctx`, `i`, etc.
- `MapRouter.openEventByStatus(...)` returns `Future<void>`, not a
  `Route`. Call it with `await`, never wrap in
  `Navigator.push(...)` / `Navigator.pushReplacement(...)`.
