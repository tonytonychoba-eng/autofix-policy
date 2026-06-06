#!/bin/bash
# 編譯並打包成 PhotoAutoImport.app（選單列 App）。
# 通知中心需要 App 以 .app bundle 形式執行，所以不能直接 swift run。
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="PhotoAutoImport"
BUNDLE_ID="com.local.photoautoimport"
BUILD_DIR=".build/release"
APP="$APP_NAME.app"

echo "==> 編譯 (release)…"
swift build -c release

echo "==> 打包 $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>照片自動匯入</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>LSMinimumSystemVersion</key>  <string>11.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>Personal use.</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc 簽章…"
codesign --force --deep --sign - "$APP"

echo ""
echo "完成！產出：$(pwd)/$APP"
echo "用 open \"$APP\" 啟動，圖示會出現在右上角選單列。"
