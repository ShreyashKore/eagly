#!/bin/bash
# Downloads Android platform-tools, scrcpy, and stages bundled libimobiledevice tools.
# Run this script before building desktop releases.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PLATFORM_TOOLS_DIR="$PROJECT_DIR/platform-tools"

MACOS_URL="https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
LINUX_URL="https://dl.google.com/android/repository/platform-tools-latest-linux.zip"
WINDOWS_URL="https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
LIBIMOBILEDEVICE_PACKAGE_URL="https://github.com/libimobiledevice-win32/imobiledevice-net/releases/download/v1.3.17/iMobileDevice-net.1.3.17.nupkg"
FFMPEG_VERSION="${FFMPEG_VERSION:-8.0.1}"
FFMPEG_WINDOWS_URL="https://github.com/GyanD/codexffmpeg/releases/download/${FFMPEG_VERSION}/ffmpeg-${FFMPEG_VERSION}-full_build-shared.zip"
SCRCPY_VERSION="${SCRCPY_VERSION:-4.0}"
SCRCPY_MACOS_ARCH="${SCRCPY_MACOS_ARCH:-$(uname -m | sed 's/arm64/aarch64/')}"
SCRCPY_LINUX_URL="https://github.com/Genymobile/scrcpy/releases/download/v${SCRCPY_VERSION}/scrcpy-linux-x86_64-v${SCRCPY_VERSION}.tar.gz"
SCRCPY_MACOS_URL="https://github.com/Genymobile/scrcpy/releases/download/v${SCRCPY_VERSION}/scrcpy-macos-${SCRCPY_MACOS_ARCH}-v${SCRCPY_VERSION}.tar.gz"
SCRCPY_WINDOWS_URL="https://github.com/Genymobile/scrcpy/releases/download/v${SCRCPY_VERSION}/scrcpy-win64-v${SCRCPY_VERSION}.zip"
# The bundled libimobiledevice (imobiledevice-net runtimes/ubuntu.16.04-x64) is
# linked against OpenSSL 1.0 (libssl.so.1.0.0 / libcrypto.so.1.0.0), a soname no
# modern distro ships. We stage the matching libs from Ubuntu 16.04's official
# libssl1.0.0 package (OpenSSL 1.0.2g — the exact ABI that runtime targets); they
# depend only on glibc, so they stay portable across distros. See
# stage_linux_openssl_runtime.
LINUX_OPENSSL_DEB_URL="http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.0.0_1.0.2g-1ubuntu4.20_amd64.deb"

# macOS libimobiledevice toolchain: sourced from public Homebrew bottles (both
# arm64 and x86_64/Intel tags) instead of the x86_64-only imobiledevice-net
# package, so the bundled idevice_* tools run natively on Apple Silicon instead
# of requiring Rosetta. See stage_macos_libimobiledevice_universal.
MACOS_LIBIMOBILEDEVICE_FORMULAE="libimobiledevice ideviceinstaller libplist libimobiledevice-glue libusbmuxd openssl libzip xz zstd"
MACOS_LIBIMOBILEDEVICE_TOOLS="idevice_id idevicesyslog ideviceinfo idevicecrashreport ideviceinstaller"

macos_homebrew_repo() {
  case "$1" in
    openssl) printf '%s' 'homebrew/core/openssl/3' ;;
    *) printf 'homebrew/core/%s' "$1" ;;
  esac
}

