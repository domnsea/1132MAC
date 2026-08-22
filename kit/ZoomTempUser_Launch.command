#!/usr/bin/env bash
# ZoomTempUser_Launch.command
# Hide this Mac account's personal Zoom identity, open a logged-out Zoom
# session, then restore the personal identity when Zoom quits.
#
# Your church group will not see the gamer Zoom login because that saved
# account (files + Keychain) is parked before Zoom starts.
# A hidden temporary Mac user is created and deleted around the session.

set -u -o pipefail

SCRIPT_NAME="ZoomTempUser_Launch.command"
SCRIPT_VERSION="1.3.0"
LOG_FILE="$HOME/Desktop/ZoomTempUser_$(date +%Y%m%d_%H%M%S).log"
RUN_ID="$(date +%Y%m%d%H%M%S)"
PARK_DIR="$HOME/.zwtf_identity_park/${RUN_ID}"

HAVE_SUDO=0
SUDO_KEEPALIVE_PID=""
TEMP_USER=""
TEMP_HOME=""
TEMP_UID=""
CLEANED_UP=0
KEYCHAIN_PARKED=0

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
  echo "macOS will ask for your password so the script can create a temporary user"
  echo "and keep your personal Zoom login hidden until you quit."
  if sudo -v; then
    HAVE_SUDO=1
    log "Admin rights granted."
    return 0
  fi
  echo "Admin rights are required."
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

run_open_as_console() {
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

zoom_process_owner() {
  local pid
  pid="$(pgrep -x "zoom.us" 2>/dev/null | head -n 1 || true)"
  if [[ -z "$pid" ]]; then
    pid="$(pgrep -x "Zoom" 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -z "$pid" ]]; then
    return 1
  fi
  ps -p "$pid" -o user= 2>/dev/null | awk '{print $1}'
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

list_zoom_identity_paths() {
  local base="$1"
  local dir
  for dir in \
    "$base/Library/Application Support" \
    "$base/Library/Caches" \
    "$base/Library/Preferences" \
    "$base/Library/Preferences/ByHost" \
    "$base/Library/Saved Application State" \
    "$base/Library/HTTPStorages" \
    "$base/Library/WebKit" \
    "$base/Library/Cookies" \
    "$base/Library/Logs" \
    "$base/Library/Group Containers" \
    "$base/Library/Containers" \
    "$base/Library/Application Scripts" \
    "$base/Library/Internet Plug-Ins" \
    "$base/Library/LaunchAgents" \
    "$base/Library/Receipts"
  do
    [[ -d "$dir" ]] || continue
    find "$dir" -maxdepth 1 \( -iname '*zoom*' -o -iname 'us.zoom*' \) 2>/dev/null
  done
  if [[ -e "$base/Documents/Zoom" ]]; then
    printf '%s\n' "$base/Documents/Zoom"
  fi
}

park_personal_zoom_files() {
  local src n=0
  mkdir -p "$PARK_DIR/items"
  : > "$PARK_DIR/manifest.txt"
  log "Parking personal Zoom files so this session cannot see them..."
  while IFS= read -r src; do
    [[ -e "$src" || -L "$src" ]] || continue
    case "$src" in
      "$PARK_DIR"*) continue ;;
    esac
    n=$((n + 1))
    mv "$src" "$PARK_DIR/items/$n" >>"$LOG_FILE" 2>&1 && {
      printf '%s\t%s\n' "$n" "$src" >> "$PARK_DIR/manifest.txt"
      log "Parked: $src"
    } || warn "Could not park: $src"
  done < <(list_zoom_identity_paths "$HOME")
  run_quiet killall -u "$USER" cfprefsd || true
  sleep 1
}

unpark_personal_zoom_files() {
  local n src
  discard_session_zoom_files
  if [[ ! -f "$PARK_DIR/manifest.txt" ]]; then
    return 0
  fi
  log "Restoring personal Zoom files..."
  while IFS=$'\t' read -r n src; do
    [[ -n "$n" && -n "$src" ]] || continue
    mkdir -p "$(dirname "$src")"
    rm -rf "$src" >>"$LOG_FILE" 2>&1 || true
    if [[ -e "$PARK_DIR/items/$n" || -L "$PARK_DIR/items/$n" ]]; then
      mv "$PARK_DIR/items/$n" "$src" >>"$LOG_FILE" 2>&1 && log "Restored: $src" || warn "Could not restore: $src"
    fi
  done < "$PARK_DIR/manifest.txt"
  run_quiet killall -u "$USER" cfprefsd || true
}

discard_session_zoom_files() {
  local p
  log "Discarding Zoom files created during the isolated session..."
  while IFS= read -r p; do
    [[ -e "$p" || -L "$p" ]] || continue
    case "$p" in
      "$PARK_DIR"*) continue ;;
    esac
    rm -rf "$p" >>"$LOG_FILE" 2>&1 && log "Removed session file: $p" || warn "Could not remove: $p"
  done < <(list_zoom_identity_paths "$HOME")
}

