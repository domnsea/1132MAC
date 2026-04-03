# BALLROOM.WTF Zoom 1132 Fix for Mac

A double-clickable macOS reset script for Zoom.

This script force-quits Zoom, removes local Zoom app data, removes shared Zoom support files that may survive a normal uninstall, and then relaunches Zoom.

## What this is for

Use this when Zoom on macOS is stuck, corrupted, refusing to launch correctly, holding onto bad local data, or repeatedly failing after reinstall attempts.

This script is especially aimed at situations where a normal app reinstall did not fully clear Zoom's saved state.

## What this script does

When run, the script:

1. Prompts for administrator approval with `sudo`
2. Tries to quit Zoom using AppleScript
3. Kills remaining Zoom-related processes if needed
4. Deletes user-level Zoom data from the current Mac account
5. Deletes system/shared Zoom data that may affect relaunch behavior
6. Opens Zoom again

## Important warning

This script is destructive by design.

It does **not** delete your Zoom account, but it **does** remove local Zoom data from the Mac.

That includes items such as:

- app support files
- cache
- cookies
- preferences
- saved application state
- web storage
- log files
- shared Zoom installer/support folders
- `~/Documents/Zoom`

If you keep anything important in `Documents/Zoom`, back it up first.

## Who should use this

This is for users who want a fast, hard reset.

It is **not** the right choice if:

- Zoom is working normally
- you only wanted to sign out and back in
- you are afraid of wiping local Zoom data
- you are in a live meeting and cannot afford interruption

## Requirements

- macOS
- Zoom or Zoom Workplace installed
- permission to enter an administrator password

No third-party packages are required.

## How to use

### Option 1: Double-click

1. Download or save `ZoomReset.command`
2. Put it somewhere easy to find, such as the Desktop
3. Quit Zoom if it is open
4. Double-click the file
5. Enter your Mac password if prompted
6. Wait for the script to finish
7. Zoom should relaunch automatically

### Option 2: Run from Terminal

```bash
chmod +x ZoomReset.command
./ZoomReset.command
```

## What gets removed

### User-level data

- `~/Library/Application Support/zoom.us`
- `~/Library/Caches/us.zoom.xos`
- `~/Library/Preferences/us.zoom.xos.plist`
- `~/Library/Saved Application State/us.zoom.xos.savedState`
- `~/Library/HTTPStorages/us.zoom.xos`
- `~/Library/HTTPStorages/us.zoom.xos.binarycookies`
- `~/Library/WebKit/us.zoom.xos`
- `~/Library/Cookies/us.zoom.xos.binarycookies`
- `~/Documents/Zoom`
- matching Zoom log folders inside `~/Library/Logs`

### System/shared data

- `/Library/Application Support/zoom.us`
- `/Library/Logs/zoom.us`
- `/Library/Preferences/us.zoom.xos.plist`
- `/Users/Shared/zoom.us`
- `/Users/Shared/Zoom`
- `/Users/Shared/ZoomInstaller`

## Expected result

After the script finishes:

- Zoom should reopen
- you may need to sign in again
- local Zoom settings may be reset
- corrupted cached state should be gone

## Troubleshooting

### macOS says the file cannot be opened

Go to:

`System Settings` → `Privacy & Security`

Then allow the script to run if macOS blocked it.

### Double-clicking does nothing

Run this in Terminal:

```bash
chmod +x ZoomReset.command
./ZoomReset.command
```

### The password looks like it is not typing

That is normal in Terminal. On macOS, password entry usually shows no characters at all.

### Zoom does not reopen automatically

Open Zoom manually from Applications after the cleanup finishes.

### The problem is still not fixed

Then the issue may not be local app data. It may be account-level, network-level, device-policy-related, or tied to Zoom itself.

## Safety notes

Read this before distributing the script to other people:

- This script uses `rm -rf`
- It removes data permanently
- It asks for administrator rights
- It should be described as a hard reset, not a routine maintenance tool
- Beginners should be warned about the `Documents/Zoom` deletion specifically

## Included tools

This script only uses built-in macOS tools:

- `bash`
- `sudo`
- `osascript`
- `pkill`
- `rm`
- `find`
- `open`

Because of that, there are no third-party dependency licenses to include.

## License note

If this stays private, you do not need to attach a license.

If you publish it on GitHub or share it publicly, add a license file so others know whether they are allowed to reuse or modify it.

A simple MIT license file is included separately as an optional choice.

## Disclaimer

Use at your own risk. Review the paths being deleted before running the script on any machine you care about.
