#!/bin/bash
# ChurchGuestZoom — BUILD 2026-08-23-L
# Double-clickable guest Zoom session that cannot load the personal/gamer login.
#
# Hang / "did nothing" bugs removed vs build E:
#   - Dialog is the first action (proof of life even if later steps fail)
#   - No python3 (Monterey often has none; that made E exit with no window)
#   - No sudo -v (hangs with no password prompt when not in a real TTY)
#   - No osascript "tell application zoom.us to quit" (AppleEvent hangs on
#     the stuck End Meeting dialog for minutes or forever)
#   - No recursive find of all of ~/Library
#   - No security dump-keychain
#   - Wait-for-quit watches zoom.us only, not leftover CptHost helpers
#   - Keychain park is best-effort: a Deny/timeout must not abort guest Zoom
#
# Launch path: exec the Zoom binary as THIS Aqua user. Not open.
# Not launchctl bsexec as another UID (that crashes in _RegisterApplication).
# Not sandbox-exec: seatbelt + a fake HOME made Zoom report no microphones
# (VB-Cable and the built-in mic both disappeared). Parked identity is
# chmod 000 so Zoom cannot read the Keychain backup without a sandbox.

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"

# ---------------------------------------------------------------------------
# Proof of life FIRST — before set -u, sudo, find, python, or Zoom AppleEvents.
# giving up after unhangs if the dialog is never clicked.
# ---------------------------------------------------------------------------
/usr/bin/osascript >/dev/null 2>&1 <<'OSA' || true
display dialog "Church Guest Zoom is starting.

1. Quit 1132wtf-v94 if it is open.
2. Click Continue.
3. Enter your Mac password if asked.
4. Click Allow if Keychain asks.

This session uses a random 6-digit Zoom name.
Your gamer Zoom comes back when you quit Zoom.
VB-Cable / microphone should appear in Zoom Audio.

If nothing else appears, look on the Desktop for ChurchGuestZoom-log.txt" buttons {"Continue"} default button 1 with title "Church Guest Zoom" giving up after 120
OSA

set -u -o pipefail

SCRIPT_NAME="ChurchGuestZoom"
SCRIPT_VERSION="2026-08-23-L"
GUEST_DISPLAY_NAME=""
LOG_FILE="$HOME/Desktop/ChurchGuestZoom-log.txt"
RUN_ID="$(date +%Y%m%d%H%M%S)"
PARK_DIR="$HOME/.zwtf_identity_park/${RUN_ID}"
NAME_BACKUP_FILE="$HOME/Desktop/ZWTF_NAME_BACKUP.txt"
GUEST_HOME="$HOME/.zwtf_guest_home"

CLEANED_UP=0
FILES_PARKED=0
KEYCHAIN_PARKED=0
REALNAME_SAVED=0
COMPUTERNAME_SAVED=0
ORIGINAL_REALNAME=""
ORIGINAL_COMPUTERNAME=""
CONSOLE_USER=""
ZOOM_BIN=""
SANDBOX_PID=""

ZOOM_KC_LABELS="Zoom Safe Meeting Storage
Zoom Meeting Storage
Zoom
us.zoom.xos
zoom.us
ZoomChat
ZoomAutoLogin
Zoom Meeting"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

append_log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

log() {
  append_log "$*"
}

warn() {
  log "WARNING: $*"
}

quote_as() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

osascript_dialog() {
  local msg="$1"
  local btn="${2:-OK}"
  local timeout="${3:-60}"
  local q
  q="$(quote_as "$msg")"
  /usr/bin/osascript >/dev/null 2>&1 -e "display dialog \"$q\" buttons {\"$btn\"} default button 1 with title \"Church Guest Zoom\" giving up after $timeout" || true
}

osascript_error() {
  local msg="$1"
  local q
  q="$(quote_as "$msg")"
  /usr/bin/osascript >/dev/null 2>&1 -e "display dialog \"$q\" buttons {\"OK\"} default button 1 with title \"Church Guest Zoom\" with icon stop giving up after 120" || true
}

die() {
  log "ERROR: $*"
  osascript_error "Church Guest Zoom failed:

$*

Log: $LOG_FILE"
  exit 1
}

# Time-bound a command so Keychain / security never hang the session.
run_with_timeout() {
  local sec="$1"
  shift
  "$@" &
  local pid=$!
  local n=0
  while kill -0 "$pid" 2>/dev/null; do
    n=$((n + 1))
    if [[ "$n" -ge "$sec" ]]; then
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
  done
  wait "$pid"
  return $?
}

