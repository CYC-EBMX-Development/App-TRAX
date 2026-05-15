#!/usr/bin/env bash
# One-shot release: build APK + IPA from the same code with the SAME
# trax-test-YYMMDD-NN.{apk,ipa} base name, upload APK to the OTA server,
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

# Defaults so `set -u` doesn't trip when the env file omits an optional key.
API_BASE_URL="${API_BASE_URL:-http://43.99.48.204/api}"
AMAP_KEY="${AMAP_KEY:-}"
AMAP_ANDROID_SDK_KEY="${AMAP_ANDROID_SDK_KEY:-}"
AMAP_IOS_SDK_KEY="${AMAP_IOS_SDK_KEY:-}"

IPA_UPLOAD=false
[[ "${1:-}" == "--ipa-upload" ]] && IPA_UPLOAD=true

TODAY=$(TZ=Asia/Shanghai date +%y%m%d)
PREFIX="trax-test-${TODAY}"

# Pick next NN considering BOTH server .apk and local .apk/.ipa.
SERVER_MAX=$(ssh -o ConnectTimeout=15 "${SSH_USER}@${SERVER_IP}" \
  "ls /var/www/trax-download/ 2>/dev/null | grep -oE '^${PREFIX}-[0-9]{2}\\.apk\$' | sed -E 's/.*-([0-9]{2})\\.apk/\\1/' | sort -n | tail -1" \
  | sed 's/^0*//')
SERVER_MAX=${SERVER_MAX:-0}
LOCAL_MAX=0
for f in build/dist/${PREFIX}-??.{apk,ipa}; do
  [[ -e "$f" ]] || continue
  n=$(basename "$f" | sed -E 's/.*-([0-9]{2})\.(apk|ipa)$/\1/' | sed 's/^0*//')
  (( ${n:-0} > LOCAL_MAX )) && LOCAL_MAX=${n:-0}
done
MAX=$(( SERVER_MAX > LOCAL_MAX ? SERVER_MAX : LOCAL_MAX ))
NEXT=$(( MAX + 1 ))
SEQ=$(printf "%02d" "$NEXT")
NAME_BASE="${PREFIX}-${SEQ}"

echo "==============================================================="
echo "==> Release: ${NAME_BASE}.apk  +  ${NAME_BASE}.ipa"
echo "==============================================================="

# --- 1) APK ---
echo "==> [1/3] Building APK ..."
flutter build apk --release \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=AMAP_KEY="${AMAP_KEY:-}" \
  --dart-define=AMAP_ANDROID_SDK_KEY="${AMAP_ANDROID_SDK_KEY:-}"
mkdir -p build/dist
cp build/app/outputs/flutter-apk/app-release.apk "build/dist/${NAME_BASE}.apk"

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
