"""Unit tests for read-only SoulspireXI launcher manifest verification."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def _load_verifier():
    path = REPO_ROOT / "scripts" / "verify-launcher-manifest.py"
    spec = importlib.util.spec_from_file_location("verify_launcher_manifest", str(path))
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules["verify_launcher_manifest"] = mod
    spec.loader.exec_module(mod)
    return mod


verifier = _load_verifier()


def _make_valid_repo(tmp: Path) -> tuple[Path, dict]:
    addon_file = tmp / "addons" / "ashita4" / "demo" / "demo.lua"
    addon_file.parent.mkdir(parents=True, exist_ok=True)
    content = b"print('soulspirexi')\n"
    addon_file.write_bytes(content)

    manifest = {
        "schemaVersion": 1,
        "serverName": "SoulspireXI",
        "defaultHost": "127.0.0.1",
        "useHairpin": False,
        "ports": {"lobby": 54231, "auth": 54001, "search": 54002},
        "repo": {
            "owner": "Infomatictek",
            "name": "soulspirexi-launcher",
            "branch": "main",
            "rawBaseUrl": "https://raw.githubusercontent.com/Infomatictek/soulspirexi-launcher/main",
        },
        "bootstrap": {},
        "files": [
            {
                "category": "addon",
                "sourcePath": "addons/ashita4/demo/demo.lua",
                "targetPath": "demo/demo.lua",
                "sha256": hashlib.sha256(content).hexdigest(),
                "size": len(content),
            }
        ],
    }
    manifest_path = tmp / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest_path, manifest


class ManifestVerificationTests(unittest.TestCase):
    def test_real_repo_manifest_passes(self):
        errors = verifier.verify_manifest(REPO_ROOT)
        self.assertEqual(errors, [])

    def test_valid_synthetic_manifest_passes(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            _make_valid_repo(tmp)
            self.assertEqual(verifier.verify_manifest(tmp), [])

    def test_merge_conflict_markers_fail(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            mpath, _ = _make_valid_repo(tmp)
            text = mpath.read_text(encoding="utf-8")
            corrupted = text.replace(
                '"size": 21',
                '<<<<<<< HEAD\n      "size": 21\n=======\n      "size": 22\n>>>>>>> branch',
            )
            mpath.write_text(corrupted, encoding="utf-8")
            errors = verifier.verify_manifest(tmp)
            self.assertTrue(any("Merge-conflict marker" in e for e in errors))

    def test_invalid_json_unexpected_char_fails(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            mpath, _ = _make_valid_repo(tmp)
            mpath.write_text('{\n  "schemaVersion": 1,\n  <\n}\n', encoding="utf-8")
            errors = verifier.verify_manifest(tmp)
            self.assertTrue(any("Invalid JSON" in e for e in errors))

    def test_duplicate_json_keys_fail(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            mpath, _ = _make_valid_repo(tmp)
            mpath.write_text('{"schemaVersion": 1, "schemaVersion": 1}\n', encoding="utf-8")
            errors = verifier.verify_manifest(tmp)
            self.assertTrue(any("Duplicate JSON key" in e for e in errors))

    def test_duplicate_target_path_fails(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            mpath, manifest = _make_valid_repo(tmp)
            second = tmp / "addons" / "ashita4" / "demo" / "DEMO.lua"
            second.write_bytes(b"print('two')\n")
            manifest["files"].append(
                {
                    "category": "addon",
                    "sourcePath": "addons/ashita4/demo/DEMO.lua",
                    "targetPath": "demo/DEMO.lua",
                    "sha256": hashlib.sha256(b"print('two')\n").hexdigest(),
                    "size": 13,
                }
            )
            mpath.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
            errors = verifier.verify_manifest(tmp)
            self.assertTrue(any("Duplicate targetPath" in e for e in errors))

    def test_missing_source_file_fails(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            mpath, manifest = _make_valid_repo(tmp)
            (tmp / "addons" / "ashita4" / "demo" / "demo.lua").unlink()
            errors = verifier.verify_manifest(tmp)
            self.assertTrue(any("Missing source file" in e for e in errors))

    def test_checksum_mismatch_and_read_only_behavior(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            _make_valid_repo(tmp)
            addon_file = tmp / "addons" / "ashita4" / "demo" / "demo.lua"
            crlf_bytes = b"print('soulspirexi')\r\n"
            addon_file.write_bytes(crlf_bytes)

            errors = verifier.verify_manifest(tmp)
            self.assertTrue(any("Checksum/size mismatch" in e for e in errors))
            # Crucial: verify_manifest MUST be strictly read-only and never rewrite client files!
            self.assertEqual(addon_file.read_bytes(), crlf_bytes)

    def test_unlisted_client_file_fails(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            _make_valid_repo(tmp)
            (tmp / "addons" / "ashita4" / "demo" / "extra.lua").write_bytes(b"-- extra\n")
            errors = verifier.verify_manifest(tmp)
            self.assertTrue(any("Client file missing from manifest.json" in e for e in errors))


if __name__ == "__main__":
    unittest.main()
