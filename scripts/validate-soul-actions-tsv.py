#!/usr/bin/env python3
"""Validate SoulspireXI launcher Soul action and visibility TSV catalogs."""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_CANDIDATES = (
    REPO_ROOT / "addons/ashita4/soulspire_soul_actions/data",
    REPO_ROOT / "addons/ashita4/overlords_soul_actions/data",
)
KIND_LIMITS = {
    "spell": (0, 1023),
    "weaponskill": (0, 511),
    "ability": (512, 2047),
}
SOUL_RE = re.compile(r"^[a-z0-9_-]{2,64}$")


def validate_dir(data_dir: Path) -> list[str]:
    errors: list[str] = []
    actions_path = data_dir / "soul_actions.tsv"
    vis_path = data_dir / "visibility.tsv"

    if not actions_path.is_file():
        errors.append(f"Missing {actions_path}")
        return errors
    if not vis_path.is_file():
        errors.append(f"Missing {vis_path}")
        return errors

    seen_actions: dict[tuple[str, str, int], int] = {}
    for ln, raw in enumerate(actions_path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.strip("\r\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if not (5 <= len(parts) <= 7):
            errors.append(f"{actions_path.name}:{ln}: expected 5..7 columns, got {len(parts)}")
            continue
        soul, kind, id_s, name, desc = (p.strip() for p in parts[:5])
        if not SOUL_RE.match(soul):
            errors.append(f"{actions_path.name}:{ln}: invalid soul key '{soul}'")
        if kind not in KIND_LIMITS:
            errors.append(f"{actions_path.name}:{ln}: invalid kind '{kind}'")
            continue
        if not id_s.isdigit():
            errors.append(f"{actions_path.name}:{ln}: non-integer ID '{id_s}'")
            continue
        aid = int(id_s)
        lo, hi = KIND_LIMITS[kind]
        if not (lo <= aid <= hi):
            errors.append(f"{actions_path.name}:{ln}: {kind} ID {aid} outside {lo}..{hi}")
        if not (1 <= len(name) <= 79):
            errors.append(f"{actions_path.name}:{ln}: name length must be 1..79")
        if not (1 <= len(desc) <= 180):
            errors.append(f"{actions_path.name}:{ln}: description length must be 1..180")
        key = (soul, kind, aid)
        if key in seen_actions:
            errors.append(f"{actions_path.name}:{ln}: duplicate key {key} (first at line {seen_actions[key]})")
        else:
            seen_actions[key] = ln

    seen_vis: dict[tuple[str, str, int], int] = {}
    for ln, raw in enumerate(vis_path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.strip("\r\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 5:
            errors.append(f"{vis_path.name}:{ln}: expected 5 columns, got {len(parts)}")
            continue
        soul, kind, id_s, lvl_s, rule = (p.strip() for p in parts)
        if not SOUL_RE.match(soul):
            errors.append(f"{vis_path.name}:{ln}: invalid soul key '{soul}'")
        if kind not in KIND_LIMITS:
            errors.append(f"{vis_path.name}:{ln}: invalid kind '{kind}'")
            continue
        if not id_s.isdigit():
            errors.append(f"{vis_path.name}:{ln}: non-integer ID '{id_s}'")
            continue
        aid = int(id_s)
        lo, hi = KIND_LIMITS[kind]
        if not (lo <= aid <= hi):
            errors.append(f"{vis_path.name}:{ln}: {kind} ID {aid} outside {lo}..{hi}")
        if not lvl_s.isdigit() or not (1 <= int(lvl_s) <= 75):
            errors.append(f"{vis_path.name}:{ln}: invalid unlock level '{lvl_s}' (expected 1..75)")
        if rule not in ("unlock", "hidden"):
            errors.append(f"{vis_path.name}:{ln}: invalid rule '{rule}' (expected unlock|hidden)")
        key = (soul, kind, aid)
        if key in seen_vis:
            errors.append(f"{vis_path.name}:{ln}: duplicate key {key} (first at line {seen_vis[key]})")
        else:
            seen_vis[key] = ln

    return errors


def main() -> int:
    data_dir = next((p for p in DATA_CANDIDATES if p.is_dir()), None)
    if data_dir is None:
        print("[error] Soul action data directory not found.", file=sys.stderr)
        return 1
    errors = validate_dir(data_dir)
    if errors:
        for e in errors:
            print(f"[error] {e}", file=sys.stderr)
        return 1
    print(f"Validated Soul action TSV catalogs in {data_dir.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
