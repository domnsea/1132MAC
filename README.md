# 1132MAC — Ballroom Zoom kit for Mac

Guest Zoom session plus a hard reset. **Do not use if you have unsaved Zoom recordings you need to keep in the current session.**

## Church / guest Zoom (use this)

Download **`ChurchGuestZoom-20260823I.zip`** only:

https://github.com/domnsea/1132MAC/raw/cursor/fix-zoom-launch-crash-8c90/ChurchGuestZoom-20260823I.zip

Unzip, drag **`ChurchGuestZoom.app`** to the Desktop, then **right-click → Open**.

A window must appear immediately. If it does not, this is the wrong zip.

Build I:

1. Force-closes stuck **End Meeting** windows
2. Parks personal Zoom files (`zoomus.enc.db`, `zoommeeting.enc.db`)
3. Tries to hide Zoom Keychain logins — **if Keychain says no, guest Zoom still starts**
4. Sets a **random 6-digit** screen name
5. Starts Zoom with `sandbox-exec` — not `open`, not `bsexec`
6. Restores gamer Zoom files when you quit Zoom

Quit **1132wtf-v94** first. Click **Allow** on Keychain if you see it. Leave the app in the Dock until Zoom quits. Log: `Desktop/ChurchGuestZoom-log.txt`.

Do not download a raw `.command` from GitHub. Do not use `BALLROOM_Mac_Universal_Reset_Kit.zip` for church.

## Reset kit

`ZoomReset_Universal_Mac.command` wipes leftover Zoom files. It can delete local recordings. It will not wipe while Zoom is still running, and it will not run as root.

See `kit/README_MAC_UNIVERSAL.txt`.
