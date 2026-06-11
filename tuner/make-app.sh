#!/bin/sh
# Bundle the tuner into a double-clickable "Black Hole Tuner.app" in tuner/dist.
# (swift run works fine too — this is just for keeping it in the Dock.)
set -e
cd "$(dirname "$0")"

swift build -c release

APP="dist/Black Hole Tuner.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp .build/release/BlackHoleTuner "$APP/Contents/MacOS/"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>      <string>BlackHoleTuner</string>
    <key>CFBundleIdentifier</key>      <string>dev.s13k.blackhole-tuner</string>
    <key>CFBundleName</key>            <string>Black Hole Tuner</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
EOF

echo "built: $PWD/$APP"
