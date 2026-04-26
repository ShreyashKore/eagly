# logview

Desktop log viewer for Android logcat and iOS syslog streams.

## Requirements

- Flutter (the workspace currently uses `fvm flutter`)

End users do **not** need to install `adb` or `libimobiledevice` separately when the desktop app is built with bundled tools.

The desktop build can ship these executables directly inside the app:

- `adb`
- `idevice_id`
- `ideviceinfo`
- `idevicesyslog`

plus their runtime libraries (`.dylib`, `.so`, `.dll`) for the target platform.

## Preparing bundled tools

`scripts/download_platform_tools.sh` always downloads `adb` for the requested platforms.
It also downloads a default upstream `libimobiledevice` bundle for macOS, Linux, and Windows when no override is configured.

If you need to pin a different `libimobiledevice` bundle, provide a per-platform prebuilt archive or extracted directory before building:

```bash
LIBIMOBILEDEVICE_MACOS_ARCHIVE=/absolute/path/to/libimobiledevice-macos.zip \
LIBIMOBILEDEVICE_LINUX_ARCHIVE=/absolute/path/to/libimobiledevice-linux.tar.xz \
LIBIMOBILEDEVICE_WINDOWS_ARCHIVE=/absolute/path/to/libimobiledevice-windows.zip \
./scripts/download_platform_tools.sh macos linux windows
```

You can also point to extracted directories instead of archives:

```bash
LIBIMOBILEDEVICE_MACOS_DIR=/absolute/path/to/macos-bundle \
LIBIMOBILEDEVICE_LINUX_DIR=/absolute/path/to/linux-bundle \
LIBIMOBILEDEVICE_WINDOWS_DIR=/absolute/path/to/windows-bundle \
./scripts/download_platform_tools.sh macos linux windows
```

The build system now copies the entire `platform-tools/<platform>/` folder into the shipped desktop app, so users do not have to install external mobile-tool dependencies manually.

The default upstream bundle currently comes from the public `iMobileDevice-net` release package and stages its x64 runtime files. On macOS, the script also builds and bundles OpenSSL 1.1 runtime dylibs from the public OpenSSL 1.1.1w source release so the `idevice_*` tools do not depend on a host Homebrew installation.

Use the environment-variable overrides if you need a different build.

See `platform-tools/README.md` for the expected bundle layout.

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
