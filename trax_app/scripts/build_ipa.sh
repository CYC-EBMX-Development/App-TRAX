#!/usr/bin/env bash
# Build a release IPA named trax-test-YYMMDD-NN.ipa for App Store / TestFlight.
#
# Usage:
#   ./scripts/build_ipa.sh              # build only (open Transporter manually)
#   ./scripts/build_ipa.sh --upload     # build + altool upload to App Store Connect
#
# Requires once-only setup for --upload:
#   - Create an App Store Connect API key: App Store Connect -> Users and
#     Access -> Integrations -> App Store Connect API -> Generate API Key
#   - Save the .p8 to ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
#   - Export in ~/trax-deploy.env (or your shell rc):
#       export ASC_API_KEY_ID=ABCD123456
#       export ASC_API_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#
set -euo pipefail

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$APP_ROOT/build/dist"
mkdir -p "$OUT_DIR"

API_BASE_URL="${API_BASE_URL:-http://43.99.48.204/api}"
AMAP_KEY="${AMAP_KEY:-}"
UPLOAD=false
[[ "${1:-}" == "--upload" ]] && UPLOAD=true

# --- compute date stamp (Asia/Shanghai) ---
DATE_STAMP=$(TZ=Asia/Shanghai date +%y%m%d)
PREFIX="trax-test-${DATE_STAMP}"

# --- choose sequence number ---
# Allow callers (e.g. release.sh) to pin the exact base name so APK and IPA
# from the same code share NN: RELEASE_NAME_BASE=trax-test-260514-07
if [[ -n "${RELEASE_NAME_BASE:-}" ]]; then
  IPA_NAME="${RELEASE_NAME_BASE}.ipa"
  SEQ=$(echo "$RELEASE_NAME_BASE" | sed -E 's/.*-([0-9]{2})$/\1/')
else
  # Counter is shared across .apk and .ipa for the same code-stamp.
  # 1) Server-side max among today's published .apk.
  SERVER_MAX=0
  if command -v ssh >/dev/null && [[ -n "${SERVER_IP:-}" && -n "${SSH_USER:-}" ]]; then
    SERVER_MAX=$(ssh -o ConnectTimeout=10 "${SSH_USER}@${SERVER_IP}" \
      "ls /var/www/trax-download/ 2>/dev/null | grep -oE '^${PREFIX}-[0-9]{2}\\.apk\$' | sed -E 's/.*-([0-9]{2})\\.apk/\\1/' | sort -n | tail -1" \
      2>/dev/null | sed 's/^0*//')
    SERVER_MAX=${SERVER_MAX:-0}
  fi
  # 2) Local max among today's .apk OR .ipa in build/dist.
  LOCAL_MAX=0
  for f in "$OUT_DIR"/${PREFIX}-??.{ipa,apk}; do
    [[ -e "$f" ]] || continue
    n=$(basename "$f" | sed -E 's/.*-([0-9]+)\.(ipa|apk)$/\1/')
    (( 10#$n > LOCAL_MAX )) && LOCAL_MAX=$((10#$n))
  done
  MAX=$(( SERVER_MAX > LOCAL_MAX ? SERVER_MAX : LOCAL_MAX ))
  NEXT=$(( MAX + 1 ))
  SEQ=$(printf "%02d" "$NEXT")
  IPA_NAME="${PREFIX}-${SEQ}.ipa"
fi
IPA_OUT="$OUT_DIR/$IPA_NAME"

# Build number must be monotonically increasing for App Store Connect.
# Use seconds-since-epoch (10 digits) — well below the 32-bit limit and always grows.
BUILD_NUMBER="$(date +%s)"
BUILD_NAME="${DATE_STAMP}.${SEQ}"

echo "==> Building $IPA_NAME  (build-name=$BUILD_NAME, build-number=$BUILD_NUMBER)"
echo "    API_BASE_URL=$API_BASE_URL"

cd "$APP_ROOT"
"$APP_ROOT/scripts/patch_amap_plugins.sh" >/dev/null 2>&1 || true

# Refresh CocoaPods (cheap if already up to date)
( cd ios && pod install --silent ) || ( cd ios && pod install )

env -u FLUTTER_STORAGE_BASE_URL -u PUB_HOSTED_URL \
    FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn \
    PUB_HOSTED_URL=https://pub.flutter-io.cn \
    flutter build ipa --release \
      --dart-define=API_BASE_URL="$API_BASE_URL" \
      --dart-define=AMAP_KEY="$AMAP_KEY" \
      --dart-define=AMAP_ANDROID_SDK_KEY="${AMAP_ANDROID_SDK_KEY:-}" \
      --dart-define=AMAP_IOS_SDK_KEY="${AMAP_IOS_SDK_KEY:-}" \
      --build-name="$BUILD_NAME" \
      --build-number="$BUILD_NUMBER"

# Flutter writes the .ipa into build/ios/ipa/ with the project display name.
SRC_IPA=$(ls -t "$APP_ROOT/build/ios/ipa/"*.ipa | head -1)
[[ -f "$SRC_IPA" ]] || { echo "!! No IPA produced under build/ios/ipa/"; exit 1; }
cp "$SRC_IPA" "$IPA_OUT"

SIZE=$(du -h "$IPA_OUT" | awk '{print $1}')
SHA1=$(shasum "$IPA_OUT" | awk '{print $1}')
echo "==> Built: $IPA_OUT  ($SIZE, sha1=$SHA1)"

if ! $UPLOAD; then
  cat <<EOF

==> Local build done.
    Next step (pick one):
      A) GUI:   open -a Transporter "$IPA_OUT"   # then click Deliver
      B) CLI:   ./scripts/build_ipa.sh --upload  # re-runs build + uploads
      C) Xcode: open ios/Runner.xcworkspace      # Window -> Organizer -> Distribute App
EOF
  exit 0
fi

# --- altool upload to App Store Connect ---
[[ -f "$HOME/trax-deploy.env" ]] && source "$HOME/trax-deploy.env"
: "${ASC_API_KEY_ID:?set ASC_API_KEY_ID in ~/trax-deploy.env}"
: "${ASC_API_ISSUER_ID:?set ASC_API_ISSUER_ID in ~/trax-deploy.env}"

echo "==> Uploading to App Store Connect (Key=$ASC_API_KEY_ID) ..."
xcrun altool --upload-app \
  --type ios \
  --file "$IPA_OUT" \
  --apiKey "$ASC_API_KEY_ID" \
  --apiIssuer "$ASC_API_ISSUER_ID"

cat <<EOF

==> Upload submitted.
    Check status at: https://appstoreconnect.apple.com/apps
    TestFlight build will show "Processing" for a few minutes,
    then become available for internal testers.
EOF
