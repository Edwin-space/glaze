#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

candidate_prefixes=(
  "$ROOT_DIR/Tools/mpv"
  "/opt/homebrew"
  "/usr/local"
)

echo "Glaze native media engine check"
echo

if command -v mpv >/dev/null 2>&1; then
  echo "mpv cli: $(command -v mpv)"
else
  echo "mpv cli: not installed"
fi

found_header=0
found_library=0

for prefix in "${candidate_prefixes[@]}"; do
  header="$prefix/include/mpv/client.h"
  render_header="$prefix/include/mpv/render.h"
  library="$prefix/lib/libmpv.dylib"

  if [[ -f "$header" ]]; then
    echo "libmpv client header: $header"
    found_header=1
  fi

  if [[ -f "$render_header" ]]; then
    echo "libmpv render header: $render_header"
  fi

  if [[ -f "$library" ]]; then
    echo "libmpv library: $library"
    found_library=1
  fi
done

echo

if [[ "$found_header" -eq 1 && "$found_library" -eq 1 ]]; then
  echo "result: libmpv development files are available"
else
  echo "result: libmpv development files are not available yet"
  echo "next: prepare a distributable libmpv build before wiring the embedded renderer"
fi
