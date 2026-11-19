#!/usr/bin/env python3
"""Read-only verification of OverlordsXI launcher manifest.json and client files.

Never rewrites manifest.json or client files on disk.
Exits 0 when valid, non-zero with actionable diagnostics on any corruption or mismatch.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

VALID_CATEGORIES = {"dat", "plugin", "addon"}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
CONFLICT_MARKER_RE = re.compile(r"^(<{7}|={7}|>{7})(?:\s|$)")

REQUIRED_TOP_LEVEL_KEYS = (
    "schemaVersion",
    "serverName",
    "defaultHost",
    "useHairpin",
    "ports",
    "repo",
    "bootstrap",
    "files",
)


def _reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
    obj: dict[str, object] = {}
    for key, val in pairs:
        if key in obj:
            raise ValueError(f"Duplicate JSON key: {key!r}")
        obj[key] = val
    return obj


def _reject_json_constant(token: str) -> object:
    raise ValueError(f"Invalid JSON constant: {token!r}")


def _validate_rel_posix_path(value: object, field_name: str, entry_idx: int, errors: list[str]) -> str | None:
    if not isinstance(value, str) or not value.strip():
        errors.append(f"files[{entry_idx}].{field_name} must be a non-empty string")
        return None
    if "\\" in value:
        errors.append(f"files[{entry_idx}].{field_name} must use POSIX forward slashes: {value!r}")
        return None
    if value.startswith("/") or ".." in value.split("/"):
        errors.append(f"files[{entry_idx}].{field_name} must be a safe relative path: {value!r}")
        return None
    return value


def expected_client_files(repo_root: Path) -> dict[str, tuple[str, str]]:
    """Return mapping of repo-relative sourcePath -> (category, targetPath) for all client payload files."""
    expected: dict[str, tuple[str, str]] = {}
    roots = [
        ("dat", repo_root / "dat-overlay" / "ROM", repo_root / "dat-overlay"),
        ("plugin", repo_root / "plugins" / "ashita4", repo_root / "plugins" / "ashita4"),
        ("addon", repo_root / "addons" / "ashita4", repo_root / "addons" / "ashita4"),
    ]
    for category, scan_root, target_base in roots:
        if not scan_root.exists():
            continue
        for file_path in sorted(
            (p for p in scan_root.rglob("*") if p.is_file()),
            key=lambda p: p.relative_to(repo_root).as_posix().lower(),
        ):
            rel_source = file_path.relative_to(repo_root).as_posix()
            rel_target = file_path.relative_to(target_base).as_posix()
            expected[rel_source] = (category, rel_target)
    return expected


def verify_manifest(repo_root: Path, manifest_path: Path | None = None) -> list[str]:
    """Verify manifest.json strictly in read-only mode. Returns a list of error strings (empty == valid)."""
    repo_root = repo_root.resolve()
    manifest_file = (manifest_path or (repo_root / "manifest.json")).resolve()
    errors: list[str] = []

    if not manifest_file.is_file():
        return [f"Manifest file not found: {manifest_file}"]

    raw_text = manifest_file.read_text(encoding="utf-8", errors="replace")

    # 1. Explicit merge-conflict marker scan before JSON parsing
    for lineno, line in enumerate(raw_text.splitlines(), start=1):
        if CONFLICT_MARKER_RE.match(line):
            errors.append(f"Merge-conflict marker detected in {manifest_file.name} at line {lineno}: {line[:80]!r}")
    if errors:
        return errors

    # 2. Strict JSON parse (rejects syntax errors, duplicate keys, NaN/Infinity)
    try:
        manifest = json.loads(
            raw_text,
            object_pairs_hook=_reject_duplicate_keys,
            parse_constant=_reject_json_constant,
        )
    except (json.JSONDecodeError, ValueError) as exc:
        return [f"Invalid JSON in {manifest_file.name}: {exc}"]

    if not isinstance(manifest, dict):
        return [f"{manifest_file.name} root must be a JSON object"]

    # 3. Top-level schema structure checks
    for key in REQUIRED_TOP_LEVEL_KEYS:
        if key not in manifest:
            errors.append(f"Missing required top-level key: {key!r}")

    if manifest.get("schemaVersion") != 1:
        errors.append(f"Unsupported schemaVersion: {manifest.get('schemaVersion')!r} (expected 1)")
    if not isinstance(manifest.get("serverName"), str) or not manifest["serverName"].strip():
        errors.append("serverName must be a non-empty string")
    if not isinstance(manifest.get("defaultHost"), str) or not manifest["defaultHost"].strip():
        errors.append("defaultHost must be a non-empty string")
    if not isinstance(manifest.get("useHairpin"), bool):
        errors.append("useHairpin must be a boolean")

    ports = manifest.get("ports")
    if not isinstance(ports, dict):
        errors.append("ports must be an object")
    else:
        for port_key in ("lobby", "auth", "search"):
            val = ports.get(port_key)
            if not isinstance(val, int) or isinstance(val, bool) or val <= 0 or val > 65535:
                errors.append(f"ports.{port_key} must be an integer between 1 and 65535")

    repo_cfg = manifest.get("repo")
    if not isinstance(repo_cfg, dict):
        errors.append("repo must be an object")
    else:
        for rk in ("owner", "name", "branch", "rawBaseUrl"):
            if not isinstance(repo_cfg.get(rk), str) or not repo_cfg[rk].strip():
                errors.append(f"repo.{rk} must be a non-empty string")

    if not isinstance(manifest.get("bootstrap"), dict):
        errors.append("bootstrap must be an object")

    files = manifest.get("files")
    if not isinstance(files, list) or len(files) == 0:
        errors.append("files must be a non-empty list")
        return errors

    # 4. Per-entry validation, duplicate checks, source existence, and SHA-256 / size checks
    seen_targets: dict[tuple[str, str], int] = {}
    seen_sources: dict[str, int] = {}
    manifest_sources: dict[str, tuple[str, str]] = {}

    for idx, entry in enumerate(files):
        if not isinstance(entry, dict):
            errors.append(f"files[{idx}] must be an object")
            continue

        category = entry.get("category")
        if category not in VALID_CATEGORIES:
            errors.append(f"files[{idx}].category invalid: {category!r} (expected one of {sorted(VALID_CATEGORIES)})")

        source_path = _validate_rel_posix_path(entry.get("sourcePath"), "sourcePath", idx, errors)
        target_path = _validate_rel_posix_path(entry.get("targetPath"), "targetPath", idx, errors)

        sha256 = entry.get("sha256")
        if not isinstance(sha256, str) or not SHA256_RE.match(sha256):
            errors.append(f"files[{idx}].sha256 must be a 64-character lowercase hex digest: {sha256!r}")

        size = entry.get("size")
        if not isinstance(size, int) or isinstance(size, bool) or size < 0:
            errors.append(f"files[{idx}].size must be a non-negative integer: {size!r}")

        if source_path:
            src_key = source_path.lower()
            if src_key in seen_sources:
                errors.append(
                    f"Duplicate sourcePath in manifest: {source_path!r} (entries {seen_sources[src_key]} and {idx})"
                )
            else:
                seen_sources[src_key] = idx

        if category in VALID_CATEGORIES and target_path:
            tgt_key = (str(category), target_path.lower())
            if tgt_key in seen_targets:
                errors.append(
                    f"Duplicate targetPath in manifest for category {category!r}: "
                    f"{target_path!r} (entries {seen_targets[tgt_key]} and {idx})"
                )
            else:
                seen_targets[tgt_key] = idx

        if source_path and target_path and category in VALID_CATEGORIES:
            manifest_sources[source_path] = (str(category), target_path)

        if source_path and isinstance(sha256, str) and SHA256_RE.match(sha256) and isinstance(size, int):
            full_path = repo_root / source_path
            if not full_path.is_file():
                errors.append(f"Missing source file for files[{idx}]: {source_path}")
                continue
            raw_bytes = full_path.read_bytes()
            actual_size = len(raw_bytes)
            actual_sha = hashlib.sha256(raw_bytes).hexdigest()
            if actual_sha != sha256 or actual_size != size:
                crlf_hint = ""
                if b"\r\n" in raw_bytes:
                    lf_bytes = raw_bytes.replace(b"\r\n", b"\n")
                    if hashlib.sha256(lf_bytes).hexdigest() == sha256:
                        crlf_hint = " (file has CRLF line endings; normalize to LF)"
                errors.append(
                    f"Checksum/size mismatch for {source_path}: "
                    f"manifest=({sha256[:12]}..., {size}B) vs disk=({actual_sha[:12]}..., {actual_size}B){crlf_hint}"
                )

    # 5. Completeness check against client payload directories
    expected = expected_client_files(repo_root)
    for src, (cat, tgt) in sorted(expected.items()):
        if src not in manifest_sources:
            errors.append(f"Client file missing from manifest.json: {src} (category={cat}, targetPath={tgt})")
        else:
            m_cat, m_tgt = manifest_sources[src]
            if (m_cat, m_tgt) != (cat, tgt):
                errors.append(
                    f"Manifest routing mismatch for {src}: manifest=({m_cat}, {m_tgt}) vs expected=({cat}, {tgt})"
                )

    for src in sorted(manifest_sources):
        if src not in expected:
            errors.append(f"Manifest entry points outside expected client payload roots: {src}")

    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "repo",
        nargs="?",
        default=str(Path(__file__).resolve().parent.parent),
        help="Launcher repository root (defaults to parent of scripts/)",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=None,
        help="Optional explicit path to manifest.json",
    )
    args = parser.parse_args(argv)

    repo_root = Path(args.repo).resolve()
    errors = verify_manifest(repo_root, manifest_path=args.manifest)
    if errors:
        print(f"Manifest verification FAILED with {len(errors)} error(s):", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    manifest_file = (args.manifest or (repo_root / "manifest.json")).resolve()
    manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
    print(f"Manifest verification PASSED ({len(manifest['files'])} files verified, read-only).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
