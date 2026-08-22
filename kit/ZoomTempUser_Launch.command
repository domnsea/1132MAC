#!/usr/bin/env bash
# ZoomTempUser_Launch.command
# Guest Zoom session on THIS Mac account that cannot see the personal/gamer
# Zoom login or screen name.
#
# Why earlier attempts failed:
#   /usr/bin/open always starts Zoom as this account with this account's
#   home, Keychain, and Full Name. Zoom then auto-loads zoomus.enc.db and
#   "Zoom Safe Meeting Storage" and shows the gamer screen name.
#
# This script:
#   1. Quits Zoom
#   2. Parks personal Zoom files (including zoomus.enc.db)
#   3. Parks Zoom Keychain items (including Zoom Safe Meeting Storage)
#   4. Sets this session's macOS Full Name to GUEST_DISPLAY_NAME
#   5. Starts Zoom with sandbox-exec on the Zoom binary from this Terminal
#      (same UID + Aqua, so a window can appear; personal files denied)
#   6. On quit, restores Full Name, files, and Keychain
#
# Edit the guest screen name here if you want something other than Guest:

GUEST_DISPLAY_NAME="Guest"

set -u -o pipefail

SCRIPT_NAME="ZoomTempUser_Launch.command"
SCRIPT_VERSION="2.0.0"
LOG_FILE="$HOME/Desktop/ZoomTempUser_$(date +%Y%m%d_%H%M%S).log"
RUN_ID="$(date +%Y%m%d%H%M%S)"
PARK_DIR="$HOME/.zwtf_identity_park/${RUN_ID}"
NAME_BACKUP_FILE="$HOME/Desktop/ZWTF_NAME_BACKUP.txt"

HAVE_SUDO=0
SUDO_KEEPALIVE_PID=""
CLEANED_UP=0
KEYCHAIN_PARKED=0
REALNAME_SAVED=0
ORIGINAL_REALNAME=""
CONSOLE_USER=""
ZOOM_BIN=""
SANDBOX_PID=""

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

die() {
  echo "$*"
  echo "Log: $LOG_FILE"
  exit 1
}

check_platform() {
  [[ "$(uname -s)" == "Darwin" ]] || die "This script is for macOS only."
}

get_console_user() {
  stat -f '%Su' /dev/console 2>/dev/null || true
}

gui_login_available() {
  local u
  u="$(get_console_user)"
  [[ -n "$u" && "$u" != "root" && "$u" != "loginwindow" ]]
}

