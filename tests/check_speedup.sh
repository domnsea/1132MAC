#!/usr/bin/env bash
# Syntax and safety checks for the Slimcast / Mac temp cleanup scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SLIM="$ROOT/tools/slimcast_speedup.sh"
MAC="$ROOT/kit/MacTempCPUCleanup.command"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

[[ -f "$SLIM" ]] || fail "missing $SLIM"
[[ -f "$MAC" ]] || fail "missing $MAC"

bash -n "$SLIM" || fail "bash -n failed on slimcast_speedup.sh"
bash -n "$MAC" || fail "bash -n failed on MacTempCPUCleanup.command"
pass "bash syntax ok"

grep -q 'use_compositing' "$SLIM" || fail "slimcast script must disable compositing"
grep -q 'node-compile-cache' "$SLIM" || fail "slimcast script must clear node compile cache"
if grep -E 'killall|pkill' "$SLIM" | grep -E 'Xtigervnc|tigervncserver|xfce4-session|cursor-server'; then
  fail "slimcast script must not kill VNC/session processes"
fi
pass "slimcast script keeps VNC/session processes"

grep -q 'zwtf_identity_park' "$MAC" || fail "mac script must mention identity parks"
grep -q 'Documents/Zoom' "$MAC" || fail "mac script must mention recordings path"
if grep -n 'rm -rf' "$MAC" | grep -E 'zwtf_identity_park|Documents/Zoom'; then
  fail "mac script must not rm identity parks or Documents/Zoom"
fi
pass "mac script does not wipe logins or recordings"

echo "All checks passed."