run_admin() {
  local f="$1"
  if [[ "$(id -u)" -eq 0 ]]; then
    /bin/bash "$f"
    return $?
  fi
  /usr/bin/osascript <<OSA
do shell script ("/bin/bash " & quoted form of "$f") with administrator privileges
OSA
}

generate_guest_name() {
  local raw
  raw="$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d ' \n')"
  if [[ -z "$raw" ]]; then
    raw="$(date +%s)"
  fi
  GUEST_DISPLAY_NAME="$(awk -v r="$raw" 'BEGIN { printf "%06d", 100000 + (r % 900000) }')"
  if [[ ${#GUEST_DISPLAY_NAME} -ne 6 ]]; then
    GUEST_DISPLAY_NAME="$(printf '%06d' $((100000 + RANDOM % 900000)))"
  fi
}

get_console_user() {
  stat -f '%Su' /dev/console 2>/dev/null || printf '%s\n' "${USER:-}"
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

# Only zoom.us. Do not treat leftover CptHost as "Zoom still running"
# or wait-for-quit hangs after the window is gone.
zoom_is_running() {
  pgrep -x "zoom.us" >/dev/null 2>&1
}

# Force-kill only. AppleEvent quit hangs on the stuck End Meeting dialog.
stop_zoom() {
  log "Force-quitting Zoom and 1132wtf-v94 (no AppleEvent quit)..."
  local round i proc
  for round in 1 2 3; do
    pkill -9 -f '/usr/local/libexec/1132wtf-v94/' >/dev/null 2>&1 || true
    pkill -9 -f 'root_launch_temp_zoom' >/dev/null 2>&1 || true
    pkill -9 -f '1132wtf' >/dev/null 2>&1 || true
    for proc in zoom.us CptHost caphost aomhost aomhost64 zAutoUpdate ZoomOpener zCrashReport zTscoder ZoomUpdater; do
      killall -9 "$proc" >/dev/null 2>&1 || true
    done
    pkill -9 -f '/Applications/zoom.us.app/' >/dev/null 2>&1 || true
    pkill -9 -f '/Applications/Zoom Workplace.app/' >/dev/null 2>&1 || true
    pkill -9 -f '/Applications/Zoom.app/' >/dev/null 2>&1 || true
    for i in 1 2 3 4 5 6; do
      if ! zoom_is_running; then
        log "Zoom is not running."
        return 0
      fi
      sleep 0.5
    done
  done
  warn "zoom.us still present after kill -9"
  return 1
}

list_zoom_identity_paths() {
  local base="$1"
  local p dir
  for p in \
    "$base/Library/Application Support/zoom.us" \
    "$base/Library/Application Support/Zoom" \
    "$base/Library/Caches/us.zoom.xos" \
    "$base/Library/Caches/Zoom" \
    "$base/Library/Logs/zoom.us" \
    "$base/Library/Logs/Zoom" \
    "$base/Library/HTTPStorages/us.zoom.xos" \
    "$base/Library/WebKit/us.zoom.xos" \
    "$base/Library/Saved Application State/us.zoom.xos.savedState" \
    "$base/Library/Preferences/us.zoom.xos.plist" \
    "$base/Library/Preferences/ZoomChat.plist" \
    "$base/Library/Preferences/us.zoom.ZoomAutoUpdater.plist" \
    "$base/Library/Preferences/us.zoom.ZoomClips.plist" \
    "$base/Library/Cookies/us.zoom.xos.binarycookies" \
    "$base/Library/Group Containers/BJ4HAAB9B3.ZoomClient3rd" \
    "$base/Library/Group Containers/us.zoom.xos" \
    "$base/Library/Containers/us.zoom.xos" \
    "$base/Library/Application Scripts/us.zoom.xos" \
    "$base/Library/LaunchAgents/us.zoom.xos.plist" \
    "$base/Library/Internet Plug-Ins/ZoomUsPlugIn.plugin" \
    "$base/.zoomus" \
    "$base/Documents/Zoom"
  do
    [[ -e "$p" || -L "$p" ]] && printf '%s\n' "$p"
  done
  # Bounded finds only — never walk all of ~/Library.
  for dir in \
    "$base/Library/Application Support" \
    "$base/Library/Preferences" \
    "$base/Library/Preferences/ByHost" \
    "$base/Library/Caches" \
    "$base/Library/Group Containers" \
    "$base/Library/Containers" \
    "$base/Library/Logs" \
    "$base/Library/HTTPStorages"
  do
    [[ -d "$dir" ]] || continue
    find "$dir" -maxdepth 2 \( -iname '*zoom*' -o -iname 'us.zoom*' \) 2>/dev/null
  done
  for dir in \
    "$base/Library/Application Support/zoom.us" \
    "$base/Library/Application Support/Zoom" \
    "$base/Library/Group Containers"
  do
    [[ -d "$dir" ]] || continue
    find "$dir" -maxdepth 6 \( -iname 'zoomus.enc.db*' -o -iname 'zoommeeting.enc.db*' \) 2>/dev/null
  done
}

park_personal_zoom_files() {
  local src n=0 seen=""
  mkdir -p "$PARK_DIR/items"
  : > "$PARK_DIR/manifest.txt"
  log "Parking personal Zoom files..."
  while IFS= read -r src; do
    [[ -e "$src" || -L "$src" ]] || continue
    case "$src" in
      "$PARK_DIR"*) continue ;;
      "$HOME/.zwtf_guest_home"*) continue ;;
      "$HOME/.zwtf_identity_park"*) continue ;;
    esac
    case "$seen" in
      *"|$src|"*) continue ;;
    esac
    seen="${seen}|$src|"
    n=$((n + 1))
    if mv "$src" "$PARK_DIR/items/$n" >>"$LOG_FILE" 2>&1; then
      printf '%s\t%s\n' "$n" "$src" >> "$PARK_DIR/manifest.txt"
      log "Parked: $src"
    else
      warn "Could not park: $src"
    fi
  done < <(list_zoom_identity_paths "$HOME")
  defaults delete us.zoom.xos >>"$LOG_FILE" 2>&1 || true
  defaults delete ZoomChat >>"$LOG_FILE" 2>&1 || true
  if [[ -n "$CONSOLE_USER" ]]; then
    killall -u "$CONSOLE_USER" cfprefsd >/dev/null 2>&1 || true
  fi
  sleep 1
  FILES_PARKED=1
}

