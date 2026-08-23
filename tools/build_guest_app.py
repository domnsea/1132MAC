#!/usr/bin/env python3
"""Build ChurchGuestZoom.app copies and the uniquely named guest zip."""
from __future__ import annotations

import os
import shutil
import stat
import zipfile
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "ChurchGuestZoom.command"
APP_BIN = ROOT / "ChurchGuestZoom.app" / "Contents" / "MacOS" / "ChurchGuestZoom"
KIT_A = ROOT / "kit" / "ChurchGuestZoom.command"
KIT_B = ROOT / "kit" / "ZoomTempUser_Launch.command"
ZIP_PATH = ROOT / "ChurchGuestZoom-20260823G.zip"
OPEN_ME = ROOT / "OPEN_ME.txt"
APP_ROOT = ROOT / "ChurchGuestZoom.app"


def copy_launchers() -> None:
    APP_BIN.parent.mkdir(parents=True, exist_ok=True)
    for dest in (APP_BIN, KIT_A, KIT_B):
        shutil.copyfile(SRC, dest)
        dest.chmod(dest.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def unix_attr(mode: int, is_dir: bool = False) -> int:
    if is_dir:
        mode |= 0o040000
        extra = 0x10
    else:
        extra = 0
    return ((mode & 0o777) << 16) | extra


def add_file(zf: zipfile.ZipFile, path: Path, arcname: str, mode: int | None = None) -> None:
    st = path.stat()
    if mode is None:
        mode = st.st_mode & 0o777
    zi = zipfile.ZipInfo(arcname.replace("\\", "/"))
    zi.date_time = datetime.fromtimestamp(st.st_mtime).timetuple()[:6]
    zi.compress_type = zipfile.ZIP_DEFLATED
    zi.create_system = 3
    zi.external_attr = unix_attr(mode, is_dir=False)
    with path.open("rb") as fh:
        zf.writestr(zi, fh.read())


def add_dir(zf: zipfile.ZipFile, arcname: str) -> None:
    if not arcname.endswith("/"):
        arcname += "/"
    zi = zipfile.ZipInfo(arcname)
    zi.date_time = (2026, 8, 23, 0, 30, 0)
    zi.create_system = 3
    zi.external_attr = unix_attr(0o755, is_dir=True)
    zf.writestr(zi, b"")


def build_zip() -> None:
    if ZIP_PATH.exists():
        ZIP_PATH.unlink()
    with zipfile.ZipFile(ZIP_PATH, "w") as zf:
        add_file(zf, OPEN_ME, "OPEN_ME.txt", 0o644)
        add_dir(zf, "ChurchGuestZoom.app/")
        add_dir(zf, "ChurchGuestZoom.app/Contents/")
        add_dir(zf, "ChurchGuestZoom.app/Contents/MacOS/")
        add_file(zf, ROOT / "ChurchGuestZoom.app/Contents/Info.plist", "ChurchGuestZoom.app/Contents/Info.plist", 0o644)
        add_file(zf, ROOT / "ChurchGuestZoom.app/Contents/PkgInfo", "ChurchGuestZoom.app/Contents/PkgInfo", 0o644)
        add_file(zf, APP_BIN, "ChurchGuestZoom.app/Contents/MacOS/ChurchGuestZoom", 0o755)


def build_reset_zip() -> None:
    reset_zip = ROOT / "BALLROOM_Mac_Universal_Reset_Kit.zip"
    if reset_zip.exists():
        reset_zip.unlink()
    with zipfile.ZipFile(reset_zip, "w") as zf:
        add_file(zf, ROOT / "kit" / "ZoomReset_Universal_Mac.command", "ZoomReset_Universal_Mac.command", 0o755)
        add_file(zf, ROOT / "kit" / "README_MAC_UNIVERSAL.txt", "README_MAC_UNIVERSAL.txt", 0o644)
        add_file(zf, ROOT / "kit" / "LICENSE_MIT.txt", "LICENSE_MIT.txt", 0o644)
        pdf = ROOT / "kit" / "BALLROOM_Mac_Universal_Zoom_Reset_Guide.pdf"
        if pdf.is_file():
            add_file(zf, pdf, "BALLROOM_Mac_Universal_Zoom_Reset_Guide.pdf", 0o644)
        add_file(zf, KIT_B, "ZoomTempUser_Launch.command", 0o755)
    print("wrote", reset_zip, "bytes", reset_zip.stat().st_size)


def main() -> None:
    os.chdir(ROOT)
    if not SRC.is_file():
        raise SystemExit("missing ChurchGuestZoom.command")
    copy_launchers()
    build_zip()
    build_reset_zip()
    print("wrote", ZIP_PATH, "bytes", ZIP_PATH.stat().st_size)


if __name__ == "__main__":
    main()