prompt_sudo() {
  HAVE_SUDO=0
  if [[ "$EUID" -eq 0 ]]; then
    HAVE_SUDO=1
    CONSOLE_USER="$(get_console_user)"
    log "Running as root; console user is $CONSOLE_USER"
    return 0
  fi
  CONSOLE_USER="$USER"
  echo "macOS will ask for your password to change the session display name and restore it later."
  if sudo -v; then
    HAVE_SUDO=1
    log "Admin rights granted."
    return 0
  fi
  die "Admin rights are required."
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

find_zoom_bin() {
  local app
  for app in \
    "/Applications/zoom.us.app" \
    "/Applications/Zoom Workplace.app" \
    "/Applications/Zoom.app" \
    "$HOME/Applications/zoom.us.app" \
    "$HOME/Applications/Zoom Workplace.app"
  do
    if [[ -x "$app/Contents/MacOS/zoom.us" ]]; then
      printf '%s\n' "$app/Contents/MacOS/zoom.us"
      return 0
    fi
  done
  return 1
}

zoom_is_running() {
  pgrep -x "zoom.us" >/dev/null 2>&1 && return 0
  pgrep -x "CptHost" >/dev/null 2>&1 && return 0
  pgrep -x "caphost" >/dev/null 2>&1 && return 0
  return 1
}

stop_zoom() {
  log "Stopping Zoom..."
  run_quiet osascript -e 'tell application "zoom.us" to quit' || true
  run_quiet osascript -e 'tell application "Zoom Workplace" to quit' || true
  run_quiet osascript -e 'tell application "Zoom" to quit' || true
  run_quiet killall "zoom.us" || true
  run_quiet killall "CptHost" || true
  run_quiet killall "caphost" || true
  run_quiet killall "zAutoUpdate" || true
  run_quiet killall "ZoomOpener" || true
  local i
  for i in $(seq 1 20); do
    if ! zoom_is_running; then
      log "Zoom is not running."
      return 0
    fi
    sleep 0.5
  done
  run_quiet killall -9 "zoom.us" || true
  run_quiet killall -9 "CptHost" || true
  sleep 1
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
    "$base/Library/LaunchAgents"
  do
    [[ -d "$dir" ]] || continue
    find "$dir" -maxdepth 1 \( -iname '*zoom*' -o -iname 'us.zoom*' \) 2>/dev/null
  done
  [[ -e "$base/.zoomus" ]] && printf '%s\n' "$base/.zoomus"
  [[ -e "$base/Documents/Zoom" ]] && printf '%s\n' "$base/Documents/Zoom"
}

park_personal_zoom_files() {
  local src n=0
  mkdir -p "$PARK_DIR/items"
  : > "$PARK_DIR/manifest.txt"
  log "Parking personal Zoom files..."
  while IFS= read -r src; do
    [[ -e "$src" || -L "$src" ]] || continue
    case "$src" in
      "$PARK_DIR"*) continue ;;
      "$HOME/.zwtf_guest_home"*) continue ;;
    esac
    n=$((n + 1))
    mv "$src" "$PARK_DIR/items/$n" >>"$LOG_FILE" 2>&1 && {
      printf '%s\t%s\n' "$n" "$src" >> "$PARK_DIR/manifest.txt"
      log "Parked: $src"
    } || warn "Could not park: $src"
  done < <(list_zoom_identity_paths "$HOME")
  HOME="$HOME" defaults delete us.zoom.xos >>"$LOG_FILE" 2>&1 || true
  HOME="$HOME" defaults delete ZoomChat >>"$LOG_FILE" 2>&1 || true
  run_quiet killall -u "$CONSOLE_USER" cfprefsd || true
  sleep 1
}

discard_session_zoom_files() {
  local p
  while IFS= read -r p; do
    [[ -e "$p" || -L "$p" ]] || continue
    case "$p" in
      "$PARK_DIR"*) continue ;;
    esac
    rm -rf "$p" >>"$LOG_FILE" 2>&1 && log "Removed guest-session file: $p"
  done < <(list_zoom_identity_paths "$HOME")
}

unpark_personal_zoom_files() {
  local n src
  discard_session_zoom_files
  [[ -f "$PARK_DIR/manifest.txt" ]] || return 0
  log "Restoring personal Zoom files..."
  while IFS=$'\t' read -r n src; do
    [[ -n "$n" && -n "$src" ]] || continue
    mkdir -p "$(dirname "$src")"
    rm -rf "$src" >>"$LOG_FILE" 2>&1 || true
    if [[ -e "$PARK_DIR/items/$n" || -L "$PARK_DIR/items/$n" ]]; then
      mv "$PARK_DIR/items/$n" "$src" >>"$LOG_FILE" 2>&1 && log "Restored: $src" || warn "Could not restore: $src"
    fi
  done < "$PARK_DIR/manifest.txt"
  run_quiet killall -u "$CONSOLE_USER" cfprefsd || true
}

