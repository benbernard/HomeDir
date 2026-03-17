#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Installing dependencies..."
npm install

echo "Building Meety.app..."
CSC_IDENTITY_AUTO_DISCOVERY=false npx electron-builder --mac --dir

echo "Installing to /Applications..."
killall Meety 2>/dev/null || true
rm -rf "/Applications/Meety.app"
cp -r "dist/mac-arm64/Meety.app" /Applications/
rm -rf dist

echo "Resetting permissions..."
tccutil reset All com.benbernard.meety 2>/dev/null || true

echo "Done! You can now use:"
echo "  open -a 'Meety'"
echo "  open -a 'Meety' https://meet.google.com/xxx-xxxx-xxx"
echo "  open gmeet://xxx-xxxx-xxx"
