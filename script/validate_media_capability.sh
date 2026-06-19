#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tool_path() {
  local tool="$1"
  local local_tool="$ROOT_DIR/Tools/$tool"

  if [[ -x "$local_tool" ]]; then
    echo "$local_tool"
    return
  fi

  if command -v "$tool" >/dev/null 2>&1; then
    command -v "$tool"
  fi
}

print_tool_status() {
  local tool="$1"
  local resolved_path
  resolved_path="$(tool_path "$tool" || true)"

  if [[ -n "$resolved_path" ]]; then
    printf "%-10s %s\n" "$tool:" "$resolved_path"
  else
    printf "%-10s %s\n" "$tool:" "not installed"
  fi
}

print_ffmpeg_license_flags() {
  local ffmpeg_path
  ffmpeg_path="$(tool_path ffmpeg || true)"

  if [[ -z "$ffmpeg_path" ]]; then
    echo "ffmpeg license flags: unavailable"
    return
  fi

  local version_line
  version_line="$("$ffmpeg_path" -version 2>/dev/null | head -n 1 || true)"
  echo "ffmpeg version: ${version_line:-unknown}"

  local configuration
  configuration="$("$ffmpeg_path" -version 2>/dev/null | sed -n 's/^configuration: //p' || true)"

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
  local ffprobe_path
  ffprobe_path="$(tool_path ffprobe || true)"

  if [[ -z "$ffprobe_path" ]]; then
    echo "  ffprobe: not installed"
    return
  fi

  echo "  ffprobe streams:"
  "$ffprobe_path" \
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

remux_sample_for_avkit() {
  local file_path="$1"
  local ffmpeg_path
  ffmpeg_path="$(tool_path ffmpeg || true)"

  if [[ -z "$ffmpeg_path" ]]; then
    echo
    echo "remux: ffmpeg not installed"
    return
  fi

  if [[ ! -f "$file_path" ]]; then
    echo
    echo "remux: file not found: $file_path"
    return
  fi

  local output_dir="${TMPDIR:-/tmp}/glaze-remux-validation"
  mkdir -p "$output_dir"

  local base_name
  base_name="$(basename "$file_path")"
  base_name="${base_name%.*}"

  local copy_output_path="$output_dir/$base_name-stream-copy.mp4"
  local audio_output_path="$output_dir/$base_name-audio-aac.mp4"
  local video_codec
  video_codec="$(inspect_primary_video_codec "$file_path")"
  local audio_codec
  audio_codec="$(inspect_primary_audio_codec "$file_path")"
  local video_tag_args=()

  if [[ "$video_codec" == "hevc" ]]; then
    video_tag_args=(-tag:v hvc1)
  fi

  echo
  echo "remux: $file_path"
  echo "  primary video codec: ${video_codec:-unknown}"
  echo "  primary audio codec: ${audio_codec:-unknown}"

  if is_avplayer_audio_candidate "$audio_codec"; then
    remux_stream_copy "$ffmpeg_path" "$file_path" "$copy_output_path" "${video_tag_args[@]}" && return
    remux_audio_aac "$ffmpeg_path" "$file_path" "$audio_output_path" "${video_tag_args[@]}" && return
  else
    remux_audio_aac "$ffmpeg_path" "$file_path" "$audio_output_path" "${video_tag_args[@]}" && return
    remux_stream_copy "$ffmpeg_path" "$file_path" "$copy_output_path" "${video_tag_args[@]}" && return
  fi

  echo "  result: all remux attempts failed"
}

remux_audio_aac() {
  local ffmpeg_path="$1"
  local file_path="$2"
  local audio_output_path="$3"
  shift 3
  local video_tag_args=("$@")

  echo "  audio-aac output: $audio_output_path"

  if "$ffmpeg_path" \
    -y \
    -hide_banner \
    -loglevel error \
    -i "$file_path" \
    -map 0:v:0 \
    -map 0:a:0? \
    -sn \
    -dn \
    -c:v copy \
    -c:a aac \
    -b:a 192k \
    -ac 2 \
    "${video_tag_args[@]}" \
    -movflags +faststart \
    "$audio_output_path"; then
    echo "  result: audio-aac remux succeeded"
    return 0
  else
    echo "  result: audio-aac remux failed"
    return 1
  fi
}

remux_stream_copy() {
  local ffmpeg_path="$1"
  local file_path="$2"
  local copy_output_path="$3"
  shift 3
  local video_tag_args=("$@")

  echo "  stream-copy output: $copy_output_path"

  if "$ffmpeg_path" \
    -y \
    -hide_banner \
    -loglevel error \
    -i "$file_path" \
    -map 0:v:0 \
    -map 0:a? \
    -sn \
    -dn \
    -c copy \
    "${video_tag_args[@]}" \
    -movflags +faststart \
    "$copy_output_path"; then
    echo "  result: stream-copy remux succeeded"
    return 0
  else
    echo "  result: stream-copy remux failed"
    return 1
  fi
}

is_avplayer_audio_candidate() {
  case "${1:-}" in
    aac|alac|mp3|ac3|eac3)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

inspect_primary_video_codec() {
  local file_path="$1"
  local ffprobe_path
  ffprobe_path="$(tool_path ffprobe || true)"

  if [[ -z "$ffprobe_path" ]]; then
    return
  fi

  "$ffprobe_path" \
    -v error \
    -select_streams v:0 \
    -show_entries stream=codec_name \
    -of default=noprint_wrappers=1:nokey=1 \
    "$file_path" 2>/dev/null | head -n 1 || true
}

inspect_primary_audio_codec() {
  local file_path="$1"
  local ffprobe_path
  ffprobe_path="$(tool_path ffprobe || true)"

  if [[ -z "$ffprobe_path" ]]; then
    return
  fi

  "$ffprobe_path" \
    -v error \
    -select_streams a:0 \
    -show_entries stream=codec_name \
    -of default=noprint_wrappers=1:nokey=1 \
    "$file_path" 2>/dev/null | head -n 1 || true
}

SHOULD_REMUX=0

if [[ "${1:-}" == "--remux" ]]; then
  SHOULD_REMUX=1
  shift
fi

echo "Glaze media capability validation"
echo
print_tool_status "ffmpeg"
print_tool_status "ffprobe"
print_tool_status "mediainfo"
print_ffmpeg_license_flags

if [[ "$#" -eq 0 ]]; then
  echo
  echo "No sample files were provided."
  echo "Usage: $0 [--remux] <sample-video-1> [sample-video-2 ...]"
  exit 0
fi

for sample_path in "$@"; do
  inspect_sample "$sample_path"
  if [[ "$SHOULD_REMUX" -eq 1 ]]; then
    remux_sample_for_avkit "$sample_path"
  fi
done
