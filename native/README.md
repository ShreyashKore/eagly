# Native scrcpy video decoder (Windows + Linux)

Shared H.264 → RGBA decoder for the embedded screen mirror on **Windows and
Linux**. macOS uses VideoToolbox instead (`macos/Runner/ScrcpyVideoPlugin.swift`).

```
Dart ScrcpyClient ──(binary channel "eagly/scrcpy_video/feed")──▶ platform plugin
                                                                      │
  scrcpy_video_decoder.{h,cc}  (FFmpeg libavcodec, runs on a worker thread)
        H.264 Annex-B ─▶ YUV420P ─▶ RGBA                               │
                                                                      ▼
  Windows: flutter::PixelBufferTexture   Linux: FlPixelBufferTexture ─▶ Texture()
```

- `scrcpy_video_decoder.{h,cc}` — shared, platform-agnostic FFmpeg decoder.
- `windows/runner/scrcpy_video_plugin.{h,cpp}` — Win32 glue (`PixelBufferTexture`),
  registered in `flutter_window.cpp`.
- `linux/runner/scrcpy_video_plugin.{h,cc}` — GTK glue (`FlPixelBufferTexture`),
  registered in `my_application.cc`.

The Dart layer (`lib/services/scrcpy_video_channel.dart`, `scrcpy_mirror.dart`,
`scrcpy_client.dart`) is platform-agnostic and already drives all three.

## Status

Compiles on Windows and Linux (build fixes landed in #42). Runtime behavior on
real devices is still being hardened — please report issues.

## Build prerequisites

### Linux (Ubuntu)
The decoder links a minimal, glibc-only FFmpeg that the build also **bundles**
into the app, so the `.deb` doesn't depend on the distro's libavcodec/libavutil
soname (which would pin it to one Ubuntu release and drag in the whole codec
tree). `scripts/build_linux_ffmpeg.sh` builds it into `.ffmpeg-dev/linux`, and
`pkg_check_modules(FFMPEG ...)` in `linux/runner/CMakeLists.txt` picks it up via
pkg-config; `linux/CMakeLists.txt` copies the `.so` into the bundle's `lib/`.
```bash
sudo apt install nasm patchelf          # nasm: x86 SIMD, patchelf: $ORIGIN rpath
bash scripts/build_linux_ffmpeg.sh      # or run scripts/setup.sh
flutter run -d linux
```
(If the staged build is absent, CMake falls back to the system FFmpeg —
`sudo apt install libavcodec-dev libavutil-dev` — but that path isn't used for
releases.)

### Windows
1. Install FFmpeg dev libraries (headers + import libs), e.g. with vcpkg:
   ```
   vcpkg install ffmpeg
   ```
   Then configure Flutter/CMake with the vcpkg toolchain so pkg-config finds
   FFmpeg, **or** pass `-DFFMPEG_INCLUDE_DIR=<dir> -DFFMPEG_LIB_DIR=<dir>`.
2. **Runtime DLLs:** `avcodec-62.dll`, `avutil-60.dll`, `swresample-6.dll`
   (avcodec's own load-time dependency) and `avformat-62.dll` ship in
   `platform-tools/windows/`. The install step in `windows/CMakeLists.txt`
   copies them next to the built exe automatically — they are load-time
   imports, so the app cannot start without them beside `eagly.exe`
   ("avcodec-62.dll was not found"). The bundled runtime is FFmpeg 8.x
   (avcodec 62 / avutil 60); build against matching import libs (CI pins
   FFmpeg 8.0.1 in release.yml). If the bundled FFmpeg major version ever
   changes, update the dev libraries in release.yml to match.

## Notes
- Software decode → CPU YUV420P→RGBA conversion (full-range BT.601). Fine for a
  live mirror at phone resolutions; revisit with hardware decode (VA-API / D3D11
  / swscale) if higher resolutions stutter.
- The decoder drops queued access units beyond a small backlog to stay at the
  live edge.
- For hardware-accelerated decode later, the worker thread + texture plumbing
  stay the same; only `ScrcpyVideoDecoder` internals change.
