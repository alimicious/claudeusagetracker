#!/bin/bash
# Builds a universal UsageTracker.app, zips it, and publishes it as a GitHub release
# tagged with the version in ./VERSION. Bump VERSION and commit before running.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(cat VERSION)
TAG="v$VERSION"
ZIP="build/UsageTracker-$VERSION.zip"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Commit your changes before releasing." >&2
    exit 1
fi
if gh release view "$TAG" >/dev/null 2>&1; then
    echo "Release $TAG already exists; bump VERSION first." >&2
    exit 1
fi

./build.sh --universal
rm -f "$ZIP"
# Leave out macOS file metadata (extended attributes) so the zip carries nothing about this Mac.
ditto -c -k --norsrc --noextattr --keepParent build/UsageTracker.app "$ZIP"

git push
gh release create "$TAG" "$ZIP" --target "$(git rev-parse HEAD)" --title "UsageTracker $VERSION" --notes-file - <<NOTES
A tiny menu bar app that shows your Claude Code usage: today's cost, your 5-hour session, a project and model breakdown, and a little mascot that types while Claude works.

## Install

1. Download **UsageTracker-$VERSION.zip** below and double-click it to unzip.
2. Drag **UsageTracker** into your **Applications** folder and open it.
3. macOS will say it can't verify the app, because it isn't notarized by Apple. Click **Done**, then open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. You only need to do this once.

Then look for the mascot in your menu bar and click it.

Requires macOS 14 or later and Claude Code. Runs on Apple Silicon and Intel Macs. Everything stays on your Mac: the app only reads Claude Code's local logs and never connects to the internet.

*Unofficial fan project, not affiliated with or endorsed by Anthropic.*
NOTES