write_keychain_helper() {
  mkdir -p "$PARK_DIR"
  cat > "$PARK_DIR/zoom_keychain.py" <<'PY'
#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys

ZOOM_RE = re.compile(r"zoom", re.I)


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def parse_records(text):
    records = []
    cur = {}
    for line in text.splitlines():
        if line.startswith("class:"):
            if cur:
                records.append(cur)
            cur = {}
            m = re.search(r'"([^"]+)"', line)
            if m:
                cur["class"] = m.group(1)
            continue
        m = re.search(
            r'"(acct|svce|labl|desc|srvr)"\s*<blob>=(?:<NULL>|"((?:\\.|[^"\\])*)")',
            line,
        )
        if m:
            cur[m.group(1)] = (m.group(2) or "").replace('\\"', '"')
    if cur:
        records.append(cur)
    return records


def is_zoom(rec):
    blob = " ".join(rec.get(k, "") for k in ("acct", "svce", "labl", "desc", "srvr"))
    return bool(ZOOM_RE.search(blob))


def password_for(rec):
    if rec.get("class") == "inet":
        cmd = ["security", "find-internet-password"]
    else:
        cmd = ["security", "find-generic-password"]
    if rec.get("svce"):
        cmd += ["-s", rec["svce"]]
    if rec.get("acct"):
        cmd += ["-a", rec["acct"]]
    if rec.get("labl") and not rec.get("svce"):
        cmd += ["-l", rec["labl"]]
    cmd += ["-w"]
    r = run(cmd)
    if r.returncode != 0:
        return None
    return r.stdout.rstrip("\n")


def delete_rec(rec):
    if rec.get("class") == "inet":
        cmd = ["security", "delete-internet-password"]
    else:
        cmd = ["security", "delete-generic-password"]
    if rec.get("svce"):
        cmd += ["-s", rec["svce"]]
    if rec.get("acct"):
        cmd += ["-a", rec["acct"]]
    if rec.get("labl") and not rec.get("svce"):
        cmd += ["-l", rec["labl"]]
    return run(cmd).returncode == 0


def add_rec(rec):
    pw = rec.get("password")
    if pw is None:
        return False
    if rec.get("class") == "inet":
        cmd = ["security", "add-internet-password"]
    else:
        cmd = ["security", "add-generic-password"]
    if rec.get("labl"):
        cmd += ["-l", rec["labl"]]
    if rec.get("svce"):
        cmd += ["-s", rec["svce"]]
    if rec.get("acct"):
        cmd += ["-a", rec["acct"]]
    cmd += ["-w", pw]
    return run(cmd).returncode == 0


def dump_all():
    r = run(["security", "dump-keychain"])
    return parse_records(r.stdout + "\n" + r.stderr)


def cmd_save(path):
    saved = []
    for rec in dump_all():
        if not is_zoom(rec):
            continue
        rec["password"] = password_for(rec)
        saved.append(rec)
        delete_rec(rec)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(saved, fh)
        fh.write("\n")
    os.chmod(path, 0o600)
    leftover = [rec for rec in dump_all() if is_zoom(rec)]
    if leftover:
        print("LEFTOVER %d" % len(leftover), file=sys.stderr)
        return 2
    print("SAVED %d" % len(saved))
    return 0


def cmd_restore(path):
    if not os.path.isfile(path):
        print("NOFILE")
        return 0
    with open(path, encoding="utf-8") as fh:
        saved = json.load(fh)
    restored = 0
    for rec in saved:
        if add_rec(rec):
            restored += 1
    print("RESTORED %d" % restored)
    return 0


def cmd_count():
    n = sum(1 for rec in dump_all() if is_zoom(rec))
    print(n)
    return 0


def main():
    if len(sys.argv) < 2:
        return 1
    op = sys.argv[1]
    if op == "save":
        return cmd_save(sys.argv[2])
    if op == "restore":
        return cmd_restore(sys.argv[2])
    if op == "count":
        return cmd_count()
    return 1


if __name__ == "__main__":
    sys.exit(main())
PY
  chmod 700 "$PARK_DIR/zoom_keychain.py"
}

