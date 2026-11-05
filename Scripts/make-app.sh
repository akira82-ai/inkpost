#!/bin/bash
# 打包最小 .app（修复裸二进制下 Cmd+V/菜单失效问题）并启动
set -e
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
swift build -c "$CONFIG" 2>&1 | grep -E "error" && exit 1 || true

BIN=".build/$CONFIG-arm64/PublishFlow"
[ -f "$BIN" ] || BIN=".build/$CONFIG/PublishFlow"
APP=".build/Inkpost.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/PublishFlow"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Inkpost</string>
  <key>CFBundleDisplayName</key><string>Inkpost</string>
  <!-- 沿用旧 bundle id：保住已存的 DeepSeek 配置（UserDefaults 域），定名后再换 -->
  <key>CFBundleIdentifier</key><string>com.publishflow.app</string>
  <key>CFBundleExecutable</key><string>PublishFlow</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force -s - "$APP" >/dev/null 2>&1 || true
echo "✅ 已打包 $APP"
open "$APP"
echo "🚀 已启动"
