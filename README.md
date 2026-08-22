# 1132MAC — Ballroom Zoom kit for Mac

Guest Zoom session plus a hard reset. **Do not use if you have unsaved Zoom recordings you need to keep in the current session.**

Download `BALLROOM_Mac_Universal_Reset_Kit.zip`.

## Guest session (hide gamer Zoom from church)

Use **ZoomTempUser_Launch.command**.

Earlier builds used `/usr/bin/open`. That always starts Zoom as this Mac account, so it reloads `zoomus.enc.db`, Keychain **Zoom Safe Meeting Storage**, and your macOS Full Name — which is why the gamer screen name kept appearing.

This version:

1. Parks personal Zoom files (including `zoomus.enc.db`)
2. Parks Zoom Keychain logins (click **Allow** if asked)
3. Sets this session’s screen name to `Guest` (edit `GUEST_DISPLAY_NAME` at the top of the script)
4. Starts Zoom with `sandbox-exec` on the Zoom binary from Terminal — not `open`
5. Restores your gamer Zoom login and name when you quit Zoom

If it cannot hide the personal identity, it will not launch.

## Reset kit

`ZoomReset_Universal_Mac.command` wipes leftover Zoom files.

See `kit/README_MAC_UNIVERSAL.txt`.
