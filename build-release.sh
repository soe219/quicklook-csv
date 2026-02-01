#!/bin/bash
#
# build-release.sh - Build QLQuickCSV and create distribution DMG
#
# Usage: ./build-release.sh [version]
# Example: ./build-release.sh 1.1
#

set -e

# Configuration
APP_NAME="QLQuickCSV"
VERSION="${1:-1.0}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
DMG_DIR="${BUILD_DIR}/dmg"
RELEASE_DIR="${BUILD_DIR}/Build/Products/Release"

echo "========================================"
echo "Building ${APP_NAME} v${VERSION}"
echo "========================================"
echo ""

# Step 1: Clean and build
echo "[1/5] Building release..."
cd "$PROJECT_DIR"

# Regenerate Xcode project if xcodegen is available
if command -v xcodegen &> /dev/null; then
    echo "  - Regenerating Xcode project..."
    xcodegen generate --quiet
fi

xcodebuild -project QLQuickCSV.xcodeproj \
    -scheme QLQuickCSV \
    -configuration Release \
    -derivedDataPath build \
    clean build \
    2>&1 | grep -E "^(Build|Compile|Link|\*\*)" | head -20

if [ ! -d "${RELEASE_DIR}/${APP_NAME}.app" ]; then
    echo "ERROR: Build failed - app not found"
    exit 1
fi
echo "  ✓ Build succeeded"
echo ""

# Step 2: Prepare DMG contents
echo "[2/5] Preparing DMG contents..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

cp -R "${RELEASE_DIR}/${APP_NAME}.app" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

# Create README
cat > "$DMG_DIR/README.txt" << 'EOF'
QLQuickCSV - Quick Look Extension for CSV/TSV Files
====================================================

INSTALLATION:
1. Drag QLQuickCSV.app to the Applications folder
2. Open QLQuickCSV.app once to register the extension
3. Go to System Settings → Privacy & Security → Extensions → Quick Look
4. Enable "CSV QL Extension"

USAGE:
- Select any .csv or .tsv file in Finder
- Press Space to preview with interactive table

FEATURES:
- Interactive table with sorting & filtering
- Column type detection (text, number, date, boolean)
- Column statistics & distinct value counts
- Multiple views: Table, Markdown, JSON
- Search across all data (Cmd+F)
- Copy as CSV, Markdown, JSON, or SQL
- Dark/Light mode support

SETTINGS:
Open QLQuickCSV.app and go to the Settings tab to customize display options.

Note: This app is ad-hoc signed for local use. You may need to
right-click and select "Open" the first time to bypass Gatekeeper.
EOF

echo "  ✓ DMG contents prepared"
echo ""

# Step 3: Create DMG
echo "[3/5] Creating DMG..."
DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"
rm -f "$DMG_PATH"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_PATH" \
    -quiet

echo "  ✓ DMG created"
echo ""

# Step 4: Create ZIP (alternative)
echo "[4/5] Creating ZIP..."
ZIP_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.zip"
rm -f "$ZIP_PATH"

cd "$DMG_DIR"
zip -r -q "$ZIP_PATH" QLQuickCSV.app README.txt
cd "$PROJECT_DIR"

echo "  ✓ ZIP created"
echo ""

# Step 5: Copy to project root
echo "[5/5] Finalizing..."
cp "$DMG_PATH" "$PROJECT_DIR/"
cp "$ZIP_PATH" "$PROJECT_DIR/"

echo "  ✓ Files copied to project root"
echo ""

# Summary
echo "========================================"
echo "Build Complete!"
echo "========================================"
echo ""
echo "Distribution files:"
DMG_SIZE=$(ls -lh "${PROJECT_DIR}/${APP_NAME}-${VERSION}.dmg" | awk '{print $5}')
ZIP_SIZE=$(ls -lh "${PROJECT_DIR}/${APP_NAME}-${VERSION}.zip" | awk '{print $5}')
echo "  ${APP_NAME}-${VERSION}.dmg  (${DMG_SIZE})"
echo "  ${APP_NAME}-${VERSION}.zip  (${ZIP_SIZE})"
echo ""
echo "To install locally:"
echo "  rm -rf /Applications/QLQuickCSV.app"
echo "  cp -R build/Build/Products/Release/QLQuickCSV.app /Applications/"
echo "  qlmanage -r"
echo ""
