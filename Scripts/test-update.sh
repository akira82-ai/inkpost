#!/bin/bash
# Real Sparkle installer/relauncher tests, in unique disposable app identities.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${INKPOST_SIGNING_IDENTITY:?Set the configured formal signing identity}"
[[ "$INKPOST_SIGNING_IDENTITY" != '-' ]] || exit 1
SCRATCH="${INKPOST_BUILD_PATH:-.build/update-tests}"
swift build --scratch-path "$SCRATCH"
BIN="$(swift build --scratch-path "$SCRATCH" --show-bin-path)"
SPARKLE="$SCRATCH/artifacts/sparkle/Sparkle"
FRAMEWORK="$SPARKLE/Sparkle.xcframework/macos-arm64_x86_64"
TEST_ROOT="$(mktemp -d /tmp/inkpost-update-test.XXXXXX)"
PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Scripts/update-config.plist)
[[ "$("$SPARKLE/bin/generate_keys" --account com.publishflow.app.sparkle -p)" == "$PUBLIC_KEY" ]]
swiftc -parse-as-library -module-name UpdateHarness -I "$BIN/Modules" -F "$FRAMEWORK" \
  Sources/PublishFlow/Services/Updates/UpdateController.swift \
  Sources/PublishFlow/Services/ApplicationInstanceLock.swift Tests/UpdateIntegration/UpdateHarness.swift \
  "$BIN"/PublishKit.build/*.swift.o -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks -o "$TEST_ROOT/UpdateHarness"
SERVER_PID=''
trap 'if [[ -n "$SERVER_PID" ]]; then kill "$SERVER_PID" 2>/dev/null || true; fi' EXIT
for SCENARIO in valid archive-tampered feed-tampered; do
  CASE_ROOT="$TEST_ROOT/$SCENARIO"
  mkdir -p "$CASE_ROOT/feed" "$CASE_ROOT/installed" "$CASE_ROOT/new"
  # The server chooses a free local port and reports it before the app is built.
  python3 -u - "$CASE_ROOT" <<'PY' &
import http.server, pathlib, sys, functools
root = pathlib.Path(sys.argv[1])
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(root/'feed'))
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
(root/'port').write_text(str(server.server_port))
server.serve_forever()
PY
  SERVER_PID=$!
  for ((i=0; i<50; i++)); do [[ -f "$CASE_ROOT/port" ]] && break; sleep 0.1; done
  PORT="$(cat "$CASE_ROOT/port")"
  for VERSION in 1.0 2.0; do
    if [[ "$VERSION" == 1.0 ]]; then APP="$CASE_ROOT/installed/UpdateHarness.app"; else APP="$CASE_ROOT/new/UpdateHarness.app"; fi
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"
    cp "$TEST_ROOT/UpdateHarness" "$APP/Contents/MacOS/UpdateHarness"
    ditto "$FRAMEWORK/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
    python3 - "$APP" "$VERSION" "$CASE_ROOT" "$PORT" "$PUBLIC_KEY" <<'PY'
import plistlib, pathlib, sys
app, version, root, port, key = sys.argv[1:]
config = dict(CFBundleIdentifier='com.publishflow.updatetest.'+pathlib.Path(root).parent.name.split('.')[-1]+'.'+pathlib.Path(root).name,
 CFBundleName='UpdateHarness', CFBundleExecutable='UpdateHarness', CFBundlePackageType='APPL',
 CFBundleVersion=version, CFBundleShortVersionString=version, LSUIElement=True, LSMinimumSystemVersion='14.0',
 SUFeedURL=f'http://127.0.0.1:{port}/appcast.xml', SUPublicEDKey=key, SURequireSignedFeed=True,
 SUSignedFeedFailureExpirationInterval=0, SUVerifyUpdateBeforeExtraction=True, SUEnableAutomaticChecks=False,
 SUAllowsAutomaticUpdates=False, UpdateTestRoot=root, NSAppTransportSecurity=dict(NSAllowsLocalNetworking=True))
with open(pathlib.Path(app)/'Contents/Info.plist', 'wb') as f: plistlib.dump(config, f)
PY
    FW="$APP/Contents/Frameworks/Sparkle.framework"
    while IFS= read -r -d '' nested; do
      codesign --force --sign "$INKPOST_SIGNING_IDENTITY" --preserve-metadata=entitlements "$nested"
    done < <(find "$FW/Versions/B" -depth \( -name '*.app' -o -name '*.xpc' -o -name Autoupdate \) -print0)
    codesign --force --sign "$INKPOST_SIGNING_IDENTITY" "$FW"
    codesign --force --sign "$INKPOST_SIGNING_IDENTITY" "$APP"
    codesign --verify --deep --strict "$APP"
  done
  ditto -c -k --sequesterRsrc --keepParent "$CASE_ROOT/new/UpdateHarness.app" "$CASE_ROOT/feed/UpdateHarness-2.zip"
  "$SPARKLE/bin/generate_appcast" --account com.publishflow.app.sparkle --maximum-deltas 0 \
    --download-url-prefix "http://127.0.0.1:$PORT/" "$CASE_ROOT/feed"
  python3 - "$CASE_ROOT" "$SCENARIO" <<'PY'
import pathlib, sys
root, scenario = pathlib.Path(sys.argv[1]), sys.argv[2]
if scenario == 'archive-tampered':
 p=root/'feed/UpdateHarness-2.zip'; data=bytearray(p.read_bytes()); data[100]^=1; p.write_bytes(data)
elif scenario == 'feed-tampered':
 p=root/'feed/appcast.xml'; data=p.read_bytes(); p.write_bytes(data.replace(b'<title>2.0</title>', b'<title>9.0</title>'))
PY
  OLD_HASH="$(shasum -a 256 "$CASE_ROOT/installed/UpdateHarness.app/Contents/Info.plist")"
  open "$CASE_ROOT/installed/UpdateHarness.app"
  for ((i=0; i<120; i++)); do
    if [[ -f "$CASE_ROOT/events.txt" ]] && rg -q 'SUCCESS|PHASE failed|ERROR|DUPLICATE' "$CASE_ROOT/events.txt"; then break; fi
    sleep 0.5
  done
  cat "$CASE_ROOT/events.txt"
  if [[ "$SCENARIO" == valid ]]; then
    rg -q 'SUCCESS NEW VERSION SINGLE OWNER' "$CASE_ROOT/events.txt"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$CASE_ROOT/installed/UpdateHarness.app/Contents/Info.plist")" == 2.0 ]]
  else
    rg -q 'PHASE failed' "$CASE_ROOT/events.txt"
    ! rg -q 'START 2.0|DUPLICATE' "$CASE_ROOT/events.txt"
    [[ "$OLD_HASH" == "$(shasum -a 256 "$CASE_ROOT/installed/UpdateHarness.app/Contents/Info.plist")" ]]
  fi
  codesign --verify --deep --strict "$CASE_ROOT/installed/UpdateHarness.app"
  kill "$SERVER_PID"
  wait "$SERVER_PID" 2>/dev/null || true
  SERVER_PID=''
done
echo "PASS: real relaunch, single ownership, rejected tampered archive/feed. Evidence: $TEST_ROOT"