park_zoom_keychain() {
  local helper json status
  write_keychain_helper
  helper="$PARK_DIR/zoom_keychain.py"
  json="$PARK_DIR/zoom_keychain.json"
  echo
  echo "If Keychain Access asks permission, click Allow."
  echo "That hides your saved gamer Zoom login for this session and puts it back when you quit."
  echo
  log "Parking Zoom Keychain items..."
  python3 "$helper" save "$json" >>"$LOG_FILE" 2>&1
  status=$?
  if [[ "$status" -ne 0 ]]; then
    echo "Could not fully hide Zoom saved passwords in Keychain."
    echo "Refusing to launch, so your gamer login cannot leak."
    echo "Log: $LOG_FILE"
    exit 1
  fi
  KEYCHAIN_PARKED=1
}

unpark_zoom_keychain() {
  local helper json
  helper="$PARK_DIR/zoom_keychain.py"
  json="$PARK_DIR/zoom_keychain.json"
  if [[ "$KEYCHAIN_PARKED" -ne 1 || ! -f "$json" ]]; then
    return 0
  fi
  log "Restoring Zoom Keychain items..."
  python3 "$helper" restore "$json" >>"$LOG_FILE" 2>&1 || warn "Could not restore every Zoom Keychain item. You may need to sign in to your personal Zoom account again."
}

personal_zoom_still_visible() {
  local p count
  while IFS= read -r p; do
    [[ -e "$p" || -L "$p" ]] || continue
    case "$p" in
      "$PARK_DIR"*) continue ;;
    esac
    return 0
  done < <(list_zoom_identity_paths "$HOME")
  if [[ -f "$PARK_DIR/zoom_keychain.py" ]]; then
    count="$(python3 "$PARK_DIR/zoom_keychain.py" count 2>/dev/null || echo 1)"
    if [[ "$count" != "0" ]]; then
      return 0
    fi
  fi
  return 1
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
  sudo dscl . -create "/Users/${TEMP_USER}" >>"$LOG_FILE" 2>&1
  sudo dscl . -create "/Users/${TEMP_USER}" UserShell /usr/bin/false >>"$LOG_FILE" 2>&1
  sudo dscl . -create "/Users/${TEMP_USER}" RealName "Zoom Guest" >>"$LOG_FILE" 2>&1
  sudo dscl . -create "/Users/${TEMP_USER}" UniqueID "$TEMP_UID" >>"$LOG_FILE" 2>&1
  sudo dscl . -create "/Users/${TEMP_USER}" PrimaryGroupID 20 >>"$LOG_FILE" 2>&1
  sudo dscl . -create "/Users/${TEMP_USER}" NFSHomeDirectory "$TEMP_HOME" >>"$LOG_FILE" 2>&1
  sudo dscl . -create "/Users/${TEMP_USER}" IsHidden 1 >>"$LOG_FILE" 2>&1
  sudo dscl . -passwd "/Users/${TEMP_USER}" "$pass" >>"$LOG_FILE" 2>&1 || true
  sudo mkdir -p "$TEMP_HOME/Library" "$TEMP_HOME/tmp" >>"$LOG_FILE" 2>&1
  sudo chown -R "${TEMP_UID}:20" "$TEMP_HOME" >>"$LOG_FILE" 2>&1
  sudo chmod 755 "$TEMP_HOME" >>"$LOG_FILE" 2>&1
  log "Temporary user home: $TEMP_HOME"
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

