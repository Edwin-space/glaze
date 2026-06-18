#!/usr/bin/env bash
set -euo pipefail

print_tool_status() {
  local tool="$1"

  if command -v "$tool" >/dev/null 2>&1; then
    printf "%-10s %s\n" "$tool:" "$(command -v "$tool")"
  else
    printf "%-10s %s\n" "$tool:" "not installed"
  fi
}

print_ffmpeg_license_flags() {
  if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "ffmpeg license flags: unavailable"
    return
  fi

  local version_line
  version_line="$(ffmpeg -version 2>/dev/null | head -n 1 || true)"
  echo "ffmpeg version: ${version_line:-unknown}"

  local configuration
  configuration="$(ffmpeg -version 2>/dev/null | sed -n 's/^configuration: //p' || true)"

  if [[ -z "$configuration" ]]; then
    echo "ffmpeg license flags: configuration unavailable"
    return
  fi

  if [[ "$configuration" == *"--enable-nonfree"* ]]; then
    echo "ffmpeg license flags: contains --enable-nonfree"
  elif [[ "$configuration" == *"--enable-gpl"* ]]; then
    echo "ffmpeg license flags: contains --enable-gpl"
  else
    echo "ffmpeg license flags: no --enable-gpl or --enable-nonfree detected"
  fi
}

inspect_file_with_mdls() {
  local file_path="$1"

  if ! command -v mdls >/dev/null 2>&1; then
    echo "  mdls: unavailable"
    return
  fi

  echo "  macOS metadata:"
  mdls -name kMDItemContentType -name kMDItemKind -name kMDItemCodecs "$file_path" 2>/dev/null | sed 's/^/    /' || true
}

inspect_file_with_ffprobe() {
  local file_path="$1"

  if ! command -v ffprobe >/dev/null 2>&1; then
    echo "  ffprobe: not installed"
    return
  fi

  echo "  ffprobe streams:"
  ffprobe \
    -v error \
    -show_entries stream=index,codec_type,codec_name,profile,width,height,pix_fmt,channels,channel_layout:format=format_name,duration,bit_rate \
    -of default=noprint_wrappers=1 \
    "$file_path" 2>/dev/null | sed 's/^/    /' || echo "    ffprobe failed"
}

inspect_sample() {
  local file_path="$1"

  echo
  echo "sample: $file_path"

  if [[ ! -f "$file_path" ]]; then
    echo "  result: file not found"
    return
  fi

  echo "  size: $(wc -c <"$file_path") bytes"
  echo "  extension: ${file_path##*.}"
  inspect_file_with_mdls "$file_path"
  inspect_file_with_ffprobe "$file_path"
}

echo "Glaze media capability validation"
echo
print_tool_status "ffmpeg"
print_tool_status "ffprobe"
print_tool_status "mediainfo"
print_ffmpeg_license_flags

if [[ "$#" -eq 0 ]]; then
  echo
  echo "No sample files were provided."
  echo "Usage: $0 <sample-video-1> [sample-video-2 ...]"
  exit 0
fi

for sample_path in "$@"; do
  inspect_sample "$sample_path"
done
