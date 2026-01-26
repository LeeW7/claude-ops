#!/bin/bash
# Quick script to rebuild and launch Claude Ops locally (debug mode)

set -e

APP_NAME="Claude Ops"
APP_DIR="$APP_NAME.app"

echo "=== Claude Ops Dev Runner ==="
echo ""

# Kill existing instance if running
if pgrep -x "ClaudeOps" > /dev/null; then
    echo "Stopping existing instance..."
    pkill -x "ClaudeOps" || true
    sleep 1
fi

# Build debug version (faster than release)
echo "Building (debug)..."
swift build 2>&1 | grep -E "Build complete|error:|warning:" | head -20 || true

# Check if build succeeded
if [ ! -f ".build/debug/ClaudeOps" ]; then
    echo "ERROR: Build failed - executable not found"
    exit 1
fi
echo "Build complete!"
echo ""

# Create/update app bundle
echo "Updating app bundle..."
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp ".build/debug/ClaudeOps" "$APP_DIR/Contents/MacOS/"

# Create Info.plist if missing
if [ ! -f "$APP_DIR/Contents/Info.plist" ]; then
    cat > "$APP_DIR/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClaudeOps</string>
    <key>CFBundleIdentifier</key>
    <string>com.claude-ops.app</string>
    <key>CFBundleName</key>
    <string>Claude Ops</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF
fi

echo "Launching..."
open "$APP_DIR"

echo ""
echo "Claude Ops is running in the menu bar!"
