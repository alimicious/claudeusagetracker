#!/bin/bash
# Builds UsageTracker.app into ./build.
#   --universal  build for both Apple Silicon and Intel Macs (used for releases)
#   --install    copy the app to /Applications and launch it
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(cat VERSION)
UNIVERSAL=false
INSTALL=false
for arg in "$@"; do
    case "$arg" in
        --universal) UNIVERSAL=true ;;
        --install) INSTALL=true ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

ARCH_FLAGS=""
if $UNIVERSAL; then ARCH_FLAGS="--arch arm64 --arch x86_64"; fi
swift build -c release $ARCH_FLAGS
BIN=$(swift build -c release $ARCH_FLAGS --show-bin-path)

APP=build/UsageTracker.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/UsageTracker" "$APP/Contents/MacOS/UsageTracker"
# Drop debug symbols: they record the build machine's absolute source paths (home folder included).
strip -S -x "$APP/Contents/MacOS/UsageTracker"

# The app draws its own icon from the mascot sprite; iconutil packs the sizes into an .icns.
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"
"$APP/Contents/MacOS/UsageTracker" --iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>UsageTracker</string>
    <key>CFBundleDisplayName</key><string>AI Usage Tracker</string>
    <key>CFBundleIdentifier</key><string>com.alimicious.usagetracker</string>
    <key>CFBundleExecutable</key><string>UsageTracker</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP ($VERSION, $(lipo -archs "$APP/Contents/MacOS/UsageTracker"))"

if $INSTALL; then
    pkill -x UsageTracker && sleep 1 || true  # give the old copy time to quit before relaunching
    rm -rf /Applications/UsageTracker.app
    cp -R "$APP" /Applications/
    open /Applications/UsageTracker.app
    echo "Installed to /Applications and launched"
fi