# GHCR blob URLs for each formula's arm64_sonoma (Apple Silicon) and sonoma
# (Intel) bottles. The sha256 embedded in each URL is itself the content
# digest (OCI blobs are content-addressed), so these pins are self-verifying.
macos_homebrew_bottle_url() {
  local formula="$1" arch="$2"
  case "$formula:$arch" in
    libimobiledevice:arm64) printf '%s' 'https://ghcr.io/v2/homebrew/core/libimobiledevice/blobs/sha256:ac0a39864d542e1b5d248efe7ee1bbb5dc58a2739dd248ec987dc7b794ef9fd9' ;;
    libimobiledevice:x86_64) printf '%s' 'https://ghcr.io/v2/homebrew/core/libimobiledevice/blobs/sha256:aa40670dbbdadabc7f035fe2ea17da68a1dab8937a4f1c0429c0a7fd58c108f5' ;;
    ideviceinstaller:arm64) printf '%s' 'https://ghcr.io/v2/homebrew/core/ideviceinstaller/blobs/sha256:b0b1ee1e1e2b51f9f26bdc5734850a520caf8d492dd6ba1f3ad89d230a379142' ;;
    ideviceinstaller:x86_64) printf '%s' 'https://ghcr.io/v2/homebrew/core/ideviceinstaller/blobs/sha256:b499a23005d13e350b43f4e72fe58c2ce52656d998c8dc5f8477a7ab28a4d05d' ;;
    libplist:arm64) printf '%s' 'https://ghcr.io/v2/homebrew/core/libplist/blobs/sha256:06036e6de87c0a8bfc917d72f2af3f63ea6eb557391035782ca8bddb5506c342' ;;
    libplist:x86_64) printf '%s' 'https://ghcr.io/v2/homebrew/core/libplist/blobs/sha256:1ee2a67e37b9aa465a9ce313101ab32cd3bc4959c6613c6cf844d01ce078adc3' ;;
    libimobiledevice-glue:arm64) printf '%s' 'https://ghcr.io/v2/homebrew/core/libimobiledevice-glue/blobs/sha256:8839511835adac2934787a8a575c3dd6e02186d60db24ddb9c9aeed8a8069883' ;;
    libimobiledevice-glue:x86_64) printf '%s' 'https://ghcr.io/v2/homebrew/core/libimobiledevice-glue/blobs/sha256:0b08285aeb078331e4240420422e5330d91aba640b21c0d1f06c470deb6b9eb6' ;;
    libusbmuxd:arm64) printf '%s' 'https://ghcr.io/v2/homebrew/core/libusbmuxd/blobs/sha256:b3dfe62a2e25c35da59e32db101d490974d93a1a6ed30755bb4380a7d947a63e' ;;
    libusbmuxd:x86_64) printf '%s' 'https://ghcr.io/v2/homebrew/core/libusbmuxd/blobs/sha256:f20787b876fc3b9c8412d92ac2adaeb3dc2526155d327b0118534bb06c208079' ;;
    openssl:arm64) printf '%s' 'https://ghcr.io/v2/homebrew/core/openssl/3/blobs/sha256:79774ba3c854f0a9f94d939c628414c9b3dd2ff5eeb1dc61743199c979dd3490' ;;
    openssl:x86_64) printf '%s' 'https://ghcr.io/v2/homebrew/core/openssl/3/blobs/sha256:f641a0a3028a7ba2ab247767a6961226ba8c1777dac6e986e6fc62ec09e4a62a' ;;
    libzip:arm64) printf '%s' 'https://ghcr.io/v2/homebrew/core/libzip/blobs/sha256:41df5da85bc172a781efd6f32c46708f7a88f9b1faa82577cec64992f5254f5b' ;;
    libzip:x86_64) printf '%s' 'https://ghcr.io/v2/homebrew/core/libzip/blobs/sha256:5b808617db89e546465d756a8d8e0ee7068806e7dc58ae06952eea528ebdce8f' ;;
    xz:arm64) printf '%s' 'https://ghcr.io/v2/homebrew/core/xz/blobs/sha256:0a6e40dbeea3358a1277f347ef9b892070096a79a81cda90edfedbfe721c4ba3' ;;
    xz:x86_64) printf '%s' 'https://ghcr.io/v2/homebrew/core/xz/blobs/sha256:fcd2df6962b5b94ef14232d02df71ee0b329482c2d8478942e07287f016ebe73' ;;
    zstd:arm64) printf '%s' 'https://ghcr.io/v2/homebrew/core/zstd/blobs/sha256:35b5150b27512a94ebaee7b4399aaa8adf42d247e6968319e4aeac3c05365281' ;;
    zstd:x86_64) printf '%s' 'https://ghcr.io/v2/homebrew/core/zstd/blobs/sha256:8b8656acd6f30bcbbb9a033ae840afea299c9f0852f71b7540492b0fe7a36742' ;;
    *) return 1 ;;
  esac
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

