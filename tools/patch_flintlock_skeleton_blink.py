#!/usr/bin/env python3
"""Remove erroneous 0xa3 actor-visibility scheduler opcodes from the 7 AkimboRA skeleton DATs.

Root cause:
  AkimboRA-Source/work/ra-rigs/build_v3.py emits opcode 0xa3 in lc07 (t=0 hidden=1, t=1 hidden=0),
  ls07 (t=0 hidden=0), and splg (t=0 hidden=0) alongside the standard per-slot weapon visibility
  opcode 0x75. No vanilla FFXI routine in any of the 7 player skeleton DATs uses 0xa3; in live
  FFXiMain.dll, 0xa3 toggles actor-wide visibility for 1 tick at the start of /ra, causing the
  entire character to briefly disappear (blink).

This tool strips ONLY the 4 0xa3 commands from lc07, ls07, and splg in the 7 player skeleton
DATs under dat-overlays/flintlock-akimbo-compact/ROM/ while preserving all 0x75 weapon-slot
visibility commands, all animation cues, tick timing, and every other DAT section byte-for-byte.
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

SKELETON_DATS = (
    "ROM/27/82.DAT",  # HumeM
    "ROM/32/58.DAT",  # HumeF
    "ROM/37/31.DAT",  # ElvaanM
    "ROM/42/4.DAT",   # ElvaanF
    "ROM/46/93.DAT",  # Tarutaru
    "ROM/51/89.DAT",  # Mithra
    "ROM/56/59.DAT",  # Galka
)
TARGET_ROUTINES = {b"lc07", b"ls07", b"splg"}


def parse_sections(data: bytes) -> list[tuple[int, bytes, bytes]]:
    result: list[tuple[int, bytes, bytes]] = []
    pos = 0
    depth = 0
    while pos < len(data):
        if pos + 16 > len(data):
            raise ValueError("Truncated DAT section header")
        (meta,) = struct.unpack_from("<I", data, pos + 4)
        kind = meta & 127
        size = ((meta >> 7) & 0x7FFFF) * 16
        if size < 16 or pos + size > len(data):
            raise ValueError(f"Invalid DAT section size {size} at offset {pos}")
        result.append((kind, data[pos : pos + 4], data[pos : pos + size]))
        depth += (kind == 1) - (kind == 0)
        if depth < 0:
            raise ValueError("Unexpected DAT directory end")
        pos += size
    if depth != 0:
        raise ValueError("Unclosed DAT directory")
    return result


def build_section(template: bytes, name: bytes, payload: bytes) -> bytes:
    if len(name) != 4:
        raise ValueError("DAT section name must be 4 bytes")
    padded = payload + bytes((-len(payload)) % 16)
    (old_meta,) = struct.unpack_from("<I", template, 4)
    blocks = (16 + len(padded)) // 16
    if blocks > 0x7FFFF:
        raise ValueError("DAT section exceeds max block size")
    new_meta = (old_meta & ~(0x7FFFF << 7)) | (blocks << 7)
    return name + struct.pack("<I", new_meta) + template[8:16] + padded


def parse_routine(data: bytes) -> tuple[int, int, int, list[tuple[int, bytes]]]:
    start, end = (n - 16 for n in struct.unpack_from("<II", data, 20))
    if not (0 <= start <= end <= len(data)):
        raise ValueError("Invalid scheduler offsets")
    rows: list[tuple[int, bytes]] = []
    pos = start
    tick = 0
    while pos < end:
        if pos + 8 > end:
            raise ValueError("Truncated scheduler command")
        op, words = data[pos : pos + 2]
        size = (words & 31) * 4
        if size < 8 or pos + size > end:
            raise ValueError("Invalid scheduler command size")
        cmd = data[pos : pos + size]
        if op == 0:
            return start, pos, tick, rows
        rows.append((tick, cmd))
        tick += struct.unpack_from("<H", cmd, 4)[0]
        pos += size
    raise ValueError("Missing scheduler terminator")


def rebuild_routine(template: bytes, events: list[tuple[int, bytes]]) -> bytes:
    data = template[16:]
    start, terminator, total, _ = parse_routine(data)
    end = struct.unpack_from("<I", data, 24)[0] - 16
    events = sorted(events, key=lambda item: item[0])
    if not events or events[0][0] != 0 or events[-1][0] > total:
        raise ValueError("Event ticks outside native schedule bounds")
    stream = bytearray()
    for i, (tick, cmd) in enumerate(events):
        next_tick = events[i + 1][0] if i + 1 < len(events) else total
        stream += cmd[:4] + struct.pack("<H", next_tick - tick) + cmd[6:]
    stream += data[terminator:end]
    prefix = bytearray(data[:start])
    struct.pack_into("<I", prefix, 24, 16 + start + len(stream))
    return build_section(template, template[:4], bytes(prefix) + bytes(stream) + data[end:])


def patch_skeleton_dat(path: Path) -> int:
    original = path.read_bytes()
    rows = parse_sections(original)
    removed_total = 0
    output: list[bytes] = []

    for kind, name, raw in rows:
        if kind == 7 and name in TARGET_ROUTINES:
            _, _, total, events = parse_routine(raw[16:])
            kept = [(t, c) for t, c in events if c[0] != 0xA3]
            removed = len(events) - len(kept)
            if removed > 0:
                rebuilt = rebuild_routine(raw, kept)
                # Verify round-trip preserves exact total duration and non-0xa3 events
                _, _, new_total, new_events = parse_routine(rebuilt[16:])
                if new_total != total:
                    raise ValueError(f"{path.name} {name!r}: total duration changed {total} -> {new_total}")
                if [(t, c[:4] + c[6:]) for t, c in new_events] != [(t, c[:4] + c[6:]) for t, c in kept]:
                    raise ValueError(f"{path.name} {name!r}: non-0xa3 command mismatch after rebuild")
                output.append(rebuilt)
                removed_total += removed
                continue
        output.append(raw)

    if removed_total > 0:
        patched = b"".join(output)
        # Re-parse full DAT to verify structural integrity
        parse_sections(patched)
        path.write_bytes(patched)
    return removed_total


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    overlay_root = repo_root / "dat-overlays" / "flintlock-akimbo-compact"
    total_removed = 0
    for rel in SKELETON_DATS:
        dat_path = overlay_root / rel
        if not dat_path.is_file():
            print(f"ERROR: Missing skeleton DAT: {dat_path}", file=sys.stderr)
            return 1
        removed = patch_skeleton_dat(dat_path)
        total_removed += removed
        print(f"{rel}: removed {removed} 0xa3 command(s)")
    print(f"Done. Total 0xa3 commands removed across 7 skeleton DATs: {total_removed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
