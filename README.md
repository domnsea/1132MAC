# 1132MAC — Ballroom Zoom reset kit for Mac

Hard reset for leftover Zoom files on macOS. **Do not use if you have unsaved Zoom recordings or other Zoom data you need to keep.**

Download `BALLROOM_Mac_Universal_Reset_Kit.zip` or use the files in `kit/`.

## Crash fix (Zoom abort on relaunch)

If Zoom dies immediately after this kit relaunches it, and the crash report shows `abort()` in `_RegisterApplication` during `+[NSApplication sharedApplication]`, Zoom was started as a Terminal/bash child instead of through Launch Services.

The reset script now:

- relaunches Zoom with `/usr/bin/open` in the logged-in GUI user's session
- never executes `Contents/MacOS/zoom.us` from bash
- flushes cached preferences after deleting Zoom plists
- refuses to launch when there is no desktop login session

Open Zoom from Applications if you are on SSH or ran the script with `sudo`.

See `kit/README_MAC_UNIVERSAL.txt` for full instructions.
