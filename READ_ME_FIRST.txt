Download this ZIP (not a .command from GitHub — that saves as text):

https://github.com/domnsea/1132MAC/raw/cursor/fix-zoom-launch-crash-8c90/ChurchGuestZoom-20260823H.zip

Unzip. Drag ChurchGuestZoom.app to the Desktop.
Right-click ChurchGuestZoom.app → Open → Open.

A window must appear immediately: "Church Guest Zoom is starting."
If nothing appears, you opened an old zip. Use H, not D/E/F/G.

Build 2026-08-23-H:
- Real .app (not a .command that Terminal can swallow)
- Dialog first, before anything that can hang
- Force-closes stuck End Meeting (no AppleEvent quit)
- Will not park/restore Zoom files or your Full Name while Zoom is still running
- No python3, no sudo-in-Terminal hang
- Parks gamer Zoom, uses a random 6-digit name
- Restores gamer Zoom when you quit

Quit 1132wtf-v94 first. Click Allow on Keychain.
Leave the app in the Dock until you quit Zoom.
Log: Desktop/ChurchGuestZoom-log.txt
