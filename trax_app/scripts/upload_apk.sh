#!/usr/bin/env bash
# Resume upload of an existing local APK to the server, then refresh the
# `trax-latest.apk` symlink and `version.json` published under
# `/var/www/trax-download/`.
#
# APK naming convention (mandatory): trax-test-YYMMDD-NN.apk
#   YYMMDD = local build date,  NN = same-day counter (01, 02, ...).
#
# The published version.json schema MUST stay in sync with
# `lib/common/services/app_update_service.dart` — the app parses these keys:
#   { "latest", "filename", "url", "sha1", "size_mb", "released_at" }
#
# Usage:
#   ./scripts/upload_apk.sh                          # auto: today + next counter
#   ./scripts/upload_apk.sh trax-test-260514-01.apk  # explicit name
#
# Counter rule: NN resets to 01 each day (Asia/Shanghai). Auto mode looks at
# files already on the server matching today's YYMMDD and picks max(NN)+1.
# Source APK is always build/app/outputs/flutter-apk/app-release.apk; the
# script will copy it into build/dist/<auto-name>.apk if needed.
set -euo pipefail

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source ~/trax-deploy.env

if [[ $# -ge 1 && -n "${1:-}" ]]; then
  NAME="$1"
else
  TODAY="$(TZ=Asia/Shanghai date +%y%m%d)"
  # Counter is shared across .apk and .ipa for the same code-stamp.
  # 1) Server-side max NN among today's published .apk on the OTA host.
  SERVER_MAX=$(ssh "${SSH_USER}@${SERVER_IP}" \
    "ls /var/www/trax-download/ 2>/dev/null | grep -oE '^trax-test-${TODAY}-[0-9]{2}\\.apk\$' | sed -E 's/.*-([0-9]{2})\\.apk/\\1/' | sort -n | tail -1" \
    | sed 's/^0*//')
  # 2) Local max NN among today's .apk OR .ipa already in build/dist (covers IPA-first builds).
  LOCAL_MAX=0
  for f in "$APP_ROOT"/build/dist/trax-test-${TODAY}-??.{apk,ipa}; do
    [[ -e "$f" ]] || continue
    n=$(basename "$f" | sed -E 's/.*-([0-9]{2})\.(apk|ipa)$/\1/' | sed 's/^0*//')
    (( ${n:-0} > LOCAL_MAX )) && LOCAL_MAX=${n:-0}
  done
  MAX_NN=$(( ${SERVER_MAX:-0} > LOCAL_MAX ? ${SERVER_MAX:-0} : LOCAL_MAX ))
  NEXT_NN=$(( MAX_NN + 1 ))
  printf -v COUNTER_PART '%02d' "$NEXT_NN"
  NAME="trax-test-${TODAY}-${COUNTER_PART}.apk"
  echo "==> auto-named: $NAME"
  mkdir -p "$APP_ROOT/build/dist"
  if [[ ! -f "$APP_ROOT/build/dist/$NAME" ]]; then
    SRC="$APP_ROOT/build/app/outputs/flutter-apk/app-release.apk"
    [[ -f "$SRC" ]] || { echo "no built APK at $SRC; run flutter build apk --release first"; exit 1; }
    cp "$SRC" "$APP_ROOT/build/dist/$NAME"
  fi
fi

APK="$APP_ROOT/build/dist/$NAME"
[[ -f "$APK" ]] || { echo "no such file: $APK"; exit 1; }

# Enforce the trax-test-YYMMDD-NN.apk naming convention so the build code
# can be parsed unambiguously by the OTA client.
if [[ ! "$NAME" =~ ^trax-test-([0-9]{6})-([0-9]{2})\.apk$ ]]; then
  echo "ERROR: APK filename must match trax-test-YYMMDD-NN.apk (got: $NAME)"
  exit 2
fi
DATE_PART="${BASH_REMATCH[1]}"
COUNTER_PART="${BASH_REMATCH[2]}"
LATEST_CODE="${DATE_PART}-${COUNTER_PART}"

SHA1=$(shasum "$APK" | awk '{print $1}')
SIZE=$(stat -f%z "$APK")
SIZE_MB=$(( (SIZE + 1048575) / 1048576 ))   # round up
RELEASED_AT="$(TZ=Asia/Shanghai date -Iseconds)"

echo "==> $NAME  ${SIZE_MB} MB  sha1=$SHA1  code=$LATEST_CODE"

# Loop rsync until success (resumes from --partial)
until rsync -avP --partial --inplace \
  -e "ssh -c chacha20-poly1305@openssh.com -o ServerAliveInterval=10 -o ServerAliveCountMax=4" \
  "$APK" "${SSH_USER}@${SERVER_IP}:/var/www/trax-download/$NAME"; do
  echo "==> rsync interrupted, retrying in 5s ..."
  sleep 5
done

echo "==> upload complete, updating symlink + version.json"
ssh "${SSH_USER}@${SERVER_IP}" "
set -e
cd /var/www/trax-download
ln -sfn '$NAME' trax-latest.apk
cat > version.json <<JSON
{
  \"latest\": \"$LATEST_CODE\",
  \"filename\": \"$NAME\",
  \"url\": \"/apk/trax-latest.apk\",
  \"sha1\": \"$SHA1\",
  \"size_mb\": $SIZE_MB,
  \"released_at\": \"$RELEASED_AT\"
}
JSON
chown -h nginx:nginx trax-latest.apk version.json 2>/dev/null || true
ls -lh '$NAME' trax-latest.apk version.json
"

echo
echo "==> Done.   http://${SERVER_IP}/download/   →   /apk/$NAME"
