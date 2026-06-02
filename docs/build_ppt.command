#!/usr/bin/env bash
# Build TRAX_App_Features.pptx from the Marp markdown source.
# Double-click in Finder (after `chmod +x`) or run from terminal.

set -euo pipefail

# Always resolve paths relative to this script so it works no matter
# where it's invoked from (Finder double-click, cron, another dir, etc.).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

SRC="docs/TRAX_App_Features.md"
OUT="docs/TRAX_App_Features.pptx"
IMG_DIR="docs/images"

if [[ ! -f "$SRC" ]]; then
  echo "❌ Source markdown not found: $SRC"
  exit 1
fi

# ── HEIC support ────────────────────────────────────────────────────
# Chromium (which Marp uses) cannot decode HEIC. Convert every *.heic
# / *.HEIC under docs/images/ to a sibling *.jpg using macOS `sips`,
# then rewrite "...heic" references in a temp markdown so the user can
# keep writing <img src="images/foo.heic"> in the source.
TMP_SRC=""
cleanup() { [[ -n "$TMP_SRC" && -f "$TMP_SRC" ]] && rm -f "$TMP_SRC"; }
trap cleanup EXIT

if [[ -d "$IMG_DIR" ]]; then
  shopt -s nullglob nocaseglob
  heic_files=( "$IMG_DIR"/*.heic )
  shopt -u nocaseglob
  if (( ${#heic_files[@]} > 0 )); then
    if ! command -v sips >/dev/null 2>&1; then
      echo "⚠️  Found HEIC files but 'sips' is not available — skipping conversion."
    else
      for heic in "${heic_files[@]}"; do
        jpg="${heic%.*}.jpg"
        # Skip if jpg exists and is newer than the heic source.
        if [[ -f "$jpg" && "$jpg" -nt "$heic" ]]; then continue; fi
        echo "🖼  Converting $(basename "$heic") → $(basename "$jpg")"
        sips -s format jpeg "$heic" --out "$jpg" >/dev/null
      done
    fi
    # Build a temp markdown with .heic refs rewritten to .jpg.
    # IMPORTANT: keep the temp file in the SAME directory as the original
    # so relative image paths like images/foo.jpg still resolve.
    TMP_SRC="$(dirname "$SRC")/.$(basename "${SRC%.*}").build.md"
    # Replace both lowercase and uppercase extension, in src="..." and ](...)
    sed -E 's#(images/[^"\)\ ]+)\.[Hh][Ee][Ii][Cc]#\1.jpg#g' "$SRC" > "$TMP_SRC"
    SRC="$TMP_SRC"
  fi
fi

# Pick a node binary — prefer Homebrew install, then PATH, then nvm default.
if ! command -v npx >/dev/null 2>&1; then
  for candidate in /opt/homebrew/bin/npx /usr/local/bin/npx "$HOME/.nvm/versions/node/$(ls -1 "$HOME/.nvm/versions/node" 2>/dev/null | tail -n1)/bin/npx"; do
    if [[ -x "$candidate" ]]; then
      export PATH="$(dirname "$candidate"):$PATH"
      break
    fi
  done
fi

if ! command -v npx >/dev/null 2>&1; then
  echo "❌ npx not found. Please install Node.js (e.g. brew install node) and retry."
  exit 1
fi

# Use an isolated cache so we don't trip on a corrupted ~/.npm cache.
export npm_config_cache="${npm_config_cache:-/tmp/npm-cache-trax}"

echo "▶ Building $OUT from docs/TRAX_App_Features.md ..."
npx --yes @marp-team/marp-cli@latest --pptx "$SRC" -o "$OUT" --allow-local-files

echo "✅ Done."
ls -lh "$OUT"

# Keep the window open when launched via Finder double-click.
if [[ -t 0 ]]; then
  :
else
  echo
  read -n 1 -s -r -p "Press any key to close..."
  echo
fi
