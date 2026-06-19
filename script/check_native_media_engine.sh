#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Glaze native media engine check"
echo

runtime_dir="$ROOT_DIR/Tools/vlc"
libvlc="$runtime_dir/lib/libvlc.dylib"
libvlccore="$runtime_dir/lib/libvlccore.dylib"
plugins_dir="$runtime_dir/plugins"
plugins_cache="$plugins_dir/plugins.dat"
share_dir="$runtime_dir/share"

echo "VLC runtime: $runtime_dir"

if [[ -f "$libvlc" ]]; then
  echo "libvlc: $libvlc"
else
  echo "libvlc: missing"
fi

if [[ -f "$libvlccore" ]]; then
  echo "libvlccore: $libvlccore"
else
  echo "libvlccore: missing"
fi

if [[ -d "$plugins_dir" ]]; then
  echo "plugins: $(find "$plugins_dir" -type f -name '*.dylib' | wc -l | tr -d ' ') dylibs"
else
  echo "plugins: missing"
fi

if [[ -f "$plugins_cache" ]]; then
  echo "plugins cache: $plugins_cache"
else
  echo "plugins cache: missing"
fi

if [[ -d "$share_dir" ]]; then
  echo "share: $share_dir"
else
  echo "share: missing"
fi

echo

if [[ -f "$libvlc" && -f "$libvlccore" && -d "$plugins_dir" && -f "$plugins_cache" && -d "$share_dir" ]]; then
  echo "result: bundled VLC runtime is available"
else
  echo "result: bundled VLC runtime is incomplete"
  echo "next: copy VLC.app/Contents/MacOS/lib, plugins, and share into Tools/vlc"
  exit 1
fi
