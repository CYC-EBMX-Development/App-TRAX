#!/usr/bin/env bash
# Build a release APK named trax-test-YYMMDD-N.apk and (optionally) deploy.
#
# Naming rule:
#   - YYMMDD = today (Asia/Shanghai)
#   - N      = sequence within the day (01..99, then 100...), auto-incremented based on what
#              already exists locally and on the server.
#
# Usage:
#   ./scripts/build_apk.sh           # build only
#   ./scripts/build_apk.sh --deploy  # build + rsync to server + update download page
#
set -euo pipefail

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$APP_ROOT/build/dist"
mkdir -p "$OUT_DIR"
source "$APP_ROOT/scripts/release_naming.sh"

API_BASE_URL="${API_BASE_URL:-http://43.99.48.204/api}"
AMAP_KEY="${AMAP_KEY:-}"
DEPLOY=false
[[ "${1:-}" == "--deploy" ]] && DEPLOY=true

# Use shared release sequence with code snapshot awareness.
if [[ -f "$HOME/trax-deploy.env" ]]; then
  # Optional: enables remote max scan for consistent numbering with uploaded APKs.
  source "$HOME/trax-deploy.env"
fi
trax_release_resolve_base "$APP_ROOT"
DATE_STAMP="$TRAX_RELEASE_DATE_STAMP"
SEQ="$TRAX_RELEASE_SEQ_STR"
APK_NAME="${TRAX_RELEASE_NAME_BASE}.apk"
APK_OUT="$OUT_DIR/$APK_NAME"

echo "==> Building $APK_NAME (API_BASE_URL=$API_BASE_URL)"

cd "$APP_ROOT"
"$APP_ROOT/scripts/patch_amap_plugins.sh" || true
env -u FLUTTER_STORAGE_BASE_URL -u PUB_HOSTED_URL \
    FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn \
    PUB_HOSTED_URL=https://pub.flutter-io.cn \
    flutter build apk --release \
      --split-per-abi \
      --dart-define=API_BASE_URL="$API_BASE_URL" \
      --dart-define=AMAP_KEY="$AMAP_KEY" \
      --dart-define=AMAP_ANDROID_SDK_KEY="${AMAP_ANDROID_SDK_KEY:-}" \
      --dart-define=AMAP_IOS_SDK_KEY="${AMAP_IOS_SDK_KEY:-}" \
      --build-name="1.0.0" \
      --build-number="${DATE_STAMP}${SEQ}"

# Prefer the arm64-v8a split build (every modern Android device); fall back
# to the legacy fat APK if --split-per-abi was not produced for some reason.
SPLIT_APK="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
FAT_APK="build/app/outputs/flutter-apk/app-release.apk"
if [[ -f "$SPLIT_APK" ]]; then
  cp "$SPLIT_APK" "$APK_OUT"
  echo "==> Source: app-arm64-v8a-release.apk (split-per-abi)"
else
  cp "$FAT_APK" "$APK_OUT"
  echo "==> Source: app-release.apk (fat APK fallback)"
fi
SIZE=$(du -h "$APK_OUT" | awk '{print $1}')
SHA1=$(shasum "$APK_OUT" | awk '{print $1}')
echo "==> Built: $APK_OUT  ($SIZE, sha1=$SHA1)"

if ! $DEPLOY; then
  echo "==> Local build done. Add --deploy to upload."
  exit 0
fi

# Delegate upload to the canonical upload_apk.sh — it owns the working
# SSH credentials, version.json schema and trax-latest.apk symlink logic.
exec "$APP_ROOT/scripts/upload_apk.sh" "$APK_NAME"
