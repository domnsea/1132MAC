# 1132MAC — Ballroom Zoom kit for Mac

Guest Zoom session plus a hard reset. **Do not use if you have unsaved Zoom recordings you need to keep in the current session.**

## Church / guest Zoom (use this)

Download **`ChurchGuestZoom-20260823G.zip`** only:

https://github.com/domnsea/1132MAC/raw/cursor/fix-zoom-launch-crash-8c90/ChurchGuestZoom-20260823G.zip

Unzip, drag **`ChurchGuestZoom.app`** to the Desktop, then **right-click → Open**.

A window must appear immediately. If it does not, this is the wrong zip.

Build G:

1. Force-closes stuck **End Meeting** windows (no AppleEvent quit — that hung forever)
2. Parks personal Zoom files, including `zoomus.enc.db` and `zoommeeting.enc.db`
3. Parks Zoom Keychain logins including **Zoom Safe Meeting Storage**
4. Sets this session’s screen name to a **random 6-digit code**
5. Starts Zoom with `sandbox-exec` on the Zoom binary — not `open`, not `bsexec`
6. Refuses to park or restore identity while Zoom is still running
7. Restores gamer Zoom when you quit Zoom

Quit **1132wtf-v94** first. Click **Allow** on Keychain. Leave the app in the Dock until Zoom quits. Log: `Desktop/ChurchGuestZoom-log.txt`.

Do not download a raw `.command` from GitHub (browsers save that as text). Do not use `BALLROOM_Mac_Universal_Reset_Kit.zip` for church.

## Reset kit

`ZoomReset_Universal_Mac.command` wipes leftover Zoom files. It can delete local recordings. It will not wipe while Zoom is still running, and it will not run as root.

See `kit/README_MAC_UNIVERSAL.txt`.