write_keychain_helper() {
  cat > "$PARK_DIR/zoom_keychain.py" <<'PY'
#!/usr/bin/env python3
import json, os, re, subprocess, sys

ZOOM_RE = re.compile(r"zoom", re.I)
LABELS = [
    "Zoom Safe Meeting Storage",
    "Zoom Meeting Storage",
    "Zoom",
    "us.zoom.xos",
    "zoom.us",
    "ZoomChat",
]


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def keychains():
    r = run(["security", "list-keychains", "-d", "user"])
    paths = re.findall(r'"([^"]+)"', r.stdout)
    return paths or [None]


def parse_records(text, keychain):
    records = []
    cur = {"keychain": keychain}
    for line in text.splitlines():
        if line.startswith("class:"):
            if len(cur) > 1:
                records.append(cur)
            cur = {"keychain": keychain, "class": re.search(r'"([^"]+)"', line).group(1) if re.search(r'"([^"]+)"', line) else "genp"}
            continue
        m = re.search(r'"(acct|svce|labl|desc|srvr)"\s*<blob>=(?:<NULL>|"((?:\\.|[^"\\])*)")', line)
        if m:
            cur[m.group(1)] = (m.group(2) or "").replace('\\"', '"')
    if len(cur) > 1:
        records.append(cur)
    return records


def is_zoom(rec):
    blob = " ".join(rec.get(k, "") for k in ("acct", "svce", "labl", "desc", "srvr"))
    if ZOOM_RE.search(blob):
        return True
    return rec.get("labl", "") in LABELS


def find_cmd(rec, with_password=False):
    if rec.get("class") == "inet":
        cmd = ["security", "find-internet-password"]
    else:
        cmd = ["security", "find-generic-password"]
    if rec.get("keychain"):
        cmd += ["-k", rec["keychain"]]
    if rec.get("svce"):
        cmd += ["-s", rec["svce"]]
    if rec.get("acct"):
        cmd += ["-a", rec["acct"]]
    if rec.get("labl"):
        cmd += ["-l", rec["labl"]]
    if with_password:
        cmd += ["-w"]
    return cmd


def delete_cmd(rec):
    if rec.get("class") == "inet":
        cmd = ["security", "delete-internet-password"]
    else:
        cmd = ["security", "delete-generic-password"]
    if rec.get("keychain"):
        cmd += ["-k", rec["keychain"]]
    if rec.get("svce"):
        cmd += ["-s", rec["svce"]]
    if rec.get("acct"):
        cmd += ["-a", rec["acct"]]
    if rec.get("labl"):
        cmd += ["-l", rec["labl"]]
    return cmd


def dump_all():
    records = []
    for kc in keychains():
        cmd = ["security", "dump-keychain"]
        if kc:
            cmd.append(kc)
        r = run(cmd)
        records.extend(parse_records(r.stdout + "\n" + r.stderr, kc))
    return records


def cmd_save(path):
    saved = []
    seen = set()
    for rec in dump_all():
        if not is_zoom(rec):
            continue
        key = (rec.get("class"), rec.get("svce"), rec.get("acct"), rec.get("labl"), rec.get("keychain"))
        if key in seen:
            continue
        seen.add(key)
        pw = run(find_cmd(rec, True))
        rec["password"] = pw.stdout.rstrip("\n") if pw.returncode == 0 else None
        saved.append(rec)
        run(delete_cmd(rec))
    for label in LABELS:
        for kc in keychains():
            cmd = ["security", "delete-generic-password", "-l", label]
            if kc:
                cmd += ["-k", kc]
            while run(cmd).returncode == 0:
                pass
    leftover = [rec for rec in dump_all() if is_zoom(rec)]
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(saved, fh)
        fh.write("\n")
    os.chmod(path, 0o600)
    if leftover:
        print("LEFTOVER %d" % len(leftover), file=sys.stderr)
        return 2
    print("SAVED %d" % len(saved))
    return 0


def cmd_restore(path):
    if not os.path.isfile(path):
        print("NOFILE")
        return 0
    for rec in dump_all():
        if is_zoom(rec):
            run(delete_cmd(rec))
    with open(path, encoding="utf-8") as fh:
        saved = json.load(fh)
    n = 0
    for rec in saved:
        pw = rec.get("password")
        if pw is None:
            continue
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
        if run(cmd).returncode == 0:
            n += 1
    print("RESTORED %d" % n)
    return 0


def cmd_count():
    print(sum(1 for rec in dump_all() if is_zoom(rec)))
    return 0


if __name__ == "__main__":
    op = sys.argv[1]
    if op == "save":
        raise SystemExit(cmd_save(sys.argv[2]))
    if op == "restore":
        raise SystemExit(cmd_restore(sys.argv[2]))
    if op == "count":
        raise SystemExit(cmd_count())
    raise SystemExit(1)
PY
  chmod 700 "$PARK_DIR/zoom_keychain.py"
}