unpark_personal_zoom_files() {
  local park="${1:-}"
  local n src failed=0
  if [[ -z "$park" ]]; then
    [[ "$FILES_PARKED" -eq 1 ]] || return 0
    park="$PARK_DIR"
  fi
  [[ -f "$park/manifest.txt" ]] || return 0
  log "Restoring personal Zoom files from $park ..."
  while IFS=$'\t' read -r n src; do
    [[ -n "$n" && -n "$src" ]] || continue
    if [[ -e "$park/items/$n" || -L "$park/items/$n" ]]; then
      mkdir -p "$(dirname "$src")"
      rm -rf "$src" >>"$LOG_FILE" 2>&1 || true
      if mv "$park/items/$n" "$src" >>"$LOG_FILE" 2>&1; then
        log "Restored: $src"
      else
        warn "Could not restore: $src"
        failed=1
      fi
    elif [[ ! -e "$src" && ! -L "$src" ]]; then
      warn "Parked item $n is gone and $src is missing."
      failed=1
    fi
  done < "$park/manifest.txt"
  if [[ "$failed" -ne 0 ]]; then
    return 1
  fi
  # Guest-session leftovers only after every parked file is back.
  while IFS= read -r src; do
    [[ -e "$src" || -L "$src" ]] || continue
    case "$src" in
      "$park"*) continue ;;
      "$HOME/.zwtf_identity_park"*) continue ;;
    esac
    if awk -F '\t' -v s="$src" '$2==s { found=1 } END { exit !found }' "$park/manifest.txt" 2>/dev/null; then
      continue
    fi
    rm -rf "$src" >>"$LOG_FILE" 2>&1 && log "Removed guest-session file: $src"
  done < <(list_zoom_identity_paths "$HOME")
  if [[ -n "${CONSOLE_USER:-}" ]]; then
    killall -u "$CONSOLE_USER" cfprefsd >/dev/null 2>&1 || true
  fi
  return 0
}

kc_field() {
  local blob="$1"
  local key="$2"
  printf '%s\n' "$blob" | awk -v k="$key" '
    $0 ~ "\"" k "\"" {
      if ($0 ~ /<NULL>/) { print ""; exit }
      n = split($0, a, "\"")
      if (n >= 4) print a[4]
      exit
    }'
}

