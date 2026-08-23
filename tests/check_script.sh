#!/usr/bin/env bash
# Syntax, hang, and sanity checks for the Zoom kit scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESET="$ROOT/kit/ZoomReset_Universal_Mac.command"
TEMP="$ROOT/kit/ZoomTempUser_Launch.command"
CHURCH="$ROOT/ChurchGuestZoom.command"
APP="$ROOT/ChurchGuestZoom.app/Contents/MacOS/ChurchGuestZoom"
APP_SCRIPT="$ROOT/ChurchGuestZoom.app/Contents/Resources/launch.command"
OPEN_CMD="$ROOT/ChurchGuestZoom-OPEN-ME.command"
PLIST="$ROOT/ChurchGuestZoom.app/Contents/Info.plist"
ZIP="$ROOT/ChurchGuestZoom-20260823L.zip"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

noncomment() {
  grep -v '^[[:space:]]*#' "$1"
}

[[ -f "$RESET" ]] || fail "missing $RESET"
[[ -f "$TEMP" ]] || fail "missing $TEMP"
[[ -f "$CHURCH" ]] || fail "missing $CHURCH"
[[ -f "$APP" ]] || fail "missing $APP"
[[ -f "$PLIST" ]] || fail "missing $PLIST"

[[ -f "$APP_SCRIPT" ]] || fail "missing $APP_SCRIPT"
[[ -f "$OPEN_CMD" ]] || fail "missing $OPEN_CMD"

bash -n "$RESET" || fail "bash -n failed on reset script"
bash -n "$TEMP" || fail "bash -n failed on temp launcher"
bash -n "$CHURCH" || fail "bash -n failed on ChurchGuestZoom.command"
bash -n "$APP_SCRIPT" || fail "bash -n failed on app launch.command"
bash -n "$OPEN_CMD" || fail "bash -n failed on OPEN-ME.command"
pass "bash syntax ok"

# Mach-O little-endian 64-bit magic 0xfeedfacf
python3 - "$APP" <<'PY' || fail "app CFBundleExecutable must be a Mach-O binary, not a shell script"
import sys
from pathlib import Path
data = Path(sys.argv[1]).read_bytes()[:4]
if data != bytes.fromhex("cffaedfe"):
    raise SystemExit("not a 64-bit Mach-O (got %s)" % data.hex())
PY
pass "app executable is Mach-O"

cmp -s "$CHURCH" "$APP_SCRIPT" || fail "Resources/launch.command must match ChurchGuestZoom.command"
cmp -s "$CHURCH" "$OPEN_CMD" || fail "OPEN-ME.command must match ChurchGuestZoom.command"
cmp -s "$CHURCH" "$TEMP" || fail "kit/ZoomTempUser_Launch.command must match ChurchGuestZoom.command"
cmp -s "$CHURCH" "$ROOT/kit/ChurchGuestZoom.command" || fail "kit/ChurchGuestZoom.command must match ChurchGuestZoom.command"
pass "launcher copies are in sync"

if grep -Eq '^[[:space:]]*(exec[[:space:]]+)?("?\$\{?zoom_app\}?"?|/Applications/[^[:space:]]+)/Contents/MacOS/' "$RESET"; then
  fail "reset script appears to exec Zoom's Mach-O stub directly"
fi
pass "reset script does not exec Contents/MacOS/zoom.us"

grep -q '/usr/bin/open' "$RESET" || fail "reset script expected /usr/bin/open"
if noncomment "$RESET" | grep -q 'tell application'; then
  fail "reset script must not AppleEvent-quit Zoom (hangs on End Meeting)"
fi
if grep -q 'continuing anyway' "$RESET"; then
  fail "reset script must not wipe Zoom data while Zoom is still running"
fi
grep -q 'Do not run this reset with sudo' "$RESET" || fail "reset script must refuse root"
grep -q 'Could not quit Zoom' "$RESET" || fail "reset script must stop if Zoom will not quit"
if noncomment "$RESET" | grep -Eq 'launchctl[[:space:]]+asuser'; then
  fail "reset script must not launchctl asuser while remaining root"
