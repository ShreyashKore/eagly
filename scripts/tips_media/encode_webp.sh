#!/usr/bin/env bash
# Turns a screen recording into a small looping animated WebP for a tip.
#
#   scripts/tips_media/encode_webp.sh in.mov out.webp [crop] [width] [fps] [quality] [hold_ms]
#
#   crop     ffmpeg crop filter args "w:h:x:y" in recording pixels, or "" for none
#   width    output width in px (default 820 ≈ 2× the tip dialog's content width)
#   fps      frames per second (default 12)
#   quality  lossy quality 0–100 (default 55)
#   hold_ms  how long the last frame stays before the loop restarts (default 1500)
#
# Optional env:
#   START, DURATION  trim the recording (seconds) before anything else.
#   ZOOM  "factor:x:y:from:to[:out_from:out_to]" — an eased push-in. The clip
#         opens on the whole (cropped) frame, so the viewer sees where they
#         are, then zooms by `factor` onto the region whose top-left is x,y
#         (cropped-frame pixels) between `from` and `to` seconds, keeping the
#         menu readable at dialog size. Give out_from:out_to to pull back out;
#         without them it stays close and the loop restart cuts back to wide.
#         Times are after trimming.
#   ZOOM_BLUR  gaussian sigma applied to frames while the zoom moves
#         (default 2). Reads as motion blur and compresses far better: a
#         sharp full-frame zoom step costs ~25 KB, a blurred one a fraction.
#   ZOOM_Q  lossy quality for those moving frames (default 20).
#
# Needs ffmpeg (frames) and img2webp from libwebp (encoding). WebPAnimEncoder
# stores only the changed rectangle of each frame and merges identical frames,
# so mostly-static UI clips stay small; a zoom changes every pixel, which is
# why its frames get the blur and lower quality above.
set -euo pipefail

in=$1 out=$2
crop=${3:-} width=${4:-820} fps=${5:-12} quality=${6:-55} hold=${7:-1500}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

trim=()
[[ -n ${START:-} ]] && trim+=(-ss "$START")
[[ -n ${DURATION:-} ]] && trim+=(-t "$DURATION")

moving=() # "from to" windows (seconds) where the zoom is in motion
if [[ -n ${ZOOM:-} ]]; then
  IFS=: read -r zf zx zy zi0 zi1 zo0 zo1 <<<"$ZOOM"
  if [[ -n $crop ]]; then
    IFS=: read -r cw ch _ <<<"$crop"
  else
    IFS=x read -r cw ch < <(ffprobe -v error -select_streams v:0 \
      -show_entries stream=width,height -of csv=s=x:p=0 "$in")
  fi
  height=$(((width * ch / cw + 1) / 2 * 2))
  # p rises 0 → 1 over [zi0, zi1] (and falls back over [zo0, zo1]),
  # smoothstep-eased at both ends.
  p="st(0,clip((it-$zi0)/($zi1-$zi0),0,1));ld(0)*ld(0)*(3-2*ld(0))"
  moving+=("$zi0 $zi1")
  if [[ -n ${zo0:-} ]]; then
    p="st(0,clip((it-$zi0)/($zi1-$zi0),0,1));st(1,clip((it-$zo0)/($zo1-$zo0),0,1));"
    p+="ld(0)*ld(0)*(3-2*ld(0))-ld(1)*ld(1)*(3-2*ld(1))"
    moving+=("$zo0 $zo1")
  fi
  enable=""
  for w in "${moving[@]}"; do
    read -r a b <<<"$w"
    enable+="${enable:++}between(t,$a,$b)"
  done
  # zoompan pans in whole input pixels; growing the region from a fixed
  # top-left keeps the motion straight. Its 'zoom' feeds back into x/y.
  filters="fps=30,zoompan=z='1+($zf-1)*($p)'"
  filters+=":x='$zx*(zoom-1)/($zf-1)':y='$zy*(zoom-1)/($zf-1)'"
  filters+=":d=1:fps=30:s=${width}x${height},fps=$fps"
  filters+=",gblur=sigma=${ZOOM_BLUR:-2}:enable='$enable'"
else
  filters="fps=$fps,scale=$width:-2:flags=lanczos"
fi
[[ -n $crop ]] && filters="crop=$crop,$filters"
ffmpeg -loglevel error "${trim[@]}" -i "$in" -vf "$filters" "$work/f%04d.png"

frames=("$work"/f*.png)
n=${#frames[@]}
delay=$((1000 / fps))

args=(-loop 0 -lossy -m 6)
for ((k = 0; k < n; k++)); do
  q=$quality
  for w in "${moving[@]+"${moving[@]}"}"; do
    read -r a b <<<"$w"
    # frame k is shown at k/fps seconds
    if awk -v t="$k" -v f="$fps" -v a="$a" -v b="$b" \
      'BEGIN { s = t / f; exit !(s >= a && s <= b) }'; then
      q=${ZOOM_Q:-20}
    fi
  done
  d=$delay
  ((k == n - 1)) && d=$hold
  args+=(-q "$q" -d "$d" "${frames[$k]}")
done
img2webp "${args[@]}" -o "$out" >/dev/null 2>&1

size=$(stat -f%z "$out" 2>/dev/null || stat -c%s "$out")
echo "$out: $n frames, $((size / 1024)) KB"
