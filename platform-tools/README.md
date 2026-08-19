# Bundled mobile tools

This directory is the source of truth for the desktop binaries that are copied into the final app bundle.

Each platform folder should contain these executables at minimum:

- `adb` / `adb.exe`
- `idevice_id` / `idevice_id.exe`
- `ideviceinfo` / `ideviceinfo.exe`
- `ideviceinstaller` / `ideviceinstaller.exe`
- `idevicesyslog` / `idevicesyslog.exe`
- `scrcpy` / `scrcpy.exe`

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
    ideviceinstaller
    idevicesyslog
    scrcpy
    scrcpy-server
    *.dylib
  linux/
    adb
    idevice_id
    ideviceinfo
    ideviceinstaller
    idevicesyslog
    scrcpy
    scrcpy-server
    *.so*
  windows/
    adb.exe
    idevice_id.exe
    ideviceinfo.exe
    ideviceinstaller.exe
    idevicesyslog.exe
    scrcpy.exe
    scrcpy-server
    *.dll
```

## Preparing bundles

`scripts/download_platform_tools.sh` always downloads `adb` and `scrcpy` for the requested platforms.
It also downloads a default upstream `libimobiledevice` bundle for Linux and Windows when no override is configured. On macOS it builds a universal (arm64 + x86_64) bundle from Homebrew bottles instead — see below.

The default `scrcpy` bundle comes from the official Genymobile GitHub release. Set `SCRCPY_VERSION` to pin a different release, or provide a platform archive/directory override:

```bash
SCRCPY_VERSION=4.0 ./scripts/download_platform_tools.sh macos linux windows

SCRCPY_MACOS_ARCHIVE=/absolute/path/to/scrcpy-macos.tar.gz \
SCRCPY_LINUX_ARCHIVE=/absolute/path/to/scrcpy-linux.tar.gz \
SCRCPY_WINDOWS_ARCHIVE=/absolute/path/to/scrcpy-windows.zip \
./scripts/download_platform_tools.sh macos linux windows
```

On macOS, `SCRCPY_MACOS_ARCH` defaults to the current machine architecture (`aarch64` on Apple Silicon, `x86_64` on Intel). Override it when preparing a bundle for a different macOS architecture.

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

The default upstream bundle for Linux and Windows comes from the public `iMobileDevice-net` release package and stages its x64 runtime files.

On macOS, `idevice_id`/`idevicesyslog`/`ideviceinfo`/`idevicecrashreport`/`ideviceinstaller` and their full dylib dependency closure (`libimobiledevice`, `libplist`, `libimobiledevice-glue`, `libusbmuxd`, `openssl@3`, `libzip`, `xz`, `zstd`) are instead sourced from public Homebrew bottles, once per architecture (`arm64_sonoma` and `sonoma`), then combined with `lipo` into universal (arm64 + x86_64) binaries. This is what lets the bundled iOS tools run natively on Apple Silicon Macs without requiring Rosetta, while still supporting Intel Macs. This step needs `lipo`/`install_name_tool` (Xcode Command Line Tools) and only runs when preparing the macOS bundle on an actual Mac; a `LIBIMOBILEDEVICE_MACOS_ARCHIVE`/`LIBIMOBILEDEVICE_MACOS_DIR` override bypasses it in favor of a pre-built bundle you provide.

Either way, the bundled `idevice_*` tools are self-contained instead of depending on a host Homebrew installation.

### macOS: quirks and gotchas

- **Raw bottles aren't relocated.** A bottle extracted straight from GHCR still has literal placeholder strings baked into its Mach-O load commands (`@@HOMEBREW_CELLAR@@/...`, `@@HOMEBREW_PREFIX@@/opt/...`) — normally `brew install` patches these to real paths as a post-install step. Since the script bypasses `brew install` entirely, `rewrite_macos_bundle_load_paths` has to do this itself via `install_name_tool -change`, and `verify_macos_bundle_linkage` fails the build if anything is left unresolved.

- **`lipo` only glues code, not dependencies.** Combining an arm64 binary with an x86_64 binary only works cleanly if both slices expect the *same* dylibs at the *same* versions — a single filename can't point at two different library versions for its two slices. This is why both arches are pulled from the same Homebrew formula version, rather than lipo-ing a new arm64 build against the old x86_64 imobiledevice-net binaries (which linked OpenSSL 1.1, not 3).

- **Apple Silicon refuses to run unsigned code, full stop** — not just a Gatekeeper prompt like on Intel. Any binary whose signature was invalidated by `install_name_tool` (which is all of these, since every load path gets rewritten) gets SIGKILL'd (`exit 137`) on launch until it's re-signed, even ad-hoc (`codesign --force --sign -`). `scripts/copy_macos_bundled_tools.sh` already re-signs everything at app-copy time; running a tool straight out of `platform-tools/macos/` without going through that script will appear to silently fail.

- **Bottle tags are pinned to a specific macOS baseline, not "latest".** URLs target `arm64_sonoma`/`sonoma` (macOS 14) bottles specifically — that's a stable floor, not a moving target; the resulting binaries run fine on newer macOS. It also means there's no automatic update path: bumping a formula version means re-pulling the `arm64_sonoma`/`sonoma` blob URLs by hand (e.g. `curl https://formulae.brew.sh/api/formula/<name>.json`) and updating the sha256-pinned URLs in `macos_homebrew_bottle_url`.

- **Only top-level `lib/*.dylib` is swept up, not nested subdirectories.** This deliberately excludes things like OpenSSL's `lib/ossl-modules/*.dylib` provider plugins (`legacy.dylib`, `capi.dylib`, …) — none of the bundled tools need them for the TLS handshake libimobiledevice does. If a future dependency needs one of those, `stage_macos_libimobiledevice_arch`'s `find` pattern will need loosening.

- **The bundle only ships the 5 tools the app actually calls** (the minimum list above), not the ~15 other `idevice*` binaries (`idevicebackup`, `irecovery`, `usbmuxd`, …) the old imobiledevice-net-based bundle carried along for free as dead weight. Nothing in the codebase invokes them; if a new feature needs one, add its name to `MACOS_LIBIMOBILEDEVICE_TOOLS` in `download_platform_tools.sh`.

- **Arch-set divergence fails loudly, not silently.** If a Homebrew formula ever stops shipping a bottle for one of the two tags (Homebrew has been reducing Intel bottle coverage over time), `stage_macos_libimobiledevice_universal` errors out listing exactly which file is missing for which arch, instead of silently shipping an arm64-only or x86_64-only binary.

On Linux, the bundled `libimobiledevice` (the `ubuntu.16.04-x64` runtime) links against OpenSSL 1.0 (`libssl.so.1.0.0` / `libcrypto.so.1.0.0`), a soname no modern distro ships. The script stages those two libs from Ubuntu 16.04's official `libssl1.0.0` package (OpenSSL 1.0.2g) so the `idevice_*` tools resolve them via their `$ORIGIN` RUNPATH; the libs depend only on glibc, keeping the bundle portable across distros.

Use the overrides above if you need a different build.
