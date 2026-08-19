#!/bin/sh
set -eu

TOOLS_SRC_DIR="${1:?source directory is required}"
TOOLS_DST_DIR="${2:?destination directory is required}"

# A build with no staged tools produces an app that cannot talk to any device:
# adb may still resolve off the developer's PATH (masking the problem on
# Android), but the idevice_* tools are not normally installed, so iOS support
# silently disappears. Fail the build rather than shipping that bundle.
if [ ! -d "$TOOLS_SRC_DIR" ]; then
  echo "error: Bundled mobile tools directory not found at $TOOLS_SRC_DIR. Run scripts/download_platform_tools.sh macos (or scripts/setup.sh) first." >&2
  exit 1
fi

if [ -z "$(find "$TOOLS_SRC_DIR" -maxdepth 1 -type f -print -quit 2>/dev/null)" ]; then
  echo "error: No bundled mobile tools were found in $TOOLS_SRC_DIR. Run scripts/download_platform_tools.sh macos (or scripts/setup.sh) first." >&2
  exit 1
fi

mkdir -p "$TOOLS_DST_DIR"

find "$TOOLS_SRC_DIR" -maxdepth 1 -type f | while IFS= read -r source_path; do
  file_name="$(basename "$source_path")"
  destination_path="$TOOLS_DST_DIR/$file_name"
  cp -f "$source_path" "$destination_path"
  chmod u+w "$destination_path" || true
  chmod +x "$destination_path" || true

  if command -v file >/dev/null 2>&1 && file "$destination_path" | grep -q 'Mach-O'; then
    codesign --force --sign - "$destination_path"
  fi

done

echo "Copied bundled mobile tools into $TOOLS_DST_DIR"

