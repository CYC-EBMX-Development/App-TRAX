#!/usr/bin/env bash
# Send hot-restart (SIGUSR2) to every running `flutter run` process on this Mac.
# Hot reload would be SIGUSR1.
set -euo pipefail
PIDS=$(ps -ef | grep "flutter_tools.snapshot run -d" | grep -v grep | awk '{print $2}' || true)
if [[ -z "$PIDS" ]]; then
  echo "No flutter run sessions found." >&2
  exit 1
fi
COUNT=0
for p in $PIDS; do
  kill -USR2 "$p" && COUNT=$((COUNT+1))
done
echo "Hot-restart signal sent to $COUNT flutter session(s)."
