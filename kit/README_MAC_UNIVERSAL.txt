BALLROOM MAC UNIVERSAL ZOOM KIT

FILES IN THIS KIT

- ZoomTempUser_Launch.command
- ZoomReset_Universal_Mac.command
- BALLROOM_Mac_Universal_Zoom_Reset_Guide.pdf
- README_MAC_UNIVERSAL.txt
- LICENSE_MIT.txt

WHICH FILE TO USE

Use ZoomTempUser_Launch.command if you want a church/guest Zoom session that
cannot see your personal/gamer Zoom login. Your gamer account is restored
when you quit Zoom.

Use ZoomReset_Universal_Mac.command if you only want to wipe leftover Zoom
files and then reopen Zoom in your own account.

GUEST / CHURCH SESSION

Double-click ZoomTempUser_Launch.command from the Mac desktop (not SSH, not sudo).

It will:

1. Ask for your Mac password
2. Quit Zoom
3. Park every personal Zoom file it can find (including Group Containers)
4. Park Zoom saved logins from Keychain (click Allow if macOS asks)
5. Refuse to start if your gamer login is still visible
6. Create a hidden temporary Mac user
7. Open Zoom logged out so you can sign in to the church account
8. Wait until you quit Zoom
9. Discard the church session files
10. Restore your gamer Zoom files and Keychain login
11. Delete the temporary user

If Keychain Access asks for permission, click Allow. That is what hides the
gamer saved login and later puts it back.

This does not keep Zoom's process running as the temporary UID. macOS aborts
that path. Your personal Zoom identity is hidden by parking the files and
saved passwords that Zoom would otherwise auto-load from this Mac account.

RESET SCRIPT

ZoomReset_Universal_Mac.command closes Zoom, deletes Zoom data, writes a
Desktop log file, and then tries to relaunch Zoom through Launch Services.

It can permanently delete local Zoom recordings.

HOW TO USE EITHER SCRIPT

1. Double-click the .command file
2. Terminal will open
3. Enter the Mac password if asked
4. If Keychain asks, click Allow
5. Let the script finish

Run it from a normal desktop Terminal window. Do not start it with sudo, and
do not run it over SSH.

IF MACOS BLOCKS THE FILE

Right-click the file, click Open, and confirm Open again.

If needed:
xattr -d com.apple.quarantine "ZoomTempUser_Launch.command"
xattr -d com.apple.quarantine "ZoomReset_Universal_Mac.command"

WHAT THIS KIT DOES NOT DO

- It does not repair internet problems
- It does not change Zoom account bans on Zoom's servers
- It does not reinstall Zoom
- It does not patch /usr/local/libexec/1132wtf-v94 (run the .command instead)

EXTRA NOTE

A log file is saved to the Desktop.
