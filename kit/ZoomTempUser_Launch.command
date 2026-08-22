#!/usr/bin/env bash
# ZoomTempUser_Launch.command
# Creates a hidden temporary Mac user, launches Zoom in the logged-in
# GUI session so a window can appear, then deletes that user when Zoom quits.
#
# Zoom itself cannot run as the temporary UID on SIP-enabled macOS.
# v94's launchctl bsexec + $ZOOM_BIN as UID 504 aborts in _RegisterApplication.
# This script keeps the temp-user lifecycle, but opens Zoom as the console
# user through Launch Services and stores Zoom's files in the temp home.

set -u -o pipefail

SCRIPT_NAME="ZoomTempUser_Launch.command"
SCRIPT_VERSION="1.2.0"
LOG_FILE="$HOME/Desktop/ZoomTempUser_$(date +%Y%m%d_%H%M%S).log"
RUN_ID="$(date +%Y%m%d%H%M%S)"

HAVE_SUDO=0
SUDO_KEEPALIVE_PID=""
TEMP_USER=""
TEMP_HOME=""
TEMP_UID=""
CLEANED_UP=0
BACKUP_SUFFIX=".zwtfbak.${RUN_ID}"
REDIRECTS=()
BACKUPS=()

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

warn() {
  log "WARNING: $*"
}

run_quiet() {
  "$@" >>"$LOG_FILE" 2>&1
  return $?
}

check_platform() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This script is for macOS only."
    exit 1
  fi
}

get_console_uid() {
  stat -f '%u' /dev/console 2>/dev/null || true
}

get_console_user() {
  stat -f '%Su' /dev/console 2>/dev/null || true
}

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
  echo "macOS will ask for your password so the script can create and later delete a temporary user."
  if sudo -v; then
    HAVE_SUDO=1
    log "Admin rights granted."
    return 0
  fi
  echo "A temporary user cannot be created without admin rights."
  exit 1
}

keep_sudo_alive() {
  while true; do
    sudo -n true >>"$LOG_FILE" 2>&1 || exit 0
    sleep 30
  done
}

kill_sudo_keepalive() {
  if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
    kill "$SUDO_KEEPALIVE_PID" >>"$LOG_FILE" 2>&1 || true
    SUDO_KEEPALIVE_PID=""
  fi
}

