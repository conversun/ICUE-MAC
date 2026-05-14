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

# Copy each <locale>.lproj so Bundle.main resolves localized strings at runtime.
for lproj in Sources/ICUE-MAC-App/Resources/*.lproj; do
    [ -d "$lproj" ] && cp -R "$lproj" "$BUNDLE/Contents/Resources/"
done

/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string '$APP_NAME'" "$BUNDLE/Contents/Info.plist" 2>/dev/null || true

echo "Built: $BUNDLE"
echo "Run: open '$BUNDLE'"
