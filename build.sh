#!/bin/bash
# Builds UsageTracker.app into ./build. Pass --install to copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/UsageTracker.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/UsageTracker "$APP/Contents/MacOS/UsageTracker"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>UsageTracker</string>
    <key>CFBundleDisplayName</key><string>AI Usage Tracker</string>
    <key>CFBundleIdentifier</key><string>com.alimicious.usagetracker</string>
    <key>CFBundleExecutable</key><string>UsageTracker</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x UsageTracker && sleep 1 || true  # give the old copy time to quit before relaunching
    rm -rf /Applications/UsageTracker.app
    cp -R "$APP" /Applications/
    open /Applications/UsageTracker.app
    echo "Installed to /Applications and launched"
fi
