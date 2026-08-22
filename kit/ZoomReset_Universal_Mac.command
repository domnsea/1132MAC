#!/usr/bin/env bash
# ZoomReset_Universal_Mac.command
# Universal macOS Zoom reset tool for Intel + Apple Silicon Macs.
# Double-click to run in Terminal.
#
# Zoom must be relaunched through Launch Services (the `open` command),
# never by executing /Applications/zoom.us.app/Contents/MacOS/zoom.us.
# Starting that stub from bash leaves procRole=Unspecified, so AppKit
# aborts in HIServices _RegisterApplication (SIGABRT / abort()).

set -u -o pipefail

SCRIPT_NAME="ZoomReset_Universal_Mac.command"
SCRIPT_VERSION="1.1.0"
LOG_FILE="$HOME/Desktop/ZoomReset_$(date +%Y%m%d_%H%M%S).log"

DELETE_LOCAL_RECORDINGS=1
DELETE_SHARED_RECORDINGS=1

# Bundle IDs used by current Zoom Workplace and older zoom.us builds.
ZOOM_BUNDLE_IDS=(
  "us.zoom.xos"
  "us.zoom.ZoomOpener"
)

log() {
  local msg="$*"
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$msg" | tee -a "$LOG_FILE"
}

warn() {
  log "WARNING: $*"
}

run_quiet() {
  "$@" >>"$LOG_FILE" 2>&1
  return $?
}

remove_path() {
  local target="$1"
  if [[ -e "$target" ]]; then
    rm -rf "$target" >>"$LOG_FILE" 2>&1 && log "Removed: $target" || warn "Could not remove: $target"
  else
    log "Not found, skipped: $target"
  fi
}

remove_with_sudo() {
  local target="$1"
  if [[ "$HAVE_SUDO" -eq 1 ]]; then
    if [[ -e "$target" ]]; then
      sudo rm -rf "$target" >>"$LOG_FILE" 2>&1 && log "Removed with sudo: $target" || warn "Could not remove with sudo: $target"
    else
      log "Not found, skipped: $target"
    fi
  else
    warn "Skipping system path without admin rights: $target"
  fi
}

print_header() {
  echo "=============================="
  echo " BALLROOM ZOOM RESET FOR MAC "
  echo "=============================="
  echo
  echo "This will close Zoom, clear Zoom data, and try to relaunch it."
  echo "Local Zoom recordings may be deleted."
  echo
}

check_platform() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This script is for macOS only."
    exit 1
  fi
}

get_arch() {
  local arch
  arch="$(uname -m 2>/dev/null || echo unknown)"
  case "$arch" in
    arm64) echo "Apple Silicon (arm64)" ;;
    x86_64) echo "Intel (x86_64)" ;;
    *) echo "$arch" ;;
  esac
}

get_console_uid() {
  stat -f '%u' /dev/console 2>/dev/null || true
}

get_console_user() {
  stat -f '%Su' /dev/console 2>/dev/null || true
}

# True when a real GUI user is logged in at the Mac (not SSH-only / loginwindow).
gui_login_available() {
  local console_user
  console_user="$(get_console_user)"
  [[ -n "$console_user" && "$console_user" != "root" && "$console_user" != "loginwindow" ]]
}

prompt_sudo() {
  HAVE_SUDO=0

  if [[ "$EUID" -eq 0 ]]; then
    HAVE_SUDO=1
    log "Already running with admin rights."
    return 0
  fi

  echo "macOS may ask for your password so the script can clean shared Zoom folders too."
  if sudo -v; then
    HAVE_SUDO=1
    log "Admin rights granted."
  else
    HAVE_SUDO=0
    warn "Admin rights were not granted. Continuing with current-user cleanup only."
  fi
}

zoom_is_running() {
  pgrep -x "zoom.us" >/dev/null 2>&1 && return 0
  pgrep -x "Zoom" >/dev/null 2>&1 && return 0
  pgrep -x "Zoom Workplace" >/dev/null 2>&1 && return 0
  pgrep -x "CptHost" >/dev/null 2>&1 && return 0
  return 1
}

stop_zoom() {
  log "Stopping Zoom processes..."
  run_quiet osascript -e 'tell application "zoom.us" to quit' || true
  run_quiet osascript -e 'tell application "Zoom Workplace" to quit' || true
  run_quiet osascript -e 'tell application "Zoom" to quit' || true
  run_quiet pkill -x "zoom.us" || true
  run_quiet pkill -x "Zoom" || true
  run_quiet pkill -x "Zoom Workplace" || true
  run_quiet pkill -x "CptHost" || true
  run_quiet pkill -x "zTscoder" || true
  wait_for_zoom_exit
  log "Zoom stop sequence finished."
}

