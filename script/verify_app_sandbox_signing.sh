#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/dist/DerivedData/Build/Products/Release/Glaze.app}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

assert_entitlement() {
  local executable_path="$1"
  local entitlement_key="$2"
  local signing_output

  if [[ ! -x "$executable_path" ]]; then
    echo "Executable not found: $executable_path" >&2
    exit 1
  fi

  signing_output="$(codesign -d -vvv --entitlements - "$executable_path" 2>&1)"
  if ! /usr/bin/awk -v key="$entitlement_key" '
    index($0, "[Key] " key) || index($0, "<key>" key "</key>") { remaining = 3 }
    remaining > 0 && ($0 ~ /\[Bool\] true/ || $0 ~ /<true\/>/) { found = 1; exit }
    remaining > 0 { remaining-- }
    END { exit(found ? 0 : 1) }
  ' <<< "$signing_output"; then
    echo "Missing or false $entitlement_key: $executable_path" >&2
    exit 1
  fi
}

assert_only_inheritance_entitlements() {
  local executable_path="$1"
  local signing_output
  local key_count

  signing_output="$(codesign -d -vvv --entitlements - "$executable_path" 2>&1)"
  key_count="$(/usr/bin/grep -Ec "^[[:space:]]*(\[Key\]|<key>)" <<< "$signing_output")"
  if [[ "$key_count" -ne 2 ]]; then
    echo "Helper must contain only app-sandbox and inherit entitlements: $executable_path" >&2
    exit 1
  fi
}

assert_entitlement "$APP_PATH/Contents/MacOS/Glaze" "com.apple.security.app-sandbox"

for tool in ffmpeg ffprobe; do
  helper_path="$APP_PATH/Contents/MacOS/$tool"
  assert_entitlement "$helper_path" "com.apple.security.app-sandbox"
  assert_entitlement "$helper_path" "com.apple.security.inherit"
  assert_only_inheritance_entitlements "$helper_path"
done

verification_output="$(mktemp)"
if ! codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>"$verification_output"; then
  if /usr/bin/grep -Evq "CSSMERR_TP_NOT_TRUSTED|^In architecture:" "$verification_output"; then
    /bin/cat "$verification_output" >&2
    /bin/rm -f "$verification_output"
    exit 1
  fi
  echo "Warning: local signing certificate trust could not be verified; structural signature checks passed." >&2
fi
/bin/rm -f "$verification_output"
echo "App Sandbox signing verified: $APP_PATH"
