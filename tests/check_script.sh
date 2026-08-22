#!/usr/bin/env bash
# Guardrails for the Zoom reset script. These checks exist because launching
# Zoom by exec'ing Contents/MacOS/zoom.us crashes macOS AppKit in
# _RegisterApplication (SIGABRT / abort()).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/kit/ZoomReset_Universal_Mac.command"

if [[ ! -f "$SCRIPT" ]]; then
  echo "FAIL: missing $SCRIPT" >&2
  exit 1
fi

bash -n "$SCRIPT"
echo "PASS: bash syntax ok"

if grep -Eq '^[[:space:]]*(exec[[:space:]]+)?("?\$\{?zoom_app\}?"?|/Applications/[^[:space:]]+)/Contents/MacOS/' "$SCRIPT"; then
  echo "FAIL: script appears to exec Zoom's Mach-O stub directly" >&2
  grep -n 'Contents/MacOS' "$SCRIPT" >&2 || true
  exit 1
fi
echo "PASS: does not exec Contents/MacOS/zoom.us"

if ! grep -q '/usr/bin/open' "$SCRIPT"; then
  echo "FAIL: expected Launch Services launch via /usr/bin/open" >&2
  exit 1
fi
echo "PASS: launches via /usr/bin/open"

if ! grep -q 'launchctl asuser' "$SCRIPT"; then
  echo "FAIL: expected launchctl asuser for root/console GUI session" >&2
  exit 1
fi
echo "PASS: uses launchctl asuser when running as root"

if ! grep -q '_RegisterApplication' "$SCRIPT"; then
  echo "FAIL: expected troubleshooting text for the known abort crash" >&2
  exit 1
fi
echo "PASS: documents _RegisterApplication crash"

if grep -q 'sandbox-exec' "$SCRIPT" && grep -Eq 'sandbox-exec .*zoom' "$SCRIPT"; then
  echo "FAIL: script must not wrap Zoom in sandbox-exec" >&2
  exit 1
fi
echo "PASS: does not sandbox-exec Zoom"

echo "All checks passed."
