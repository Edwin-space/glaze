#!/usr/bin/env bash
set -euo pipefail

VERSION="${FFMPEG_VERSION:-8.1.2}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${FFMPEG_BUILD_DIR:-${TMPDIR:-/private/tmp}/glaze-ffmpeg-lgpl}"
ARCHIVE="$WORK_DIR/ffmpeg-$VERSION.tar.xz"
SOURCE_DIR="$WORK_DIR/ffmpeg-$VERSION"
INSTALL_DIR="$WORK_DIR/install"
TOOLS_DIR="$ROOT_DIR/Tools"
SOURCE_URL="https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz"
MACOS_MIN_VERSION="${MACOS_MIN_VERSION:-15.0}"

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "missing required command: $command_name" >&2
    exit 1
  fi
}

require_command curl
require_command tar
require_command make
require_command xcrun

SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
CLANG="$(xcrun -find clang)"

mkdir -p "$WORK_DIR" "$TOOLS_DIR"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "Downloading FFmpeg $VERSION source from $SOURCE_URL"
  curl --fail --location --output "$ARCHIVE" "$SOURCE_URL"
fi

rm -rf "$SOURCE_DIR" "$INSTALL_DIR"
tar -xf "$ARCHIVE" -C "$WORK_DIR"

cd "$SOURCE_DIR"

CONFIGURE_FLAGS=(
  "--prefix=$INSTALL_DIR"
  "--cc=$CLANG"
  "--host-cc=$CLANG"
  "--host-ld=$CLANG"
  "--sysroot=$SDKROOT"
  "--extra-cflags=-isysroot $SDKROOT -mmacosx-version-min=$MACOS_MIN_VERSION"
  "--extra-ldflags=-isysroot $SDKROOT -mmacosx-version-min=$MACOS_MIN_VERSION"
  "--host-cflags=-isysroot $SDKROOT -mmacosx-version-min=$MACOS_MIN_VERSION"
  "--host-ldflags=-isysroot $SDKROOT -mmacosx-version-min=$MACOS_MIN_VERSION"
  "--disable-gpl"
  "--disable-nonfree"
  "--disable-doc"
  "--disable-debug"
  "--disable-ffplay"
  "--disable-autodetect"
)

echo "Configuring LGPL-only FFmpeg tools"
./configure "${CONFIGURE_FLAGS[@]}"

if grep -q -- "--enable-gpl\|--enable-nonfree" ffbuild/config.log; then
  echo "Refusing to continue: GPL or nonfree flag detected in FFmpeg configuration." >&2
  exit 1
fi

echo "Building ffmpeg and ffprobe"
make -j"$(sysctl -n hw.ncpu)" ffmpeg ffprobe
make install-progs

cp "$INSTALL_DIR/bin/ffmpeg" "$TOOLS_DIR/ffmpeg"
cp "$INSTALL_DIR/bin/ffprobe" "$TOOLS_DIR/ffprobe"
chmod +x "$TOOLS_DIR/ffmpeg" "$TOOLS_DIR/ffprobe"

{
  echo "FFmpeg local validation build"
  echo "version: $VERSION"
  echo "source: $SOURCE_URL"
  echo "built_at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  "$TOOLS_DIR/ffmpeg" -version | sed -n '1,8p'
} >"$TOOLS_DIR/FFMPEG_BUILD.txt"

echo "Installed local FFmpeg tools:"
echo "  $TOOLS_DIR/ffmpeg"
echo "  $TOOLS_DIR/ffprobe"
