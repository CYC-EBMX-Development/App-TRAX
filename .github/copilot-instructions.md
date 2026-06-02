# GitHub Copilot instructions

This is a thin pointer file. The real rules live in
[`AGENTS.md`](../AGENTS.md) at the repo root — read it before suggesting
any code change.

Highlights you must respect:

- **Never** invoke `flutter build apk` or `flutter build ipa` directly.
  Use `trax_app/scripts/build_apk.sh` (Android) or
  `trax_app/scripts/build_ipa.sh` (iOS). A Gradle guard in
  `trax_app/android/app/build.gradle.kts` will fail any release whose
  `versionCode` isn't today's `YYMMDDNN` (Asia/Shanghai).
- After a successful Android build, install with
  `adb -s <serial> install -r trax_app/build/dist/trax-test-YYMMDD-NN.apk`.
- Map provider (`MapProviderService`) is resolved from GPS, not locale.
  See "Map provider rules" in `AGENTS.md` for the cold-start ordering
  trap and the AMap `Marker` API caveats.
- Backend compile check: `cd backend && mvn -q -DskipTests compile`.
