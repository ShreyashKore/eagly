# Contributing to Eagly

Thank you for your interest in contributing!

## Requirements

- [Flutter](https://flutter.dev/docs/get-started/install) (this workspace uses `fvm flutter`)
- Dart SDK `^3.9.0`

## Quick Setup

The fastest way to get a working checkout is the one-shot setup script, which validates
your toolchain, installs the platform build dependencies, downloads the bundled mobile
tools, and runs `flutter pub get`:

```bash
./scripts/setup.sh              # set up for the current host platform
./scripts/setup.sh --packaging  # also install release-packaging tooling (Fastforge, …)
```

On Windows, run it from **Git Bash** (`bash scripts/setup.sh`). See
[`docs/SETUP.md`](SETUP.md) for the full, platform-by-platform walkthrough and
prerequisites the script can't install for you.

The rest of this document describes the individual steps `setup.sh` automates, for when
you want to run them manually.

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

On Linux the script invokes [`scripts/build_linux_ffmpeg.sh`](../scripts/build_linux_ffmpeg.sh), which builds a minimal, glibc-only H.264 FFmpeg (libavcodec/libavutil) for the native scrcpy screen-mirror decoder and stages it under `.ffmpeg-dev/linux/`. Keeping FFmpeg out of the distro packages keeps the resulting `.deb` distro-independent. On Windows the equivalent FFmpeg dev headers/import libs are downloaded instead.

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

## Desktop Packaging

Release packaging is handled by [Fastforge](https://fastforge.dev/).

### One-time tooling

Install Fastforge:

```bash
dart pub global activate fastforge
```

Additional platform-specific tools:

- macOS DMG: `npm install -g appdmg`
- Windows EXE: install Inno Setup 6
- Linux DEB: `dpkg-deb` is available on standard Debian/Ubuntu environments

### Package builds

```bash
fastforge package --platform=macos --targets=dmg --artifact-name='eagly-{{build_name}}-{{platform}}{{#is_installer}}-setup{{/is_installer}}{{#ext}}.{{ext}}{{/ext}}'
fastforge package --platform=linux --targets=deb --artifact-name='eagly-{{build_name}}-{{platform}}{{#is_installer}}-setup{{/is_installer}}{{#ext}}.{{ext}}{{/ext}}'
fastforge package --platform=windows --targets=exe,msix --artifact-name='eagly-{{build_name}}-{{platform}}{{#is_installer}}-setup{{/is_installer}}{{#ext}}.{{ext}}{{/ext}}'
```

Artifacts are written under `dist/<pubspec-version>/`.

### Linux glibc baseline

Everything native in the Linux bundle is compiled during the build — the runner
binary, the minimal FFmpeg, and `libsentry.so` + `crashpad_handler`, which
`sentry_flutter` builds from source — so the package inherits the **build host's**
glibc. A release built on Ubuntu 24.04 shipped a `libsentry.so` that referenced
`GLIBC_2.38` and refused to start on Ubuntu 22.04:

```
/opt/eagly/eagly: /lib/x86_64-linux-gnu/libc.so.6: version `GLIBC_2.38' not found
(required by /opt/eagly/lib/libsentry.so)
```

The release therefore builds the Linux target inside an **`ubuntu:22.04`
container** (`.github/workflows/release.yml`), not on the runner image, which
fixes the floor at **glibc 2.35 / libstdc++6 12 (`GLIBCXX_3.4.30`)** regardless of
which runner images GitHub currently offers. `linux/packaging/deb/make_config.yaml`
declares the same floor (`libc6 (>= 2.35)`, `libstdc++6 (>= 12)`) so an install on
anything older fails in apt rather than at startup.

[`scripts/check_linux_glibc_baseline.sh`](../scripts/check_linux_glibc_baseline.sh)
enforces it: the release fails before uploading if any ELF in the package needs a
newer symbol. Point it at a build bundle or at any `.deb`:

```bash
scripts/check_linux_glibc_baseline.sh                       # build/linux/x64/release/bundle
scripts/check_linux_glibc_baseline.sh dist/1.2.2/eagly-1.2.2-linux.deb
GLIBC_MAX_VERSION=2.36 scripts/check_linux_glibc_baseline.sh   # after a deliberate bump
```

To reproduce a release-identical `.deb` locally (any distro, Docker required):

```bash
docker run --rm -v "$PWD:/src" -w /src ubuntu:22.04 bash -c '
  apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl git jq unzip xz-utils build-essential clang cmake ninja-build \
    pkg-config libgtk-3-dev liblzma-dev openjdk-17-jdk libcurl4-openssl-dev nasm \
    patchelf binutils
  git config --global --add safe.directory /src
  git clone -b "$(jq -r .flutter .fvmrc)" --depth 1 https://github.com/flutter/flutter.git /flutter
  export PATH="/flutter/bin:/root/.pub-cache/bin:$PATH" CI=true
  export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
  bash scripts/download_platform_tools.sh linux
  flutter pub get && dart pub global activate fastforge
  dart pub global run fastforge:main package --platform=linux --targets=deb
  scripts/check_linux_glibc_baseline.sh "$(find dist -name "*.deb" | head -1)"'
```

The JDK in that list is not optional: `sentry_flutter` depends on `package:jni`,
which registers a Linux FFI plugin whose `CMakeLists.txt` calls `find_package(JNI)`.
It needs both `libjvm.so` and `libjawt.so`, so `openjdk-17-jdk-headless` fails —
`libjawt.so` only ships in the full JRE. Installing the JDK is also not sufficient
on its own: CMake 3.22's `FindJNI` resolves the JDK through `JAVA_HOME` and does
not fall back to `javac` on `PATH`, so the recipe exports it. Ubuntu's runner images happen to include a
JDK, which is why this never surfaced before the build moved into a container.

Lowering the baseline further is not actually possible today: the prebuilt
`scrcpy` binary bundled from upstream already requires `GLIBC_2.35`, so Ubuntu
22.04 is the floor no matter what the app itself is compiled against. (`adb` and
the libimobiledevice bundle are far older — `GLIBC_2.16` and an Ubuntu 16.04
build.) Raising it means bumping the container tag, both version floors above,
and the defaults in the check script together.

For Windows MSIX metadata and signing notes, see [`docs/windows-msix.md`](windows-msix.md).

