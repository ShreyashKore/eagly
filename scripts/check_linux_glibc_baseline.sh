#!/bin/bash
# Fails if anything the Linux bundle ships needs a glibc / libstdc++ symbol newer
# than the baseline the .deb promises (see linux/packaging/deb/make_config.yaml).
#
# Why: the app and its bundled native libs (libsentry.so + crashpad_handler from
# sentry_flutter, the minimal FFmpeg, the Flutter engine) are compiled on the CI
# image, so they inherit *its* glibc. Building on ubuntu-24.04 produced a
# libsentry.so that referenced GLIBC_2.38 and made the .deb refuse to start on
# Ubuntu 22.04 ("version `GLIBC_2.38' not found"). The release workflow now
# builds inside an ubuntu:22.04 container; this script is the guard that keeps a
# future image or toolchain bump from silently raising the floor again.
#
# Usage:
#   scripts/check_linux_glibc_baseline.sh [bundle-dir | package.deb]
#
# 2.35 is also the lowest baseline available: the prebuilt scrcpy binary bundled
# from upstream already requires GLIBC_2.35 (adb needs only 2.16, and the
# libimobiledevice bundle is an Ubuntu 16.04 build).
#
# Defaults to build/linux/x64/release/bundle. Overridable baselines:
#   GLIBC_MAX_VERSION   (default 2.35   — Ubuntu 22.04)
#   GLIBCXX_MAX_VERSION (default 3.4.30 — libstdc++6 12.x, shipped by 22.04)
#   CXXABI_MAX_VERSION  (default 1.3.13)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

TARGET="${1:-$PROJECT_DIR/build/linux/x64/release/bundle}"
GLIBC_MAX_VERSION="${GLIBC_MAX_VERSION:-2.35}"
GLIBCXX_MAX_VERSION="${GLIBCXX_MAX_VERSION:-3.4.30}"
CXXABI_MAX_VERSION="${CXXABI_MAX_VERSION:-1.3.13}"

if ! command -v readelf >/dev/null 2>&1; then
  echo "ERROR: readelf not found (install binutils) — cannot verify the glibc baseline." >&2
  exit 2
fi

# A .deb is the real artifact, so allow checking one directly (CI passes the
# build bundle; a maintainer can point this at a downloaded release).
SCAN_DIR="$TARGET"
TMP_DIR=""
if [ -f "$TARGET" ] && [[ "$TARGET" == *.deb ]]; then
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  dpkg-deb -x "$TARGET" "$TMP_DIR"
  SCAN_DIR="$TMP_DIR"
fi

if [ ! -d "$SCAN_DIR" ]; then
  echo "ERROR: $SCAN_DIR not found — build the Linux bundle first." >&2
  exit 2
fi

# ── Version helpers ──────────────────────────────────────────────────────────

# True when $1 is strictly newer than $2 (dotted numeric versions).
version_gt() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$2" ]
}

# glibc tags a few ABI changes with a non-numeric version name; map the ones we
# know to the release that introduced them so they compare like any other.
numeric_version() {
  case "$1" in
    ABI_DT_RELR) echo "2.36" ;;
    *[!0-9.]*) echo "" ;;
    *) echo "$1" ;;
  esac
}

max_for_prefix() {
  case "$1" in
    GLIBC) echo "$GLIBC_MAX_VERSION" ;;
    GLIBCXX) echo "$GLIBCXX_MAX_VERSION" ;;
    CXXABI) echo "$CXXABI_MAX_VERSION" ;;
    *) echo "" ;;
  esac
}

# Compared as hex: reading the raw magic through a command substitution makes
# bash warn about the null bytes in every non-ELF file it meets.
is_elf() {
  [ "$(od -An -tx1 -N4 -- "$1" 2>/dev/null | tr -d '[:space:]')" = "7f454c46" ]
}

# Every versioned symbol reference in an ELF, as "PREFIX VERSION" pairs.
symbol_versions() {
  readelf -W --dyn-syms "$1" 2>/dev/null |
    grep -oE '@+(GLIBC|GLIBCXX|CXXABI)_[A-Za-z0-9._]+' |
    sed -E 's/^@+//; s/_/ /' |
    sort -u
}

# ── Scan ─────────────────────────────────────────────────────────────────────

violations=0
scanned=0
summary=""

while IFS= read -r file; do
  is_elf "$file" || continue
  scanned=$((scanned + 1))
  rel="${file#"$SCAN_DIR"/}"
  worst=""

  while read -r prefix version; do
    [ -n "${prefix:-}" ] || continue
    limit="$(max_for_prefix "$prefix")"
    [ -n "$limit" ] || continue
    numeric="$(numeric_version "$version")"
    if [ -z "$numeric" ]; then
      echo "WARNING: $rel references unknown ${prefix}_${version} — cannot compare." >&2
      continue
    fi
    if [ "$prefix" = "GLIBC" ] && { [ -z "$worst" ] || version_gt "$numeric" "$worst"; }; then
      worst="$numeric"
    fi
    if version_gt "$numeric" "$limit"; then
      violations=$((violations + 1))
      echo "FAIL: $rel needs ${prefix}_${version} (baseline ${prefix}_${limit})"
      readelf -W --dyn-syms "$file" 2>/dev/null |
        grep -oE "[^[:space:]]+@@?${prefix}_${version}" |
        sed -E "s/@@?${prefix}_${version}$//" |
        sort -u | sed 's/^/        needs /'
    fi
  done < <(symbol_versions "$file")

  if [ -n "$worst" ]; then
    summary+=$(printf '\n  %-52s GLIBC_%s' "$rel" "$worst")
  else
    summary+=$(printf '\n  %-52s %s' "$rel" "no versioned glibc references")
  fi
done < <(find "$SCAN_DIR" -type f | sort)

if [ "$scanned" -eq 0 ]; then
  echo "ERROR: no ELF binaries found under $SCAN_DIR." >&2
  exit 2
fi

echo "Scanned $scanned ELF file(s) in $SCAN_DIR:${summary}"
echo

if [ "$violations" -gt 0 ]; then
  cat >&2 <<EOF
ERROR: $violations symbol version(s) exceed the release baseline
       (glibc $GLIBC_MAX_VERSION / libstdc++ $GLIBCXX_MAX_VERSION).
       The .deb would fail to start on Ubuntu 22.04 with
       "version \`GLIBC_x.y' not found". Build the Linux release inside the
       ubuntu:22.04 container the release workflow uses, or — if the floor is
       being raised deliberately — bump both this baseline and the libc6
       dependency in linux/packaging/deb/make_config.yaml.
EOF
  exit 1
fi

echo "OK: nothing requires more than glibc $GLIBC_MAX_VERSION / libstdc++ $GLIBCXX_MAX_VERSION."
