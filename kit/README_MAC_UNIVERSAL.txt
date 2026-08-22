BALLROOM MAC UNIVERSAL ZOOM KIT

FILES IN THIS KIT

- ZoomTempUser_Launch.command
- ZoomReset_Universal_Mac.command
- BALLROOM_Mac_Universal_Zoom_Reset_Guide.pdf
- README_MAC_UNIVERSAL.txt
- LICENSE_MIT.txt

WHICH FILE TO USE

Use ZoomTempUser_Launch.command if you want Zoom to open now, with a hidden
temporary Mac user that is deleted when you quit Zoom.

Use ZoomReset_Universal_Mac.command if you only want to wipe leftover Zoom
files and then reopen Zoom in your own account.

TEMPORARY USER LAUNCH

Double-click ZoomTempUser_Launch.command from the Mac desktop (not SSH, not sudo).

It will:

1. Ask for your Mac password
2. Create a hidden temporary user
3. Point this session's Zoom files at that user's home
4. Open Zoom through Launch Services in your desktop session
5. Wait until you quit Zoom
6. Restore your previous Zoom files
7. Delete the temporary user

This is the replacement for v94's launchctl bsexec + $ZOOM_BIN path, which
crashes with Abort trap 6 / _RegisterApplication because macOS will not give
a temporary UID a visible window on the logged-in desktop.

Zoom's window process runs as you. The temporary user holds the isolated files
and is removed when Zoom closes.

RESET SCRIPT

ZoomReset_Universal_Mac.command closes Zoom, deletes Zoom data, writes a
Desktop log file, and then tries to relaunch Zoom through Launch Services.

It can permanently delete local Zoom recordings.

HOW TO USE EITHER SCRIPT

1. Double-click the .command file
2. Terminal will open
3. Enter the Mac password if asked
4. Let the script finish

Run it from a normal desktop Terminal window. Do not start it with sudo, and
do not run it over SSH.

IF MACOS BLOCKS THE FILE

Right-click the file, click Open, and confirm Open again.

If needed:
xattr -d com.apple.quarantine "ZoomTempUser_Launch.command"
xattr -d com.apple.quarantine "ZoomReset_Universal_Mac.command"

IF ZOOM CRASHES IMMEDIATELY

A crash report with abort() in _RegisterApplication and Parent Process: bash
means Zoom was started as a Terminal child or as another UID. Use the temp-user
launcher above, or open Zoom from Applications. Do not run
/Applications/zoom.us.app/Contents/MacOS/zoom.us from Terminal.

WHAT THIS KIT DOES NOT DO

- It does not repair internet problems
- It does not change Zoom account bans on Zoom's servers
- It does not reinstall Zoom
- It does not patch /usr/local/libexec/1132wtf-v94 (run the .command instead)

EXTRA NOTE

A log file is saved to the Desktop.
