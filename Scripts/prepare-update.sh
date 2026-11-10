#!/bin/bash
# Prepare signed update assets locally. This script never publishes or uploads them.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:?Usage: prepare-update.sh /path/to/Inkpost.app /new/output/directory /path/to/release-notes.txt}"
OUTPUT="${2:?Provide a new output directory}"
NOTES="${3:?Provide UTF-8 plain-text release notes}"
SCRATCH="${INKPOST_BUILD_PATH:-.build/compact}"
TOOLS="$SCRATCH/artifacts/sparkle/Sparkle/bin"
ACCOUNT="com.publishflow.app.sparkle"
[[ -d "$APP" && -f "$NOTES" && ! -e "$OUTPUT" ]] || { echo "App/notes missing or output already exists" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ && "$BUILD" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || { echo "Invalid version" >&2; exit 1; }
PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")
KEYCHAIN_PUBLIC_KEY=$("$TOOLS/generate_keys" --account "$ACCOUNT" -p)
[[ "$PUBLIC_KEY" == "$KEYCHAIN_PUBLIC_KEY" ]] || { echo "Update key does not match this app" >&2; exit 1; }
mkdir -p "$OUTPUT"
ARCHITECTURES="$(lipo -archs "$APP/Contents/MacOS/PublishFlow")"
case "$ARCHITECTURES" in
  arm64|x86_64) ARCH="$ARCHITECTURES" ;;
  'x86_64 arm64'|'arm64 x86_64') ARCH=universal ;;
  *) echo "Unsupported application architectures: $ARCHITECTURES" >&2; exit 1 ;;
esac
ARCHIVE="Inkpost-$VERSION-$ARCH.zip"
# Only the application belongs in the install archive. Preserve nested helper symlinks/modes.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT/$ARCHIVE"
cp "$NOTES" "$OUTPUT/Inkpost-$VERSION-$ARCH.txt"
"$TOOLS/generate_appcast" --account "$ACCOUNT" --maximum-deltas 0 --embed-release-notes \
  --download-url-prefix "https://github.com/akira82-ai/inkpost/releases/download/v$VERSION/" "$OUTPUT"
"$TOOLS/sign_update" --account "$ACCOUNT" --verify "$OUTPUT/appcast.xml"
(cd "$OUTPUT" && shasum -a 256 "$ARCHIVE" appcast.xml > SHA256SUMS.txt)
echo "Prepared signed update assets at $OUTPUT. Not uploaded. Publish appcast.xml with its matching v$VERSION Release."