park_zoom_keychain() {
  local label dump acct svce pass n=0 i
  mkdir -p "$PARK_DIR/kc"
  chmod 700 "$PARK_DIR" "$PARK_DIR/kc" 2>/dev/null || true
  log "Parking Zoom Keychain items, including Zoom Safe Meeting Storage..."
  osascript_dialog "If a Keychain box appears, click Allow.

That saves your gamer Zoom login so it can come back later.

If it does not appear, or you click Deny, guest Zoom still starts.
Personal Zoom files are already hidden." "Continue" 25
  while IFS= read -r label; do
    [[ -n "$label" ]] || continue
    i=0
    while [[ "$i" -lt 6 ]]; do
      dump="$(run_with_timeout 6 /usr/bin/security find-generic-password -l "$label" 2>/dev/null || true)"
      [[ -n "$dump" ]] || break
      acct="$(kc_field "$dump" "acct")"
      svce="$(kc_field "$dump" "svce")"
      pass=""
      if run_with_timeout 8 /usr/bin/security find-generic-password -l "$label" -w >"$PARK_DIR/kc/tmp.pass" 2>/dev/null; then
        pass="$(cat "$PARK_DIR/kc/tmp.pass" 2>/dev/null || true)"
      fi
      rm -f "$PARK_DIR/kc/tmp.pass"
      if [[ -z "$pass" ]]; then
        warn "Could not read Keychain secret for $label; leaving it in place so it can be restored later."
        break
      fi
      n=$((n + 1))
      printf '%s\n' "$label" > "$PARK_DIR/kc/$n.label"
      printf '%s\n' "$acct" > "$PARK_DIR/kc/$n.acct"
      printf '%s\n' "$svce" > "$PARK_DIR/kc/$n.svce"
      printf '%s' "$pass" > "$PARK_DIR/kc/$n.pass"
      chmod 600 "$PARK_DIR/kc/$n.pass" 2>/dev/null || true
      if run_with_timeout 8 /usr/bin/security delete-generic-password -l "$label" >/dev/null 2>&1; then
        log "Parked Keychain item: $label"
      else
        warn "Saved $label but could not delete it from Keychain."
        break
      fi
      i=$((i + 1))
    done
  done <<EOF
$ZOOM_KC_LABELS
EOF
  KEYCHAIN_PARKED=1
  if keychain_zoom_still_present; then
    warn "Keychain would not hide every Zoom login (Allow was denied, timed out, or blocked)."
    osascript_dialog "Keychain did not hide every saved Zoom login.

Guest Zoom will still start. Files are parked.
Your gamer Zoom login was left in Keychain so it is not lost.

Click Continue." "Continue" 20
  else
    log "Zoom Keychain logins are hidden and backed up for restore."
  fi
}

unpark_zoom_keychain() {
  local park="${1:-}"
  local i label acct svce pass
  local -a cmd
  if [[ -z "$park" ]]; then
    [[ "$KEYCHAIN_PARKED" -eq 1 ]] || return 0
    park="$PARK_DIR"
  fi
  log "Restoring Zoom Keychain items from $park ..."
  i=1
  while [[ -f "$park/kc/$i.label" ]]; do
    label="$(cat "$park/kc/$i.label")"
    acct="$(cat "$park/kc/$i.acct" 2>/dev/null || true)"
    svce="$(cat "$park/kc/$i.svce" 2>/dev/null || true)"
    pass=""
    if [[ -f "$park/kc/$i.pass" ]]; then
      pass="$(cat "$park/kc/$i.pass")"
    fi
    if [[ -z "$pass" ]]; then
      # A previous partial restore may have already put this item back.
      if run_with_timeout 6 /usr/bin/security find-generic-password -l "$label" >/dev/null 2>&1; then
        log "Keychain already has $label; continuing remaining items."
        i=$((i + 1))
        continue
      fi
      warn "Keychain backup missing for $label; keeping park dir."
      return 1
    fi
    cmd=(/usr/bin/security add-generic-password -U -l "$label" -w "$pass")
    [[ -n "$acct" ]] && cmd+=(-a "$acct")
    [[ -n "$svce" ]] && cmd+=(-s "$svce")
    if run_with_timeout 8 "${cmd[@]}" >/dev/null 2>&1; then
      log "Restored Keychain item: $label"
    else
      warn "Could not restore Keychain item: $label; keeping park dir."
      return 1
    fi
    i=$((i + 1))
  done
  return 0
}

keychain_zoom_still_present() {
  local label
  while IFS= read -r label; do
    [[ -n "$label" ]] || continue
    if run_with_timeout 6 /usr/bin/security find-generic-password -l "$label" >/dev/null 2>&1; then
      log "Keychain still has: $label"
      return 0
    fi
  done <<EOF
$ZOOM_KC_LABELS
EOF
  return 1
}