fi
pass "reset script launch path"

if noncomment "$TEMP" | grep -Eq 'launchctl[[:space:]]+bsexec'; then
  fail "guest launcher must not use launchctl bsexec"
fi
pass "guest launcher does not use bsexec"

if noncomment "$TEMP" | grep -Eq '/usr/bin/open|open -na'; then
  fail "guest launcher must not use open to start Zoom"
fi
pass "guest launcher does not use open"

# Hang / "did nothing" bugs from build E
if noncomment "$TEMP" | grep -q python3; then
  fail "guest launcher must not call python3 (Monterey often has none)"
fi
pass "guest launcher does not call python3"

if noncomment "$TEMP" | grep -Eq 'sudo[[:space:]]+-v'; then
  fail "guest launcher must not use sudo -v (hangs with no TTY)"
fi
pass "guest launcher does not use sudo -v"

if noncomment "$TEMP" | grep -q 'tell application'; then
  fail "guest launcher must not AppleEvent-quit Zoom (hangs on End Meeting)"
fi
pass "guest launcher does not AppleEvent-quit Zoom"

if noncomment "$TEMP" | grep -q 'dump-keychain'; then
  fail "guest launcher must not dump-keychain (hangs on Allow)"
fi
pass "guest launcher does not dump-keychain"

if grep -F 'find "$base/Library"' "$TEMP" | grep -v maxdepth >/dev/null; then
  fail "guest launcher must not recursively find all of ~/Library"
fi
pass "guest launcher does not walk all of ~/Library"

grep -q 'run_with_timeout' "$TEMP" || fail "guest launcher must time-bound Keychain/security calls"
grep -q 'giving up after' "$TEMP" || fail "guest launcher dialogs must give up so they cannot hang forever"
grep -q 'killall -9' "$TEMP" || fail "guest launcher must force-kill Zoom"
grep -q 'pgrep -x "zoom.us"' "$TEMP" || fail "wait-for-quit must watch zoom.us only, not CptHost"
if noncomment "$TEMP" | grep -Eq '/usr/bin/sandbox-exec|sandbox-exec -f'; then
  fail "guest launcher must not sandbox-exec Zoom (hides VB-Cable and every other mic)"
fi
grep -F 'exec "$ZOOM_BIN"' "$TEMP" >/dev/null || fail "guest launcher must exec the Zoom binary"
grep -q 'lock_park_dir' "$TEMP" || fail "guest launcher must lock the park dir before Zoom"
grep -q 'chown -R root:wheel' "$TEMP" || fail "park lock must chown to root so same-UID Zoom cannot read Keychain backups"
grep -q 'run_admin_cmd' "$TEMP" || fail "admin commands must run inline, not via a helper script file"
grep -q 'quoted form of (item 1 of argv)' "$TEMP" || fail "admin command must be passed as an osascript argument"
if grep -E '\.lock\.\$\$\.sh|\.unlock\.\$\$\.sh' "$TEMP"; then
  fail "must not write a replaceable .lock/.unlock helper for root to reopen"
fi
grep -q 'killall coreaudiod' "$TEMP" || fail "guest launcher must restart CoreAudio so mics reappear"
grep -q 'zAutoJoinVoip' "$TEMP" || fail "guest launcher must auto-join computer audio"
pass "guest launcher unhang guards and microphone path"

