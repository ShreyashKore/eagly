# iPhone screen mirror: not done yet

> **Status: not built.** What the iPhone mirror does today is in
> [docs/IOS_SCREEN_MIRROR.md](../docs/IOS_SCREEN_MIRROR.md).

- **CoreDevice video on iOS 27**: needs HEVC alongside H.264 in `ScrcpyVideoPlugin.swift`
  (VideoToolbox) and `native/scrcpy_video_decoder.cc` (FFmpeg's `hevc`, which the Linux build
  script leaves out). It would give Windows / Linux live video.
- Mounting the developer disk image from Eagly (the crate can, with a TSS request to Apple), so a
  restarted phone does not need Xcode again.
- Recording on Windows / Linux (screenshots are too slow to record), scroll-wheel and trackpad
  scrolling, and phone→desktop clipboard sync.
