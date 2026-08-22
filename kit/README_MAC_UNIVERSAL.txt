BALLROOM MAC UNIVERSAL ZOOM KIT

Use ZoomTempUser_Launch.command for a church/guest Zoom session that cannot
see your personal/gamer Zoom login or screen name.

HOW TO USE

1. Double-click ZoomTempUser_Launch.command on the Mac desktop
2. Enter your Mac password if asked
3. If Keychain Access asks, click Allow
4. Zoom opens as a guest. Screen name is Guest
5. Sign in with the church Zoom account if you need it
6. Leave Terminal open. When you quit Zoom, your gamer login is restored

To use a different guest screen name, edit GUEST_DISPLAY_NAME at the top of
ZoomTempUser_Launch.command before you run it.

WHY THE GAMER NAME KEPT SHOWING

Zoom was being started with the normal Open command. That always reloads this
Mac account's Zoom profile, the Zoom Safe Meeting Storage keychain item, and
your macOS Full Name.

This launcher parks those, then starts Zoom with sandbox-exec from Terminal.

If Keychain asks and you click Deny, your gamer login stays visible and the
script will refuse to start Zoom.

RESET SCRIPT

ZoomReset_Universal_Mac.command wipes leftover Zoom files. It can delete
local recordings.

Run either script from the desktop, not SSH, and not with sudo.
