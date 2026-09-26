#!/usr/bin/env bash
# Builds "Cheet with Both Hands.app" into ./build.
#   scripts/build-app.sh            # release build for this Mac's architecture
#   UNIVERSAL=1 scripts/build-app.sh  # arm64 + x86_64
#   CONFIG=debug scripts/build-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
CONFIG="${CONFIG:-release}"
APP_NAME="Cheet with Both Hands"
EXECUTABLE="CheetWithBothHands"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "▸ Compiling ($CONFIG)…"
swift build -c "$CONFIG" "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}" --product "$EXECUTABLE"
BIN_DIR="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}" --show-bin-path)"

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# render_icon <name> <style> [inputs…]: renders build/<name>.icns when it's missing or older than
# the icon script or any of the inputs.
render_icon() {
  local name="$1" style="$2" icns="$BUILD_DIR/$1.icns"
  shift 2
  local stale=0
  for input in "$ROOT/scripts/make-icon.swift" ${@+"$@"}; do
    if [[ "$input" -nt "$icns" ]]; then stale=1; fi
  done
  if [[ ! -f "$icns" || $stale == 1 ]]; then
    echo "▸ Rendering $name…"
    local iconset="$BUILD_DIR/$name.iconset"
    rm -rf "$iconset"
    swift "$ROOT/scripts/make-icon.swift" "$iconset" "$style" ${@+"$@"} >/dev/null
    iconutil -c icns "$iconset" -o "$icns"
  fi
  cp "$icns" "$APP/Contents/Resources/$name.icns"
}
# Cheeter is the bundle icon; the classic icon is swapped in at runtime when chosen in Settings.
render_icon AppIcon cheeter "$ROOT/Resources/Cheeter/Cheeter.png"
render_icon ClassicAppIcon classic
cp "$ROOT"/Resources/Cheeter/*.png "$APP/Contents/Resources/"   # mascot art for the splash and picker

echo "▸ Signing (ad-hoc)…"
codesign --force --sign - --timestamp=none "$APP" >/dev/null

echo "✓ Built $APP"
