#!/bin/bash
# First-time developer setup for Eagly on macOS, Linux, and Windows.
#
# Validates the toolchain, installs platform build dependencies, downloads the
# bundled mobile tools (adb / scrcpy / libimobiledevice), and runs
# `flutter pub get` so you can build and run the desktop app.
#
# On Windows, run this from Git Bash (PowerShell can't execute .sh directly):
#   bash scripts/setup.sh
#
# Usage:
#   ./scripts/setup.sh              # set up for the current host platform
#   ./scripts/setup.sh --packaging  # also install release-packaging tooling
#   ./scripts/setup.sh --help
#
# Install yourself first (the script cannot — see docs/SETUP.md):
#   macOS    — Xcode + Command Line Tools, CocoaPods
#   Linux    — nothing extra; the apt build packages are installed for you
#   Windows  — Visual Studio 2022 (Desktop C++), Git for Windows, iTunes (runtime)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

WITH_PACKAGING=0

# ── logging ──────────────────────────────────────────────────────────────────
log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

for arg in "$@"; do
  case "$arg" in
    --packaging) WITH_PACKAGING=1 ;;
    -h|--help)   usage 0 ;;
    *)           warn "Unknown option: $arg"; usage 1 ;;
  esac
done

# ── host platform ────────────────────────────────────────────────────────────
case "$(uname -s)" in
  Darwin)               HOST=macos ;;
  Linux)                HOST=linux ;;
  MINGW*|MSYS*|CYGWIN*) HOST=windows ;;
  *) die "Unsupported host '$(uname -s)'." ;;
esac
log "Setting up Eagly for host platform: $HOST"

# ── required CLI tools ───────────────────────────────────────────────────────
for tool in curl unzip git; do
  have "$tool" || die "'$tool' is required but was not found on PATH."
done

# ── Flutter via fvm ──────────────────────────────────────────────────────────
FLUTTER_VERSION="$(sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PROJECT_DIR/.fvmrc")"
FLUTTER="flutter"
DART="dart"
if have fvm; then
  log "Installing the pinned Flutter $FLUTTER_VERSION via fvm..."
  (cd "$PROJECT_DIR" && fvm install)
  FLUTTER="fvm flutter"
  DART="fvm dart"
elif have flutter; then
  warn "fvm not found — falling back to the system 'flutter'."
  warn "This repo pins Flutter $FLUTTER_VERSION via .fvmrc; install fvm for an exact match:"
  warn "  https://fvm.app/documentation/getting-started/installation"
else
  die "Neither 'fvm' nor 'flutter' is installed. Install fvm (recommended), then re-run:
  https://fvm.app/documentation/getting-started/installation"
fi

# ── platform build dependencies ──────────────────────────────────────────────
install_linux_build_deps() {
  # nasm + patchelf build the minimal, bundled FFmpeg for the native scrcpy
  # decoder (scripts/build_linux_ffmpeg.sh, run via download_platform_tools.sh).
  # That replaces the system libav*-dev: the decoder links the bundled FFmpeg so
  # the .deb doesn't pin the distro's libavcodec/libavutil soname.
  local pkgs=(clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
              libstdc++-12-dev nasm patchelf)
  if ! have apt-get; then
    warn "Non-apt distro detected. Install the equivalents of: ${pkgs[*]}"
    return
  fi
  log "Installing Linux build dependencies (sudo apt-get)..."
  sudo apt-get update
  sudo apt-get install -y "${pkgs[@]}"
}

check_macos_build_deps() {
  if ! xcode-select -p >/dev/null 2>&1; then
    warn "Xcode Command Line Tools not found. Install Xcode from the App Store and run:"
    warn "  xcode-select --install"
  fi
  if ! have pod; then
    warn "CocoaPods not found (needed by some Flutter plugins). Install it with:"
    warn "  sudo gem install cocoapods   # or: brew install cocoapods"
  fi
  # macOS uses VideoToolbox for the scrcpy decoder, so no FFmpeg dev libs are needed.
}

check_windows_build_deps() {
  local vswhere="/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
  if [ -f "$vswhere" ]; then
    local vs_path
    vs_path="$("$vswhere" -latest -products '*' \
      -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 \
      -property installationPath 2>/dev/null || true)"
    if [ -z "$vs_path" ]; then
      warn "Visual Studio with the 'Desktop development with C++' workload was not found."
      warn "Install it from https://visualstudio.microsoft.com/ before building."
    fi
  else
    warn "Could not detect Visual Studio (vswhere.exe missing). Ensure VS 2022 with C++ is installed."
  fi
}

case "$HOST" in
  linux)   install_linux_build_deps ;;
  macos)   check_macos_build_deps ;;
  windows) check_windows_build_deps ;;
esac

# ── bundled mobile tools (+ Windows FFmpeg dev libs) ─────────────────────────
log "Downloading bundled mobile tools (adb, scrcpy, libimobiledevice)..."
bash "$SCRIPT_DIR/download_platform_tools.sh" "$HOST"

# ── Windows: persist FFmpeg build variables ──────────────────────────────────
# download_windows_ffmpeg_dev wrote these into .ffmpeg-dev/.env; the build reads
# them as environment variables (see windows/runner/CMakeLists.txt).
persist_windows_ffmpeg_env() {
  local env_file="$PROJECT_DIR/.ffmpeg-dev/.env"
  if [ ! -f "$env_file" ]; then
    warn "Expected $env_file not found; FFmpeg build variables were not set."
    return
  fi
  if ! have setx; then
    warn "'setx' not found; could not persist FFmpeg variables. Set these manually:"
    cat "$env_file" >&2
    return
  fi
  log "Persisting FFmpeg build variables as user environment variables..."
  local name value
  while IFS='=' read -r name value; do
    [ -z "$name" ] && continue
    export "$name=$value"          # this session
    setx "$name" "$value" >/dev/null  # persisted for future terminals
    echo "  $name=$value"
  done < "$env_file"
}

if [ "$HOST" = "windows" ]; then
  persist_windows_ffmpeg_env
fi

# ── Dart/Flutter packages ────────────────────────────────────────────────────
log "Fetching Dart/Flutter packages..."
(cd "$PROJECT_DIR" && $FLUTTER pub get)

# ── optional: release-packaging tooling ──────────────────────────────────────
if [ "$WITH_PACKAGING" -eq 1 ]; then
  log "Installing release-packaging tooling (Fastforge)..."
  $DART pub global activate fastforge
  case "$HOST" in
    macos)
      if have npm; then npm install -g appdmg
      else warn "npm not found; install Node.js then 'npm install -g appdmg' for .dmg packaging."; fi
      ;;
    windows)
      if have choco; then choco install innosetup --no-progress -y
      else warn "Chocolatey not found; install Inno Setup 6 manually for .exe packaging: https://jrsoftware.org/isdl.php"; fi
      ;;
    linux)
      have dpkg-deb || warn "'dpkg-deb' not found; install 'dpkg' for .deb packaging."
      ;;
  esac
fi

# ── done ─────────────────────────────────────────────────────────────────────
log "Setup complete 🎉"
echo
if [ "$HOST" = "windows" ]; then
  echo "Open a NEW terminal (so the FFmpeg variables take effect), then run:"
fi
echo "Run the app with:"
echo "  $FLUTTER run -d $HOST"
echo
echo "Validate your checkout with:"
echo "  $FLUTTER analyze lib test"
echo "  $FLUTTER test"
