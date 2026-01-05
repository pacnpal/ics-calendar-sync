#!/bin/bash
set -e

# Build script for ICS Calendar Sync.app
# Creates a proper macOS app bundle using XcodeGen and xcodebuild

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="ICS Calendar Sync"
BUILD_DIR="$PROJECT_DIR/build"

cd "$PROJECT_DIR"

echo "Building ICS Calendar Sync..."
echo ""

# Check for xcodegen
if ! command -v xcodegen &> /dev/null; then
    echo "Error: xcodegen not found. Install with: brew install xcodegen"
    exit 1
fi

# Generate Xcode project from project.yml
echo "Generating Xcode project..."
xcodegen generate --quiet

# Build with xcodebuild
echo "Building with xcodebuild..."
xcodebuild \
    -project ICSCalendarSyncGUI.xcodeproj \
    -scheme "ICS Calendar Sync" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    build \
    -quiet

# Copy to project root
echo "Copying app bundle..."
rm -rf "$PROJECT_DIR/$APP_NAME.app"
cp -r "$BUILD_DIR/Build/Products/Release/$APP_NAME.app" "$PROJECT_DIR/"

echo ""
echo "Build complete!"
echo "App bundle: $PROJECT_DIR/$APP_NAME.app"
echo ""
echo "To install:"
echo "  cp -r \"$APP_NAME.app\" /Applications/"
echo ""
echo "To run:"
echo "  open \"$APP_NAME.app\""
