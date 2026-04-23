# logview

Desktop log viewer for Android logcat and iOS syslog streams.

## Requirements

- Flutter (the workspace currently uses `fvm flutter`)
- Android logs: `adb` available on `PATH` or bundled with the app
- iOS logs: `libimobiledevice` tools available on `PATH` or bundled with the app:
  - `idevice_id`
  - `ideviceinfo`
  - `idevicesyslog`

On macOS, you can install the iOS tooling with Homebrew:

```bash
brew install libimobiledevice
```

## Features

- Discover connected Android and iOS devices
- Stream Android logs with `adb logcat -v threadtime`
- Stream iOS logs with `idevicesyslog`
- Preserve multi-line iOS syslog entries in the log viewer
- Filter, search, import, and export logs from the desktop UI

## Validation

```bash
fvm flutter analyze
fvm flutter test -r compact
```