remove_park_dir() {
  if [[ -d "$PARK_DIR" ]]; then
    rm -rf "$PARK_DIR" >>"$LOG_FILE" 2>&1 || warn "Could not remove $PARK_DIR"
  fi
  rmdir "$HOME/.zwtf_identity_park" >>"$LOG_FILE" 2>&1 || true
}

cleanup() {
  local status=$?
  if [[ "$CLEANED_UP" -eq 1 ]]; then
    return 0
  fi
  CLEANED_UP=1
  kill_sudo_keepalive
  stop_zoom || true
  unpark_personal_zoom_files
  unpark_zoom_keychain
  delete_temp_user
  remove_park_dir
  log "Cleanup finished. Personal Zoom identity should be restored."
  return "$status"
}

wait_for_zoom_start() {
  local i
  for i in $(seq 1 20); do
    sleep 1
    if zoom_is_running; then
      log "Zoom is running as $(zoom_process_owner || echo unknown)."
      return 0
    fi
  done
  return 1
}

wait_for_zoom_quit() {
  echo
  echo "Zoom should now be logged out of your personal/gamer account."
  echo "Sign in with the church account for this session."
  echo "Leave this Terminal window open. When you quit Zoom, your gamer"
  echo "Zoom login is restored and the temporary user is deleted."
  echo
  log "Waiting for Zoom to quit..."
  while zoom_is_running; do
    sudo -n true >>"$LOG_FILE" 2>&1 || true
    sleep 2
  done
  sleep 1
  log "Zoom has quit."
}

launch_isolated_zoom() {
  local zoom_app="$1"
  local owner

  log "Trying to open Zoom as temporary user ${TEMP_USER}..."
  if sudo -u "$TEMP_USER" -H /usr/bin/open -na "$zoom_app" >>"$LOG_FILE" 2>&1; then
    if wait_for_zoom_start; then
      owner="$(zoom_process_owner || true)"
      if [[ "$owner" == "$TEMP_USER" ]]; then
        log "Zoom is running as the temporary user."
        return 0
      fi
      log "open-as-temp-user started Zoom as ${owner:-unknown}; keeping the parked personal identity."
      return 0
    fi
  fi

  log "Opening Zoom through Launch Services in the desktop session (personal Zoom files still parked)."
  if run_open_as_console -na "$zoom_app" \
    || run_open_as_console -na "Zoom Workplace" \
    || run_open_as_console -na "zoom.us" \
    || run_open_as_console -na "Zoom"; then
    if wait_for_zoom_start; then
      return 0
    fi
  fi
  return 1
}

main() {
  check_platform
  mkdir -p "$(dirname "$LOG_FILE")"
  : > "$LOG_FILE"

  echo "===================================="
  echo " ZOOM GUEST SESSION FOR MAC "
  echo "===================================="
  echo
  echo "This hides your personal/gamer Zoom login, opens Zoom logged out,"
  echo "and puts your personal Zoom back when you quit."
  echo

  log "Script started: $SCRIPT_NAME v$SCRIPT_VERSION"
  log "macOS user: $USER"
  log "Console GUI user: $(get_console_user)"
  log "Log file: $LOG_FILE"
  log "Park directory: $PARK_DIR"

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
  mkdir -p "$PARK_DIR"
  chmod 700 "$PARK_DIR"
  park_personal_zoom_files
  park_zoom_keychain

  if personal_zoom_still_visible; then
    echo "Could not fully hide personal Zoom data. Refusing to launch."
    echo "Log: $LOG_FILE"
    exit 1
  fi
  log "Personal Zoom identity is parked and hidden from this session."

  create_temp_user

  if ! launch_isolated_zoom "$zoom_app"; then
    echo "Zoom did not stay running."
    echo "Log: $LOG_FILE"
    exit 1
  fi

  wait_for_zoom_quit
  echo
  echo "Done. Personal Zoom login restored. Temporary user removed."
  echo "Log: $LOG_FILE"
  log "Script finished."
}

main "$@"
