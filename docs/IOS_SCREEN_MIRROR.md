# iPhone screen mirror

The Mirror pane shows an iPhone's screen and drives it with the mouse and keyboard, as it does
for Android with scrcpy. iOS has no scrcpy: the picture and the input come from two different
places, and what works depends on the host and the phone.

| | Picture | Input |
| --- | --- | --- |
| macOS | QuickTime's capture route: about 50 fps at the phone's full resolution | CoreDevice HID: live touch, keyboard, hardware buttons |
| Windows / Linux | CoreDevice screenshots, under two a second | CoreDevice HID |

Input needs **Developer Mode** and **Xcode 27's developer disk image** mounted on the phone
(opening Xcode with the phone connected mounts it; it stays mounted until the phone restarts).
Without them the mirror is view-only on macOS, and on Windows / Linux there is no picture either,
and the pane says so. The QuickTime route needs neither, only camera permission.

## Where the picture comes from

- **QuickTime's capture route** (`macos/Runner/IosScreenCapturePlugin.swift`). Once a process
  sets `kCMIOHardwarePropertyAllowScreenCaptureDevices`, macOS offers each USB iPhone as a muxed
  `AVCaptureDevice` (model `"iOS Device"`); QuickTime Player's *New Movie Recording* uses the same
  thing. Frames arrive as `CVPixelBuffer`s and go straight into a Flutter texture. Any iOS
  version, no Developer Mode — but macOS asks for **camera permission** (`NSCameraUsageDescription`).
  macOS asks on behalf of the app that started the process tree: Eagly when opened from Finder,
  but the terminal or IDE when it was started by `fvm flutter run`. One without a camera usage
  description is refused without a prompt, and the pane says which case it is (the plugin checks
  whether its parent is `launchd`). To try the mirror from a dev build, `open` the built app.
  The capture device's unique ID is a UUID, not the UDID, so the phone is matched **by its name**;
  two connected phones with the same name are refused as ambiguous.
  The device is muxed, picture and sound; only its video port is connected, so Eagly never asks
  the phone for audio. The camera permission cannot be avoided on this route: macOS gates every
  CoreMediaIO capture device behind it, and shows its camera indicator while one is open. The
  ways around it are speaking QuickTime's USB protocol directly (as `quicktime_video_hack` does,
  over raw USB, fighting macOS's own driver for the phone) or CoreDevice's display stream on
  iOS 27 (below). Until then the pane says, before a mirror starts, that macOS will ask for the
  camera and show its indicator, and that the iPhone may show its microphone indicator.
- **CoreDevice screenshots** (`start_ios_screenshot_stream` in `rust/src/api/ios_mirror.rs`):
  `com.apple.coredevice.screencaptureservice`, back to back. The fallback on Windows / Linux, and
  on macOS when the capture route fails (camera permission denied, say), with a note saying why.
- **CoreDevice's display stream** (`com.apple.coredevice.displayservice`, HEVC over RTP) is what
  Xcode 27's Device Hub shows. It needs **iOS 27** — on iOS 26.6 the phone refuses with "Remote
  control requires iOS 27.0 or later on this device." and reports `supportedFeatures: 0` — and
  Eagly's decoders are H.264-only, so it is **not shown yet**. On iOS 27 it is still opened, and
  its RTP thrown away, because input needs it (below).

## Input

Touch, keyboard and buttons go through the HID services in Xcode's developer disk image
(`dtuhidd`: `com.apple.coredevice.hid.universalhidservice` for the touchscreen,
`com.apple.coredevice.hid.indigo` for keys and buttons), reached over a lockdown
`CoreDeviceProxy` tunnel with the `idevice` crate's userspace TCP stack — no root, no TUN driver,
on every desktop OS. One worker per session owns the connections (`run_input`); the Dart send
calls are **synchronous** bridge calls that enqueue in order, because touch order matters and
async bridge calls have none.

- **Touch** is live: down / move / up reports as the mouse moves, in fractions of the panel's
  own *portrait* frame (0–65535 on the wire). A landscape picture is mapped back through the
  interface orientation SpringBoard reports (`toPanel`, `read_ios_interface_orientation`).
- **A session waits for the phone's virtual devices.** `dtuhidd` creates a touchscreen, a
  keyboard and buttons for every session that connects, and the event system opened the
  touchscreen about 150 ms later. Events sent before then were queued and dispatched in one burst
  ("dispatched 6 pending events"), or dropped ("No active service, dropping event"); the device
  test's first run, started right after the phone woke, had its drags land as taps. So
  `start_ios_input` returns only 300 ms after connecting, and a closing session waits 100 ms for
  its last events: a release sent just before the connection closed was dropped too. With both,
  every device opens with "dispatched 0 pending events" (`idevicesyslog -p dtuhidd` shows it).
- **A still finger wobbles a pixel.** Without it, a drag that stops and then lets go still flings,
  as if the finger had lifted mid-swipe: on an iPhone 16e every release after a pause flicked the
  home screen a page, whether the still reports repeated one position or moved by one unit (of
  65535). A ±1-pixel wobble every 16 ms, like a real finger's, settles it; so does a decelerating
  release. The worker does the wobble whenever a finger is down and no move arrived for 16 ms.
- **Keys** go over as HID usages, which Flutter's `PhysicalKeyboardKey.usbHidUsage` already is —
  modifiers too, as keys of their own — and the phone types through **its own hardware-keyboard
  layout**, unlike Android, where printable keys travel as text in the host's layout
  (`IosKeyboardTranslator`). On macOS ⌘ is ⌘, but only ⌘A/C/V/X/Z reach the phone; other ⌘ chords
  stay with Eagly. On Windows / Linux Ctrl becomes the phone's ⌘ and the Windows key its Control.
  ⌘V / Ctrl+V puts the desktop's text on the phone's pasteboard (`pasteboardservice`) and presses
  ⌘V there. There is no phone→desktop clipboard sync.
