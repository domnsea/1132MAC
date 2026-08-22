BALLROOM MAC UNIVERSAL ZOOM RESET KIT

WHAT THIS DOES

This Mac script works on:
- Intel Macs
- Apple Silicon Macs
- newer Zoom Workplace installs
- older zoom.us installs

It closes Zoom, deletes Zoom data, writes a Desktop log file, and then tries to relaunch Zoom through Launch Services.

It is configured to delete:
- local Zoom data in the current Mac user account
- shared/system Zoom data if admin permission is granted
- local Documents/Zoom recordings
- shared Zoom recording folders when available

IMPORTANT WARNING

This can permanently delete local Zoom recordings.
Do not run it if you need to keep those files.

FILES IN THIS KIT

- ZoomReset_Universal_Mac.command
- BALLROOM_Mac_Universal_Zoom_Reset_Guide.pdf
- README_MAC_UNIVERSAL.txt
- LICENSE_MIT.txt

HOW TO USE

1. Double-click ZoomReset_Universal_Mac.command
2. Terminal will open
3. Read the prompt and continue
4. Enter the Mac password if asked
5. Let the script finish
6. Zoom should try to reopen automatically

Run it from a normal desktop Terminal window. Do not start it with sudo, and do not run it over SSH. The script will ask for a password itself when it needs admin rights.

IF MACOS BLOCKS THE FILE

Try this:
- right-click the file
- click Open
- confirm Open again

If needed, remove quarantine in Terminal:
xattr -d com.apple.quarantine "ZoomReset_Universal_Mac.command"

IF ZOOM CRASHES IMMEDIATELY ON RELAUNCH

A macOS crash report for zoom.us with all of these points is a launch-path problem, not a Zoom data-corruption problem:

- abort() called
- Crashed thread in _RegisterApplication / GetCurrentProcess
- +[NSApplication sharedApplication] during startup
- Parent Process: bash
- Process Role: Unspecified

That abort happens when the Zoom app stub is started as a Terminal child, from SSH, from a background agent, as root, or inside sandbox-exec. AppKit then cannot get an application serial number from launchservicesd and calls abort().

Do this instead:

1. Open Zoom from Applications, Spotlight, or Finder
2. Do not run /Applications/zoom.us.app/Contents/MacOS/zoom.us from Terminal
3. Do not wrap Zoom in sandbox-exec
4. Re-run this script from a desktop Terminal window without sudo
5. If the Mac just woke from sleep, wait a few seconds, then open Zoom from Applications

This kit relaunches Zoom with /usr/bin/open in the logged-in GUI user's session. It never executes the Contents/MacOS/zoom.us binary.

WHAT IT DOES NOT DO

- It does not repair internet problems
- It does not fix Zoom account bans or server-side restrictions
- It does not reinstall Zoom
- It does not preserve local recordings

EXTRA NOTE

A log file is saved to the Desktop so the user can see what was removed or skipped.
