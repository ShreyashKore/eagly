#!/bin/bash
# Downloads Android platform-tools (adb) for each target platform.
# Run this script once before building the app.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PLATFORM_TOOLS_DIR="$PROJECT_DIR/platform-tools"

MACOS_URL="https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
LINUX_URL="https://dl.google.com/android/repository/platform-tools-latest-linux.zip"
WINDOWS_URL="https://dl.google.com/android/repository/platform-tools-latest-windows.zip"

TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

download_and_extract() {
  local url="$1"
  local target_dir="$2"
  local platform="$3"
  local zip_file="$TMP_DIR/${platform}.zip"

  echo "Downloading platform-tools for $platform..."
  curl -L -o "$zip_file" "$url"

  echo "Extracting adb for $platform..."
  mkdir -p "$target_dir"

  if [ "$platform" = "windows" ]; then
    unzip -o -j "$zip_file" "platform-tools/adb.exe" "platform-tools/AdbWinApi.dll" "platform-tools/AdbWinUsbApi.dll" -d "$target_dir"
  else
    unzip -o -j "$zip_file" "platform-tools/adb" -d "$target_dir"
    chmod +x "$target_dir/adb"
  fi

  echo "Done: $platform"
}

# Parse arguments - default to all platforms
PLATFORMS="${@:-macos linux windows}"

for platform in $PLATFORMS; do
  case "$platform" in
    macos)
      download_and_extract "$MACOS_URL" "$PLATFORM_TOOLS_DIR/macos" "macos"
      ;;
    linux)
      download_and_extract "$LINUX_URL" "$PLATFORM_TOOLS_DIR/linux" "linux"
      ;;
    windows)
      download_and_extract "$WINDOWS_URL" "$PLATFORM_TOOLS_DIR/windows" "windows"
      ;;
    *)
      echo "Unknown platform: $platform (use: macos, linux, windows)"
      exit 1
      ;;
  esac
done

echo ""
echo "Platform tools downloaded successfully!"
echo "You can now build the app with bundled adb."
