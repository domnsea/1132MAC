#!/usr/bin/env bash
# Guardrails for the Zoom kit scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESET="$ROOT/kit/ZoomReset_Universal_Mac.command"
TEMP="$ROOT/kit/ZoomTempUser_Launch.command"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$RESET" ]] || fail "missing $RESET"
[[ -f "$TEMP" ]] || fail "missing $TEMP"

bash -n "$RESET"
bash -n "$TEMP"
echo "PASS: bash syntax ok"

if grep -Eq '^[[:space:]]*(exec[[:space:]]+)?("?\$\{?zoom_app\}?"?|/Applications/[^[:space:]]+)/Contents/MacOS/' "$RESET"; then
  fail "reset script appears to exec Zoom's Mach-O stub directly"
fi
echo "PASS: reset script does not exec Contents/MacOS/zoom.us"

grep -q '/usr/bin/open' "$RESET" || fail "reset script expected /usr/bin/open"
grep -q 'launchctl asuser' "$RESET" || fail "reset script expected launchctl asuser"
grep -q '_RegisterApplication' "$RESET" || fail "reset script expected _RegisterApplication note"
echo "PASS: reset script launch path"

if grep -q 'sandbox-exec' "$RESET" && grep -Eq 'sandbox-exec .*zoom' "$RESET"; then
  fail "reset script must not wrap Zoom in sandbox-exec"
fi
echo "PASS: reset script does not sandbox-exec Zoom"

if grep -Eq '^[[:space:]]*[^#[:space:]].*launchctl[[:space:]]+bsexec' "$TEMP" || grep -Eq '^[[:space:]]*launchctl[[:space:]]+bsexec' "$TEMP"; then
  fail "temp-user launcher must not use launchctl bsexec"
fi
echo "PASS: temp-user launcher does not use bsexec"

grep -q '/usr/bin/open' "$TEMP" || fail "temp-user launcher expected /usr/bin/open"
grep -q 'Creating hidden temporary user' "$TEMP" || fail "temp-user launcher must create a temp user"
grep -q 'Deleting temporary user' "$TEMP" || fail "temp-user launcher must delete the temp user"
grep -q 'Waiting for Zoom to quit' "$TEMP" || fail "temp-user launcher must wait for Zoom to quit"
echo "PASS: temp-user launcher lifecycle"

if grep -q 'sandbox-exec' "$TEMP" && grep -Eq 'sandbox-exec .*zoom' "$TEMP"; then
  fail "temp-user launcher must not wrap Zoom in sandbox-exec"
fi
echo "PASS: temp-user launcher does not sandbox-exec Zoom"

echo "All checks passed."
