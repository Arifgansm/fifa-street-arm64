#!/usr/bin/env python3
"""Names the functions behind the offsets of a crash in fifastreet.log
("Unhandled signal 11 at .../game/fifastreet+0x2C1C6C" and the lines of the
backtrace under it), and prints the recompiled C++ of the guest functions
among them, from the generated/ folder the build left.

    scripts/crash-info.py [DIR] [OFFSET...]

DIR     build.sh's folder (default ~/.local/share/FifaStreet-arm64)
OFFSET  hex offsets into game/fifastreet; without any, they are taken from
        the last crash in game/Logs/fifastreet.log

Reads the game's own symbol table: nothing else is needed (no binutils).
"""
import re
import struct
import sys
from pathlib import Path

LINES = 120


def symbols(path: Path) -> list[tuple[int, int, str]]:
    """The functions in an ELF64 little-endian file: (address, size, name)."""
    data = path.read_bytes()
    if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
        sys.exit(f"error: {path} is not a 64-bit little-endian ELF file")
    shoff, = struct.unpack_from("<Q", data, 0x28)
    shentsize, shnum = struct.unpack_from("<HH", data, 0x3A)
    sections = [struct.unpack_from("<IIQQQQIIQQ", data, shoff + i * shentsize) for i in range(shnum)]
    found = []
    for _, kind, _, _, offset, size, link, _, _, entsize in sections:
        if kind not in (2, 11) or not entsize:  # SHT_SYMTAB, SHT_DYNSYM
            continue
        strings = sections[link][4]
        for at in range(offset, offset + size, entsize):
            name, info, _, shndx, value, length = struct.unpack_from("<IBBHQQ", data, at)
            if info & 0xF == 2 and shndx and value:  # STT_FUNC, defined
                end = data.index(b"\0", strings + name)
                found.append((value, length, data[strings + name:end].decode("utf-8", "replace")))
    found.sort()
    return found


def lookup(table: list[tuple[int, int, str]], offset: int) -> str:
    low, high = 0, len(table)
    while low < high:
        middle = (low + high) // 2
        if table[middle][0] <= offset:
            low = middle + 1
        else:
            high = middle
    if not low:
        return "?"
    address, size, name = table[low - 1]
    if size and offset >= address + size:
        return f"? (after {name})"
    return f"{name}+0x{offset - address:X}"


def last_crash(log: Path) -> list[int]:
    """The fifastreet offsets of the last crash in the log, fault first."""
    try:
        lines = log.read_text(errors="replace").splitlines()
    except OSError:
        sys.exit(f"error: no log at {log}: pass the offsets by hand")
    start = max((i for i, line in enumerate(lines) if "Unhandled signal" in line), default=None)
    if start is None:
        sys.exit(f"error: no crash in {log}")
    offsets = []
    for line in lines[start:start + 40]:
        match = re.search(r"/fifastreet\+0x([0-9A-Fa-f]+)", line)
        if match:
            offsets.append(int(match.group(1), 16))
    return offsets


def source(generated: Path, name: str) -> list[str]:
    """The recompiled C++ of a guest function, as codegen wrote it."""
    definition = f"DEFINE_REX_FUNC({name})"
    for path in sorted(generated.rglob("*.cpp")):
        try:
            lines = path.read_text(errors="replace").splitlines()
        except OSError:
            continue
        for i, line in enumerate(lines):
            if line.startswith(definition):
                return [f"// {path.relative_to(generated)}:{i + 1}"] + lines[i:i + LINES]
    return []


def main(argv: list[str]) -> int:
    args = argv[1:]
    folder = Path.home() / ".local/share/FifaStreet-arm64"
    if args and not re.fullmatch(r"(0x)?[0-9A-Fa-f]+", args[0]):
        folder = Path(args.pop(0)).expanduser()
    exe = folder / "game/fifastreet"
    offsets = [int(a, 16) for a in args] or last_crash(folder / "game/Logs/fifastreet.log")
    table = symbols(exe)
    names = []
    for offset in offsets:
        where = lookup(table, offset)
        print(f"fifastreet+0x{offset:X}  {where}")
        names.append(where.split("+")[0])
    generated = folder / "ReStreet/Installer/recomp-template/generated"
    shown = set()
    for name in names:
        guest = re.search(r"sub_[0-9A-F]{8}", name)
        if not guest or guest.group(0) in shown or not generated.is_dir():
            continue
        shown.add(guest.group(0))
        print()
        print("\n".join(source(generated, guest.group(0))) or f"// {guest.group(0)}: source not found")
        if len(shown) == 2:
            break
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
