#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Glaze"
BUNDLE_ID="app.glaze.player"
MIN_SYSTEM_VERSION="15.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
RESOURCE_BUNDLE_NAME="Glaze_Glaze.bundle"
LOCAL_TOOLS_DIR="$ROOT_DIR/Tools"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
sleep 0.2
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  pkill -9 -x "$APP_NAME" >/dev/null 2>&1 || true
fi

swift build
BUILD_DIR="$(swift build --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"
BUILD_RESOURCE_BUNDLE="$BUILD_DIR/$RESOURCE_BUNDLE_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -d "$BUILD_RESOURCE_BUNDLE" ]]; then
  cp -R "$BUILD_RESOURCE_BUNDLE" "$APP_BUNDLE/$RESOURCE_BUNDLE_NAME"
fi

if [[ -d "$LOCAL_TOOLS_DIR" ]]; then
  mkdir -p "$APP_RESOURCES/Tools"
  for tool in ffmpeg ffprobe; do
    if [[ -f "$LOCAL_TOOLS_DIR/$tool" ]]; then
      cp "$LOCAL_TOOLS_DIR/$tool" "$APP_RESOURCES/Tools/$tool"
      chmod +x "$APP_RESOURCES/Tools/$tool"
    fi
  done

  if [[ -d "$LOCAL_TOOLS_DIR/vlc" ]]; then
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
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Video</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.movie</string>
        <string>public.video</string>
        <string>public.audiovisual-content</string>
        <string>org.matroska.mkv</string>
        <string>io.mpv.mkv</string>
      </array>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>mkv</string>
        <string>mp4</string>
        <string>mov</string>
        <string>avi</string>
        <string>webm</string>
        <string>m4v</string>
      </array>
    </dict>
  </array>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

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