wait_for_zoom_exit() {
  local i
  for i in $(seq 1 15); do
    if ! zoom_is_running; then
      log "Zoom processes have exited."
      return 0
    fi
    sleep 1
  done
  warn "Zoom processes were still running after 15 seconds; continuing anyway."
}

flush_pref_cache() {
  log "Flushing cached macOS preferences..."
  run_quiet killall -u "$USER" cfprefsd || true
  sleep 1
}

clean_user() {
  log "Cleaning Zoom data for current user: $HOME"

  remove_path "$HOME/Library/Application Support/zoom.us"
  remove_path "$HOME/Library/Application Support/Zoom"
  remove_path "$HOME/Library/Caches/us.zoom.xos"
  remove_path "$HOME/Library/Caches/zoom.us"
  remove_path "$HOME/Library/Preferences/us.zoom.xos.plist"
  remove_path "$HOME/Library/Preferences/zoom.us.plist"
  remove_path "$HOME/Library/Saved Application State/us.zoom.xos.savedState"
  remove_path "$HOME/Library/Saved Application State/zoom.us.savedState"
  remove_path "$HOME/Library/HTTPStorages/us.zoom.xos"
  remove_path "$HOME/Library/HTTPStorages/us.zoom.xos.binarycookies"
  remove_path "$HOME/Library/WebKit/us.zoom.xos"
  remove_path "$HOME/Library/Cookies/us.zoom.xos.binarycookies"
  remove_path "$HOME/Library/Logs/zoom.us"

  if [[ "$DELETE_LOCAL_RECORDINGS" -eq 1 ]]; then
    remove_path "$HOME/Documents/Zoom"
  else
    log "Local recordings retained by configuration."
  fi

  if [[ -d "$HOME/Library/Logs" ]]; then
    while IFS= read -r found; do
      remove_path "$found"
    done < <(find "$HOME/Library/Logs" -maxdepth 1 \( -iname 'zoom*' -o -iname 'us.zoom*' \) 2>/dev/null)
  fi
}

clean_system() {
  log "Cleaning shared and machine-level Zoom data..."

  remove_with_sudo "/Library/Application Support/zoom.us"
  remove_with_sudo "/Library/Application Support/Zoom"
  remove_with_sudo "/Library/Logs/zoom.us"
  remove_with_sudo "/Library/Preferences/us.zoom.xos.plist"
  remove_with_sudo "/Library/Preferences/zoom.us.plist"
  remove_with_sudo "/Users/Shared/zoom.us"
  remove_with_sudo "/Users/Shared/Zoom"
  remove_with_sudo "/Users/Shared/ZoomInstaller"

  if [[ "$DELETE_SHARED_RECORDINGS" -eq 1 ]]; then
    remove_with_sudo "/Users/Shared/Zoom/Recordings"
  else
    log "Shared recordings retained by configuration."
  fi
}

find_zoom_app() {
  local candidates=(
    "/Applications/Zoom Workplace.app"
    "/Applications/zoom.us.app"
    "/Applications/Zoom.app"
    "$HOME/Applications/Zoom Workplace.app"
    "$HOME/Applications/zoom.us.app"
    "$HOME/Applications/Zoom.app"
  )

  local app
  for app in "${candidates[@]}"; do
    if [[ -d "$app" ]]; then
      printf '%s\n' "$app"
      return 0
    fi
  done

  local mdfind_result
  mdfind_result="$(mdfind 'kMDItemKind == "Application" && (kMDItemFSName == "Zoom Workplace.app" || kMDItemFSName == "zoom.us.app" || kMDItemFSName == "Zoom.app")' 2>/dev/null | head -n 1 || true)"
  if [[ -n "$mdfind_result" ]]; then
    printf '%s\n' "$mdfind_result"
    return 0
  fi

  return 1
}

