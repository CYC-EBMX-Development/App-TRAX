#!/usr/bin/env bash
# Build a release IPA named trax-test-YYMMDD-N.ipa for App Store / TestFlight.
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
source "$APP_ROOT/scripts/release_naming.sh"

# Pick up AMAP_KEY / AMAP_*_SDK_KEY / ASC_* from the shared deploy env
# (same file build_apk.sh uses). Without this the AMap REST calls (place
# search, reverse-geocode, directions) silently return empty results.
if [[ -f "$HOME/trax-deploy.env" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/trax-deploy.env"
fi

API_BASE_URL="${API_BASE_URL:-http://43.99.48.204/api}"
AMAP_KEY="${AMAP_KEY:-}"
UPLOAD=false
[[ "${1:-}" == "--upload" ]] && UPLOAD=true

# --- compute release base ---
trax_release_resolve_base "$APP_ROOT"
DATE_STAMP="$TRAX_RELEASE_DATE_STAMP"
PREFIX="$TRAX_RELEASE_PREFIX"
SEQ="$TRAX_RELEASE_SEQ_STR"

# Allow callers (e.g. release.sh) to pin the exact base name so APK and IPA
# from the same code share the same sequence:
#   RELEASE_NAME_BASE=trax-test-260514-07
if [[ -n "${RELEASE_NAME_BASE:-}" ]]; then
  IPA_NAME="${RELEASE_NAME_BASE}.ipa"
  if [[ "$RELEASE_NAME_BASE" =~ ^trax-test-([0-9]{6})-([0-9]+)$ ]]; then
    DATE_STAMP="${BASH_REMATCH[1]}"
    SEQ="${BASH_REMATCH[2]}"
  else
    echo "!! invalid RELEASE_NAME_BASE: $RELEASE_NAME_BASE"
    echo "   expected format: trax-test-YYMMDD-N"
    exit 2
  fi
else
  IPA_NAME="${TRAX_RELEASE_NAME_BASE}.ipa"
fi
IPA_OUT="$OUT_DIR/$IPA_NAME"

# iOS version rule:
# - version (CFBundleShortVersionString): fixed 1.0.0
# - build number (CFBundleVersion): YYMMDD + sequence (01, 02 ... 100 ...)
BUILD_NAME="1.0.0"
BUILD_NUMBER="${DATE_STAMP}${SEQ}"

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
