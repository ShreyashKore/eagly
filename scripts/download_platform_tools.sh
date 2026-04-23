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
  local extracted_dir="$TMP_DIR/extracted-$(basename "$archive_path")"

  rm -rf "$extracted_dir"
  mkdir -p "$extracted_dir"

  case "$archive_path" in
    *.zip)
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

  copy_directory_contents_flat "$extracted_dir" "$target_dir"
}

stage_optional_bundle() {
  local source_spec="$1"
  local target_dir="$2"
  local platform="$3"

  if [ -z "$source_spec" ]; then
    echo "No libimobiledevice bundle configured for $platform; keeping any existing bundled files."
    return
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

  extract_archive_flat "$archive_path" "$target_dir"
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
