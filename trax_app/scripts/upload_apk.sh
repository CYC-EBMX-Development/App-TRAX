#!/usr/bin/env bash
# Resume upload of an existing local APK to the server, then update symlink + version.json.
# Usage: ./scripts/upload_apk.sh trax-test-260508-02.apk
set -euo pipefail
NAME="${1:?usage: upload_apk.sh <apk-filename-in-build/dist>}"
APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APK="$APP_ROOT/build/dist/$NAME"
[[ -f "$APK" ]] || { echo "no such file: $APK"; exit 1; }
source ~/trax-deploy.env
SHA1=$(shasum "$APK" | awk '{print $1}')
SIZE=$(stat -f%z "$APK")
echo "==> $NAME  $SIZE bytes  sha1=$SHA1"
# Loop rsync until success (resumes from --partial)
until rsync -avP --partial --inplace \
  -e "ssh -i $SSH_KEY -c chacha20-poly1305@openssh.com -o ServerAliveInterval=10 -o ServerAliveCountMax=4" \
  "$APK" "ubuntu@$SERVER_IP:/var/www/trax-download/$NAME"; do
  echo "==> rsync interrupted, retrying in 5s ..."
  sleep 5
done
echo "==> upload complete, updating symlink + version.json"
ssh -i "$SSH_KEY" "ubuntu@$SERVER_IP" "
cd /var/www/trax-download &&
sudo ln -sfn '$NAME' trax-latest.apk &&
printf '{\"file\":\"%s\",\"size\":%s,\"sha1\":\"%s\",\"built_at\":\"%s\"}\n' \
  '$NAME' '$SIZE' '$SHA1' '$(TZ=Asia/Shanghai date -Iseconds)' \
  | sudo tee version.json &&
sudo chown -h www-data:www-data trax-latest.apk version.json 2>/dev/null || true
ls -lh '$NAME' trax-latest.apk version.json
"
echo
echo "==> Done.   http://43.153.210.122/download/   →   /apk/$NAME"