grep -q 'Zoom Safe Meeting Storage' "$TEMP" || fail "guest launcher must park Zoom Safe Meeting Storage"
grep -q 'generate_guest_name' "$TEMP" || fail "guest launcher must generate a random 6-digit name"
grep -q 'zoommeeting.enc.db' "$TEMP" || fail "guest launcher must clear stuck meeting state"
grep -q 'RealName' "$TEMP" || fail "guest launcher must swap macOS Full Name"
grep -q 'Parking personal Zoom files' "$TEMP" || fail "guest launcher must park personal Zoom files"
grep -q 'Refusing to launch' "$TEMP" || fail "guest launcher must refuse to launch if isolation fails"
grep -q 'Waiting for Zoom to quit' "$TEMP" || fail "guest launcher must wait for Zoom to quit"
grep -q 'display dialog' "$CHURCH" || fail "launcher must show an immediate dialog"
grep -q 'Do not run as root' "$TEMP" || fail "guest launcher must refuse root"
grep -q 'Could not quit Zoom' "$TEMP" || fail "guest launcher must stop if Zoom will not quit"
if grep -A2 'still present after kill' "$TEMP" | grep -q 'return 0'; then
  fail "stop_zoom must not succeed if Zoom is still running"
fi
python3 - "$TEMP" <<'PY' || fail "cleanup must not restore Full Name while Zoom is still running"
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
start = text.find("if ! stop_zoom; then")
if start < 0:
    raise SystemExit("missing stop_zoom failure branch")
end = text.find("\n  fi\n", start)
if end < 0:
    raise SystemExit("could not find end of stop_zoom failure branch")
if "restore_display_name" in text[start:end]:
    raise SystemExit("failure branch restores display name")
if "CLEANED_UP=1" in text[start:end]:
    raise SystemExit("failure branch must not mark cleanup done or EXIT cannot retry")
PY
if grep -q 'Could not hide Zoom saved logins' "$TEMP"; then
  fail "guest launcher must not abort the whole session on Keychain failure"
fi
grep -q 'Guest Zoom will still start' "$TEMP" || fail "guest launcher must continue if Keychain Deny/timeout"
python3 - "$TEMP" <<'PY' || fail "file identity check must not treat Keychain leftovers as a hard fail"
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
start = text.find("identity_still_visible()")
end = text.find("\nread_realname()")
if start < 0 or end < 0:
    raise SystemExit("could not find identity_still_visible")
if "keychain_zoom_still_present" in text[start:end]:
    raise SystemExit("identity_still_visible still hard-fails on Keychain")
PY
python3 - "$TEMP" <<'PY' || fail "Keychain items must be backed up before delete"
import sys, re
from pathlib import Path
text = Path(sys.argv[1]).read_text()
start = text.find("park_zoom_keychain()")
end = text.find("\nunpark_zoom_keychain()")
if start < 0 or end < 0:
    raise SystemExit("could not find park_zoom_keychain")
body = text[start:end]
if "delete-generic-password -s" in body or "delete-internet-password" in body:
    raise SystemExit("unrestorable Keychain delete by service")
if ".pass" not in body:
    raise SystemExit("park_zoom_keychain does not save a password backup")
del_at = body.find("delete-generic-password")
pass_at = body.find(".pass")
if del_at < 0:
    raise SystemExit("park_zoom_keychain never deletes Keychain items")
if pass_at < 0 or pass_at > del_at:
    raise SystemExit("password backup must be written before delete")
if "leaving it in place so it can be restored later" not in body:
    raise SystemExit("must skip delete when the secret cannot be read")
PY
python3 - "$TEMP" <<'PY' || fail "Keychain restore must keep password backups until the whole restore succeeds"
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
start = text.find("unpark_zoom_keychain()")
end = text.find("\nkeychain_zoom_still_present()")
if start < 0 or end < 0:
    raise SystemExit("could not find unpark_zoom_keychain")
body = text[start:end]
if 'rm -f "$park/kc/$i.pass"' in body or "rm -f \"$park/kc/$i.pass\"" in body:
    raise SystemExit("unpark_zoom_keychain must not delete a password backup per item")
if "keeping park dir" not in body:
    raise SystemExit("unpark_zoom_keychain must keep the park when an add fails")
if "Keychain already has" not in body:
    raise SystemExit("unpark_zoom_keychain must skip items already restored on retry")
