# Bundled mobile tools

This directory is the source of truth for the desktop binaries that are copied into the final app bundle.

Each platform folder should contain these executables at minimum:

- `adb` / `adb.exe`
- `idevice_id` / `idevice_id.exe`
- `ideviceinfo` / `ideviceinfo.exe`
- `idevicesyslog` / `idevicesyslog.exe`

It should also contain any runtime libraries required by those tools, for example:

- macOS: `*.dylib`
- Linux: `*.so*`
- Windows: `*.dll`

## Expected layout

```text
platform-tools/
  macos/
    adb
    idevice_id
    ideviceinfo
    idevicesyslog
    *.dylib
  linux/
    adb
    idevice_id
    ideviceinfo
    idevicesyslog
    *.so*
  windows/
    adb.exe
    idevice_id.exe
    ideviceinfo.exe
    idevicesyslog.exe
    *.dll
```

## Preparing bundles

`scripts/download_platform_tools.sh` always downloads `adb` for the requested platforms.
It also downloads a default upstream `libimobiledevice` bundle for macOS, Linux, and Windows when no override is configured.

To stage a different `libimobiledevice` bundle as part of the app, provide either an archive path/URL or an extracted directory for each platform:

```bash
LIBIMOBILEDEVICE_MACOS_ARCHIVE=/absolute/path/to/libimobiledevice-macos.zip \
LIBIMOBILEDEVICE_LINUX_ARCHIVE=/absolute/path/to/libimobiledevice-linux.tar.xz \
LIBIMOBILEDEVICE_WINDOWS_ARCHIVE=/absolute/path/to/libimobiledevice-windows.zip \
./scripts/download_platform_tools.sh macos linux windows
```

Or use extracted directories:

```bash
LIBIMOBILEDEVICE_MACOS_DIR=/absolute/path/to/macos-bundle \
LIBIMOBILEDEVICE_LINUX_DIR=/absolute/path/to/linux-bundle \
LIBIMOBILEDEVICE_WINDOWS_DIR=/absolute/path/to/windows-bundle \
./scripts/download_platform_tools.sh macos linux windows
```

The script flattens the provided bundle into `platform-tools/<platform>/`, and the desktop build scripts copy everything in that folder into the shipped app.

The default upstream bundle currently comes from the public `iMobileDevice-net` release package and stages its x64 runtime files. On macOS, the script also builds and bundles OpenSSL 1.1 runtime dylibs from the public OpenSSL 1.1.1w source release so the `idevice_*` tools do not depend on a host Homebrew installation.

Use the overrides above if you need a different build.