download_adb() {
  local url="$1"
  local target_dir="$2"
  local platform="$3"
  local zip_file="$TMP_DIR/${platform}-adb.zip"

  echo "Downloading adb for $platform..."
  curl -L --fail -o "$zip_file" "$url"

  mkdir -p "$target_dir"

  if [ "$platform" = "windows" ]; then
    unzip -o -j "$zip_file" \
      "platform-tools/adb.exe" \
      "platform-tools/AdbWinApi.dll" \
      "platform-tools/AdbWinUsbApi.dll" \
      -d "$target_dir"
  else
    unzip -o -j "$zip_file" "platform-tools/adb" -d "$target_dir"
    chmod +x "$target_dir/adb"
  fi
}

copy_directory_contents_flat() {
  local source_dir="$1"
  local target_dir="$2"

  find "$source_dir" \( -type f -o -type l \) | while IFS= read -r source_path; do
    if [ -L "$source_path" ] && [ -d "$source_path" ]; then
      continue
    fi

    cp -f "$source_path" "$target_dir/$(basename "$source_path")"
  done
}

copy_matching_contents_flat() {
  local source_dir="$1"
  local target_dir="$2"
  local path_pattern="$3"

  find "$source_dir" \( -type f -o -type l \) -path "$path_pattern" | while IFS= read -r source_path; do
    if [ -L "$source_path" ] && [ -d "$source_path" ]; then
      continue
    fi

    cp -f "$source_path" "$target_dir/$(basename "$source_path")"
  done
}

download_public_ghcr_blob() {
  local repository="$1"
  local blob_url="$2"
  local output_path="$3"
  local token

  token="$(
    (curl -fsSL "https://ghcr.io/token?scope=repository:$repository:pull&service=ghcr.io" || true) |
      sed -n 's/.*"token":"\([^"]*\)".*/\1/p'
  )"

  if [ -z "$token" ]; then
    echo "Failed to acquire a GitHub Container Registry token for $repository" >&2
    exit 1
  fi

  curl -L --fail \
    -H "Authorization: Bearer $token" \
    -H 'Accept: application/vnd.oci.image.layer.v1.tar+gzip' \
    -o "$output_path" \
    "$blob_url"
}

extract_archive_flat() {
  local archive_path="$1"
  local target_dir="$2"
  local source_subdir="${3:-}"
  local extracted_dir
  extracted_dir="$TMP_DIR/extracted-$(basename "$archive_path")"
  local copy_source_dir="$extracted_dir"

  rm -rf "$extracted_dir"
  mkdir -p "$extracted_dir"

  case "$archive_path" in
    *.zip|*.nupkg)
      unzip -o "$archive_path" -d "$extracted_dir" >/dev/null
      ;;
    *.tar.gz|*.tgz)
      tar -xzf "$archive_path" -C "$extracted_dir"
      ;;
    *.tar.xz|*.txz)
      tar -xJf "$archive_path" -C "$extracted_dir"
      ;;
    *.tar.bz2|*.tbz2)
      tar -xjf "$archive_path" -C "$extracted_dir"
      ;;
    *)
      echo "Unsupported archive format: $archive_path" >&2
      exit 1
      ;;
  esac

  if [ -n "$source_subdir" ]; then
    copy_source_dir="$extracted_dir/$source_subdir"
    if [ ! -d "$copy_source_dir" ]; then
      echo "Expected archive subdirectory not found: $source_subdir" >&2
      exit 1
    fi
  fi

  copy_directory_contents_flat "$copy_source_dir" "$target_dir"
}

default_bundle_url() {
  local platform="$1"
  case "$platform" in
    linux|windows) printf '%s' "$LIBIMOBILEDEVICE_PACKAGE_URL" ;;
    *) return 1 ;;
  esac
}

