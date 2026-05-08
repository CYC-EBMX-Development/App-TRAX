#!/usr/bin/env bash
# Build a release APK named trax-test-YYMMDD-NN.apk and (optionally) deploy.
#
# Naming rule:
#   - YYMMDD = today (Asia/Shanghai)
#   - NN     = 2-digit sequence within the day, auto-incremented based on what
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

API_BASE_URL="${API_BASE_URL:-http://43.153.210.122/api}"
DEPLOY=false
[[ "${1:-}" == "--deploy" ]] && DEPLOY=true

# --- compute date stamp (Asia/Shanghai) ---
DATE_STAMP=$(TZ=Asia/Shanghai date +%y%m%d)
PREFIX="trax-test-${DATE_STAMP}"

# --- find next sequence number ---
LOCAL_MAX=0
for f in "$OUT_DIR"/${PREFIX}-??.apk; do
  [[ -e "$f" ]] || continue
  n=$(basename "$f" .apk | awk -F- '{print $NF}')
  (( 10#$n > LOCAL_MAX )) && LOCAL_MAX=$((10#$n))
done

REMOTE_MAX=0
if $DEPLOY; then
  source ~/trax-deploy.env
  REMOTE_MAX=$(ssh -i "$SSH_KEY" "ubuntu@$SERVER_IP" \
    "ls /var/www/trax-download/${PREFIX}-*.apk 2>/dev/null | sed -E 's/.*-([0-9]+)\.apk/\1/' | sort -n | tail -1" \
    || echo 0)
  REMOTE_MAX=${REMOTE_MAX:-0}
  REMOTE_MAX=$((10#$REMOTE_MAX))
fi

NEXT=$(( (LOCAL_MAX > REMOTE_MAX ? LOCAL_MAX : REMOTE_MAX) + 1 ))
SEQ=$(printf "%02d" "$NEXT")
APK_NAME="${PREFIX}-${SEQ}.apk"
APK_OUT="$OUT_DIR/$APK_NAME"

echo "==> Building $APK_NAME (API_BASE_URL=$API_BASE_URL)"

cd "$APP_ROOT"
env -u FLUTTER_STORAGE_BASE_URL -u PUB_HOSTED_URL \
    FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn \
    PUB_HOSTED_URL=https://pub.flutter-io.cn \
    flutter build apk --release \
      --dart-define=API_BASE_URL="$API_BASE_URL" \
      --build-name="${DATE_STAMP}.${SEQ}" \
      --build-number="$(date +%s)"

cp "build/app/outputs/flutter-apk/app-release.apk" "$APK_OUT"
SIZE=$(du -h "$APK_OUT" | awk '{print $1}')
SHA1=$(shasum "$APK_OUT" | awk '{print $1}')
echo "==> Built: $APK_OUT  ($SIZE, sha1=$SHA1)"

if ! $DEPLOY; then
  echo "==> Local build done. Add --deploy to upload."
  exit 0
fi

echo "==> Uploading to server ..."
rsync -avP --partial --inplace \
  -e "ssh -i $SSH_KEY -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o TCPKeepAlive=yes" \
  "$APK_OUT" "ubuntu@$SERVER_IP:/var/www/trax-download/$APK_NAME"

echo "==> Updating /var/www/trax-download/trax-latest.apk symlink and version.json"
ssh -i "$SSH_KEY" "ubuntu@$SERVER_IP" "
  cd /var/www/trax-download &&
  sudo ln -sfn '$APK_NAME' trax-latest.apk &&
  printf '{\"file\":\"%s\",\"size\":%s,\"sha1\":\"%s\",\"built_at\":\"%s\"}\n' \
    '$APK_NAME' '$(stat -f%z "$APK_OUT")' '$SHA1' '$(TZ=Asia/Shanghai date -Iseconds)' \
    | sudo tee version.json > /dev/null &&
  ls -lh '$APK_NAME' trax-latest.apk version.json
"

echo
echo "==> Done. URLs:"
echo "    Page : http://43.153.210.122/download/"
echo "    APK  : http://43.153.210.122/apk/$APK_NAME"
echo "    Latest: http://43.153.210.122/apk/trax-latest.apk"
