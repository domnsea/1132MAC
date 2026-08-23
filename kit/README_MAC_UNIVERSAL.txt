BALLROOM MAC UNIVERSAL ZOOM KIT

Church / guest session: download ChurchGuestZoom-20260823H.zip and run
ChurchGuestZoom.app (right-click ? Open). A window must appear immediately.

Do not use this reset zip for church. Do not open a raw .command from GitHub.

HOW TO USE THE APP

1. Quit 1132wtf-v94
2. Right-click ChurchGuestZoom.app ? Open
3. Click Continue, enter your Mac password if asked
4. Click Allow if Keychain Access asks
5. Zoom opens with a random 6-digit screen name
6. Leave the app in the Dock. When you quit Zoom, gamer login is restored

WHY EARLIER BUILDS DID NOTHING

The .command could be saved as text, or hang with no window on:
sudo password (no TTY), AppleEvent-quit of a stuck End Meeting dialog,
missing python3 on Monterey, or a full search of ~/Library.

Build H is an .app. Dialog is the first action. Those hang paths are gone.
It will not park or restore Zoom files, Keychain, or Full Name while Zoom
is still running.

WHY THE GAMER NAME KEPT SHOWING

Zoom was being started with the normal Open command. That always reloads this
Mac account's Zoom profile, the Zoom Safe Meeting Storage keychain item, and
your macOS Full Name.

This launcher parks those, then starts Zoom with sandbox-exec — not open.

RESET SCRIPT

ZoomReset_Universal_Mac.command wipes leftover Zoom files. It can delete
local recordings. It is not the church guest launcher. It will not wipe
while Zoom is still running, and it will not run as root.

Run from the desktop, not SSH, and not with sudo.