default_bundle_subdir() {
  local platform="$1"
  case "$platform" in
    linux) printf '%s' 'runtimes/ubuntu.16.04-x64/native' ;;
    windows) printf '%s' 'runtimes/win-x64/native' ;;
    *) return 1 ;;
  esac
}

bundle_contains_file() {
  local target_dir="$1"
  local file_name="$2"
  [ -f "$target_dir/$file_name" ]
}

# Downloads and extracts one Homebrew formula's bottle for one macOS arch,
# then flattens the specific idevice_* tools we ship (bin/) and every
# top-level lib/*.dylib (excluding nested dirs like openssl's ossl-modules/,
# which we don't need) into a per-arch staging dir.
stage_macos_libimobiledevice_arch() {
  local target_dir="$1"
  local arch="$2"
  local formula

  for formula in $MACOS_LIBIMOBILEDEVICE_FORMULAE; do
    local repo archive_path extracted_dir
    repo="$(macos_homebrew_repo "$formula")"
    archive_path="$TMP_DIR/macos-$arch-$formula.tar.gz"
    extracted_dir="$TMP_DIR/macos-$arch-$formula"

    echo "Downloading macOS ($arch) Homebrew bottle for $formula..."
    download_public_ghcr_blob "$repo" "$(macos_homebrew_bottle_url "$formula" "$arch")" "$archive_path"

    rm -rf "$extracted_dir"
    mkdir -p "$extracted_dir"
    tar -xzf "$archive_path" -C "$extracted_dir"

    local tool
    for tool in $MACOS_LIBIMOBILEDEVICE_TOOLS; do
      copy_matching_contents_flat "$extracted_dir" "$target_dir" "*/bin/$tool"
    done

    find "$extracted_dir" \( -type f -o -type l \) -path '*/lib/*.dylib' -not -path '*/lib/*/*' |
      while IFS= read -r source_path; do
        cp -f "$source_path" "$target_dir/$(basename "$source_path")"
      done
  done
}

# Stages idevice_id/idevicesyslog/ideviceinfo/idevicecrashreport/ideviceinstaller
# plus their full dylib dependency closure for macOS as universal (arm64 +
# x86_64) binaries, built by lipo-combining matching Homebrew bottles for each
# arch. This replaces the x86_64-only imobiledevice-net package for macOS so
# Apple Silicon Macs don't need Rosetta to run the bundled iOS tools, while
# still supporting Intel Macs natively too.
stage_macos_libimobiledevice_universal() {
  local target_dir="$1"
  local arm64_dir="$TMP_DIR/macos-universal-arm64"
  local x86_64_dir="$TMP_DIR/macos-universal-x86_64"
  local issues_file="$TMP_DIR/macos-universal-issues.txt"

  if bundle_contains_file "$target_dir" 'idevice_id' && bundle_contains_file "$target_dir" 'libimobiledevice-1.0.dylib'; then
    return
  fi

  rm -rf "$arm64_dir" "$x86_64_dir"
  mkdir -p "$arm64_dir" "$x86_64_dir"
  : > "$issues_file"

  echo "Staging libimobiledevice toolchain for macOS (arm64 + x86_64, from Homebrew bottles)..."
  stage_macos_libimobiledevice_arch "$arm64_dir" arm64
  stage_macos_libimobiledevice_arch "$x86_64_dir" x86_64

  find "$arm64_dir" -maxdepth 1 -type f | while IFS= read -r arm64_path; do
    local name
    name="$(basename "$arm64_path")"
    if [ ! -f "$x86_64_dir/$name" ]; then
      echo "$name: staged for arm64 but missing for x86_64" >> "$issues_file"
      continue
    fi
    lipo -create "$arm64_path" "$x86_64_dir/$name" -output "$target_dir/$name"
  done

  find "$x86_64_dir" -maxdepth 1 -type f | while IFS= read -r x86_64_path; do
    local name
    name="$(basename "$x86_64_path")"
    if [ ! -f "$arm64_dir/$name" ]; then
      echo "$name: staged for x86_64 but missing for arm64" >> "$issues_file"
    fi
  done

  if [ -s "$issues_file" ]; then
    echo "error: macOS libimobiledevice arch bundles diverged between arm64 and x86_64:" >&2
    cat "$issues_file" >&2
    exit 1
  fi
}

