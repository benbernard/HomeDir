#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Building..."
npx electron-builder --mac --dir

APP_SRC="dist/mac-arm64/Todo Tracker.app"
DEST="/Applications/Todo Tracker.app"

if [ ! -d "$APP_SRC" ]; then
  echo "Build output not found: $APP_SRC" >&2
  exit 1
fi

echo "Installing to /Applications..."
rm -rf "$DEST"
cp -R "$APP_SRC" "$DEST"

echo "Done. Installed: $DEST"