- **Buttons** are Consumer-page usages: Home is Menu (0x40), Lock is Power (0x30), volume is
  0xE9 / 0xEA. The App switcher button is a double Home press.
- **Rotate** is Device Hub's simulated rotation (`com.apple.coredevice.devicecontrol`). Apps that
  can turn follow it; the iPhone home screen does not.
- **On iOS 27 input needs an open display stream.** The phone drops synthetic HID events unless
  a `displayservice` media stream is running (the crate's notes), so where the phone can stream,
  `start_ios_input` starts one — audio then video, exactly as Device Hub does — and drains its RTP.
  The phone then shows its screen-sharing indicator. iOS 26.6 takes the events without one.

## Recording

iOS has no `screenrecord`, so on macOS the Mac records: the capture plugin hands each frame it
already has to an `AVAssetWriter` (`IosScreenRecorder`), H.264 at about 4 bits a pixel a second,
into a temporary mp4 that Dart moves to where the user saves it. Its size is the first frame's; a
frame rotated mid-recording is letterboxed into it. There is no time limit and no sound (only the
capture's video port is connected). Stopping the mirror finishes the recording, and the record
button stays live so it can still be saved. Unverified on hardware.

## Starting

`IosMirrorSession.start` probes what the phone offers, starts the picture, **waits for the first
frame**, and only then connects input. The order matters: starting the QuickTime route
re-enumerates the phone on USB, which drops every usbmux connection once — an input tunnel opened
before it would die, and the Logs pane's syslog stream sees an end-of-stream and restarts.

## What hardware showed

iPhone 16e (iPhone17,5), iOS 26.6, macOS 26, 2026-10-21:

- The CoreDevice tunnel comes up in about **75 ms**.
- A CoreDevice screenshot takes about **575 ms** and is a 1170×2532 PNG of about 6.8 MB:
  **about 1.7 frames a second**. `jpeg` is refused.
- The QuickTime route: the first frame **5.5 s** after starting; then **about 50 fps** at the full
  1170×2532, still or moving (frames every 16.7 ms, the 95th percentile gap 35–45 ms).
- **Touch to picture**: from the first move report to a changed frame arriving on the Mac,
  **71–125 ms, median 93 ms** (7 drags). Drawing it adds a frame or two. scrcpy quotes 35–70 ms.
- Taps, live drags, HID keyboard typing and the Home button all landed with no display stream
  open.
- `test/device/ios_mirror_device_test.dart` passed against Eagly's own code. The probe took
  100 ms, or 559 ms with the phone just woken. A screenshot took 0.9–1.5 s; three from the stream
  took 1.4–2.7 s. Two drags that stopped before letting go stayed on the page, and a flick went to
  the Today View and back.

## A Flutter engine crash to know about

Every captured frame redraws the window, and redrawing while the window's size is in flux
hits an unfixed Flutter engine bug on macOS: Impeller dereferences a null texture in
`Canvas::SetupRenderPass` ([flutter/flutter#192522](https://github.com/flutter/flutter/pull/192522)).
A mirror crashed Eagly that way seconds after starting. The plugin holds its redraws back while
the window is resizing, moving, going full screen, changing screen or Space, or coming to the
front (`WindowTransitionGuard`), which lowers the odds. docs/KNOWN_ISSUES.md has the
workarounds.

## Things the phone does while it is mirrored

- **"Are you connecting a pair of headphones?"** Starting the QuickTime route makes the Mac an
  audio device for the phone. The first time, iOS asks, in a modal alert that swallows every touch
  until it is answered on the phone. The pane shows a hint while the mirror starts.
- **A 9:41 status bar.** iOS draws the clean screen-recording status bar while its screen is
  captured, so the QuickTime picture shows 9:41 with full bars. CoreDevice screenshots show the
  real one, which is why the screenshot button prefers them.
- On iOS 27, the **screen-sharing indicator** and a "This device was viewed remotely from Mac"
  notice afterwards (strings in `dtremotedisplayd`). It also refuses to stream during a phone or
  VoIP call, while Siri is active, or while the microphone or camera is in use.

## Not done yet

- **CoreDevice video on iOS 27**: needs HEVC alongside H.264 in `ScrcpyVideoPlugin.swift`
  (VideoToolbox) and `native/scrcpy_video_decoder.cc` (FFmpeg's `hevc`, which the Linux build
  script leaves out). It would give Windows / Linux live video.
- **Unverified on hardware**: anything on iOS 27 (no phone was at hand), iOS 17.4–18, landscape
  touch mapping, rotation, the pasteboard, and a phone with two capture devices of one name.
- Mounting the developer disk image from Eagly (the crate can, with a TSS request to Apple), so a
  restarted phone does not need Xcode again.
- Recording on Windows / Linux (screenshots are too slow to record), scroll-wheel and trackpad
  scrolling, and phone→desktop clipboard sync.

## Tests

- `test/ios_keyboard_test.dart`, `test/ios_mirror_session_test.dart` and the iPhone group in
  `test/mirror_controller_test.dart` run against fakes.
- `test/device/ios_mirror_device_test.dart` drives a real phone through the Rust half: support,
  screenshots, the screenshot stream, a settled drag that must not fling, a flick there and back,
  and Home. It needs the phone unlocked on a home-screen page:

  ```bash
  cd rust && cargo build --release && cd ..
  EAGLY_TEST_IOS_UDID=<udid> fvm flutter test test/device/ios_mirror_device_test.dart
  ```
