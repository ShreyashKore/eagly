#!/bin/bash
# Downloads Android platform-tools and stages bundled libimobiledevice tools.
# Run this script before building desktop releases.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PLATFORM_TOOLS_DIR="$PROJECT_DIR/platform-tools"

MACOS_URL="https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
LINUX_URL="https://dl.google.com/android/repository/platform-tools-latest-linux.zip"
WINDOWS_URL="https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
LIBIMOBILEDEVICE_PACKAGE_URL="https://github.com/libimobiledevice-win32/imobiledevice-net/releases/download/v1.3.17/iMobileDevice-net.1.3.17.nupkg"
MACOS_OPENSSL_URL="https://github.com/openssl/openssl/releases/download/OpenSSL_1_1_1w/openssl-1.1.1w.tar.gz"

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

  find "$source_dir" -type f | while IFS= read -r source_path; do
    cp -f "$source_path" "$target_dir/$(basename "$source_path")"
  done
}

extract_archive_flat() {
  local archive_path="$1"
  local target_dir="$2"
  local source_subdir="${3:-}"
  local extracted_dir="$TMP_DIR/extracted-$(basename "$archive_path")"
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
    macos|linux|windows) printf '%s' "$LIBIMOBILEDEVICE_PACKAGE_URL" ;;
    *) return 1 ;;
  esac
}

default_bundle_subdir() {
  local platform="$1"
  case "$platform" in
    macos) printf '%s' 'runtimes/osx-x64/native' ;;
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

build_macos_openssl_runtime() {
  local target_dir="$1"
  local archive_path="$TMP_DIR/openssl-1.1.1w.tar.gz"
  local source_dir="$TMP_DIR/openssl-1.1.1w"

  if bundle_contains_file "$target_dir" 'libssl.1.1.dylib' && bundle_contains_file "$target_dir" 'libcrypto.1.1.dylib'; then
    return
  fi

  echo "Building OpenSSL 1.1 runtime for macOS..."
  curl -L --fail -o "$archive_path" "$MACOS_OPENSSL_URL"

  rm -rf "$source_dir"
  tar -xzf "$archive_path" -C "$TMP_DIR"

  (
    cd "$source_dir"
    env CFLAGS='-arch x86_64' CXXFLAGS='-arch x86_64' LDFLAGS='-arch x86_64' ./Configure darwin64-x86_64-cc shared no-tests >/dev/null
    make build_libs >/dev/null
  )

  cp -f "$source_dir/libssl.1.1.dylib" "$target_dir/libssl.1.1.dylib"
  cp -f "$source_dir/libcrypto.1.1.dylib" "$target_dir/libcrypto.1.1.dylib"
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
      idevice_*|inetcat|ios_webkit_debug_proxy|iproxy|irecovery|plistutil|usbmuxd|lib*.dylib)
        ;;
      *)
        continue
        ;;
    esac

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

prepare_macos_bundle_runtime() {
  local target_dir="$1"

  build_macos_openssl_runtime "$target_dir"
  rewrite_macos_bundle_load_paths "$target_dir"
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

mark_binaries_executable() {
  local target_dir="$1"
  if [ "$(uname -s)" = "Darwin" ] || [ "$(uname -s)" = "Linux" ]; then
    find "$target_dir" -maxdepth 1 -type f \
      \( -name 'adb' -o -name 'idevice_*' -o -name '*.dylib' -o -name '*.so' -o -name '*.so.*' \) \
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
  local idevicesyslog_name="idevicesyslog"

  if [ "$platform" = "windows" ]; then
    adb_name="adb.exe"
    idevice_id_name="idevice_id.exe"
    ideviceinfo_name="ideviceinfo.exe"
    idevicesyslog_name="idevicesyslog.exe"
  fi

  for tool_name in "$adb_name" "$idevice_id_name" "$ideviceinfo_name" "$idevicesyslog_name"; do
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

  stage_optional_bundle "$(platform_bundle_spec "$platform")" "$target_dir" "$platform"
  if [ "$platform" = "macos" ]; then
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
echo "The app will ship adb plus any staged libimobiledevice binaries from platform-tools/<platform>/."
