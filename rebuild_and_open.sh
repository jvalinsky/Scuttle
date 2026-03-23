#!/bin/bash

# Rebuild and open ScuttleRoomApp

set -e

echo "⚙️ Generating Xcode Project..."
xcodegen generate

echo "🏗️ Building ScuttleRoomApp..."
xcodebuild build \
  -scheme "ScuttleRoomApp" \
  -destination "platform=macOS" \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO

APP_PATH="build/Build/Products/Debug/ScuttleRoomApp.app"

if [ -d "$APP_PATH" ]; then
  echo "🚀 Opening ScuttleRoomApp..."
  open "$APP_PATH"
else
  echo "❌ Error: App bundle not found at $APP_PATH"
  exit 1
fi