park_zoom_keychain() {
  write_keychain_helper
  echo
  echo "If Keychain Access asks permission, click Allow."
  echo "That is required to hide your gamer Zoom login."
  echo
  log "Parking Zoom Keychain items, including Zoom Safe Meeting Storage..."
  if ! python3 "$PARK_DIR/zoom_keychain.py" save "$PARK_DIR/zoom_keychain.json" >>"$LOG_FILE" 2>&1; then
    die "Could not hide Zoom saved logins in Keychain. Refusing to launch."
  fi
  KEYCHAIN_PARKED=1
}

unpark_zoom_keychain() {
  [[ "$KEYCHAIN_PARKED" -eq 1 && -f "$PARK_DIR/zoom_keychain.json" ]] || return 0
  log "Restoring Zoom Keychain items..."
  python3 "$PARK_DIR/zoom_keychain.py" restore "$PARK_DIR/zoom_keychain.json" >>"$LOG_FILE" 2>&1 \
    || warn "Could not restore every Zoom Keychain item. You may need to sign in to your personal Zoom account again."
}

identity_still_visible() {
  local p count
  if [[ -e "$HOME/Library/Application Support/zoom.us/data/zoomus.enc.db" ]]; then
    return 0
  fi
  if [[ -e "$HOME/Library/Preferences/us.zoom.xos.plist" ]]; then
    return 0
  fi
  while IFS= read -r p; do
    [[ -e "$p" || -L "$p" ]] || continue
    case "$p" in
      "$PARK_DIR"*) continue ;;
    esac
    return 0
  done < <(list_zoom_identity_paths "$HOME")
  count="$(python3 "$PARK_DIR/zoom_keychain.py" count 2>/dev/null || echo 1)"
  [[ "$count" == "0" ]] || return 0
  return 1
}

read_realname() {
  local raw
  raw="$(dscl . -read "/Users/${CONSOLE_USER}" RealName 2>/dev/null || true)"
  printf '%s\n' "$raw" | awk 'NR==1 { sub(/^RealName:[[:space:]]*/, ""); if ($0 != "") print; next } { print }' | sed '/^$/d'
}

set_guest_display_name() {
  ORIGINAL_REALNAME="$(read_realname)"
  if [[ -z "$ORIGINAL_REALNAME" ]]; then
    ORIGINAL_REALNAME="$(id -F 2>/dev/null || true)"
  fi
  printf '%s\n' "$ORIGINAL_REALNAME" > "$PARK_DIR/original_realname.txt"
  printf '%s\n' "$ORIGINAL_REALNAME" > "$NAME_BACKUP_FILE"
  chmod 600 "$NAME_BACKUP_FILE" >>"$LOG_FILE" 2>&1 || true
  log "Saved macOS Full Name; setting session name to: $GUEST_DISPLAY_NAME"
  sudo dscl . -create "/Users/${CONSOLE_USER}" RealName "$GUEST_DISPLAY_NAME" >>"$LOG_FILE" 2>&1 \
    || die "Could not set the guest display name."
  REALNAME_SAVED=1
  run_quiet dscacheutil -flushcache || true
}

restore_display_name() {
  local name=""
  [[ "$REALNAME_SAVED" -eq 1 ]] || return 0
  if [[ -f "$PARK_DIR/original_realname.txt" ]]; then
    name="$(cat "$PARK_DIR/original_realname.txt")"
  else
    name="$ORIGINAL_REALNAME"
  fi
  [[ -n "$name" ]] || return 0
  log "Restoring macOS Full Name."
  sudo dscl . -create "/Users/${CONSOLE_USER}" RealName "$name" >>"$LOG_FILE" 2>&1 \
    || warn "Could not restore Full Name. Backup is on your Desktop: $NAME_BACKUP_FILE"
  run_quiet dscacheutil -flushcache || true
  rm -f "$NAME_BACKUP_FILE" >>"$LOG_FILE" 2>&1 || true
}

write_sandbox_profile() {
  cat > "$PARK_DIR/zoom.sb" <<EOF
(version 1)
(allow default)
(allow device-camera)
(allow device-microphone)
(allow mach-lookup)
(deny file-read* file-write*
  (subpath "$PARK_DIR")
)
EOF
}

