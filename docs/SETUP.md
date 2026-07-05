# First-Time Setup

This guide gets a fresh checkout of **Eagly** building and running on macOS,
Windows, or Linux. It mirrors what the release CI (`.github/workflows/release.yml`)
does, so a local clone matches a release build.

A single cross-platform script, [`scripts/setup.sh`](../scripts/setup.sh),
handles all three platforms — it detects the host, installs build deps, downloads
the bundled tools, and runs `flutter pub get`. On Windows it additionally downloads
the FFmpeg dev libraries and persists `FFMPEG_INCLUDE_DIR` / `FFMPEG_LIB_DIR`.

> **Windows:** run it from **Git Bash** (`bash scripts/setup.sh`) — PowerShell
> can't execute `.sh` directly, and Git Bash is required anyway by the underlying
> [`download_platform_tools.sh`](../scripts/download_platform_tools.sh).

`setup.sh` calls [`scripts/download_platform_tools.sh`](../scripts/download_platform_tools.sh),
which downloads the bundled `adb`, `scrcpy`, and `libimobiledevice` binaries (and,
on Windows, the FFmpeg dev headers + import libs).

---

## Prerequisites you must install manually

The setup scripts validate these and warn if missing, but they **cannot** install
them for you.

### All platforms

- **[fvm](https://fvm.app/documentation/getting-started/installation)** (recommended)
  — pins Flutter to the version in [`.fvmrc`](../.fvmrc) (currently **3.41.7**).
  `fvm install` (run by the setup script) downloads that exact SDK.
  Without fvm the script falls back to a system `flutter`, which may not match.

### macOS

- **Xcode** + Command Line Tools (`xcode-select --install`)
- **CocoaPods** (`sudo gem install cocoapods` or `brew install cocoapods`)

### Windows

- **Visual Studio 2022** with the **"Desktop development with C++"** workload
- **[Git for Windows](https://git-scm.com/download/win)** — provides the Bash
  shell that `download_platform_tools.sh` runs under
- **[iTunes](https://www.apple.com/itunes/)** — only needed at runtime for iOS
  device support

### Linux

- Nothing extra — `setup.sh` installs the apt packages for you (`clang`, `cmake`,
  `ninja-build`, `pkg-config`, `libgtk-3-dev`, `liblzma-dev`, `libstdc++-12-dev`,
  `nasm`, `patchelf`, `libcurl4-openssl-dev`) and builds a minimal, bundled FFmpeg
  for the scrcpy decoder (`scripts/build_linux_ffmpeg.sh`). On non-apt distros,
  install the equivalents.

---

## Run it

### macOS / Linux

```bash
./scripts/setup.sh
# or, to also install release-packaging tooling (Fastforge, appdmg):
./scripts/setup.sh --packaging
```

### Windows (Git Bash)

```bash
bash scripts/setup.sh
# or, with release-packaging tooling (Fastforge, Inno Setup):
bash scripts/setup.sh --packaging
```

> On Windows, the build finds the FFmpeg dev libraries automatically from the
> staged `.ffmpeg-dev/` directory, so no terminal restart is needed. `setup.sh`
> also persists `FFMPEG_INCLUDE_DIR` / `FFMPEG_LIB_DIR` as user variables (picked
> up by a **new** terminal) for builds run from outside the repo.

---

## After setup

```bash
fvm flutter run -d macos      # also: windows / linux
fvm flutter analyze lib test
fvm flutter test
```

---

## What the script does (and doesn't)

- **Do**: install/validate Flutter (via fvm), install Linux build deps, download
  bundled mobile tools, download Windows FFmpeg dev libs and persist the build
  variables, run `flutter pub get`.
- **Don't**: install Xcode, Visual Studio, fvm, or iTunes — those are heavyweight
  and/or licensed installers you provide yourself.

### Release packaging (`--packaging`)

Only needed to produce installers (`.dmg` / `.exe` / `.msix` / `.deb`), not to run
the app. It installs [Fastforge](https://fastforge.dev/) and the per-platform
packager:

- **macOS**: `appdmg` (via npm)
- **Windows**: Inno Setup (via Chocolatey, if present)
- **Linux**: `dpkg-deb` (already present on Debian/Ubuntu)

See [docs/CONTRIBUTING.md](CONTRIBUTING.md) for more on the packaging flow.

---

## Customizing the bundled `libimobiledevice` / `scrcpy`

`download_platform_tools.sh` accepts overrides via environment variables
(archives or pre-extracted directories) — see
[docs/CONTRIBUTING.md](CONTRIBUTING.md#pinning-a-custom-libimobiledevice-build)
and [`platform-tools/README.md`](../platform-tools/README.md).
