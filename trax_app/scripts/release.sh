#!/usr/bin/env bash
# One-shot release: build APK + IPA from the same code with the SAME
# trax-test-YYMMDD-N.{apk,ipa} base name, upload APK to the OTA server,
# leave IPA in build/dist/ for manual upload via Transporter / altool.
#
# Usage:
#   ./scripts/release.sh              # build both, upload APK
#   ./scripts/release.sh --ipa-upload # also altool-upload IPA to App Store Connect
#
set -euo pipefail
APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$APP_ROOT"
source ~/trax-deploy.env
source "$APP_ROOT/scripts/release_naming.sh"

# Defaults so `set -u` doesn't trip when the env file omits an optional key.
API_BASE_URL="${API_BASE_URL:-http://43.99.48.204/api}"
AMAP_KEY="${AMAP_KEY:-}"
AMAP_ANDROID_SDK_KEY="${AMAP_ANDROID_SDK_KEY:-}"
AMAP_IOS_SDK_KEY="${AMAP_IOS_SDK_KEY:-}"

IPA_UPLOAD=false
[[ "${1:-}" == "--ipa-upload" ]] && IPA_UPLOAD=true

TODAY=$(TZ=Asia/Shanghai date +%y%m%d)
PREFIX="trax-test-${TODAY}"
# Shared sequence allocator:
# - same code snapshot => same sequence
# - code changed on same day => next sequence
trax_release_resolve_base "$APP_ROOT"
NAME_BASE="$TRAX_RELEASE_NAME_BASE"

echo "==============================================================="
echo "==> Release: ${NAME_BASE}.apk  +  ${NAME_BASE}.ipa"
echo "==============================================================="

# --- 1) APK ---
echo "==> [1/3] Building APK ..."
# Parse YYMMDD + NN out of NAME_BASE so the APK's --build-name and
# --build-number match the YYMMDDNN convention used by build_apk.sh and
# build_ipa.sh (the OTA client parses both fields).
if [[ "$NAME_BASE" =~ ^trax-test-([0-9]{6})-([0-9]+)$ ]]; then
  R_DATE="${BASH_REMATCH[1]}"
  R_SEQ="${BASH_REMATCH[2]}"
else
  echo "!! unable to parse NAME_BASE=$NAME_BASE"; exit 2
fi
flutter build apk --release \
  --split-per-abi \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=AMAP_KEY="${AMAP_KEY:-}" \
  --dart-define=AMAP_ANDROID_SDK_KEY="${AMAP_ANDROID_SDK_KEY:-}" \
  --build-name="1.0.0" \
  --build-number="${R_DATE}${R_SEQ}"
mkdir -p build/dist
# Distribute only the arm64-v8a slice (covers all modern Android devices)
# to keep the download size roughly half of the fat APK.
SPLIT_APK="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
FAT_APK="build/app/outputs/flutter-apk/app-release.apk"
if [[ -f "$SPLIT_APK" ]]; then
  cp "$SPLIT_APK" "build/dist/${NAME_BASE}.apk"
else
  cp "$FAT_APK" "build/dist/${NAME_BASE}.apk"
fi

echo "==> [2/3] Uploading APK ..."
./scripts/upload_apk.sh "${NAME_BASE}.apk"

# --- 2) IPA (same NN) ---
echo "==> [3/3] Building IPA (same name) ..."
if $IPA_UPLOAD; then
  RELEASE_NAME_BASE="$NAME_BASE" ./scripts/build_ipa.sh --upload
else
  RELEASE_NAME_BASE="$NAME_BASE" ./scripts/build_ipa.sh
fi

echo
echo "==> Release done: ${NAME_BASE}.apk (server) + ${NAME_BASE}.ipa (build/dist)"