stage_linux_openssl_runtime() {
  local target_dir="$1"
  local deb_path="$TMP_DIR/libssl1.0.0.deb"
  local extract_dir="$TMP_DIR/libssl1.0.0"

  if bundle_contains_file "$target_dir" 'libssl.so.1.0.0' && bundle_contains_file "$target_dir" 'libcrypto.so.1.0.0'; then
    return
  fi

  echo "Staging OpenSSL 1.0 runtime for Linux libimobiledevice..."
  curl -L --fail -o "$deb_path" "$LINUX_OPENSSL_DEB_URL"

  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"

  # A .deb is an ar(1) archive whose payload is data.tar.{xz,gz,zst}. Prefer
  # dpkg-deb when present; otherwise fall back to ar + tar with auto-detection.
  if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb -x "$deb_path" "$extract_dir"
  else
    (
      cd "$extract_dir"
      ar x "$deb_path"
      local data_archive
      data_archive="$(find . -maxdepth 1 -name 'data.tar.*' | head -1)"
      if [ -z "$data_archive" ]; then
        echo "error: no data.tar.* payload found in $deb_path" >&2
        exit 1
      fi
      tar -xf "$data_archive"
    )
  fi

  local lib
  for lib in libssl.so.1.0.0 libcrypto.so.1.0.0; do
    local found
    found="$(find "$extract_dir" -name "$lib" -type f | head -1)"
    if [ -z "$found" ]; then
      echo "error: $lib not found in $LINUX_OPENSSL_DEB_URL" >&2
      exit 1
    fi
    cp -f "$found" "$target_dir/$lib"
  done
}

