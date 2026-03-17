#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Installing dependencies..."
npm install

echo "Building Meety.app..."
npx electron-builder --mac --dir

echo "Installing to /Applications..."
killall Meety 2>/dev/null || true
rm -rf "/Applications/Meety.app"
cp -r "dist/mac-arm64/Meety.app" /Applications/
rm -rf dist

# ─── CRITICAL FIX: Do NOT reset TCC permissions ───
# The original script had: tccutil reset All com.benbernard.meety
# This DESTROYS any previously granted camera/mic/screen permissions,
# which is exactly why nothing works after a reinstall.
#
# If you truly need a fresh permission state, reset only specific services:
#   tccutil reset Camera com.benbernard.meety
#   tccutil reset Microphone com.benbernard.meety
#   tccutil reset ScreenCapture com.benbernard.meety
#
# But normally you should NOT reset at all — let the OS remember grants.

echo ""
echo "Done! You can now use:"
echo "  open -a 'Meety'"
echo "  open -a 'Meety' https://meet.google.com/xxx-xxxx-xxx"
echo "  open gmeet://xxx-xxxx-xxx"
echo ""
echo "IMPORTANT: On first launch, grant Camera and Microphone when prompted."
echo "For screen sharing, manually add Meety in:"
echo "  System Settings > Privacy & Security > Screen & System Audio Recording"
echo ""