launch_guest_zoom() {
  local guest_home="$HOME/.zwtf_guest_home"
  mkdir -p "$guest_home/tmp" "$guest_home/Library"
  write_sandbox_profile
  log "Starting Zoom with sandbox-exec (not open). Guest screen name: $GUEST_DISPLAY_NAME"
  (
    export HOME="$guest_home"
    export TMPDIR="$guest_home/tmp"
    exec /usr/bin/sandbox-exec -f "$PARK_DIR/zoom.sb" "$ZOOM_BIN"
  ) >>"$LOG_FILE" 2>&1 &
  SANDBOX_PID=$!
  log "Zoom guest process pid $SANDBOX_PID"
}

wait_for_zoom_start() {
  local i
  for i in $(seq 1 25); do
    sleep 1
    if zoom_is_running; then
      log "Zoom is running."
      return 0
    fi
    if [[ -n "$SANDBOX_PID" ]] && ! kill -0 "$SANDBOX_PID" 2>/dev/null; then
      break
    fi
  done
  return 1
}

wait_for_zoom_quit() {
  echo
  echo "Zoom is in a guest session. Screen name for this session: $GUEST_DISPLAY_NAME"
  echo "Sign in with the church account if you need that account."
  echo "Leave this Terminal window open until you quit Zoom."
  echo
  log "Waiting for Zoom to quit..."
  while zoom_is_running || { [[ -n "$SANDBOX_PID" ]] && kill -0 "$SANDBOX_PID" 2>/dev/null; }; do
    sudo -n true >>"$LOG_FILE" 2>&1 || true
    sleep 2
  done
  sleep 1
  log "Zoom has quit."
}

remove_park_dir() {
  rm -rf "$HOME/.zwtf_guest_home" >>"$LOG_FILE" 2>&1 || true
  if [[ -d "$PARK_DIR" ]]; then
    rm -rf "$PARK_DIR" >>"$LOG_FILE" 2>&1 || true
  fi
  rmdir "$HOME/.zwtf_identity_park" >>"$LOG_FILE" 2>&1 || true
}

cleanup() {
  local status=$?
  [[ "$CLEANED_UP" -eq 1 ]] && return 0
  CLEANED_UP=1
  kill_sudo_keepalive
  stop_zoom || true
  restore_display_name
  unpark_personal_zoom_files
  unpark_zoom_keychain
  remove_park_dir
  log "Cleanup finished. Personal Zoom identity restored."
  return "$status"
}

main() {
  check_platform
  mkdir -p "$(dirname "$LOG_FILE")"
  : > "$LOG_FILE"

  echo "===================================="
  echo " ZOOM GUEST SESSION "
  echo "===================================="
  echo
  echo "This hides your personal/gamer Zoom login and screen name."
  echo "This session's screen name will be: $GUEST_DISPLAY_NAME"
  echo

  log "Script started: $SCRIPT_NAME v$SCRIPT_VERSION"
  log "Log file: $LOG_FILE"

  gui_login_available || die "Run this from the Mac desktop, not SSH."
  prompt_sudo
  keep_sudo_alive &
  SUDO_KEEPALIVE_PID=$!
  trap 'cleanup' EXIT INT TERM

  ZOOM_BIN="$(find_zoom_bin || true)"
  [[ -n "$ZOOM_BIN" ]] || die "Zoom is not installed."
  log "Zoom binary: $ZOOM_BIN"

  stop_zoom
  mkdir -p "$PARK_DIR"
  chmod 700 "$PARK_DIR"
  park_personal_zoom_files
  park_zoom_keychain
  if identity_still_visible; then
    die "Personal Zoom identity is still visible. Refusing to launch."
  fi
  log "Personal Zoom files and Keychain logins are hidden."
  set_guest_display_name
  launch_guest_zoom
  if ! wait_for_zoom_start; then
    die "Zoom did not stay running. See the log."
  fi
  wait_for_zoom_quit
  echo
  echo "Done. Personal Zoom login and name restored."
  echo "Log: $LOG_FILE"
  log "Script finished."
}

main "$@"
