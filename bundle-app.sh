#!/bin/bash
# Script to create a distributable macOS app bundle and DMG installer for ClaudeOps

set -e

APP_NAME="Claude Ops"
BUNDLE_ID="com.claude-ops.app"
VERSION="1.0.0"
DMG_NAME="Claude-Ops-${VERSION}"
APP_DIR="$APP_NAME.app"
DMG_DIR="dmg-staging"

echo "========================================="
echo "  Claude Ops - macOS App Builder"
echo "========================================="
echo ""

# Step 1: Build release version
echo "Step 1/5: Building release version..."
swift build -c release 2>&1 | grep -E "Build complete|error:" || true
echo "  ✓ Build complete"
echo ""

# Step 2: Create app bundle
echo "Step 2/5: Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
cp ".build/release/ClaudeOps" "$APP_DIR/Contents/MacOS/"

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>ClaudeOps</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2024-2025. All rights reserved.</string>
</dict>
</plist>
EOF

echo "  ✓ App bundle created: $APP_DIR"
echo ""

# Step 3: Create DMG staging area
echo "Step 3/5: Preparing DMG contents..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

# Copy app to staging
cp -R "$APP_DIR" "$DMG_DIR/"

# Create Applications symlink
ln -s /Applications "$DMG_DIR/Applications"

# Create a README for the DMG
cat > "$DMG_DIR/README.txt" << 'EOF'
Claude Ops - Installation Instructions
======================================

1. Drag "Claude Ops.app" to the Applications folder
2. Open Applications and double-click "Claude Ops"
3. The app will appear in your menu bar (top right)
4. Click the icon and select "Start" to run the server

Requirements:
- macOS 14.0 or later
- GitHub CLI (gh) installed and authenticated
- Claude Code CLI installed

Configuration:
- Create a repo_map.json file in your working directory
- See README.md for full documentation

For support, visit: https://github.com/YOUR_USERNAME/claude-ops
EOF

echo "  ✓ DMG staging prepared"
echo ""

# Step 4: Create the DMG
echo "Step 4/5: Creating DMG installer..."
rm -f "${DMG_NAME}.dmg"

# Create DMG with better settings
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDBZ \
    -fs HFS+ \
    "${DMG_NAME}.dmg" 2>&1 | grep -v "created:" || true

echo "  ✓ DMG created: ${DMG_NAME}.dmg"
echo ""

# Step 5: Cleanup
echo "Step 5/5: Cleaning up..."
rm -rf "$DMG_DIR"
echo "  ✓ Cleanup complete"
echo ""

# Summary
echo "========================================="
echo "  Build Complete!"
echo "========================================="
echo ""
echo "  App Bundle: $APP_DIR"
echo "  DMG Installer: ${DMG_NAME}.dmg"
echo "  Size: $(du -h "${DMG_NAME}.dmg" | cut -f1)"
echo ""
echo "Distribution:"
echo "  Share the DMG file with others. They can:"
echo "  1. Double-click the DMG to mount it"
echo "  2. Drag 'Claude Ops' to Applications"
echo "  3. Eject the DMG"
echo "  4. Run from Applications"
echo ""
echo "Local Install:"
echo "  cp -R \"$APP_DIR\" /Applications/"
echo ""
echo "Run Now:"
echo "  open \"$APP_DIR\""
echo ""
