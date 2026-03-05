#!/bin/bash
set -e

APP_NAME="ICUE XC7"
BUNDLE="$APP_NAME.app"

swift build -c release

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp .build/release/ICUE-MAC-App "$BUNDLE/Contents/MacOS/$APP_NAME"
cp Sources/ICUE-MAC-App/Resources/Info.plist "$BUNDLE/Contents/"

/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string '$APP_NAME'" "$BUNDLE/Contents/Info.plist" 2>/dev/null || true

echo "Built: $BUNDLE"
echo "Run: open '$BUNDLE'"