# Ask Launch Services to open a GUI app in the console user's WindowServer.
# Do not replace this with a direct exec of Contents/MacOS/zoom.us.
run_open() {
  local console_uid
  console_uid="$(get_console_uid)"

  if [[ "$EUID" -eq 0 && -n "$console_uid" && "$console_uid" != "0" ]]; then
    if launchctl asuser "$console_uid" /usr/bin/open "$@" >>"$LOG_FILE" 2>&1; then
      return 0
    fi
    if sudo -u "#${console_uid}" /usr/bin/open "$@" >>"$LOG_FILE" 2>&1; then
      return 0
    fi
    warn "Could not open as console user ${console_uid}; retrying in the current session."
  fi

  /usr/bin/open "$@" >>"$LOG_FILE" 2>&1
}

reregister_zoom_app() {
  local zoom_app="$1"
  local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

  if [[ -x "$lsregister" && -d "$zoom_app" ]]; then
    log "Re-registering Zoom with Launch Services: $zoom_app"
    run_quiet "$lsregister" -f "$zoom_app" || warn "lsregister failed for $zoom_app"
  fi
}

explain_registerapplication_crash() {
  warn "Zoom did not stay running after launch."
  warn "If macOS showed a crash report for zoom.us with abort() in _RegisterApplication,"
  warn "Zoom was started as a Terminal/bash child instead of through Launch Services."
  warn "Open Zoom from Applications, Spotlight, or Finder — do not run Contents/MacOS/zoom.us."
  warn "Do not wrap Zoom in sandbox-exec. If this script was started with sudo or over SSH,"
  warn "run it from a desktop Terminal window without sudo (it will ask for a password itself)."
}

launch_zoom() {
  local zoom_app bundle_id

  if ! gui_login_available; then
    warn "No macOS GUI login session is available (console user: $(get_console_user))."
    warn "Zoom cannot register with WindowServer from SSH or a background agent."
    warn "Sit at the Mac, then open Zoom from Applications."
    return 1
  fi

  zoom_app="$(find_zoom_app || true)"
  if [[ -n "$zoom_app" ]]; then
    reregister_zoom_app "$zoom_app"
  fi

  log "Launching Zoom through Launch Services (open). Console user: $(get_console_user)"

  if [[ -n "$zoom_app" ]]; then
    log "Launching Zoom from: $zoom_app"
    if run_open "$zoom_app"; then
      if wait_for_zoom_start; then
        return 0
      fi
      warn "Open reported success but Zoom did not stay running: $zoom_app"
    else
      warn "Open failed for detected app path: $zoom_app"
    fi
  fi

  for bundle_id in "${ZOOM_BUNDLE_IDS[@]}"; do
    log "Trying bundle id: $bundle_id"
    if run_open -b "$bundle_id"; then
      if wait_for_zoom_start; then
        return 0
      fi
    fi
  done

  log "Trying fallback app names..."
  if run_open -a "Zoom Workplace" && wait_for_zoom_start; then
    return 0
  fi
  if run_open -a "zoom.us" && wait_for_zoom_start; then
    return 0
  fi
  if run_open -a "Zoom" && wait_for_zoom_start; then
    return 0
  fi

  log "Trying AppleScript activate as a last Launch Services fallback..."
  if run_quiet osascript -e 'tell application "zoom.us" to activate' \
    || run_quiet osascript -e 'tell application "Zoom Workplace" to activate' \
    || run_quiet osascript -e 'tell application "Zoom" to activate'; then
    if wait_for_zoom_start; then
      return 0
    fi
  fi

  explain_registerapplication_crash
  return 1
}

wait_for_zoom_start() {
  local i
  for i in $(seq 1 8); do
    sleep 1
    if zoom_is_running; then
      log "Zoom is running."
      return 0
    fi
  done
  return 1
}

main() {
  check_platform
  print_header

  mkdir -p "$(dirname "$LOG_FILE")"
  : > "$LOG_FILE"

  log "Script started: $SCRIPT_NAME v$SCRIPT_VERSION"
  log "macOS user: $USER"
  log "Detected CPU architecture: $(get_arch)"
  log "Console GUI user: $(get_console_user)"
  log "Log file: $LOG_FILE"
  log "DELETE_LOCAL_RECORDINGS=$DELETE_LOCAL_RECORDINGS"
  log "DELETE_SHARED_RECORDINGS=$DELETE_SHARED_RECORDINGS"

  prompt_sudo
  stop_zoom
  clean_user
  clean_system
  flush_pref_cache
  launch_zoom || true

  echo
  echo "Done."
  echo "A log file was saved to your Desktop:"
  echo "$LOG_FILE"
  echo
  echo "You can close this Terminal window."
  log "Script finished."
}

main "$@"
