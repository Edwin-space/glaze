#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Glaze"
BUNDLE_ID="com.edwin.glaze"
CONFIGURATION="${GLAZE_CONFIGURATION:-Debug}"
SCHEME="GlazeMac"

# `release` builds and runs the optimised configuration. Debug is built -Onone and
# SwiftUI does far more per-frame bookkeeping in it, so judge real-world responsiveness
# here rather than from a Debug run.
if [[ "$MODE" == "release" ]]; then
  CONFIGURATION="Release"
  MODE="run"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_SPEC="$ROOT_DIR/project.yml"
XCODEPROJ="$ROOT_DIR/Glaze.xcodeproj"
DERIVED_DATA_DIR="$ROOT_DIR/dist/DerivedData"
APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Stop only the copy this script builds and runs.
#
# This used to be `pkill -x Glaze`, which matches on process name and therefore also
# killed the Glaze running under someone's Xcode debugger — a build here would end
# their debugging session with no warning.
#
# Matching on the executable path needs care: the repository lives under a Hangul
# directory name, and the kernel reports that path decomposed (NFD) while the shell
# holds it composed (NFC), so a plain `pgrep -f "$APP_BINARY"` silently matches
# nothing. Python compares the two after normalising both.
stop_our_app() {
  /usr/bin/python3 - "$APP_BINARY" <<'PYEOF' || true
import os, signal, subprocess, sys, unicodedata

def key(path):
    return unicodedata.normalize("NFC", path)

target = key(sys.argv[1])
listing = subprocess.run(["/bin/ps", "-axo", "pid=,comm="], capture_output=True, text=True).stdout

for line in listing.splitlines():
    pid, _, command = line.strip().partition(" ")
    if key(command) != target:
        continue
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.kill(int(pid), sig)
        except ProcessLookupError:
            break
PYEOF
  sleep 0.4
}

stop_our_app

if command -v xcodegen >/dev/null 2>&1; then
  XCODEGEN_BIN="xcodegen"
elif [[ -x "$HOME/bin/xcodegen" ]]; then
  XCODEGEN_BIN="$HOME/bin/xcodegen"
else
  echo "xcodegen not found (checked PATH and ~/bin). Install it, e.g. 'brew install xcodegen'." >&2
  exit 1
fi

# Regenerate whenever project.yml changed OR any source file is newer than the
# generated project — xcodegen snapshots file references at generation time, so
# adding/removing a .swift file needs a regenerate too, not just editing project.yml.
NEEDS_REGENERATE=0
if [[ ! -d "$XCODEPROJ" ]] || [[ "$PROJECT_SPEC" -nt "$XCODEPROJ/project.pbxproj" ]]; then
  NEEDS_REGENERATE=1
elif find "$ROOT_DIR/Sources/GlazeMac" -newer "$XCODEPROJ/project.pbxproj" -print -quit 2>/dev/null | grep -q .; then
  NEEDS_REGENERATE=1
fi
if [[ "$NEEDS_REGENERATE" -eq 1 ]]; then
  (cd "$ROOT_DIR" && "$XCODEGEN_BIN" generate)
fi

xcodebuild \
  -project "$XCODEPROJ" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

# Deliberately not `open -n`. Launching a second instance of the same bundle id
# sometimes produces a process with no window at all: the app runs and takes the menu
# bar, but `CGWindowListCopyWindowInfo` reports no window and none is ever drawn.
# Replacing the running instance avoids that.
open_app() {
  stop_our_app
  if [[ $# -gt 0 ]]; then
    # `-a` is required here. Without it `open` treats every argument as something to
    # open in its own right, so the video would go to whatever app currently claims
    # the file type rather than to the build under test.
    /usr/bin/open -a "$APP_BUNDLE" "$@"
  else
    /usr/bin/open "$APP_BUNDLE"
  fi
}

case "$MODE" in
  run)
    shift || true
    open_app "$@"
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
    echo "usage: $0 [run|release|--bundle|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
