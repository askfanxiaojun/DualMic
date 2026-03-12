#!/bin/bash
# DualMic release build script
# Uses the Apple Development certificate already configured in the Xcode project.
# Code signing is REQUIRED for macOS TCC (microphone / screen recording) to work.

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_PATH="$BUILD_DIR/Build/Products/Release/DualMic.app"

echo "▶ Building DualMic (Release)..."

xcodebuild \
    -project "$PROJECT_DIR/DualMic.xcodeproj" \
    -scheme DualMic \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    clean build

echo ""
echo "✅ Build complete: $APP_PATH"
echo ""

# Optional: copy to /Applications
read -p "Copy to /Applications? (y/N) " COPY
if [[ "$COPY" =~ ^[Yy]$ ]]; then
    if [ -d "/Applications/DualMic.app" ]; then
        echo "Removing old version..."
        rm -rf "/Applications/DualMic.app"
    fi
    cp -R "$APP_PATH" /Applications/
    echo "✅ Copied to /Applications/DualMic.app"
    echo ""
    echo "⚠️  First launch: click '系统声音' in the app to trigger the"
    echo "   screen recording permission dialog, then grant access."
fi