identity_still_visible() {
  local p
  if [[ -e "$HOME/Library/Application Support/zoom.us/data/zoomus.enc.db" ]]; then
    log "Identity still visible: zoomus.enc.db"
    return 0
  fi
  if [[ -e "$HOME/Library/Application Support/zoom.us/data/zoommeeting.enc.db" ]]; then
    log "Identity still visible: zoommeeting.enc.db"
    return 0
  fi
  if [[ -e "$HOME/Library/Preferences/us.zoom.xos.plist" ]]; then
    log "Identity still visible: us.zoom.xos.plist"
    return 0
  fi
  while IFS= read -r p; do
    [[ -e "$p" || -L "$p" ]] || continue
    case "$p" in
      "$PARK_DIR"*) continue ;;
      "$HOME/.zwtf_identity_park"*) continue ;;
      "$HOME/.zwtf_guest_home"*) continue ;;
    esac
    log "Identity still visible: $p"
    return 0
  done < <(list_zoom_identity_paths "$HOME")
  # Keychain leftovers do not abort launch. Allow/Deny prompts are unreliable
  # and were aborting sessions after files were already parked.
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
  cat > "$PARK_DIR/set_name.sh" <<EOF
#!/bin/bash
set -e
dscl . -create "/Users/${CONSOLE_USER}" RealName "$GUEST_DISPLAY_NAME"
scutil --set ComputerName "$GUEST_DISPLAY_NAME" || true
dscacheutil -flushcache || true
EOF
  chmod 700 "$PARK_DIR/set_name.sh"
  if run_admin "$PARK_DIR/set_name.sh" >>"$LOG_FILE" 2>&1; then
    REALNAME_SAVED=1
    if [[ -s "$PARK_DIR/original_computername.txt" ]]; then
      COMPUTERNAME_SAVED=1
    fi
  else
    warn "Could not set macOS Full Name (password cancelled?). Continuing with Zoom prefs only."
  fi
}

capture_computername_before_change() {
  ORIGINAL_COMPUTERNAME="$(scutil --get ComputerName 2>/dev/null || true)"
  printf '%s\n' "$ORIGINAL_COMPUTERNAME" > "$PARK_DIR/original_computername.txt"
}

# Owner can chmod a 000 path back; Zoom will not. This replaces sandbox-exec
# so CoreAudio still sees VB-Cable and the built-in mic.
unlock_park_dir() {
  local dir="$1"
  [[ -n "$dir" && -e "$dir" ]] || return 0
  chmod u+rwx "$dir" 2>/dev/null || true
  if [[ -d "$dir" ]]; then
    find "$dir" -exec chmod u+rwX {} + 2>/dev/null || true
  fi
  chmod 700 "$dir" 2>/dev/null || true
  [[ -d "$dir/kc" ]] && chmod 700 "$dir/kc" 2>/dev/null || true
  return 0
}

lock_park_dir() {
  local dir="$1"
  [[ -d "$dir" ]] || return 1
  find "$dir" -type f -exec chmod a-rwx {} + 2>/dev/null || true
  find "$dir" -type d -mindepth 1 -exec chmod a-rwx {} + 2>/dev/null || true
  chmod a-rwx "$dir" 2>/dev/null || true
  log "Locked parked identity at $dir so Zoom can run without sandbox-exec."
}

refresh_coreaudio() {
  log "Restarting CoreAudio so microphones (including VB-Cable) reappear..."
  killall coreaudiod >/dev/null 2>&1 || true
  sleep 2
}

detect_vb_cable_name() {
  local name=""
  name="$(system_profiler SPAudioDataType 2>/dev/null | awk '
    /^[[:space:]]+[^:]+:$/ {
      n=$0
      sub(/^[[:space:]]+/, "", n)
      sub(/:$/, "", n)
    }
    tolower(n) ~ /vb-cable|vbcable|vb-audio|cable output|cable input/ {
      if ($0 ~ /Input Channels/) { print n; exit }
    }
  ')"
  if [[ -z "$name" ]]; then
    name="$(system_profiler SPAudioDataType 2>/dev/null | awk '
      {
        line=$0
        low=tolower($0)
      }
      low ~ /vb-cable|vbcable|vb-audio|cable output/ {
        n=line
        sub(/^[[:space:]]+/, "", n)
        sub(/:$/, "", n)
        print n
        exit
      }
    ')"
  fi
  printf '%s' "$name"
}

