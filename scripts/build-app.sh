#!/usr/bin/env bash
# Builds "Cheet with Both Hands.app" into ./build.
#   scripts/build-app.sh            # release build for this Mac's architecture
#   UNIVERSAL=1 scripts/build-app.sh  # arm64 + x86_64
#   CONFIG=debug scripts/build-app.sh
#   VERSION=1.2.0 BUILD_NUMBER=42 scripts/build-app.sh  # stamp the bundle version (CI release builds)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
CONFIG="${CONFIG:-release}"
APP_NAME="Cheet with Both Hands"
EXECUTABLE="CheetWithBothHands"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

# Universal builds compile each architecture separately and merge them with lipo, which (unlike
# `swift build --arch arm64 --arch x86_64`) doesn't need Xcode's xcbuild.
ARCHS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCHS=(arm64 x86_64)
fi

BINARY="$BUILD_DIR/$EXECUTABLE"
mkdir -p "$BUILD_DIR"
if [[ ${#ARCHS[@]} -eq 0 ]]; then
  echo "▸ Compiling ($CONFIG)…"
  swift build -c "$CONFIG" --product "$EXECUTABLE"
  cp "$(swift build -c "$CONFIG" --show-bin-path)/$EXECUTABLE" "$BINARY"
else
  SLICES=()
  for arch in "${ARCHS[@]}"; do
    echo "▸ Compiling ($CONFIG, $arch)…"
    swift build -c "$CONFIG" --arch "$arch" --product "$EXECUTABLE"
    SLICES+=("$(swift build -c "$CONFIG" --arch "$arch" --show-bin-path)/$EXECUTABLE")
  done
  lipo -create "${SLICES[@]}" -output "$BINARY"
fi

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv "$BINARY" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
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
    echo "▸ Rendering ${name}…" # braces: bash 3.2 in a UTF-8 locale reads "…" as part of the name
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
