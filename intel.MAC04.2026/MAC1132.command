#!/usr/bin/env bash
# ZoomReset.command — Double-click to run on macOS
# Stops Zoom, clears all data, and relaunches fresh.
set -euo pipefail

echo "=============================="
echo " BALLROOM.WTF ZOOM 1132 FIX (Mac) BY DOMNSEA "
echo "=============================="
echo ""
echo "This will close Zoom, wipe its saved data, and relaunch it."
echo "You may be prompted for your Mac password for system-level cleanup."
echo ""

# Prompt for sudo upfront so it doesn't interrupt later steps
sudo -v

clean_user() {
  rm -rf \
    "$HOME/Library/Application Support/zoom.us" \
    "$HOME/Library/Caches/us.zoom.xos" \
    "$HOME/Library/Preferences/us.zoom.xos.plist" \
    "$HOME/Library/Saved Application State/us.zoom.xos.savedState" \
    "$HOME/Library/HTTPStorages/us.zoom.xos" \
    "$HOME/Library/HTTPStorages/us.zoom.xos.binarycookies" \
    "$HOME/Library/WebKit/us.zoom.xos" \
    "$HOME/Library/Cookies/us.zoom.xos.binarycookies" \
    "$HOME/Documents/Zoom"

  if [[ -d "$HOME/Library/Logs" ]]; then
    find "$HOME/Library/Logs" -maxdepth 1 -iname 'zoom*' -exec rm -rf {} + 2>/dev/null || true
  fi
}

clean_system() {
  sudo rm -rf \
    "/Library/Application Support/zoom.us" \
    "/Library/Logs/zoom.us" \
    "/Library/Preferences/us.zoom.xos.plist" \
    "/Users/Shared/zoom.us" \
    "/Users/Shared/Zoom" \
    "/Users/Shared/ZoomInstaller"
}

echo "Stopping Zoom..."
osascript -e 'tell application "zoom.us" to quit' 2>/dev/null || true
osascript -e 'tell application "Zoom Workplace" to quit' 2>/dev/null || true
osascript -e 'tell application "Zoom" to quit' 2>/dev/null || true
pkill -x "zoom.us" 2>/dev/null || true
pkill -x "Zoom" 2>/dev/null || true
pkill -x "CptHost" 2>/dev/null || true
pkill -x "zTscoder" 2>/dev/null || true

echo "Cleaning user Zoom data..."
clean_user

echo "Cleaning system Zoom data..."
clean_system

echo "Launching Zoom..."
open -a "zoom.us" 2>/dev/null || open -a "Zoom Workplace" 2>/dev/null || open -a "Zoom"

echo ""
echo "Done! Zoom has been reset and relaunched."
echo "(You can close this window.)"
