GitHub serves .command files as text. Download the ZIP instead:

  ChurchGuestZoom-20260822D.zip

https://github.com/domnsea/1132MAC/raw/cursor/fix-zoom-launch-crash-8c90/ChurchGuestZoom-20260822D.zip

1. Double-click the zip to unzip it
2. Right-click ChurchGuestZoom.command → Open
3. Quit 1132wtf-v94 first
4. Click Allow if Keychain asks
5. Leave Terminal open until you quit Zoom

If a previous download saved as ChurchGuestZoom.command.txt, rename it to
ChurchGuestZoom.command (delete the .txt), then in Terminal:

  chmod +x ~/Downloads/ChurchGuestZoom.command
  xattr -d com.apple.quarantine ~/Downloads/ChurchGuestZoom.command