log_audio_devices() {
  log "Audio plug-ins in /Library/Audio/Plug-Ins/HAL:"
  ls -1 /Library/Audio/Plug-Ins/HAL 2>/dev/null | while IFS= read -r p; do
    log "  HAL: $p"
  done
  log "Audio devices from system_profiler:"
  system_profiler SPAudioDataType 2>/dev/null | awk '
    /^[[:space:]]+[^:]+:$/ { n=$0; sub(/^[[:space:]]+/, "", n); sub(/:$/, "", n) }
    /Input Channels/ { print "  input: " n }
  ' | while IFS= read -r line; do
    [[ -n "$line" ]] && log "$line"
  done
}

seed_zoom_prefs_into() {
  local root="$1"
  local data="$root/Library/Application Support/zoom.us/data"
  local plist="$root/Library/Preferences/us.zoom.xos"
  local mic_name="${2:-}"
  mkdir -p "$data" "$root/Library/Preferences" "$root/tmp"
  defaults write "$plist" ZoomUserName -string "$GUEST_DISPLAY_NAME"
  defaults write "$plist" UserName -string "$GUEST_DISPLAY_NAME"
  defaults write "$plist" DisplayName -string "$GUEST_DISPLAY_NAME"
  defaults write "$plist" LastUserName -string "$GUEST_DISPLAY_NAME"
  defaults write "$plist" ConfUserName -string "$GUEST_DISPLAY_NAME"
  defaults write "$plist" kZoomUserName -string "$GUEST_DISPLAY_NAME"
  defaults write "$plist" AutoLogin -bool false
  defaults write "$plist" rememberMe -bool false
  defaults write "$plist" AutoSignIn -bool false
  # Computer audio must auto-join or Zoom says there is nothing to connect to.
  defaults write "$plist" zAutoJoinVoip -bool true
  defaults write "$plist" SetUseSystemDefaultMicForVOIP -bool true
  defaults write "$plist" SetUseSystemDefaultSpeakerForVOIP -bool true
  defaults write "$plist" AudioAutoAdjust -bool true
  defaults write "$plist" EnableOriginalSound -bool true
  if [[ -n "$mic_name" ]]; then
    defaults write "$plist" ZoomChat.Audio.MicName -string "$mic_name"
  fi
  printf '%s\n' "[General]" "nRememberAccount=0" > "$data/Zoom.us.ini"
}

seed_guest_zoom_prefs() {
  local mic_name=""
  mic_name="$(detect_vb_cable_name || true)"
  log "Writing guest Zoom name $GUEST_DISPLAY_NAME into a fresh profile (no prior meeting)."
  if [[ -n "$mic_name" ]]; then
    log "Preferring microphone: $mic_name"
  else
    log "No VB-Cable device name found yet; Zoom will use the system default mic after CoreAudio refresh."
  fi
  # Real home: Cocoa Zoom uses NSHomeDirectory(), not a fake HOME.
  seed_zoom_prefs_into "$HOME" "$mic_name"
  seed_zoom_prefs_into "$GUEST_HOME" "$mic_name"
  if [[ -n "$CONSOLE_USER" ]]; then
    killall -u "$CONSOLE_USER" cfprefsd >/dev/null 2>&1 || true
  fi
}

restore_display_name_from() {
  local park="$1"
  local name="" current="" expected_cn="" current_cn=""
  [[ -f "$park/original_realname.txt" ]] || return 0
  name="$(cat "$park/original_realname.txt")"
  [[ -n "$name" ]] || return 0
  log "Restoring macOS Full Name from $park"
  printf '%s\n' "$name" > "$park/restore_realname.txt"
  cat > "$park/restore_name.sh" <<EOF
#!/bin/bash
name=\$(cat "$park/restore_realname.txt")
dscl . -create "/Users/${CONSOLE_USER}" RealName "\$name"
EOF
  if [[ -f "$park/original_computername.txt" ]]; then
    printf 'cname=$(cat "%s")\n' "$park/original_computername.txt" >> "$park/restore_name.sh"
    printf 'if [ -n "$cname" ]; then scutil --set ComputerName "$cname"; fi\n' >> "$park/restore_name.sh"
  fi
  printf 'dscacheutil -flushcache || true\n' >> "$park/restore_name.sh"
  chmod 700 "$park/restore_name.sh"
  if ! run_admin "$park/restore_name.sh" >>"$LOG_FILE" 2>&1; then
    warn "Could not restore Full Name. Backup is on your Desktop: $NAME_BACKUP_FILE"
    return 1
  fi
  current="$(read_realname)"
  if [[ "$current" != "$name" ]]; then
    warn "Full Name is still not restored. Backup is on your Desktop: $NAME_BACKUP_FILE"
    return 1
  fi
  if [[ -f "$park/original_computername.txt" ]]; then
    expected_cn="$(cat "$park/original_computername.txt")"
    current_cn="$(scutil --get ComputerName 2>/dev/null || true)"
    if [[ -n "$expected_cn" && "$current_cn" != "$expected_cn" ]]; then
      warn "ComputerName is still not restored."
      return 1
    fi
  fi
  rm -f "$NAME_BACKUP_FILE" >>"$LOG_FILE" 2>&1 || true
  return 0
}

