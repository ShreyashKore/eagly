#!/usr/bin/env bash
# Builds the layout inspector's on-device helper (inspector_helper/) into
# assets/inspector/eagly-inspector.jar, a dex jar that Eagly pushes to an
# Android device and runs with app_process (docs/LAYOUT_INSPECTOR.md §2.3).
#
# The jar is committed, so building Eagly needs no Android SDK; run this only
# after changing the helper's source, and commit the result with it.
#
# Needs a JDK (17+) and an Android SDK with build-tools and a platform:
#   ANDROID_HOME     defaults to ~/Library/Android/sdk (macOS) or ~/Android/Sdk
#   ANDROID_PLATFORM defaults to the newest installed platform
#   JAVA_HOME        defaults to whatever `javac` is on PATH
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/inspector_helper/src"
out="$root/assets/inspector/eagly-inspector.jar"

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$sdk" ]]; then
  for candidate in "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    [[ -d "$candidate" ]] && sdk="$candidate" && break
  done
fi
[[ -d "$sdk" ]] || { echo "No Android SDK; set ANDROID_HOME." >&2; exit 1; }

platform="${ANDROID_PLATFORM:-$(ls "$sdk/platforms" | sort -V | tail -1)}"
android_jar="$sdk/platforms/$platform/android.jar"
build_tools="$(ls -d "$sdk"/build-tools/* | sort -V | tail -1)"
[[ -f "$android_jar" ]] || { echo "Missing $android_jar" >&2; exit 1; }

javac="${JAVA_HOME:+$JAVA_HOME/bin/}javac"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Java 8 bytecode, so the jar runs from API 21 up. No lambdas: android.jar has
# no LambdaMetafactory to compile them against.
"$javac" -source 8 -target 8 -Xlint:-options -encoding UTF-8 \
  -bootclasspath "$android_jar" -d "$work/classes" \
  $(find "$src" -name '*.java')

mkdir -p "$(dirname "$out")"
"$build_tools/d8" --release --min-api 21 --lib "$android_jar" \
  --output "$work/helper.jar" $(find "$work/classes" -name '*.class')
cp "$work/helper.jar" "$out"
echo "Built $out ($(wc -c < "$out" | tr -d ' ') bytes) against $platform"
