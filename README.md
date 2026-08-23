# Slimcast / leftover resource cleanup

The remote desktop felt frozen because VNC was streaming **1920x1200 at 60fps in 24-bit color**, and the viewer could enlarge that desktop again. The VM itself was idle; the viewer could not keep up.

## This remote desktop (Linux)

Already applied on the current session:

- VNC locked at **1024x768**, **16-bit color**, **8fps** (viewer cannot resize it back up)
- Window compositor off
- Wallpaper process (`xfdesktop`) stopped
- Plank dock stopped
- Unused caches removed

Refresh the Slimcast tab if the screen went blank after the VNC restart.

To run it again:

```bash
bash tools/slimcast_speedup.sh
```

The script restarts VNC only when frame rate/depth are still at the slow defaults.

## Mac leftover Zoom CPU / temp

Double-click `kit/MacTempCPUCleanup.command` on the Mac.

It stops leftover Zoom helpers **only when Zoom is not running**, then deletes caches, logs, and temp files.

It does **not** delete:

- Zoom logins (`Application Support`, prefs)
- parked identity (`~/.zwtf_identity_park`)
- `Documents/Zoom` recordings

For a hard Zoom wipe, keep using `BALLROOM_Mac_Universal_Reset_Kit.zip`.

## Tests

```bash
./tests/check_speedup.sh
```
