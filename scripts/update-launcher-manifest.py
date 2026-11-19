#!/usr/bin/env python3
"""Regenerates the file hashes and sizes in manifest.json (or verifies in --check mode)."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path


TEXT_LF_SUFFIXES = {".lua", ".md", ".json", ".yml", ".yaml", ".py", ".cs", ".xaml", ".csproj"}


def sha256_file(path: Path) -> tuple[str, int]:
    raw = path.read_bytes()
    if path.suffix.lower() in TEXT_LF_SUFFIXES and b"\r\n" in raw:
        raw = raw.replace(b"\r\n", b"\n")
        path.write_bytes(raw)
    return hashlib.sha256(raw).hexdigest(), len(raw)


def _run_read_only_check(repo_root: Path) -> int:
    verifier_path = Path(__file__).resolve().parent / "verify-launcher-manifest.py"
    spec = importlib.util.spec_from_file_location("verify_launcher_manifest", str(verifier_path))
    if not spec or not spec.loader:
        print(f"Could not load verifier: {verifier_path}", file=sys.stderr)
        return 2
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return int(mod.main([str(repo_root)]))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Run read-only manifest verification without modifying manifest.json or client files.",
    )
    args = parser.parse_args(argv)

    repo_root = Path(__file__).resolve().parent.parent
    if args.check:
        return _run_read_only_check(repo_root)

    manifest_path = repo_root / "manifest.json"
    raw_text = manifest_path.read_text(encoding="utf-8")
    for lineno, line in enumerate(raw_text.splitlines(), start=1):
        if line.startswith(("<<<<<<<", "=======", ">>>>>>>")):
            print(
                f"ERROR: Unresolved merge-conflict marker in {manifest_path} at line {lineno}. "
                "Resolve conflicts before regenerating manifest.json.",
                file=sys.stderr,
            )
            return 1

    manifest = json.loads(raw_text)

    entries: list[dict[str, object]] = []

    dat_root = repo_root / "dat-overlay" / "ROM"
    if dat_root.exists():
        for file_path in sorted(
            (p for p in dat_root.rglob("*") if p.is_file()),
            key=lambda p: p.relative_to(repo_root).as_posix().lower(),
        ):
            rel_repo = file_path.relative_to(repo_root).as_posix()
            rel_dat = file_path.relative_to(repo_root / "dat-overlay").as_posix()
            digest, size = sha256_file(file_path)
            entries.append(
                {
                    "category": "dat",
                    "sourcePath": rel_repo,
                    "targetPath": rel_dat,
                    "sha256": digest,
                    "size": size,
                }
            )

    plugins_root = repo_root / "plugins" / "ashita4"
    if plugins_root.exists():
        for file_path in sorted(
            (p for p in plugins_root.rglob("*") if p.is_file()),
            key=lambda p: p.relative_to(repo_root).as_posix().lower(),
        ):
            rel_repo = file_path.relative_to(repo_root).as_posix()
            rel_plugin = file_path.relative_to(plugins_root).as_posix()
            digest, size = sha256_file(file_path)
            entries.append(
                {
                    "category": "plugin",
                    "sourcePath": rel_repo,
                    "targetPath": rel_plugin,
                    "sha256": digest,
                    "size": size,
                }
            )

    addons_root = repo_root / "addons" / "ashita4"
    if addons_root.exists():
        for file_path in sorted(
            (p for p in addons_root.rglob("*") if p.is_file()),
            key=lambda p: p.relative_to(repo_root).as_posix().lower(),
        ):
            rel_repo = file_path.relative_to(repo_root).as_posix()
            rel_addon = file_path.relative_to(addons_root).as_posix()
            digest, size = sha256_file(file_path)
            entries.append(
                {
                    "category": "addon",
                    "sourcePath": rel_repo,
                    "targetPath": rel_addon,
                    "sha256": digest,
                    "size": size,
                }
            )

    manifest["files"] = entries
    with manifest_path.open("w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(manifest, indent=2) + "\n")
    print(f"Updated {manifest_path} with {len(entries)} file entries.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
