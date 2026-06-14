#!/bin/bash
# Builds a minimal, self-contained FFmpeg for the native scrcpy H.264 decoder on
# Linux and stages it under .ffmpeg-dev/linux/{include,lib}.
#
# Why build instead of using the system FFmpeg: the runner links libavcodec/
# libavutil into the binary, so a .deb built against the distro FFmpeg pins that
# distro's soname (e.g. ubuntu-24.04 → libavcodec60/libavutil58) and refuses to
# install anywhere else. The distro's libavcodec also NEEDED-links the whole
# codec universe (x264/vpx/dav1d/…) plus librsvg→cairo→pango→glib, which clashes
# with the app's own GTK GLib if bundled.
#
# native/scrcpy_video_decoder.cc only needs the built-in H.264 decoder
# (avcodec_find_decoder(AV_CODEC_ID_H264) + send/receive frame). Disabling every
# other component and FFmpeg sub-library yields libavcodec + libavutil that
# depend on glibc only — small, conflict-free, and portable across distros.
# These are bundled into the app's lib/ dir (RUNPATH $ORIGIN/lib); see
# linux/CMakeLists.txt. Keep FFMPEG_VERSION in sync with the Windows DLLs that
# scrcpy ships (download_platform_tools.sh) so all platforms share an API major.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FFMPEG_VERSION="${FFMPEG_VERSION:-8.0.1}"
FFMPEG_SOURCE_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
DEST="$PROJECT_DIR/.ffmpeg-dev/linux"

build_ffmpeg() {
  local tmp src asm_flag
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  echo "Downloading FFmpeg ${FFMPEG_VERSION} source..."
  curl -L --fail -o "$tmp/ffmpeg.tar.xz" "$FFMPEG_SOURCE_URL"
  tar -xf "$tmp/ffmpeg.tar.xz" -C "$tmp"
  src="$tmp/ffmpeg-${FFMPEG_VERSION}"

  # x86 SIMD needs an assembler; fall back to C-only if none is available so a
  # bare dev machine can still build (CI installs nasm for optimized decode).
  asm_flag=""
  if ! command -v nasm >/dev/null 2>&1 && ! command -v yasm >/dev/null 2>&1; then
    echo "WARNING: nasm/yasm not found — building without x86 SIMD (slower decode)."
    asm_flag="--disable-x86asm"
  fi

  echo "Configuring minimal FFmpeg (H.264 decode only)..."
  (
    cd "$src"
    ./configure \
      --prefix="$DEST" \
      --disable-static --enable-shared --enable-pic \
      --disable-everything \
      --enable-decoder=h264 \
      --enable-parser=h264 \
      --disable-avdevice --disable-avfilter --disable-avformat \
      --disable-swresample --disable-swscale \
      --disable-programs --disable-doc \
      --disable-htmlpages --disable-manpages --disable-podpages --disable-txtpages \
      --disable-network --disable-autodetect --disable-debug \
      --disable-zlib --disable-lzma --disable-bzlib --disable-iconv \
      --disable-sdl2 --disable-xlib --disable-libxcb \
      $asm_flag
    make -j"$(nproc 2>/dev/null || echo 2)"
    make install
  )
}

stage_runpath() {
  # The bundled .so files sit together in the app's lib/ dir. patchelf gives each
  # an $ORIGIN RUNPATH so any FFmpeg sibling (e.g. libavutil) resolves from that
  # dir rather than the (absent) system FFmpeg. libavcodec/libavutil are also
  # linked directly by the runner, so this is belt-and-suspenders, but it keeps
  # the bundle correct if more decoders are enabled later.
  if command -v patchelf >/dev/null 2>&1; then
    local so
    for so in "$DEST"/lib/*.so*; do
      [ -f "$so" ] || continue
      patchelf --set-rpath '$ORIGIN' "$so" 2>/dev/null || true
    done
  else
    echo "WARNING: patchelf not found — skipping \$ORIGIN RUNPATH on FFmpeg libs."
  fi
}

if [ -d "$DEST/include" ] && ls "$DEST"/lib/libavcodec.so* >/dev/null 2>&1; then
  echo "Minimal Linux FFmpeg already present at $DEST"
else
  rm -rf "$DEST"
  mkdir -p "$DEST"
  build_ffmpeg
  stage_runpath
  echo "Minimal Linux FFmpeg ready at $DEST"
fi

# In GitHub Actions, forward to GITHUB_ENV so the build step finds the headers
# and import libs (mirrors download_windows_ffmpeg_dev).
if [ -n "${GITHUB_ENV:-}" ]; then
  {
    printf 'FFMPEG_INCLUDE_DIR=%s/include\n' "$DEST"
    printf 'FFMPEG_LIB_DIR=%s/lib\n' "$DEST"
  } >> "$GITHUB_ENV"
fi
