# AGENTS.md

## Cursor Cloud specific instructions

This repo is a **macOS-only** Zoom kit: double-clickable `.command` launcher scripts, a
`ChurchGuestZoom.app` bundle, a Python build tool, and a shell-based test suite. There is no
web/server component. The dev environment needs only `bash` and `python3`, both preinstalled
on the cloud VM, so no dependency installation is required.

### Services / components

- `ChurchGuestZoom.command` — the launcher (the "application"). It is the source of truth;
  `ChurchGuestZoom.app/Contents/MacOS/ChurchGuestZoom`, `kit/ChurchGuestZoom.command`, and
  `kit/ZoomTempUser_Launch.command` are byte-identical copies produced by the build tool.
- `tools/build_guest_app.py` — regenerates the launcher copies and the distribution zips
  (`ChurchGuestZoom-20260823H.zip`, `BALLROOM_Mac_Universal_Reset_Kit.zip`).
- `tests/check_script.sh` — lint + sanity/test suite (bash `bash -n` syntax checks plus grep/
  python assertions on the scripts and zip contents).

### Lint / test / build / run

- Lint + test: `./tests/check_script.sh` (bash syntax checks are the lint step; there is no
  separate linter — `shellcheck` is not required).
- Build: `python3 tools/build_guest_app.py`.
- Run: `./ChurchGuestZoom.command`.

### Non-obvious caveats

- The launcher **cannot run end-to-end on Linux by design**: `main()` calls `uname -s` and
  exits with `ERROR: This app is for macOS only.` on anything but Darwin. It relies on
  `osascript`, `sandbox-exec`, Keychain (`security`), and `dscl`, none of which exist here.
  On Linux it still starts and writes a log (falling back to `/tmp/ChurchGuestZoom-log.txt`
  when `~/Desktop` is absent), then hits the macOS guard — that is expected, not a failure.
- Running `tools/build_guest_app.py` rewrites the two committed `.zip` files. They usually
  differ from `HEAD` only by embedded file timestamps, so `git checkout -- *.zip` after a
  build if you did not intend to change the shipped artifacts.
- `tests/check_script.sh` enforces that the four launcher copies stay byte-identical, so
  after editing `ChurchGuestZoom.command` you must re-run the build tool before the tests
  will pass again.