rewrite_macos_bundle_load_paths() {
  local target_dir="$1"

  if ! command -v otool >/dev/null 2>&1 || ! command -v install_name_tool >/dev/null 2>&1; then
    echo "warning: macOS linkage tools are unavailable; skipping Mach-O load path rewrite."
    return
  fi

  find "$target_dir" -maxdepth 1 -type f | while IFS= read -r target_path; do
    if ! file "$target_path" | grep -q 'Mach-O'; then
      continue
    fi

    local target_name
    target_name="$(basename "$target_path")"

    case "$target_name" in
      scrcpy|idevice*|inetcat|ios_webkit_debug_proxy|iproxy|irecovery|plistutil|usbmuxd|lib*.dylib)
        ;;
      *)
        continue
        ;;
    esac

    chmod u+w "$target_path" || true

    if [[ "$target_name" == *.dylib ]]; then
      install_name_tool -id "@loader_path/$target_name" "$target_path"
    fi

    otool -L "$target_path" | tail -n +2 | awk '{print $1}' | while IFS= read -r dependency_path; do
      if [ -z "$dependency_path" ]; then
        continue
      fi

      local dependency_name
      dependency_name="$(basename "$dependency_path")"

      case "$dependency_path" in
        /usr/lib/*|/System/*|@loader_path/*)
          continue
          ;;
      esac

      if bundle_contains_file "$target_dir" "$dependency_name"; then
        install_name_tool -change "$dependency_path" "@loader_path/$dependency_name" "$target_path"
      fi
    done
  done
}

verify_macos_bundle_linkage() {
  local target_dir="$1"
  local issues_file="$TMP_DIR/macos-linkage-issues.txt"

  : > "$issues_file"

  find "$target_dir" -maxdepth 1 -type f | while IFS= read -r target_path; do
    if ! file "$target_path" | grep -q 'Mach-O'; then
      continue
    fi

    local unresolved_paths
    unresolved_paths="$(
      otool -L "$target_path" | tail -n +2 | awk '{print $1}' |
        grep -E '^(/usr/local/opt/|/opt/homebrew/|@@HOMEBREW_PREFIX@@/opt/|@@HOMEBREW_CELLAR@@/)' || true
    )"

    if [ -n "$unresolved_paths" ]; then
      {
        echo "$(basename "$target_path")"
        printf '%s\n' "$unresolved_paths"
        echo
      } >> "$issues_file"
    fi
  done

  if [ -s "$issues_file" ]; then
    echo "error: macOS bundle still references host-only libraries after staging:" >&2
    cat "$issues_file" >&2
    exit 1
  fi
}

prepare_macos_bundle_runtime() {
  local target_dir="$1"

  rewrite_macos_bundle_load_paths "$target_dir"
  verify_macos_bundle_linkage "$target_dir"
}

stage_optional_bundle() {
  local source_spec="$1"
  local target_dir="$2"
  local platform="$3"
  local source_subdir="${4:-}"

  if [ -z "$source_spec" ]; then
    echo "No libimobiledevice override configured for $platform; downloading the default upstream bundle."
    source_spec="$(default_bundle_url "$platform")"
    source_subdir="$(default_bundle_subdir "$platform")"
  fi

  echo "Staging libimobiledevice bundle for $platform..."

  if [ -d "$source_spec" ]; then
    copy_directory_contents_flat "$source_spec" "$target_dir"
    return
  fi

  local archive_path="$source_spec"
  if [[ "$source_spec" =~ ^https?:// ]]; then
    archive_path="$TMP_DIR/${platform}-libimobiledevice$(basename "$source_spec")"
    curl -L --fail -o "$archive_path" "$source_spec"
  fi

  if [ ! -f "$archive_path" ]; then
    echo "libimobiledevice bundle not found for $platform: $source_spec" >&2
    exit 1
  fi

  extract_archive_flat "$archive_path" "$target_dir" "$source_subdir"
}

scrcpy_bundle_spec() {
  local platform="$1"
  case "$platform" in
    macos) printf '%s' "${SCRCPY_MACOS_ARCHIVE:-${SCRCPY_MACOS_DIR:-$SCRCPY_MACOS_URL}}" ;;
    linux) printf '%s' "${SCRCPY_LINUX_ARCHIVE:-${SCRCPY_LINUX_DIR:-$SCRCPY_LINUX_URL}}" ;;
    windows) printf '%s' "${SCRCPY_WINDOWS_ARCHIVE:-${SCRCPY_WINDOWS_DIR:-$SCRCPY_WINDOWS_URL}}" ;;
  esac
}

stage_scrcpy_bundle() {
  local source_spec="$1"
  local target_dir="$2"
  local platform="$3"

  echo "Staging scrcpy bundle for $platform..."

  if [ -d "$source_spec" ]; then
    copy_directory_contents_flat "$source_spec" "$target_dir"
    return
  fi

  local archive_path="$source_spec"
  if [[ "$source_spec" =~ ^https?:// ]]; then
    archive_path="$TMP_DIR/${platform}-scrcpy-$(basename "$source_spec")"
    curl -L --fail -o "$archive_path" "$source_spec"
  fi

  if [ ! -f "$archive_path" ]; then
    echo "scrcpy bundle not found for $platform: $source_spec" >&2
    exit 1
  fi

  extract_archive_flat "$archive_path" "$target_dir"
}

mark_binaries_executable() {
  local target_dir="$1"
  if [ "$(uname -s)" = "Darwin" ] || [ "$(uname -s)" = "Linux" ]; then
    # 'idevice*' (not 'idevice_*') so every libimobiledevice tool gets +x, not
    # just idevice_id; the other CLIs (idevicesyslog, ideviceinfo, …) and the
    # standalone helpers below ship without an exec bit in the upstream bundle.
    find "$target_dir" -maxdepth 1 -type f \
      \( -name 'adb' -o -name 'scrcpy' -o -name 'idevice*' \
         -o -name 'inetcat' -o -name 'iproxy' -o -name 'irecovery' \
         -o -name 'ios_webkit_debug_proxy' -o -name 'plistutil' -o -name 'usbmuxd' \
         -o -name '*.dylib' -o -name '*.so' -o -name '*.so.*' \) \
      -exec chmod +x {} +
  fi
}

verify_expected_tools() {
  local target_dir="$1"
  local platform="$2"
  local missing=0

  local adb_name="adb"
  local idevice_id_name="idevice_id"
  local ideviceinfo_name="ideviceinfo"
  local ideviceinstaller_name="ideviceinstaller"
  local idevicesyslog_name="idevicesyslog"
  local scrcpy_name="scrcpy"

  if [ "$platform" = "windows" ]; then
    adb_name="adb.exe"
    idevice_id_name="idevice_id.exe"
    ideviceinfo_name="ideviceinfo.exe"
    ideviceinstaller_name="ideviceinstaller.exe"
    idevicesyslog_name="idevicesyslog.exe"
    scrcpy_name="scrcpy.exe"
  fi

  for tool_name in "$adb_name" "$idevice_id_name" "$ideviceinfo_name" "$ideviceinstaller_name" "$idevicesyslog_name" "$scrcpy_name"; do
    if [ ! -f "$target_dir/$tool_name" ]; then
      echo "warning: Expected bundled tool missing for $platform: $tool_name"
      missing=1
    fi
  done

  if [ "$missing" -eq 1 ]; then
    echo "warning: $platform bundle is incomplete. See platform-tools/README.md for the expected layout."
  fi
}

platform_bundle_spec() {
  local platform="$1"
  case "$platform" in
    macos) printf '%s' "${LIBIMOBILEDEVICE_MACOS_ARCHIVE:-${LIBIMOBILEDEVICE_MACOS_DIR:-}}" ;;
    linux) printf '%s' "${LIBIMOBILEDEVICE_LINUX_ARCHIVE:-${LIBIMOBILEDEVICE_LINUX_DIR:-}}" ;;
    windows) printf '%s' "${LIBIMOBILEDEVICE_WINDOWS_ARCHIVE:-${LIBIMOBILEDEVICE_WINDOWS_DIR:-}}" ;;
  esac
}

current_host_platform() {
  case "$(uname -s)" in
    Darwin) printf '%s' 'macos' ;;
    Linux) printf '%s' 'linux' ;;
    MINGW*|MSYS*|CYGWIN*) printf '%s' 'windows' ;;
    *) printf '%s' 'unknown' ;;
  esac
}

is_macos_host() {
  [ "$(current_host_platform)" = "macos" ]
}

download_windows_ffmpeg_dev() {
  # Build-time headers + MSVC import libs, pinned to match the avcodec-62/avutil-60
  # runtime DLLs that ship with scrcpy (see windows/runner/CMakeLists.txt).
  local dest="$PROJECT_DIR/.ffmpeg-dev"

  if [ ! -d "$dest/include" ] || [ ! -d "$dest/lib" ]; then
    echo "Downloading Windows FFmpeg ${FFMPEG_VERSION} dev headers..."
    local zip="$TMP_DIR/ffmpeg-shared.zip"
    local extracted="$TMP_DIR/ffmpeg-shared"
    curl -L --fail -o "$zip" "$FFMPEG_WINDOWS_URL"
    mkdir -p "$extracted"
    unzip -o "$zip" -d "$extracted" >/dev/null
    local root
    root="$(find "$extracted" -mindepth 1 -maxdepth 1 -type d | head -1)"
    mkdir -p "$dest"
    cp -r "$root/include" "$dest/"
    cp -r "$root/lib" "$dest/"
    echo "FFmpeg dev headers ready at $dest"
  else
    echo "FFmpeg dev headers already present at $dest"
  fi

  # Resolve a Windows-style absolute path for CMake and .env consumers.
  local win_dest
  if command -v cygpath >/dev/null 2>&1; then
    win_dest="$(cygpath -w "$dest")"
  else
    # Fallback for MSYS2 /c/... style paths; leave unchanged on non-Windows.
    win_dest="$(echo "$dest" | sed 's|^/\([a-zA-Z]\)/|\1:/|; s|/|\\|g')"
  fi

  # Write .env so setup.sh can persist the vars as user environment variables.
  printf 'FFMPEG_INCLUDE_DIR=%s\\include\n' "$win_dest" > "$dest/.env"
  printf 'FFMPEG_LIB_DIR=%s\\lib\n' "$win_dest" >> "$dest/.env"

  # In GitHub Actions, forward to GITHUB_ENV for subsequent build steps.
  if [ -n "${GITHUB_ENV:-}" ]; then
    printf 'FFMPEG_INCLUDE_DIR=%s\\include\n' "$win_dest" >> "$GITHUB_ENV"
    printf 'FFMPEG_LIB_DIR=%s\\lib\n' "$win_dest" >> "$GITHUB_ENV"
  fi
}

prepare_platform_bundle() {
  local platform="$1"
  local target_dir="$PLATFORM_TOOLS_DIR/$platform"

  mkdir -p "$target_dir"

  case "$platform" in
    macos)
      download_adb "$MACOS_URL" "$target_dir" "$platform"
      ;;
    linux)
      download_adb "$LINUX_URL" "$target_dir" "$platform"
      ;;
    windows)
      download_adb "$WINDOWS_URL" "$target_dir" "$platform"
      ;;
    *)
      echo "Unknown platform: $platform (use: macos, linux, windows)" >&2
      exit 1
      ;;
  esac

  if [ "$platform" = "macos" ] && [ -z "$(platform_bundle_spec "$platform")" ]; then
    # No override configured: source the idevice_* toolchain from Homebrew
    # bottles as universal (arm64 + x86_64) binaries. This step needs lipo/
    # install_name_tool, so it only runs on an actual macOS host.
    if is_macos_host; then
      stage_macos_libimobiledevice_universal "$target_dir"
    else
      echo "Skipping macOS libimobiledevice staging on non-macOS host ($(current_host_platform)); this step requires lipo/install_name_tool from Xcode Command Line Tools. Provide LIBIMOBILEDEVICE_MACOS_ARCHIVE/_DIR to stage a pre-built bundle instead."
    fi
  else
    stage_optional_bundle "$(platform_bundle_spec "$platform")" "$target_dir" "$platform"
  fi
  stage_scrcpy_bundle "$(scrcpy_bundle_spec "$platform")" "$target_dir" "$platform"
  if [ "$platform" = "windows" ]; then
    # Build-time FFmpeg headers + import libs for the native scrcpy decoder.
    # Writes .ffmpeg-dev/.env (consumed by scripts/setup.sh) and forwards
    # FFMPEG_INCLUDE_DIR / FFMPEG_LIB_DIR to GITHUB_ENV when running in CI.
    download_windows_ffmpeg_dev
  fi
  if [ "$platform" = "linux" ]; then
    # Stage the OpenSSL 1.0 libs the bundled libimobiledevice links against, so
    # idevice_* tools load via their RUNPATH ($ORIGIN, alongside the tools in
    # data/) instead of failing on the absent libssl.so.1.0.0 soname.
    stage_linux_openssl_runtime "$target_dir"
    # Build a minimal, glibc-only FFmpeg (H.264 decode) for the native scrcpy
    # decoder, staged under .ffmpeg-dev/linux and bundled into the app's lib/
    # dir so the .deb stays portable across distros. Forwards FFMPEG_* to
    # GITHUB_ENV in CI.
    FFMPEG_VERSION="$FFMPEG_VERSION" bash "$SCRIPT_DIR/build_linux_ffmpeg.sh"
  fi
  if [ "$platform" = "macos" ] && is_macos_host; then
    prepare_macos_bundle_runtime "$target_dir"
  fi
  mark_binaries_executable "$target_dir"
  verify_expected_tools "$target_dir" "$platform"

  echo "Prepared bundled mobile tools for $platform in $target_dir"
}

PLATFORMS="${*:-macos linux windows}"

for platform in $PLATFORMS; do
  prepare_platform_bundle "$platform"
done

echo
echo "Bundled mobile tools prepared successfully."
echo "The app will ship adb, scrcpy, and any staged libimobiledevice binaries from platform-tools/<platform>/."
