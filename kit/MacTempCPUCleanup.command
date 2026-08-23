#!/usr/bin/env bash
# MacTempCPUCleanup.command
# Drop leftover Zoom CPU, caches, logs, and temp files.
# Does not delete Zoom logins, identity parks, or Documents/Zoom recordings.
# Double-click to run in Terminal on macOS.

set -u -o pipefail

LOG_FILE="$HOME/Desktop/MacTempCPUCleanup_$(date +%Y%m%d_%H%M%S).log"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

zoom_running() {
  pgrep -x "zoom.us" >/dev/null 2>&1 \
    || pgrep -x "Zoom" >/dev/null 2>&1 \
    || pgrep -x "Zoom Workplace" >/dev/null 2>&1
}

remove_path() {
  local target="$1"
  case "$target" in
    "$HOME/.zwtf_identity_park"|"$HOME/.zwtf_identity_park"/*|"$HOME/Documents/Zoom"|"$HOME/Documents/Zoom"/*)
      log "Refusing to remove protected path: $target"
      return 0
      ;;
  esac
  if [[ -e "$target" ]]; then
    rm -rf "$target" >>"$LOG_FILE" 2>&1 && log "Removed: $target" || log "WARNING: Could not remove: $target"
  else
    log "Not found, skipped: $target"
  fi
}

kill_helpers_when_idle() {
  if zoom_running; then
    log "Zoom is running — leaving meeting helpers alone."
    return 0
  fi

  log "Zoom is not running — stopping leftover helpers..."
  local name
  for name in CptHost zTscoder aomhost ZoomUpdater ZoomOpener crashpad_handler; do
    pkill -x "$name" >>"$LOG_FILE" 2>&1 && log "Stopped leftover process: $name" || true
  done
}

clean_caches_and_temp() {
  log "Cleaning Zoom caches, logs, and temp files..."

  remove_path "$HOME/Library/Caches/us.zoom.xos"
  remove_path "$HOME/Library/Caches/zoom.us"
  remove_path "$HOME/Library/Caches/Zoom"
  remove_path "$HOME/Library/Logs/zoom.us"
  remove_path "$HOME/Library/Saved Application State/us.zoom.xos.savedState"
  remove_path "$HOME/Library/Saved Application State/zoom.us.savedState"
  remove_path "$HOME/Library/HTTPStorages/us.zoom.xos"
  remove_path "$HOME/Library/HTTPStorages/us.zoom.xos.binarycookies"
  remove_path "$HOME/Library/WebKit/us.zoom.xos"
  remove_path "$HOME/Library/Cookies/us.zoom.xos.binarycookies"

  if [[ -d "$HOME/Library/Logs" ]]; then
    while IFS= read -r found; do
      remove_path "$found"
    done < <(find "$HOME/Library/Logs" -maxdepth 1 \( -iname 'zoom*' -o -iname 'us.zoom*' \) 2>/dev/null)
  fi

  # Session logs on the Desktop from earlier Church Guest Zoom runs.
  if [[ -d "$HOME/Desktop" ]]; then
    while IFS= read -r found; do
      remove_path "$found"
    done < <(find "$HOME/Desktop" -maxdepth 1 \( -name 'ChurchGuestZoom-log.txt' -o -name 'ZoomReset_*.log' \) 2>/dev/null)
  fi

  # Generic temp leftovers only. Identity parks stay.
  if [[ -d /tmp ]]; then
    while IFS= read -r found; do
      remove_path "$found"
    done < <(find /tmp -maxdepth 2 \( -iname '*zoom*' -o -iname '*us.zoom*' \) 2>/dev/null)
  fi
}

main() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This script is for macOS only."
    echo "On the Slimcast Linux desktop run: bash tools/slimcast_speedup.sh"
    exit 1
  fi

  mkdir -p "$(dirname "$LOG_FILE")"
  : > "$LOG_FILE"

  echo "=============================="
  echo " Mac Zoom temp / CPU cleanup"
  echo "=============================="
  echo
  echo "This does not wipe Zoom logins or recordings."
  echo "Parked identity at ~/.zwtf_identity_park is left alone."
  echo

  log "Script started"
  log "User: $USER"
  kill_helpers_when_idle
  clean_caches_and_temp

  echo
  echo "Done. Log: $LOG_FILE"
  echo "You can close this Terminal window."
  log "Script finished"
}

main "$@"
