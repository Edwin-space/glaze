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

# A desktop VLC ships plugins we may not redistribute and a great deal we never
# use. The set we do ship was audited one plugin at a time against each one's own
# embedded licence declaration (Tools/vlc/LICENSE-THIRD-PARTY.md) and written down
# in Packaging/vlc-plugins.txt. Keeping only what that file names is what stops a
# GPL plugin walking back in the next time this script is run.
MANIFEST="$ROOT_DIR/Packaging/vlc-plugins.txt"
if [[ ! -f "$MANIFEST" ]]; then
  echo "Missing $MANIFEST — refusing to install an unaudited plugin set" >&2
  exit 1
fi

removed=0
while IFS= read -r plugin; do
  name="$(basename "$plugin")"
  if ! grep -Fxq "$name" "$MANIFEST"; then
    rm -f "$plugin"
    removed=$((removed + 1))
  fi
done < <(find "$TOOLS_DIR/plugins" -maxdepth 1 -type f -name "*.dylib")

missing=0
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  if [[ ! -f "$TOOLS_DIR/plugins/$name" ]]; then
    echo "  missing from this VLC build: $name" >&2
    missing=$((missing + 1))
  fi
done < "$MANIFEST"

# Anything that is not a plugin binary: BD-J Java archives we have no use for, and
# the stale plugin cache, whose recorded paths no longer match where these live.
find "$TOOLS_DIR/plugins" -maxdepth 1 ! -name "*.dylib" -type f -delete

# VLC's own translations and Lua scripts. Glaze never shows VLC's interface and
# ships no Lua plugin, so these are forty megabytes of nothing.
rm -rf "$TOOLS_DIR/share/locale" "$TOOLS_DIR/share/lua"

kept="$(find "$TOOLS_DIR/plugins" -maxdepth 1 -type f -name "*.dylib" | wc -l | tr -d " ")"
echo "Installed VLC runtime:"
echo "  $TOOLS_DIR"
echo "  plugins kept: $kept   removed as unaudited: $removed"
if (( missing > 0 )); then
  echo "  WARNING: $missing plugin(s) named in the manifest are not in this VLC build" >&2
fi
