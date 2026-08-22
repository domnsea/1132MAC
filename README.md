# 1132MAC — Ballroom Zoom kit for Mac

Hard reset plus a guest Zoom session launcher. **Do not use if you have unsaved Zoom recordings you need to keep in the current session.**

Download `BALLROOM_Mac_Universal_Reset_Kit.zip` or use the files in `kit/`.

## Guest session (hide gamer Zoom from church)

`kit/ZoomTempUser_Launch.command` parks **all** personal Zoom identity on this Mac account before Zoom opens:

- Zoom app support, caches, cookies, preferences, group containers
- Saved Zoom logins in Keychain
- Then opens Zoom logged out

Sign in with the church account. When you quit Zoom, the parked gamer login is restored and the hidden temporary user is deleted.

If it cannot fully hide the personal Zoom login, it **refuses to launch** rather than show your gamer name.

## Reset kit

`kit/ZoomReset_Universal_Mac.command` still does a hard wipe of leftover Zoom files.

See `kit/README_MAC_UNIVERSAL.txt` for full instructions.
