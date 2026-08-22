#!/usr/bin/env bash
# Guardrails for the Zoom kit scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESET="$ROOT/kit/ZoomReset_Universal_Mac.command"
TEMP="$ROOT/kit/ZoomTempUser_Launch.command"
CHURCH="$ROOT/ChurchGuestZoom.command"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$RESET" ]] || fail "missing $RESET"
[[ -f "$TEMP" ]] || fail "missing $TEMP"
[[ -f "$CHURCH" ]] || fail "missing $CHURCH"

bash -n "$RESET"
bash -n "$TEMP"
bash -n "$CHURCH"
echo "PASS: bash syntax ok"

if grep -Eq '^[[:space:]]*(exec[[:space:]]+)?("?\$\{?zoom_app\}?"?|/Applications/[^[:space:]]+)/Contents/MacOS/' "$RESET"; then
  fail "reset script appears to exec Zoom's Mach-O stub directly"
fi
echo "PASS: reset script does not exec Contents/MacOS/zoom.us"

grep -q '/usr/bin/open' "$RESET" || fail "reset script expected /usr/bin/open"
grep -q 'launchctl asuser' "$RESET" || fail "reset script expected launchctl asuser"
echo "PASS: reset script launch path"

if grep -Eq '^[[:space:]]*[^#[:space:]].*launchctl[[:space:]]+bsexec' "$TEMP" || grep -Eq '^[[:space:]]*launchctl[[:space:]]+bsexec' "$TEMP"; then
  fail "guest launcher must not use launchctl bsexec"
fi
echo "PASS: guest launcher does not use bsexec"

if grep -Eq '^[[:space:]]*/usr/bin/open' "$TEMP" || grep -Eq '[^[:alnum:]_]open -na' "$TEMP"; then
  fail "guest launcher must not use open to start Zoom"
fi
echo "PASS: guest launcher does not use open"

grep -q 'sandbox-exec' "$TEMP" || fail "guest launcher must use sandbox-exec"
grep -q 'Zoom Safe Meeting Storage' "$TEMP" || fail "guest launcher must park Zoom Safe Meeting Storage"
grep -q 'GUEST_DISPLAY_NAME' "$TEMP" || fail "guest launcher must set a guest display name"
grep -q 'RealName' "$TEMP" || fail "guest launcher must swap macOS Full Name"
grep -q 'Parking personal Zoom files' "$TEMP" || fail "guest launcher must park personal Zoom files"
grep -q 'Refusing to launch' "$TEMP" || fail "guest launcher must refuse to launch if isolation fails"
grep -q 'Waiting for Zoom to quit' "$TEMP" || fail "guest launcher must wait for Zoom to quit"
echo "PASS: guest launcher identity isolation"

echo "All checks passed."
