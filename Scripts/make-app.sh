#!/bin/bash
# Build a self-contained local app without deleting existing output.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"
SCRATCH="${INKPOST_BUILD_PATH:-.build/compact}"
: "${INKPOST_SIGNING_IDENTITY:?Set INKPOST_SIGNING_IDENTITY to the configured formal code-signing identity}"
if [[ "$INKPOST_SIGNING_IDENTITY" == "-" ]]; then
  echo "Ad-hoc signing is not allowed" >&2
  exit 1
fi
swift build -c "$CONFIG" --scratch-path "$SCRATCH"
BIN_DIR="$(swift build -c "$CONFIG" --scratch-path "$SCRATCH" --show-bin-path)"
APP=".build/Inkpost-Compact.app"
# Do not overwrite the running executable/resources before the replacement has passed signing.
STAGING_ROOT="$(mktemp -d .build/inkpost-stage.XXXXXX)"
STAGED_APP="$STAGING_ROOT/Inkpost-Compact.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
swift Scripts/make-icon.swift .build/Inkpost.iconset
iconutil -c icns .build/Inkpost.iconset -o "$STAGED_APP/Contents/Resources/Inkpost.icns"
cp "$BIN_DIR/PublishFlow" "$STAGED_APP/Contents/MacOS/PublishFlow"
cp -R "$BIN_DIR/PublishFlow_PublishKit.bundle" "$STAGED_APP/Contents/Resources/"
cat > "$STAGED_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Inkpost</string>
<key>CFBundleDisplayName</key><string>墨驿 Inkpost</string>
<key>CFBundleIdentifier</key><string>com.publishflow.app</string>
<key>CFBundleIconFile</key><string>Inkpost.icns</string>
<key>CFBundleExecutable</key><string>PublishFlow</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.15.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign "$INKPOST_SIGNING_IDENTITY" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
# Quit all identified app copies gracefully, then the lock owner (including direct binaries).
# Do not continue after a refusal/timeout or kill unrelated executables by name.
swift Scripts/stop-app.swift
"$STAGED_APP/Contents/MacOS/PublishFlow" --stop-running-instance
if [[ -e "$APP" ]]; then
  PREVIOUS_ROOT="$(mktemp -d .build/inkpost-previous.XXXXXX)"
  mv "$APP" "$PREVIOUS_ROOT/Inkpost-Compact.app"
  echo "Previous app preserved at $PREVIOUS_ROOT/Inkpost-Compact.app"
fi
mv "$STAGED_APP" "$APP"
rmdir "$STAGING_ROOT"
APP_EXECUTABLE="$(cd "$APP/Contents/MacOS" && pwd)/PublishFlow"
open "$APP"
sleep 2
pgrep -f "^${APP_EXECUTABLE}$" >/dev/null || { echo "Inkpost failed to launch" >&2; exit 1; }
