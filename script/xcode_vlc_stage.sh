#!/usr/bin/env bash
set -euo pipefail

# Run as a postbuild script phase (see project.yml) for the GlazeMac Xcode target.
# Stages the bundled VLC runtime and ffmpeg/ffprobe binaries into the built app,
# signs executable helpers for App Sandbox inheritance, and patches VLC's dylib
# load paths to be bundle-relative.
# Mirrors the logic that used to live inline in script/build_and_run.sh.

ROOT_DIR="${SRCROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOCAL_TOOLS_DIR="$ROOT_DIR/Tools"

if [[ -z "${BUILT_PRODUCTS_DIR:-}" || -z "${CONTENTS_FOLDER_PATH:-}" ]]; then
  echo "xcode_vlc_stage.sh: missing Xcode build environment, skipping" >&2
  exit 0
fi

APP_RESOURCES="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Resources"
APP_EXECUTABLES="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/MacOS"
HELPER_ENTITLEMENTS="$ROOT_DIR/Packaging/GlazeHelper.entitlements"
mkdir -p "$APP_RESOURCES"

if [[ ! -d "$LOCAL_TOOLS_DIR" ]]; then
  echo "xcode_vlc_stage.sh: $LOCAL_TOOLS_DIR not found, skipping" >&2
  exit 0
fi

mkdir -p "$APP_RESOURCES/Tools" "$APP_EXECUTABLES"
for tool in ffmpeg ffprobe; do
  if [[ -f "$LOCAL_TOOLS_DIR/$tool" ]]; then
    helper_path="$APP_EXECUTABLES/$tool"
    cp "$LOCAL_TOOLS_DIR/$tool" "$helper_path"
    chmod +x "$helper_path"

    if [[ "${CONFIGURATION:-Debug}" == "Release" ]]; then
      signing_identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
      if [[ -z "$signing_identity" ]]; then
        signing_identity="-"
      fi
      codesign \
        --force \
        --sign "$signing_identity" \
        --identifier "${PRODUCT_BUNDLE_IDENTIFIER:-com.edwin.glaze}.$tool" \
        --options runtime \
        --entitlements "$HELPER_ENTITLEMENTS" \
        --generate-entitlement-der \
        --timestamp=none \
        "$helper_path"
    fi
  fi
done

# Remove helpers staged by older builds so an incremental Archive cannot retain
# an unsandboxed executable under Contents/Resources.
rm -f \
  "$APP_RESOURCES/Tools/ffmpeg" \
  "$APP_RESOURCES/Tools/ffprobe" \
  "$APP_EXECUTABLES/Tools/ffmpeg" \
  "$APP_EXECUTABLES/Tools/ffprobe"

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
