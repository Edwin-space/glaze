#!/usr/bin/env bash
set -euo pipefail

VERSION="${VLC_VERSION:-3.0.21}"
ARCHIVE_NAME="vlc-$VERSION-arm64.dmg"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${VLC_RUNTIME_WORK_DIR:-${TMPDIR:-/private/tmp}/glaze-vlc-runtime}"
DMG_PATH="$WORK_DIR/$ARCHIVE_NAME"
TOOLS_DIR="$ROOT_DIR/Tools/vlc"
SOURCE_URL="https://get.videolan.org/vlc/$VERSION/macosx/$ARCHIVE_NAME"

mkdir -p "$WORK_DIR"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Downloading VLC $VERSION arm64 runtime"
  curl -L -o "$DMG_PATH" "$SOURCE_URL"
fi

mount_output="$(hdiutil attach "$DMG_PATH" -nobrowse -readonly)"
volume_path="$(printf '%s\n' "$mount_output" | awk '/\/Volumes\// { print substr($0, index($0, "/Volumes/")); exit }')"

if [[ -z "$volume_path" ]]; then
  echo "Unable to find mounted VLC volume" >&2
  exit 1
fi

cleanup() {
  hdiutil detach "$volume_path" >/dev/null 2>&1 || true
}
trap cleanup EXIT

source_root="$volume_path/VLC.app/Contents/MacOS"
if [[ ! -d "$source_root/lib" || ! -d "$source_root/plugins" || ! -d "$source_root/share" ]]; then
  echo "Mounted VLC app is missing expected lib/plugins/share directories" >&2
  exit 1
fi

rm -rf "$TOOLS_DIR"
mkdir -p "$TOOLS_DIR"
cp -R "$source_root/lib" "$TOOLS_DIR/lib"
cp -R "$source_root/plugins" "$TOOLS_DIR/plugins"
cp -R "$source_root/share" "$TOOLS_DIR/share"

echo "Installed VLC runtime:"
echo "  $TOOLS_DIR"
