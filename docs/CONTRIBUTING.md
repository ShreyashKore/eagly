# Contributing to Eagly

Thank you for your interest in contributing!

## Requirements

- [Flutter](https://flutter.dev/docs/get-started/install) (this workspace uses `fvm flutter`)
- Dart SDK `^3.9.0`

## Preparing Bundled Platform Tools

End users do **not** need to install `adb` or `libimobiledevice` separately — the desktop build ships these executables directly inside the app:

- `adb`
- `idevice_id`
- `ideviceinfo`
- `idevicesyslog`

plus their runtime libraries (`.dylib`, `.so`, `.dll`) for each target platform.

### Downloading tools

```bash
./scripts/download_platform_tools.sh macos linux windows
```

`scripts/download_platform_tools.sh` always downloads `adb` for the requested platforms and downloads a default upstream `libimobiledevice` bundle (from the `iMobileDevice-net` release package) for macOS, Linux, and Windows.

On macOS the script also builds and bundles OpenSSL 1.1 runtime dylibs from the public OpenSSL 1.1.1w source so the `idevice_*` tools work without a Homebrew installation.

### Pinning a custom `libimobiledevice` build

Supply a per-platform archive **or** an extracted directory before running the script:

```bash
# Using archives
LIBIMOBILEDEVICE_MACOS_ARCHIVE=/path/to/libimobiledevice-macos.zip \
LIBIMOBILEDEVICE_LINUX_ARCHIVE=/path/to/libimobiledevice-linux.tar.xz \
LIBIMOBILEDEVICE_WINDOWS_ARCHIVE=/path/to/libimobiledevice-windows.zip \
./scripts/download_platform_tools.sh macos linux windows

# Using pre-extracted directories
LIBIMOBILEDEVICE_MACOS_DIR=/path/to/macos-bundle \
LIBIMOBILEDEVICE_LINUX_DIR=/path/to/linux-bundle \
LIBIMOBILEDEVICE_WINDOWS_DIR=/path/to/windows-bundle \
./scripts/download_platform_tools.sh macos linux windows
```

See `platform-tools/README.md` for the expected bundle layout.

### Copying tools for macOS builds

```bash
./scripts/copy_macos_bundled_tools.sh
```

## Validation

```bash
fvm flutter analyze
fvm flutter test -r compact
```

## Windows Packaging (MSIX)

Windows MSIX packaging is configured through `pubspec.yaml` using the `msix` package.

For the release signing process, certificate requirements, and the steps to avoid `Unknown publisher` install warnings, see [`doc/windows-msix.md`](windows-msix.md).

