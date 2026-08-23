BALLROOM MAC UNIVERSAL ZOOM KIT

Church / guest session: download ChurchGuestZoom-20260823K.zip.
Right-click ChurchGuestZoom-OPEN-ME.command or ChurchGuestZoom.app, then Open.

Do not use this reset zip for church. Do not open a raw .command from GitHub.

HOW TO USE

1. Quit 1132wtf-v94
2. Right-click ChurchGuestZoom-OPEN-ME.command or ChurchGuestZoom.app, then Open
3. Click Continue, enter your Mac password if asked
4. Click Allow if Keychain Access asks (if it does not, guest Zoom still starts)
5. Zoom opens with a random 6-digit screen name
6. Leave it running. When you quit Zoom, gamer login files are restored

WHY EARLIER BUILDS DID NOTHING

The .app was a shell script, so macOS ignored the click. Build K has a real
Mac binary plus OPEN-ME.command. Keychain Deny no longer aborts guest Zoom.

WHY THE GAMER NAME KEPT SHOWING

Zoom was being started with the normal Open command. That always reloads this
Mac account's Zoom profile, the Zoom Safe Meeting Storage keychain item, and
your macOS Full Name.

This launcher parks those, then starts Zoom with sandbox-exec -- not open.

RESET SCRIPT

ZoomReset_Universal_Mac.command wipes leftover Zoom files. It can delete
local recordings. It is not the church guest launcher. It will not wipe
while Zoom is still running, and it will not run as root.

Run from the desktop, not SSH, and not with sudo.
