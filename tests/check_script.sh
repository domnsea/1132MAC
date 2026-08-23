#!/usr/bin/env bash
# Syntax, hang, and sanity checks for the Zoom kit scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESET="$ROOT/kit/ZoomReset_Universal_Mac.command"
TEMP="$ROOT/kit/ZoomTempUser_Launch.command"
CHURCH="$ROOT/ChurchGuestZoom.command"
APP="$ROOT/ChurchGuestZoom.app/Contents/MacOS/ChurchGuestZoom"
PLIST="$ROOT/ChurchGuestZoom.app/Contents/Info.plist"
ZIP="$ROOT/ChurchGuestZoom-20260823I.zip"

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

bash -n "$RESET" || fail "bash -n failed on reset script"
bash -n "$TEMP" || fail "bash -n failed on temp launcher"
bash -n "$CHURCH" || fail "bash -n failed on ChurchGuestZoom.command"
bash -n "$APP" || fail "bash -n failed on .app executable"
pass "bash syntax ok"

cmp -s "$CHURCH" "$APP" || fail "app executable must match ChurchGuestZoom.command"
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
pass "guest launcher unhang guards"

grep -q 'sandbox-exec' "$TEMP" || fail "guest launcher must use sandbox-exec"
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
    "ChurchGuestZoom.app/Contents/Info.plist",
    "ChurchGuestZoom.app/Contents/PkgInfo",
    "ChurchGuestZoom.app/Contents/MacOS/ChurchGuestZoom",
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
    data = zf.read("ChurchGuestZoom.app/Contents/MacOS/ChurchGuestZoom")
    if b"2026-08-23-I" not in data:
        raise SystemExit("zip app is not build F")
    if b"python3" in b"\n".join(line for line in data.splitlines() if not line.lstrip().startswith(b"#")):
        raise SystemExit("zip app still calls python3")
print("zip ok")
PY
pass "zip ChurchGuestZoom-20260823I.zip contains executable .app"

echo "All checks passed."
