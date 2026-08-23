# Slimcast / leftover resource cleanup

The Cursor remote desktop was lagging because XFCE was compositing with software GL, Plank kept restarting, and leftover caches sat in the home directory.

## This remote desktop (Linux)

Already applied on the current session:

- Window compositor off
- Wallpaper set to a solid color
- Plank dock and bamf stopped (they respawn from `desktop-init.sh`)
- Go build cache, nvm download cache, Mesa shader cache, and `/tmp/node-compile-cache` removed

To run it again:

```bash
bash tools/slimcast_speedup.sh
```

VNC is left running so the session stays connected.

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
