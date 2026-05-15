#!/usr/bin/env bash
# Patch the (4-years-stale) amap_flutter_map / amap_flutter_base plugins in
# the pub-cache so they compile against modern Flutter (3.x) + AGP 8.
#
# Patches:
#   1) hashValues(...)          → Object.hash(...)           (dart sdk dropped hashValues)
#   2) v1-embedding registerWith(PluginRegistry.Registrar)   → no-op stub
#      (java symbol removed; v2 onAttachedToEngine still works)
#   3) io.flutter.view.FlutterMain  → io.flutter.FlutterInjector
#      (FlutterMain removed in newer Flutter android embedding)
#
# Re-run after any `flutter pub get` / `flutter pub cache repair` that
# re-extracts the plugin tarballs.
set -euo pipefail

CACHE="${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.flutter-io.cn"
MAP="$CACHE/amap_flutter_map-3.0.0"
BASE="$CACHE/amap_flutter_base-3.0.0"

if [[ ! -d "$MAP" || ! -d "$BASE" ]]; then
  echo "amap plugins not found in pub cache; run 'flutter pub get' first." >&2
  exit 1
fi

echo "==> Patching hashValues -> Object.hash"
grep -rl "hashValues(" "$BASE/lib" "$MAP/lib" 2>/dev/null \
  | xargs -I{} sed -i '' 's/hashValues(/Object.hash(/g' {} || true

echo "==> Patching ConvertUtil FlutterMain -> FlutterInjector"
CV="$MAP/android/src/main/java/com/amap/flutter/map/utils/ConvertUtil.java"
if [[ -f "$CV" ]] && grep -q "io.flutter.view.FlutterMain" "$CV"; then
  sed -i '' 's|import io.flutter.view.FlutterMain;|import io.flutter.FlutterInjector;|' "$CV"
  sed -i '' 's|FlutterMain\.getLookupKeyForAsset|FlutterInjector.instance().flutterLoader().getLookupKeyForAsset|g' "$CV"
fi

echo "==> Stubbing v1 registerWith(PluginRegistry.Registrar)"
PLUGIN="$MAP/android/src/main/java/com/amap/flutter/map/AMapFlutterMapPlugin.java"
if [[ -f "$PLUGIN" ]] && grep -q "PluginRegistry\.Registrar registrar" "$PLUGIN"; then
  python3 - "$PLUGIN" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p).read()
s = re.sub(
    r'public static void registerWith\(PluginRegistry\.Registrar registrar\)\s*\{.*?^    \}\s*$',
    'public static void registerWith(Object registrar) {\n        // v1 embedding API stripped (legacy plugin shim).\n    }',
    s, count=1, flags=re.DOTALL | re.MULTILINE)
open(p, 'w').write(s)
PY
fi

echo "==> Done. AMap plugins patched for Flutter 3.x / AGP 8."