restore_display_name() {
  restore_display_name_from "$PARK_DIR"
}

restore_leftover_parks() {
  local dir oldest=""
  [[ -d "$HOME/.zwtf_identity_park" ]] || return 0
  # RUN_ID is a timestamp. The oldest leftover is the original gamer identity.
  # Restoring every leftover in a loop would discard the first restore.
  for dir in "$HOME/.zwtf_identity_park"/*; do
    [[ -d "$dir" ]] || continue
    [[ "$dir" == "$PARK_DIR" ]] && continue
    if [[ -z "$oldest" || "$dir" < "$oldest" ]]; then
      oldest="$dir"
    fi
  done
  [[ -n "$oldest" ]] || return 0
  log "Restoring oldest leftover parked Zoom identity from $oldest"
  unlock_park_dir "$oldest" || {
    warn "Could not unlock leftover park $oldest; leaving it in place."
    return 1
  }
  if ! unpark_personal_zoom_files "$oldest"; then
    warn "Leftover file restore failed. Keeping $oldest"
    lock_park_dir "$oldest"
    return 1
  fi
  if ! unpark_zoom_keychain "$oldest"; then
    warn "Leftover Keychain restore failed. Keeping $oldest"
    lock_park_dir "$oldest"
    return 1
  fi
  if ! restore_display_name_from "$oldest"; then
    warn "Leftover display-name restore failed. Keeping $oldest"
    lock_park_dir "$oldest"
    return 1
  fi
  rm -rf "$oldest" >>"$LOG_FILE" 2>&1 || true
  log "Removed leftover park after restore: $oldest"
}

launch_guest_zoom() {
  local zoom_dir
  mkdir -p "$GUEST_HOME/tmp" "$GUEST_HOME/Library"
  lock_park_dir "$PARK_DIR"
  log_audio_devices
  zoom_dir="$(dirname "$ZOOM_BIN")"
  log "Starting Zoom binary (not open, not sandbox-exec). Guest screen name: $GUEST_DISPLAY_NAME"
  (
    cd "$zoom_dir" || exit 1
    unset TMPDIR
    exec "$ZOOM_BIN"
  ) >>"$LOG_FILE" 2>&1 &
  SANDBOX_PID=$!
  log "Zoom guest process pid $SANDBOX_PID"
}

wait_for_zoom_start() {
  local i
  for i in $(seq 1 20); do
    sleep 1
    if zoom_is_running; then
      log "Zoom is running."
      return 0
    fi
    if [[ -n "$SANDBOX_PID" ]] && ! kill -0 "$SANDBOX_PID" 2>/dev/null; then
      log "Zoom process exited before a window appeared."
      break
    fi
  done
  return 1
}

wait_for_zoom_quit() {
  log "Waiting for Zoom to quit..."
  osascript_dialog "Zoom should be open.

Your name this session:
$GUEST_DISPLAY_NAME

Microphone: Zoom → Settings → Audio.
Pick VB-Cable (or CABLE Output). If macOS asks to allow Microphone, click OK.

Leave Church Guest Zoom in the Dock until you quit Zoom.
When Zoom quits, your gamer login is restored.

If Zoom never appeared, click OK and check the Desktop log." "OK" 30
  local waited=0
  while zoom_is_running; do
    sleep 2
    waited=$((waited + 2))
    if [[ "$waited" -ge 14400 ]]; then
      warn "Waited 4 hours; restoring now."
      break
    fi
  done
  sleep 1
  log "Zoom has quit."
  killall -9 CptHost caphost aomhost ZoomOpener >/dev/null 2>&1 || true
}

remove_park_dir() {
  rm -rf "$GUEST_HOME" >>"$LOG_FILE" 2>&1 || true
  if [[ -d "$PARK_DIR" ]]; then
    rm -rf "$PARK_DIR" >>"$LOG_FILE" 2>&1 || true
  fi
  rmdir "$HOME/.zwtf_identity_park" >>"$LOG_FILE" 2>&1 || true
}

cleanup() {
  [[ "$CLEANED_UP" -eq 1 ]] && return 0
  if ! stop_zoom; then
    warn "Zoom still running; not restoring parked files or display name onto a live Zoom."
    log "Parked identity remains in $PARK_DIR. Desktop backup: $NAME_BACKUP_FILE. Restore will retry on exit."
    return 1
  fi
  unlock_park_dir "$PARK_DIR"
  if ! restore_display_name; then
    warn "Display-name restore failed. Keeping $PARK_DIR so the next launch can retry. Do not delete this folder."
    lock_park_dir "$PARK_DIR"
    CLEANED_UP=0
    return 1
  fi
  if ! unpark_personal_zoom_files; then
    warn "File restore failed. Keeping $PARK_DIR so the next launch can retry. Do not delete this folder."
    lock_park_dir "$PARK_DIR"
    CLEANED_UP=0
    return 1
  fi
  if ! unpark_zoom_keychain; then
    warn "Keychain restore failed. Keeping $PARK_DIR so the next launch can retry. Do not delete this folder."
    lock_park_dir "$PARK_DIR"
    CLEANED_UP=0
    return 1
  fi
  remove_park_dir
  CLEANED_UP=1
  log "Cleanup finished. Personal Zoom identity restored."
  return 0
}

main() {
  if ! touch "$LOG_FILE" 2>/dev/null; then
    LOG_FILE="/tmp/ChurchGuestZoom-log.txt"
    touch "$LOG_FILE" 2>/dev/null || true
  fi
  printf '\n==== %s  %s v%s ====\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$SCRIPT_NAME" "$SCRIPT_VERSION" >>"$LOG_FILE"
  log "Started as $0 pid $$ user $(id 2>/dev/null || true)"

  if [[ "$(uname -s)" != "Darwin" ]]; then
    die "This app is for macOS only."
  fi
  if [[ "$(id -u)" -eq 0 ]]; then
    die "Do not run as root and do not use sudo. Right-click Open ChurchGuestZoom.app as your normal Mac user."
  fi

  CONSOLE_USER="$(get_console_user)"
  if [[ -z "$CONSOLE_USER" || "$CONSOLE_USER" == "root" || "$CONSOLE_USER" == "loginwindow" ]]; then
    die "Run this from the Mac desktop, not SSH."
  fi

  generate_guest_name
  log "Guest display name: $GUEST_DISPLAY_NAME"
  osascript_dialog "CHURCH GUEST ZOOM
Build $SCRIPT_VERSION

Your Zoom name this session:

$GUEST_DISPLAY_NAME

Stuck End Meeting windows are force-closed.
Personal Zoom is parked until you quit Zoom.
VB-Cable and other mics stay visible in Zoom Audio." "Continue" 40

  trap 'cleanup' EXIT INT TERM

  ZOOM_BIN="$(find_zoom_bin || true)"
  [[ -n "$ZOOM_BIN" ]] || die "Zoom is not installed in /Applications."
  log "Zoom binary: $ZOOM_BIN"

  stop_zoom || die "Could not quit Zoom. Quit 1132wtf-v94 and Zoom, then run again."
  refresh_coreaudio
  restore_leftover_parks || die "Could not restore the previous Zoom identity.

Enter your Mac password if asked, and click Allow if Keychain asks.
Then run Church Guest Zoom again.

Do not start another guest session until this restore works.
Desktop name backup: $NAME_BACKUP_FILE
Log: $LOG_FILE"
  mkdir -p "$PARK_DIR/items" "$PARK_DIR/kc"
  chmod 700 "$PARK_DIR"
  capture_computername_before_change
  park_personal_zoom_files
  park_zoom_keychain
  if identity_still_visible; then
    die "Personal Zoom files are still visible. Refusing to launch."
  fi
  log "Personal Zoom files are hidden."
  set_guest_display_name
  seed_guest_zoom_prefs
  launch_guest_zoom
  if ! wait_for_zoom_start; then
    die "Zoom did not stay running. See the Desktop log."
  fi
  wait_for_zoom_quit
  if cleanup; then
    osascript_dialog "Done. Personal Zoom login and name restored.

Log: $LOG_FILE" "OK" 20
  else
    osascript_dialog "Zoom is still running, so gamer Zoom was not restored yet.

Quit Zoom. Restore retries when this app exits.
If Zoom is still running then, run Church Guest Zoom again after you quit Zoom.

Parked files: $PARK_DIR
Backup name: $NAME_BACKUP_FILE
Log: $LOG_FILE" "OK" 30
  fi
  log "Script finished."
}

main "$@"
