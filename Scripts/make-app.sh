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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PublishFlow" "$APP/Contents/MacOS/PublishFlow"
cp -R "$BIN_DIR/PublishFlow_PublishKit.bundle" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Inkpost</string>
<key>CFBundleDisplayName</key><string>墨驿 Inkpost</string>
<key>CFBundleIdentifier</key><string>com.publishflow.app</string>
<key>CFBundleExecutable</key><string>PublishFlow</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.12.2</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign "$INKPOST_SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
APP_EXECUTABLE="$(cd "$APP/Contents/MacOS" && pwd)/PublishFlow"
while IFS= read -r pid; do
  [[ -n "$pid" ]] && kill "$pid"
done < <(pgrep -f "^${APP_EXECUTABLE}$" || true)
open "$APP"
sleep 2
pgrep -f "^${APP_EXECUTABLE}$" >/dev/null || { echo "Inkpost failed to launch" >&2; exit 1; }
