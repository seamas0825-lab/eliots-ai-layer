#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
BUILD_DIR="$PROJECT_DIR/.build/release"
OUTPUT_DIR="$PROJECT_DIR/dist"
APP_DIR="$OUTPUT_DIR/Eliot's AI Layer.app"

cd "$PROJECT_DIR"
swift build -c release

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/SelectAI" "$APP_DIR/Contents/MacOS/SelectAI"
cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Assets/EliotsAILayer.icns" "$APP_DIR/Contents/Resources/EliotsAILayer.icns"
chmod +x "$APP_DIR/Contents/MacOS/SelectAI"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
