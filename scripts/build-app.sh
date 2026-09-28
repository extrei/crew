#!/bin/sh
set -eu

CREW_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$CREW_ROOT"
swift build -c release
CREW_BIN=$(swift build -c release --show-bin-path)
CREW_APP="$CREW_ROOT/dist/Crew.app"
mkdir -p "$CREW_APP/Contents/MacOS"
cp "$CREW_BIN/Crew" "$CREW_APP/Contents/MacOS/Crew"
cat > "$CREW_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>Crew</string>
    <key>CFBundleIdentifier</key><string>local.crew.agentbar</string>
    <key>CFBundleName</key><string>Crew</string>
    <key>CFBundleDisplayName</key><string>Crew</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$CREW_APP"
printf '%s\n' "$CREW_APP"
