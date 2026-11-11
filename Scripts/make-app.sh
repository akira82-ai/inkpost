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
APP="${INKPOST_APP_OUTPUT:-.build/Inkpost-Compact.app}"
VERSION="${INKPOST_APP_VERSION:-0.18.0}"
BUILD_VERSION="${INKPOST_BUILD_VERSION:-$VERSION}"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ && "$BUILD_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || { echo "Invalid app/build version" >&2; exit 1; }
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
<key>CFBundleShortVersionString</key><string>0.18.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$STAGED_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_VERSION" "$STAGED_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Merge Scripts/update-config.plist" "$STAGED_APP/Contents/Info.plist"
FRAMEWORK="$SCRATCH/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$FRAMEWORK" ]] || { echo "Sparkle framework is missing" >&2; exit 1; }
mkdir -p "$STAGED_APP/Contents/Frameworks"
ditto "$FRAMEWORK" "$STAGED_APP/Contents/Frameworks/Sparkle.framework"
cp Sources/PublishFlow/Sparkle-LICENSE.txt "$STAGED_APP/Contents/Resources/"
# Re-sign nested code inside-out using the configured identity; preserve helper entitlements.
FRAMEWORK_COPY="$STAGED_APP/Contents/Frameworks/Sparkle.framework"
while IFS= read -r -d '' nested; do
  codesign --force --sign "$INKPOST_SIGNING_IDENTITY" --preserve-metadata=entitlements "$nested"
done < <(find "$FRAMEWORK_COPY/Versions/B" -depth \( -name '*.xpc' -o -name '*.app' -o -name Autoupdate \) -print0)
codesign --force --sign "$INKPOST_SIGNING_IDENTITY" "$FRAMEWORK_COPY"
codesign --force --sign "$INKPOST_SIGNING_IDENTITY" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
# Pack-only mode never stops or replaces a running app (used for release preparation/tests).
if [[ "${INKPOST_PACK_ONLY:-0}" == "1" ]]; then
  [[ ! -e "$APP" ]] || { echo "Output already exists: $APP" >&2; exit 1; }
  mv "$STAGED_APP" "$APP"
  rmdir "$STAGING_ROOT"
  echo "Signed app prepared at $APP"
  exit 0
fi
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
