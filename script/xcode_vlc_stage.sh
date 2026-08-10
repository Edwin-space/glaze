#!/usr/bin/env bash
set -euo pipefail

# Run as a postbuild script phase (see project.yml) for the GlazeMac Xcode target.
# Stages the bundled VLC runtime and ffmpeg/ffprobe binaries into the built app's
# Resources folder, and patches VLC's dylib load paths to be bundle-relative.
# Mirrors the logic that used to live inline in script/build_and_run.sh.

ROOT_DIR="${SRCROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOCAL_TOOLS_DIR="$ROOT_DIR/Tools"

if [[ -z "${BUILT_PRODUCTS_DIR:-}" || -z "${CONTENTS_FOLDER_PATH:-}" ]]; then
  echo "xcode_vlc_stage.sh: missing Xcode build environment, skipping" >&2
  exit 0
fi

APP_RESOURCES="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Resources"
mkdir -p "$APP_RESOURCES"

if [[ ! -d "$LOCAL_TOOLS_DIR" ]]; then
  echo "xcode_vlc_stage.sh: $LOCAL_TOOLS_DIR not found, skipping" >&2
  exit 0
fi

mkdir -p "$APP_RESOURCES/Tools"
for tool in ffmpeg ffprobe; do
  if [[ -f "$LOCAL_TOOLS_DIR/$tool" ]]; then
    cp "$LOCAL_TOOLS_DIR/$tool" "$APP_RESOURCES/Tools/$tool"
    chmod +x "$APP_RESOURCES/Tools/$tool"
  fi
done

if [[ -d "$LOCAL_TOOLS_DIR/vlc" ]]; then
  rm -rf "$APP_RESOURCES/Tools/vlc"
  cp -R "$LOCAL_TOOLS_DIR/vlc" "$APP_RESOURCES/Tools/vlc"

  while IFS= read -r dylib_path; do
    dylib_name="$(basename "$dylib_path")"
    install_name_tool -id "@loader_path/$dylib_name" "$dylib_path" 2>/dev/null || true
    install_name_tool -change "@rpath/libvlccore.dylib" "@loader_path/libvlccore.dylib" "$dylib_path" 2>/dev/null || true
    codesign --force --sign - "$dylib_path" >/dev/null 2>&1 || true
  done < <(find "$APP_RESOURCES/Tools/vlc/lib" -maxdepth 1 -type f -name "*.dylib")

  while IFS= read -r plugin_path; do
    install_name_tool -change "@rpath/libvlccore.dylib" "@loader_path/../lib/libvlccore.dylib" "$plugin_path" 2>/dev/null || true
    codesign --force --sign - "$plugin_path" >/dev/null 2>&1 || true
  done < <(find "$APP_RESOURCES/Tools/vlc/plugins" -type f -name "*.dylib")
fi