PY
grep -q 'restore_leftover_parks || die' "$TEMP" || fail "guest launcher must abort if leftover restore fails"
grep -q 'oldest leftover parked Zoom identity' "$TEMP" || fail "leftover restore must use the oldest park only"
python3 - "$TEMP" <<'PY' || fail "leftover restore must not delete every leftover park"
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
start = text.find("restore_leftover_parks()")
end = text.find("\nlaunch_guest_zoom()")
if start < 0 or end < 0:
    raise SystemExit("could not find restore_leftover_parks")
body = text[start:end]
if 'for dir in "$HOME/.zwtf_identity_park"/*' in body and 'rm -rf "$dir"' in body:
    raise SystemExit("leftover restore still deletes every leftover park")
if "Removed leftover park after restore" not in body:
    raise SystemExit("leftover restore must only remove the park it restored")
if "Dropping newer leftover park without restoring" in body:
    raise SystemExit("must not delete newer leftover parks without restoring them")
if "Leaving newer leftover park in place" not in body:
    raise SystemExit("newer leftover parks must be left in place after oldest restore")
if "Other leftover parks remain" not in body:
    raise SystemExit("must not start a new guest session while newer leftover parks remain")
if "Leftover Keychain restore failed" not in body:
    raise SystemExit("leftover restore must keep a park when Keychain restore fails")
if "Leftover file restore failed" not in body:
    raise SystemExit("leftover restore must keep a park when file restore fails")
if "if ! unpark_personal_zoom_files" not in body:
    raise SystemExit("leftover restore must check file restore before deleting the park")
if "if ! restore_display_name_from" not in body:
    raise SystemExit("leftover restore must check display-name restore before deleting the park")
if "Leftover display-name restore failed" not in body:
    raise SystemExit("leftover restore must keep a park when display-name restore fails")
if "identity_still_visible" in body:
    raise SystemExit("leftover restore must retry Keychain/name even if files are already restored")
PY
python3 - "$TEMP" <<'PY' || fail "file restore must not overwrite already-restored identity"
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
start = text.find("unpark_personal_zoom_files()")
end = text.find("\nkc_field()")
if start < 0 or end < 0:
    raise SystemExit("could not find unpark_personal_zoom_files")
if "not overwriting" not in text[start:end]:
    raise SystemExit("unpark_personal_zoom_files must not overwrite dest files already restored")
PY
python3 - "$TEMP" <<'PY' || fail "Keychain backups must be root-locked immediately after park"
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
start = text.find("\nmain()")
if start < 0:
    raise SystemExit("could not find main")
body = text[start:]
name_at = body.find("set_guest_display_name")
park_at = body.find("park_zoom_keychain")
lock_at = body.find("lock_park_dir")
id_at = body.find("identity_still_visible")
if min(name_at, park_at, lock_at, id_at) < 0:
    raise SystemExit("main missing lock/park steps")
if not (name_at < park_at < lock_at < id_at):
    raise SystemExit("lock must run immediately after parking Keychain, before launch work")
PY
python3 - "$TEMP" <<'PY' || fail "cleanup must not delete the park if file or Keychain restore fails"
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
start = text.find("\ncleanup()")
end = text.find("\nmain()")
if start < 0 or end < 0:
    raise SystemExit("could not find cleanup")
body = text[start:end]
unlock_at = body.find("if ! unlock_park_dir")
fail_at = body.find("if ! restore_display_name")
file_at = body.find("if ! unpark_personal_zoom_files")
kc_at = body.find("if ! unpark_zoom_keychain")
rm_at = body.find("remove_park_dir")
if unlock_at < 0 or fail_at < 0 or file_at < 0 or kc_at < 0 or rm_at < 0:
    raise SystemExit("cleanup missing restore guards or remove_park_dir")
if min(unlock_at, fail_at, file_at, kc_at) > rm_at:
    raise SystemExit("cleanup removes park before checking restore")
if unlock_at > fail_at:
    raise SystemExit("cleanup must unlock the park before restore")
chunk = body[unlock_at:rm_at]
if chunk.count("return 1") < 4:
    raise SystemExit("cleanup must return before remove_park_dir when unlock or restore fails")
