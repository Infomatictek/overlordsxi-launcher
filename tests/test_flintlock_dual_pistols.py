"""Focused validation tests for COR Flintlock Phase 1 dual-pistol integration."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

EXPECTED_RACE_SKELETON_DATS = {
    "ROM/27/82.DAT",
    "ROM/32/58.DAT",
    "ROM/37/31.DAT",
    "ROM/42/4.DAT",
    "ROM/46/93.DAT",
    "ROM/51/89.DAT",
    "ROM/56/59.DAT",
}


def _load_verifier():
    path = REPO_ROOT / "scripts" / "verify-launcher-manifest.py"
    spec = importlib.util.spec_from_file_location("verify_launcher_manifest", str(path))
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules["verify_launcher_manifest"] = mod
    spec.loader.exec_module(mod)
    return mod


verifier = _load_verifier()


class FlintlockDualPistolsValidationTests(unittest.TestCase):
    def test_compact_overlay_asset_mapping_and_integrity(self):
        overlay_root = REPO_ROOT / "dat-overlays" / "flintlock-akimbo-compact" / "ROM"
        self.assertTrue(overlay_root.is_dir(), "Staged compact overlay ROM directory must exist")

        dat_files = sorted(p for p in overlay_root.rglob("*") if p.is_file())
        self.assertEqual(len(dat_files), 278, "Expected 7 skeleton + 271 firearm = 278 DAT files")

        rel_paths = {p.relative_to(overlay_root.parent).as_posix() for p in dat_files}
        self.assertTrue(
            EXPECTED_RACE_SKELETON_DATS.issubset(rel_paths),
            f"Missing race skeleton DATs: {EXPECTED_RACE_SKELETON_DATS - rel_paths}",
        )
        self.assertEqual(len(rel_paths - EXPECTED_RACE_SKELETON_DATS), 271)

        # Zero conflicts with base SoulspireXI dat-overlay/ROM/
        base_rom = REPO_ROOT / "dat-overlay" / "ROM"
        base_rels = {p.relative_to(base_rom.parent).as_posix().lower() for p in base_rom.rglob("*") if p.is_file()}
        conflicts = {r for r in rel_paths if r.lower() in base_rels}
        self.assertEqual(conflicts, set(), f"Unexpected DAT path conflicts with base overlay: {conflicts}")

    def test_manifest_optional_overlay_is_disabled_by_default_and_gated(self):
        manifest = json.loads((REPO_ROOT / "manifest.json").read_text(encoding="utf-8"))
        optional_overlays = manifest.get("optionalOverlays", [])
        matches = [o for o in optional_overlays if o.get("id") == "flintlock-akimbo-compact"]
        self.assertEqual(len(matches), 1)

        ov = matches[0]
        self.assertIs(ov.get("defaultEnabled"), False, "Flintlock overlay must be disabled by default")
        self.assertEqual(ov.get("overlayFolder"), "flintlock-akimbo-compact")
        self.assertEqual(ov.get("soulGate"), {"job": 17, "branch": 1, "soul": "flintlock"})
        self.assertEqual(len(ov.get("files", [])), 278)

        # Core manifest.files must NOT contain any Flintlock dual-pistol DATs
        core_dats = {
            f["targetPath"].lower()
            for f in manifest.get("files", [])
            if f.get("category") == "dat"
        }
        for entry in ov["files"]:
            self.assertNotIn(entry["targetPath"].lower(), core_dats)

    def test_verifier_rejects_optional_overlay_conflict_with_base_dat(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            base_dat = tmp / "dat-overlay" / "ROM" / "118" / "108.DAT"
            base_dat.parent.mkdir(parents=True, exist_ok=True)
            base_dat.write_bytes(b"base")

            opt_dat = tmp / "dat-overlays" / "flintlock-akimbo-compact" / "ROM" / "118" / "108.DAT"
            opt_dat.parent.mkdir(parents=True, exist_ok=True)
            opt_dat.write_bytes(b"conflict")

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
                        "category": "dat",
                        "sourcePath": "dat-overlay/ROM/118/108.DAT",
                        "targetPath": "ROM/118/108.DAT",
                        "sha256": hashlib.sha256(b"base").hexdigest(),
                        "size": 4,
                    }
                ],
                "optionalOverlays": [
                    {
                        "id": "flintlock-akimbo-compact",
                        "name": "Flintlock",
                        "description": "Conflict test",
                        "overlayFolder": "flintlock-akimbo-compact",
                        "defaultEnabled": False,
                        "files": [
                            {
                                "category": "dat-optional",
                                "sourcePath": "dat-overlays/flintlock-akimbo-compact/ROM/118/108.DAT",
                                "targetPath": "ROM/118/108.DAT",
                                "sha256": hashlib.sha256(b"conflict").hexdigest(),
                                "size": 8,
                            }
                        ],
                    }
                ],
            }
            (tmp / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
            errors = verifier.verify_manifest(tmp)
            self.assertTrue(
                any("conflicts with base dat-overlay" in e for e in errors),
                f"Expected conflict error, got: {errors}",
            )

    def test_holstered_pistols_are_symmetrical_across_all_182_firearm_dats(self):
        overlay_root = REPO_ROOT / "dat-overlays" / "flintlock-akimbo-compact" / "ROM"
        firearm_count = 0
        skel_count = 0

        def iter_sections(raw: bytes):
            pos = 0
            n = len(raw)
            while pos + 16 <= n:
                name = raw[pos : pos + 4]
                word = struct.unpack_from("<I", raw, pos + 4)[0]
                kind = word & 0x7F
                size = ((word >> 7) & 0x7FFFF) * 16
                if size < 16 or pos + size > n:
                    break
                yield kind, name, raw[pos : pos + size]
                pos += size

        def rigid_centroid(sec_raw: bytes, n_verts: int):
            body = sec_raw[16:]
            v_off = 2 * struct.unpack_from("<I", body, 30)[0]
            sx = sy = sz = 0.0
            for i in range(n_verts):
                x, y, z = struct.unpack_from("<fff", body, v_off + i * 24)
                sx += x
                sy += y
                sz += z
            return sx / n_verts, sy / n_verts, sz / n_verts

        for dat_path in sorted(overlay_root.rglob("*.DAT")):
            rel = dat_path.relative_to(overlay_root.parent).as_posix()
            raw = dat_path.read_bytes()
            secs = {(k, n): d for k, n, d in iter_sections(raw)}

            if rel in EXPECTED_RACE_SKELETON_DATS:
                skel_count += 1
                for req in (
                    (0x2B, b"q3d0"), (0x2B, b"q3d1"), (0x2B, b"q3d2"),
                    (0x2B, b"q3h0"), (0x2B, b"q3h1"), (0x2B, b"q3h2"),
                    (0x2B, b"q3a0"), (0x2B, b"q3a1"), (0x2B, b"q3a2"),
                    (0x07, b"lc07"), (0x07, b"ls07"), (0x07, b"splg"),
                ):
                    self.assertIn(req, secs, f"Missing skeleton section {req} in {rel}")
                continue

            if (0x2A, b"wep8") not in secs or (0x2A, b"wep7") not in secs:
                continue

            firearm_count += 1
            self.assertIn((0x2A, b"wep2"), secs, f"Missing wep2 in {rel}")
            info = next((d for (k, n), d in secs.items() if n == b"info"), None)
            self.assertIsNotNone(info, f"Missing info section in {rel}")
            self.assertEqual(info[30], 0x07, f"Expected AkimboRA info[30]=0x07 in {rel}")

            wep2_body = secs[(0x2A, b"wep2")][16:]
            n_gun = struct.unpack_from("<H", wep2_body, 2 * struct.unpack_from("<I", wep2_body, 18)[0])[0]
            c8 = rigid_centroid(secs[(0x2A, b"wep8")], n_gun)
            c7 = rigid_centroid(secs[(0x2A, b"wep7")], n_gun)

            self.assertLess(abs(c8[0] + c7[0]), 0.015, f"X asymmetry in {rel}: wep8={c8} wep7={c7}")
            self.assertLess(abs(c8[1] - c7[1]), 0.005, f"Y asymmetry in {rel}: wep8={c8} wep7={c7}")
            self.assertLess(abs(c8[2] - c7[2]), 0.005, f"Z asymmetry in {rel}: wep8={c8} wep7={c7}")
            self.assertLess(abs(c8[2]), 0.25, f"Unexpected rear/front Z offset in {rel}: wep8={c8}")
            self.assertLess(abs(c7[2]), 0.25, f"Unexpected rear/front Z offset in {rel}: wep7={c7}")

        self.assertEqual(skel_count, 7)
        self.assertEqual(firearm_count, 182)

    def test_flintlock_lua_unit_suite_passes(self):
        lua_bin = shutil.which("luajit") or shutil.which("lua")
        if not lua_bin:
            self.skipTest("Neither luajit nor lua found in PATH")
        spec = REPO_ROOT / "addons" / "ashita4" / "soulspire_flintlock" / "tests" / "flintlock_spec.lua"
        proc = subprocess.run([lua_bin, str(spec)], cwd=str(REPO_ROOT), capture_output=True, text=True, check=False)
        self.assertEqual(proc.returncode, 0, f"Lua test failed:\n{proc.stdout}\n{proc.stderr}")
        self.assertIn("soulspire_flintlock tests: OK", proc.stdout)


if __name__ == "__main__":
    unittest.main()
