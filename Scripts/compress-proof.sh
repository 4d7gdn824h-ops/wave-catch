#!/bin/bash
# simctl recordVideo stores the portrait framebuffer (1290x2796) even when the
# app is landscape. That buffer is 90 degrees clockwise from the upright
# screenshots (those PNGs needed the other direction, a 180 degree flip).
# transpose=2 turns it counter-clockwise so the sky matches the PNGs, then
# scale fills 1280x590 with no pad.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: compress-proof.sh input.mp4 output.mp4" >&2
  exit 2
fi

input=$1
output=$2

ffprobe -hide_banner -show_streams -show_format "$input" >&2 || true

encode() {
  local bitrate=$1
  ffmpeg -y -i "$input" \
    -vf "transpose=2,scale=1280:-2,setsar=1" \
    -c:v libx264 -pix_fmt yuv420p -profile:v high \
    -b:v "$bitrate" -maxrate "$bitrate" -bufsize 4M \
    -movflags +faststart -an \
    "$output"
}

encode 1800k
size=$(wc -c < "$output" | tr -d ' ')
if [[ "$size" -gt 15000000 ]]; then
  echo "retrying at a lower bitrate ($size bytes)" >&2
  encode 1100k
  size=$(wc -c < "$output" | tr -d ' ')
fi

width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$output")
height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$output")
pix=$(ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of csv=p=0 "$output")
duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$output")
echo "proof video ${width}x${height} ${pix} duration ${duration}s ${size} bytes"

if [[ "$width" != "1280" || "$height" != "590" ]]; then
  echo "expected 1280x590, got ${width}x${height}" >&2
  exit 1
fi
if [[ "$pix" != "yuv420p" ]]; then
  echo "expected yuv420p, got ${pix}" >&2
  exit 1
fi
if [[ "$size" -gt 15000000 || "$size" -eq 0 ]]; then
  echo "proof video is ${size} bytes" >&2
  exit 1
fi
