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

## ⚠️ Status: written but not yet compiled

These were authored on macOS and have **not been built or run** on Windows or
Linux. Expect to fix compile issues on first build — please report them.

## Build prerequisites

### Linux (Ubuntu)
```bash
sudo apt install libavcodec-dev libavutil-dev
flutter run -d linux
```
`pkg_check_modules(FFMPEG ...)` in `linux/runner/CMakeLists.txt` finds them via
pkg-config (already used for GTK). Ubuntu ships libavcodec at runtime too.

### Windows
1. Install FFmpeg dev libraries (headers + import libs), e.g. with vcpkg:
   ```
   vcpkg install ffmpeg
   ```
   Then configure Flutter/CMake with the vcpkg toolchain so pkg-config finds
   FFmpeg, **or** pass `-DFFMPEG_INCLUDE_DIR=<dir> -DFFMPEG_LIB_DIR=<dir>`.
2. **Runtime DLLs:** `avcodec-62.dll`, `avutil-60.dll` (and `avformat-62.dll`)
   already ship in `platform-tools/windows/`, but the loader must find them next
   to `Runner.exe`. Either copy them beside the built exe, or add the bundled
   tools dir to the DLL search path at startup (`AddDllDirectory`). The bundled
   FFmpeg is 7.1 → build against matching headers (avcodec 62) to keep struct
   layouts compatible.

## Notes
- Software decode → CPU YUV420P→RGBA conversion (full-range BT.601). Fine for a
  live mirror at phone resolutions; revisit with hardware decode (VA-API / D3D11
  / swscale) if higher resolutions stutter.
- The decoder drops queued access units beyond a small backlog to stay at the
  live edge.
- For hardware-accelerated decode later, the worker thread + texture plumbing
  stay the same; only `ScrcpyVideoDecoder` internals change.