if "CLEANED_UP=1" in chunk:
    raise SystemExit("cleanup must not mark done while Keychain backup still exists")
PY
pass "guest launcher identity isolation"

# Proof of life is the first osascript, before set -u work.
first_osascript="$(grep -n '^/usr/bin/osascript' "$CHURCH" | head -n1 | cut -d: -f1)"
setu_line="$(grep -n '^set -u' "$CHURCH" | head -n1 | cut -d: -f1)"
[[ -n "$first_osascript" && -n "$setu_line" ]] || fail "could not locate osascript / set -u"
[[ "$first_osascript" -lt "$setu_line" ]] || fail "proof-of-life dialog must run before set -u"
pass "proof-of-life dialog is the first action"

grep -q 'CFBundleExecutable' "$PLIST" || fail "Info.plist missing CFBundleExecutable"
grep -q 'ChurchGuestZoom' "$PLIST" || fail "Info.plist missing executable name"
pass "app bundle Info.plist"

# Guest name generator: 10 samples, always 6 digits in 100000-999999
name_ok=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  raw="$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d ' \n')"
  [[ -n "$raw" ]] || raw="$(date +%s)"
  name="$(awk -v r="$raw" 'BEGIN { printf "%06d", 100000 + (r % 900000) }')"
  echo "$name" | grep -Eq '^[0-9]{6}$' || fail "generated name is not 6 digits: $name"
  [[ "$name" -ge 100000 && "$name" -le 999999 ]] || fail "generated name out of range: $name"
  name_ok=$((name_ok + 1))
done
pass "guest name generator ($name_ok samples)"

[[ -f "$ZIP" ]] || fail "missing $ZIP — run tools/build_guest_app.py"
python3 - "$ZIP" <<'PY' || fail "zip contents or unix bits are wrong"
import sys, zipfile
zpath = sys.argv[1]
need = {
    "OPEN_ME.txt",
    "ChurchGuestZoom-OPEN-ME.command",
    "ChurchGuestZoom.app/Contents/Info.plist",
    "ChurchGuestZoom.app/Contents/PkgInfo",
    "ChurchGuestZoom.app/Contents/MacOS/ChurchGuestZoom",
    "ChurchGuestZoom.app/Contents/Resources/launch.command",
}
with zipfile.ZipFile(zpath) as zf:
    names = set(zf.namelist())
    missing = need - names
    if missing:
        raise SystemExit("zip missing: %s" % sorted(missing))
    info = zf.getinfo("ChurchGuestZoom.app/Contents/MacOS/ChurchGuestZoom")
    mode = (info.external_attr >> 16) & 0o777
    if mode & 0o111 == 0:
        raise SystemExit("app executable in zip is not executable (mode=%o)" % mode)
    macho = zf.read("ChurchGuestZoom.app/Contents/MacOS/ChurchGuestZoom")
    if macho[:4] != bytes.fromhex("cffaedfe"):
        raise SystemExit("zip app is not Mach-O")
    cmdinfo = zf.getinfo("ChurchGuestZoom-OPEN-ME.command")
    cmdmode = (cmdinfo.external_attr >> 16) & 0o777
    if cmdmode & 0o111 == 0:
        raise SystemExit("OPEN-ME.command in zip is not executable (mode=%o)" % cmdmode)
    data = zf.read("ChurchGuestZoom.app/Contents/Resources/launch.command")
    if b"2026-08-23-L" not in data:
        raise SystemExit("zip launch.command is not build L")
    if b"python3" in b"\n".join(line for line in data.splitlines() if not line.lstrip().startswith(b"#")):
        raise SystemExit("zip launcher still calls python3")
    if b"/usr/bin/sandbox-exec" in data or b"sandbox-exec -f" in data:
        raise SystemExit("zip launcher still uses sandbox-exec")
print("zip ok")
PY
pass "zip ChurchGuestZoom-20260823L.zip contains Mach-O app and OPEN-ME.command"

echo "All checks passed."
