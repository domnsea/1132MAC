# 1132MAC — Ballroom Zoom kit for Mac

Guest Zoom session plus a hard reset. **Do not use if you have unsaved Zoom recordings you need to keep in the current session.**

## Church / guest Zoom (use this)

Download **`ChurchGuestZoom-20260823M.zip`** only:

https://github.com/domnsea/1132MAC/raw/cursor/fix-identity-still-visible-5211/ChurchGuestZoom-20260823M.zip

Unzip. **Right-click** `ChurchGuestZoom-OPEN-ME.command` or `ChurchGuestZoom.app` → **Open**.

Throw away zips **H** and **K** and **L**. H/L aborted with “Personal Zoom identity is still visible” because macOS rewrote Zoom prefs after they were parked. K hid every microphone.

Build M:

1. Force-closes stuck **End Meeting** windows
2. Parks personal Zoom files (`zoomus.enc.db`, `zoommeeting.enc.db`)
3. Deletes the prefs file macOS puts back after parking, so guest Zoom is not aborted
4. Tries to hide Zoom Keychain logins after backing them up — **if Keychain says no, guest Zoom still starts and the login is not deleted**
5. Sets a **random 6-digit** screen name
6. Starts Zoom as this Mac user — not `open`, not `bsexec`, **not sandbox-exec** (so VB-Cable can appear)
7. Restores gamer Zoom files when you quit Zoom

Quit **1132wtf-v94** first. Click **Allow** on Keychain if you see it. In Zoom: **Settings → Audio → Microphone → VB-Cable**. Leave the app in the Dock until Zoom quits. Log: `Desktop/ChurchGuestZoom-log.txt`.

Do not download a raw `.command` from GitHub. Do not use `BALLROOM_Mac_Universal_Reset_Kit.zip` for church.

## Reset kit

`ZoomReset_Universal_Mac.command` wipes leftover Zoom files. It can delete local recordings. It will not wipe while Zoom is still running, and it will not run as root.

See `kit/README_MAC_UNIVERSAL.txt`.
