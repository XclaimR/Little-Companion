#!/bin/sh
# Builds "Little Companion.app" and a zip ready to attach to a GitHub Release.
#   scripts/package.sh [version]                 -> dist/Little Companion.app, dist/LittleCompanion-<version>.zip
# Optional, for a download that opens without Gatekeeper warnings (needs an Apple Developer account):
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)"   sign with your Developer ID instead of ad-hoc
#   NOTARY_PROFILE=<keychain profile>                         notarize and staple (xcrun notarytool store-credentials)
set -e
cd "$(dirname "$0")/.."
VERSION=${1:-$(git describe --tags --always 2>/dev/null || echo dev)}
APP="dist/Little Companion.app"

echo "building release…"
if swift build -c release --arch arm64 --arch x86_64 >/dev/null 2>&1; then
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/LittleCompanion"   # universal: Apple silicon and Intel
else
  swift build -c release >/dev/null
  BIN=".build/release/LittleCompanion"
  echo "note: built for this Mac's architecture only ($(uname -m)); a universal build needs Xcode."
fi

rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LittleCompanion"
cp Sources/LittleCompanion/Resources/*.png Sources/LittleCompanion/Resources/*.json "$APP/Contents/Resources/"

# App icon: Ollie sitting facing you, drawn crisp at every size.
ICONSET=$(mktemp -d)/AppIcon.iconset; mkdir -p "$ICONSET"
python3 tools/art/readme_media.py --icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Little Companion</string>
  <key>CFBundleDisplayName</key><string>Little Companion</string>
  <key>CFBundleIdentifier</key><string>io.github.xclaimr.littlecompanion</string>
  <key>CFBundleExecutable</key><string>LittleCompanion</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION#v}</string>
  <key>CFBundleVersion</key><string>${VERSION#v}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT licence</string>
</dict></plist>
PLIST

if [ -n "$SIGN_ID" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
  codesign --force --sign - "$APP"   # ad-hoc: runs fine, but a downloaded copy needs "Open Anyway" once
fi
codesign --verify --strict "$APP"

ZIP="dist/LittleCompanion-$VERSION.zip"
rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
if [ -n "$NOTARY_PROFILE" ]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
fi
echo "done: $APP"
echo "      $ZIP  (attach this to a GitHub Release)"
