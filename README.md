# 1132MAC — Ballroom Zoom kit for Mac

Guest Zoom session plus a hard reset. **Do not use if you have unsaved Zoom recordings you need to keep in the current session.**

## Church / guest Zoom (use this)

Download **`ChurchGuestZoom-20260823M.zip`** only:

https://github.com/domnsea/1132MAC/raw/cursor/fix-zoom-launch-crash-8c90/ChurchGuestZoom-20260823M.zip

Unzip. **Right-click** `ChurchGuestZoom-OPEN-ME.command` or `ChurchGuestZoom.app` → **Open**.

Throw away zip **L** and earlier. Leftover parked logins from those runs used to abort before Zoom opened. Build **K** also hid every microphone via `sandbox-exec`.

Build M:

1. Force-closes stuck **End Meeting** windows
2. Parks personal Zoom files (`zoomus.enc.db`, `zoommeeting.enc.db`)
3. Tries to hide Zoom Keychain logins after backing them up — **if Keychain says no, guest Zoom still starts and the login is not deleted**
4. Sets a **random 6-digit** screen name
5. Starts Zoom as this Mac user — not `open`, not `bsexec`, **not sandbox-exec** (so VB-Cable can appear)
6. Does **not** abort if leftover identity parks remain or a lock password is missed
7. Restores gamer Zoom files when you quit Zoom

Quit **1132wtf-v94** first. Click **Allow** on Keychain if you see it. Look behind other windows for the Mac password box. In Zoom: **Settings → Audio → Microphone → VB-Cable**. Leave the app in the Dock until Zoom quits. Log: `Desktop/ChurchGuestZoom-log.txt`.

Do not download a raw `.command` from GitHub. Do not use `BALLROOM_Mac_Universal_Reset_Kit.zip` for church.

## Reset kit

`ZoomReset_Universal_Mac.command` wipes leftover Zoom files. It can delete local recordings. It will not wipe while Zoom is still running, and it will not run as root.

See `kit/README_MAC_UNIVERSAL.txt`.
