#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Glaze"
BUNDLE_ID="app.glaze.player"
CONFIGURATION="${GLAZE_CONFIGURATION:-Debug}"
SCHEME="GlazeMac"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_SPEC="$ROOT_DIR/project.yml"
XCODEPROJ="$ROOT_DIR/Glaze.xcodeproj"
DERIVED_DATA_DIR="$ROOT_DIR/dist/DerivedData"
APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
sleep 0.2
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  pkill -9 -x "$APP_NAME" >/dev/null 2>&1 || true
fi

if command -v xcodegen >/dev/null 2>&1; then
  XCODEGEN_BIN="xcodegen"
elif [[ -x "$HOME/bin/xcodegen" ]]; then
  XCODEGEN_BIN="$HOME/bin/xcodegen"
else
  echo "xcodegen not found (checked PATH and ~/bin). Install it, e.g. 'brew install xcodegen'." >&2
  exit 1
fi

if [[ ! -d "$XCODEPROJ" ]] || [[ "$PROJECT_SPEC" -nt "$XCODEPROJ/project.pbxproj" ]]; then
  (cd "$ROOT_DIR" && "$XCODEGEN_BIN" generate)
fi

xcodebuild \
  -project "$XCODEPROJ" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --bundle|bundle)
    echo "$APP_BUNDLE"
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--bundle|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
