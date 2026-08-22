# 1132MAC — Ballroom Zoom kit for Mac

Hard reset plus a temporary-user Zoom launcher. **Do not use if you have unsaved Zoom recordings or other Zoom data you need to keep.**

Download `BALLROOM_Mac_Universal_Reset_Kit.zip` or use the files in `kit/`.

## Temporary user launch (window that actually appears)

v94's `/usr/local/libexec/1132wtf-v94/root_launch_temp_zoom.sh` starts Zoom as a temp UID with `launchctl bsexec` and `$ZOOM_BIN`. On SIP-enabled macOS that aborts in `_RegisterApplication` (`Abort trap: 6`) and never shows a window.

`kit/ZoomTempUser_Launch.command` keeps the lifecycle you asked for:

1. Creates a hidden temporary Mac user
2. Opens Zoom in **your** desktop session through Launch Services (so a window can appear)
3. Stores that session's Zoom files in the temp user's home
4. When you quit Zoom, restores your previous Zoom files and deletes the temp user

Zoom cannot display a window while its process runs as the temporary UID on this Mac. The temp user is the isolated file owner; the GUI process is the logged-in user.

## Reset kit

`kit/ZoomReset_Universal_Mac.command` still does a hard wipe of leftover Zoom files.

See `kit/README_MAC_UNIVERSAL.txt` for full instructions.