run_as_console() {
  local console_uid
  console_uid="$(get_console_uid)"
  if [[ "$EUID" -eq 0 && -n "$console_uid" && "$console_uid" != "0" ]]; then
    if launchctl asuser "$console_uid" /usr/bin/open "$@" >>"$LOG_FILE" 2>&1; then
      return 0
    fi
    if sudo -u "#${console_uid}" /usr/bin/open "$@" >>"$LOG_FILE" 2>&1; then
      return 0
    fi
  fi
  /usr/bin/open "$@" >>"$LOG_FILE" 2>&1
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

zoom_is_running() {
  pgrep -x "zoom.us" >/dev/null 2>&1 && return 0
  pgrep -x "Zoom" >/dev/null 2>&1 && return 0
  pgrep -x "Zoom Workplace" >/dev/null 2>&1 && return 0
  pgrep -x "CptHost" >/dev/null 2>&1 && return 0
  return 1
}

stop_zoom() {
  log "Stopping existing Zoom processes..."
  run_quiet osascript -e 'tell application "zoom.us" to quit' || true
  run_quiet osascript -e 'tell application "Zoom Workplace" to quit' || true
  run_quiet osascript -e 'tell application "Zoom" to quit' || true
  run_quiet pkill -x "zoom.us" || true
  run_quiet pkill -x "Zoom" || true
  run_quiet pkill -x "Zoom Workplace" || true
  run_quiet pkill -x "CptHost" || true
  run_quiet pkill -x "zTscoder" || true
  local i
  for i in $(seq 1 15); do
    if ! zoom_is_running; then
      log "Zoom processes have exited."
      return 0
    fi
    sleep 1
  done
  warn "Zoom processes were still running; continuing anyway."
}

free_hidden_uid() {
  local used uid
  used="$(dscl . -list /Users UniqueID 2>/dev/null | awk '{print $2}')"
  for uid in $(seq 241 398); do
    if ! printf '%s\n' "$used" | grep -qx "$uid"; then
      printf '%s\n' "$uid"
      return 0
    fi
  done
  return 1
}

create_temp_user() {
  local rand pass
  rand="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 6 || true)"
  if [[ ${#rand} -lt 6 ]]; then
    rand="${RUN_ID: -6}"
  fi
  TEMP_USER="zwtf${rand}"
  TEMP_HOME="/Users/${TEMP_USER}"
  TEMP_UID="$(free_hidden_uid || true)"
  if [[ -z "$TEMP_UID" ]]; then
    echo "Could not find a free hidden user ID."
    exit 1
  fi
  pass="$(openssl rand -base64 18 2>/dev/null || date +%s)"

  log "Creating hidden temporary user ${TEMP_USER} (uid ${TEMP_UID})"

  if dscl . -read "/Users/${TEMP_USER}" >/dev/null 2>&1; then
    warn "User ${TEMP_USER} already exists; choosing another name."
    rand="${RUN_ID}"
    TEMP_USER="zwtf${rand: -8}"
    TEMP_HOME="/Users/${TEMP_USER}"
  fi

  sudo dscl . -create "/Users/${TEMP_USER}" >>"$LOG_FILE" 2>&1
  sudo dscl . -create "/Users/${TEMP_USER}" UserShell /usr/bin/false >>"$LOG_FILE" 2>&1
  sudo dscl . -create "/Users/${TEMP_USER}" RealName "Zoom Temporary" >>"$LOG_FILE" 2>&1
  sudo dscl . -create "/Users/${TEMP_USER}" UniqueID "$TEMP_UID" >>"$LOG_FILE" 2>&1
  sudo dscl . -create "/Users/${TEMP_USER}" PrimaryGroupID 20 >>"$LOG_FILE" 2>&1
  sudo dscl . -create "/Users/${TEMP_USER}" NFSHomeDirectory "$TEMP_HOME" >>"$LOG_FILE" 2>&1
  sudo dscl . -create "/Users/${TEMP_USER}" IsHidden 1 >>"$LOG_FILE" 2>&1
  sudo dscl . -passwd "/Users/${TEMP_USER}" "$pass" >>"$LOG_FILE" 2>&1 || warn "Could not set temp user password (login is disabled anyway)."

  sudo mkdir -p "$TEMP_HOME/Library/Application Support" \
    "$TEMP_HOME/Library/Caches" \
    "$TEMP_HOME/Library/Preferences" \
    "$TEMP_HOME/Library/Saved Application State" \
    "$TEMP_HOME/Library/HTTPStorages" \
    "$TEMP_HOME/Library/WebKit" \
    "$TEMP_HOME/Library/Cookies" \
    "$TEMP_HOME/Library/Logs" \
    "$TEMP_HOME/tmp" >>"$LOG_FILE" 2>&1
  sudo chown -R "${TEMP_UID}:20" "$TEMP_HOME" >>"$LOG_FILE" 2>&1
  sudo chmod 755 "$TEMP_HOME" >>"$LOG_FILE" 2>&1
  sudo chmod +a "$(get_console_user) allow list,add_file,search,add_subdirectory,delete_child,read,write,execute,append,delete,file_inherit,directory_inherit" "$TEMP_HOME" >>"$LOG_FILE" 2>&1 \
    || sudo chmod -R 777 "$TEMP_HOME" >>"$LOG_FILE" 2>&1

  log "Temporary user home: $TEMP_HOME"
}

zoom_data_paths() {
  local base="$1"
  printf '%s\n' \
    "$base/Library/Application Support/zoom.us" \
    "$base/Library/Application Support/Zoom" \
    "$base/Library/Caches/us.zoom.xos" \
    "$base/Library/Caches/zoom.us" \
    "$base/Library/Preferences/us.zoom.xos.plist" \
    "$base/Library/Preferences/zoom.us.plist" \
    "$base/Library/Saved Application State/us.zoom.xos.savedState" \
    "$base/Library/Saved Application State/zoom.us.savedState" \
    "$base/Library/HTTPStorages/us.zoom.xos" \
    "$base/Library/HTTPStorages/us.zoom.xos.binarycookies" \
    "$base/Library/WebKit/us.zoom.xos" \
    "$base/Library/Cookies/us.zoom.xos.binarycookies" \
    "$base/Library/Logs/zoom.us"
}

stage_temp_path() {
  local real="$1"
  local rel="${real#$HOME/}"
  printf '%s/%s\n' "$TEMP_HOME" "$rel"
}

redirect_zoom_data() {
  local real staged parent
  log "Pointing this account's Zoom files at the temporary user home..."
  while IFS= read -r real; do
    staged="$(stage_temp_path "$real")"
    parent="$(dirname "$real")"
    mkdir -p "$parent" >>"$LOG_FILE" 2>&1 || true
    sudo mkdir -p "$(dirname "$staged")" >>"$LOG_FILE" 2>&1 || true

    if [[ -L "$real" ]]; then
      rm -f "$real" >>"$LOG_FILE" 2>&1 || true
    elif [[ -e "$real" ]]; then
      mv "$real" "${real}${BACKUP_SUFFIX}" >>"$LOG_FILE" 2>&1 && BACKUPS+=("$real") || warn "Could not move aside: $real"
    fi

    if [[ "$real" == *.plist || "$real" == *.binarycookies ]]; then
      sudo touch "$staged" >>"$LOG_FILE" 2>&1 || true
    else
      sudo mkdir -p "$staged" >>"$LOG_FILE" 2>&1 || true
    fi
    sudo chown -R "$(get_console_uid):20" "$(dirname "$staged")" >>"$LOG_FILE" 2>&1 || true
    ln -s "$staged" "$real" >>"$LOG_FILE" 2>&1 && REDIRECTS+=("$real") || warn "Could not redirect: $real"
  done < <(zoom_data_paths "$HOME")
}

restore_zoom_data() {
  local real
  for real in "${REDIRECTS[@]+"${REDIRECTS[@]}"}"; do
    if [[ -L "$real" ]]; then
      rm -f "$real" >>"$LOG_FILE" 2>&1 || true
    fi
  done
  REDIRECTS=()
  for real in "${BACKUPS[@]+"${BACKUPS[@]}"}"; do
    if [[ -e "${real}${BACKUP_SUFFIX}" ]]; then
      rm -rf "$real" >>"$LOG_FILE" 2>&1 || true
      mv "${real}${BACKUP_SUFFIX}" "$real" >>"$LOG_FILE" 2>&1 && log "Restored: $real" || warn "Could not restore: $real"
    fi
  done
  BACKUPS=()
}

delete_temp_user() {
  if [[ -z "$TEMP_USER" ]]; then
    return 0
  fi
  if ! dscl . -read "/Users/${TEMP_USER}" >/dev/null 2>&1; then
    TEMP_USER=""
    return 0
  fi
  log "Deleting temporary user ${TEMP_USER}"
  if command -v sysadminctl >/dev/null 2>&1; then
    sudo sysadminctl -deleteUser "$TEMP_USER" >>"$LOG_FILE" 2>&1 || true
  fi
  if dscl . -read "/Users/${TEMP_USER}" >/dev/null 2>&1; then
    sudo dscl . -delete "/Users/${TEMP_USER}" >>"$LOG_FILE" 2>&1 || warn "Could not delete user record ${TEMP_USER}"
  fi
  if [[ -n "$TEMP_HOME" && -d "$TEMP_HOME" ]]; then
    sudo rm -rf "$TEMP_HOME" >>"$LOG_FILE" 2>&1 || warn "Could not remove $TEMP_HOME"
  fi
  TEMP_USER=""
}

cleanup() {
  local status=$?
  if [[ "$CLEANED_UP" -eq 1 ]]; then
    return 0
  fi
  CLEANED_UP=1
  kill_sudo_keepalive
  stop_zoom || true
  restore_zoom_data
  delete_temp_user
  log "Cleanup finished."
  return "$status"
}

launch_zoom_for_gui() {
  local zoom_app="$1"
  log "Launching Zoom through Launch Services as $(get_console_user)"
  if run_as_console -na "$zoom_app"; then
    return 0
  fi
  warn "open -na failed; trying app name fallbacks."
  run_as_console -na "Zoom Workplace" && return 0
  run_as_console -na "zoom.us" && return 0
  run_as_console -na "Zoom" && return 0
  return 1
}

wait_for_zoom_start() {
  local i
  for i in $(seq 1 20); do
    sleep 1
    if zoom_is_running; then
      log "Zoom is running."
      return 0
    fi
  done
  return 1
}

wait_for_zoom_quit() {
  echo
  echo "Zoom is open. Leave this Terminal window alone."
  echo "When you quit Zoom, the temporary user is deleted."
  echo
  log "Waiting for Zoom to quit..."
  while zoom_is_running; do
    sudo -n true >>"$LOG_FILE" 2>&1 || true
    sleep 2
  done
  sleep 1
  log "Zoom has quit."
}

main() {
  check_platform
  mkdir -p "$(dirname "$LOG_FILE")"
  : > "$LOG_FILE"

  echo "===================================="
  echo " ZOOM TEMPORARY USER LAUNCH FOR MAC "
  echo "===================================="
  echo
  echo "This creates a hidden temporary Mac user, opens Zoom in your"
  echo "desktop session, and deletes that user when you quit Zoom."
  echo

  log "Script started: $SCRIPT_NAME v$SCRIPT_VERSION"
  log "macOS user: $USER"
  log "Console GUI user: $(get_console_user)"
  log "Log file: $LOG_FILE"

  if ! gui_login_available; then
    echo "No desktop login session. Run this from the Mac, not SSH."
    exit 1
  fi

  prompt_sudo
  keep_sudo_alive &
  SUDO_KEEPALIVE_PID=$!
  trap 'cleanup' EXIT INT TERM

  local zoom_app
  zoom_app="$(find_zoom_app || true)"
  if [[ -z "$zoom_app" ]]; then
    echo "Zoom is not installed in Applications."
    exit 1
  fi
  log "Using Zoom app: $zoom_app"

  stop_zoom
  create_temp_user
  redirect_zoom_data

  if ! launch_zoom_for_gui "$zoom_app"; then
    echo "Could not ask Launch Services to open Zoom."
    exit 1
  fi

  if ! wait_for_zoom_start; then
    echo
    echo "Zoom did not stay running. If macOS showed Abort trap 6 / _RegisterApplication,"
    echo "Zoom was still started outside your desktop session."
    echo "Log: $LOG_FILE"
    exit 1
  fi

  wait_for_zoom_quit
  echo
  echo "Done. Temporary user removed."
  echo "Log: $LOG_FILE"
  log "Script finished."
}

main "$@"
