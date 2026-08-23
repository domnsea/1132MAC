#!/usr/bin/env python3
"""Compile tools/macos_stub.s to a real x86_64 Mach-O executable (no dyld)."""
from __future__ import annotations

import struct
import subprocess
import sys
from pathlib import Path

MH_MAGIC_64 = 0xFEEDFACF
CPU_TYPE_X86_64 = 0x01000007
CPU_SUBTYPE_X86_64_ALL = 3
MH_EXECUTE = 2
MH_NOUNDEFS = 1
LC_SEGMENT_64 = 0x19
LC_UNIXTHREAD = 0x5
X86_THREAD_STATE64 = 4
x86_THREAD_STATE64_COUNT = 42
VM_PROT_READ = 1
VM_PROT_WRITE = 2
VM_PROT_EXECUTE = 4
S_REGULAR = 0
S_ATTR_PURE_INSTRUCTIONS = 0x80000000
S_ATTR_SOME_INSTRUCTIONS = 0x00000400


def parse_object(data: bytes) -> bytes:
    magic, _cputype, _cpusub, _filetype, ncmds, _sizeofcmds, _flags, _res = struct.unpack_from("<IIIIIIII", data)
    if magic != MH_MAGIC_64:
        raise SystemExit("stub.o is not a 64-bit Mach-O")
    off = 32
    text = None
    relocs: list[tuple[int, int, int]] = []
    symbols: dict[int, int] = {}
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd == LC_SEGMENT_64:
            nsects = struct.unpack_from("<I", data, off + 64)[0]
            so = off + 72
            for _s in range(nsects):
                name = data[so : so + 16].split(b"\0")[0]
                _addr, size = struct.unpack_from("<QQ", data, so + 32)
                soff, _align, reloff, nreloc = struct.unpack_from("<IIII", data, so + 48)
                if name == b"__text":
                    text = bytearray(data[soff : soff + size])
                    for i in range(nreloc):
                        r_addr, packed = struct.unpack_from("<iI", data, reloff + i * 8)
                        r_symbolnum = packed & 0xFFFFFF
                        r_pcrel = (packed >> 24) & 1
                        r_length = (packed >> 25) & 3
                        relocs.append((r_addr, r_symbolnum, r_pcrel, r_length))
                so += 80
        elif cmd == 2:  # LC_SYMTAB
            symoff, nsyms, stroff, _strsize = struct.unpack_from("<IIII", data, off + 8)
            for i in range(nsyms):
                _strx, _typ, _sect, _desc, val = struct.unpack_from("<IBBHQ", data, symoff + i * 16)
                symbols[i] = val
        off += cmdsize
    if text is None:
        raise SystemExit("no __text in stub.o")
    for r_addr, r_symbolnum, r_pcrel, r_length in relocs:
        if not r_pcrel or r_length != 2:
            raise SystemExit("unsupported reloc")
        target = symbols[r_symbolnum]
        disp = target - (r_addr + 4)
        struct.pack_into("<i", text, r_addr, disp)
    return bytes(text)


def build_executable(text: bytes) -> bytes:
    pagezero = struct.pack(
        "<II16sQQQQIIII",
        LC_SEGMENT_64,
        72,
        b"__PAGEZERO",
        0,
        0x100000000,
        0,
        0,
        0,
        0,
        0,
        0,
    )
    sect_name = b"__text"
    seg_name = b"__TEXT"
    # header 32 + pagezero 72 + text seg 152 + unixthread 184 = 440
    sizeofcmds = 72 + 152 + 184
    header_size = 32 + sizeofcmds
    entry = 0x100000000 + header_size
    filesize = 4096
    sect = (
        sect_name.ljust(16, b"\0")
        + seg_name.ljust(16, b"\0")
        + struct.pack(
            "<QQIIIIIIII",
            entry,
            len(text),
            header_size,
            2,
            0,
            0,
            0,
            S_REGULAR | S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS,
            0,
            0,
        )
    )
    text_seg = struct.pack(
        "<II16sQQQQIIII",
        LC_SEGMENT_64,
        72 + 80,
        b"__TEXT",
        0x100000000,
        filesize,
        0,
        filesize,
        VM_PROT_READ | VM_PROT_EXECUTE,
        VM_PROT_READ | VM_PROT_EXECUTE,
        1,
        0,
    ) + sect
    regs = [0] * 21
    regs[16] = entry  # rip
    unixthread = struct.pack("<IIII", LC_UNIXTHREAD, 184, X86_THREAD_STATE64, x86_THREAD_STATE64_COUNT) + struct.pack(
        "<21Q", *regs
    )
    header = struct.pack(
        "<IIIIIIII",
        MH_MAGIC_64,
        CPU_TYPE_X86_64,
        CPU_SUBTYPE_X86_64_ALL,
        MH_EXECUTE,
        3,
        sizeofcmds,
        MH_NOUNDEFS,
        0,
    )
    blob = header + pagezero + text_seg + unixthread + text
    if len(blob) > filesize:
        raise SystemExit("stub too large")
    return blob.ljust(filesize, b"\0")


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    src = root / "tools" / "macos_stub.s"
    obj = Path("/tmp/macos_stub.o")
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "ChurchGuestZoom.app" / "Contents" / "MacOS" / "ChurchGuestZoom"
    subprocess.check_call(
        ["clang", "-target", "x86_64-apple-macos10.13", "-c", "-o", str(obj), str(src)]
    )
    text = parse_object(obj.read_bytes())
    exe = build_executable(text)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(exe)
    out.chmod(0o755)
    print("wrote", out, "bytes", len(exe), "text", len(text))


if __name__ == "__main__":
    main()
