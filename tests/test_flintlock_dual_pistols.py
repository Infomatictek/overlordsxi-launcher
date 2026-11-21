"""Focused validation tests for COR Flintlock Phase 1 dual-pistol integration."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import math
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

    def test_flintlock_lua_unit_suite_passes(self):
        lua_bin = shutil.which("luajit") or shutil.which("lua")
        if not lua_bin:
            self.skipTest("Neither luajit nor lua found in PATH")
        spec = REPO_ROOT / "addons" / "ashita4" / "soulspire_flintlock" / "tests" / "flintlock_spec.lua"
        proc = subprocess.run([lua_bin, str(spec)], cwd=str(REPO_ROOT), capture_output=True, text=True, check=False)
        self.assertEqual(proc.returncode, 0, f"Lua test failed:\n{proc.stdout}\n{proc.stderr}")
        self.assertIn("soulspire_flintlock tests: OK", proc.stdout)

    def test_no_0xa3_blink_opcode_and_valid_weapon_visibility_and_motions(self):
        patcher_path = REPO_ROOT / "tools" / "patch_flintlock_skeleton_blink.py"
        spec = importlib.util.spec_from_file_location("patch_flintlock_skeleton_blink", str(patcher_path))
        assert spec and spec.loader
        patcher = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(patcher)

        overlay_root = REPO_ROOT / "dat-overlays" / "flintlock-akimbo-compact"
        # 1. Verify zero 0xa3 scheduler commands across ALL 278 overlay DATs
        a3_hits = []
        for dat_path in sorted((overlay_root / "ROM").rglob("*.DAT")):
            for kind, name, raw in patcher.parse_sections(dat_path.read_bytes()):
                if kind != 7:
                    continue
                try:
                    _, _, _, events = patcher.parse_routine(raw[16:])
                except ValueError:
                    continue
                for tick, cmd in events:
                    if cmd[0] == 0xA3:
                        a3_hits.append((dat_path.relative_to(overlay_root).as_posix(), name, tick))
        self.assertEqual(a3_hits, [], f"Unexpected 0xa3 actor-visibility commands found: {a3_hits}")

        # 2. Verify all 7 skeleton DATs preserve 0x75 weapon visibility timing and clean q3* motion clips
        for rel in sorted(EXPECTED_RACE_SKELETON_DATS):
            rows = patcher.parse_sections((overlay_root / rel).read_bytes())
            routines = {name: raw for kind, name, raw in rows if kind == 7 and name in {b"lc07", b"ls07", b"splg"}}
            self.assertEqual(set(routines.keys()), {b"lc07", b"ls07", b"splg"}, f"Missing routines in {rel}")

            def vis75(rname):
                _, _, _, evs = patcher.parse_routine(routines[rname][16:])
                return [
                    (t, struct.unpack_from("<H", c, 6)[0], struct.unpack_from("<I", c, 8)[0], struct.unpack_from("<h", c, 12)[0])
                    for t, c in evs
                    if c[0] == 0x75
                ]

            lc07_vis = vis75(b"lc07")
            self.assertIn((0, 0, 1, 2), lc07_vis, f"{rel} lc07 missing t=0 hide wep2")
            self.assertIn((1, 0, 1, 2), lc07_vis, f"{rel} lc07 missing t=1 hide wep2")
            self.assertIn((16, 0, 0, 2), lc07_vis, f"{rel} lc07 missing t=16 show wep2")
            self.assertTrue(any(t == 16 and slot == 8 and dur > 0 for t, dur, _, slot in lc07_vis))
            self.assertTrue(any(t == 16 and slot == 7 and dur > 0 for t, dur, _, slot in lc07_vis))

            ls07_vis = vis75(b"ls07")
            self.assertIn((74, 0, 1, 2), ls07_vis, f"{rel} ls07 missing t=74 hide wep2")
            self.assertIn((74, 0, 0, 8), ls07_vis, f"{rel} ls07 missing t=74 restore wep8")
            self.assertIn((74, 0, 0, 7), ls07_vis, f"{rel} ls07 missing t=74 restore wep7")

            splg_vis = vis75(b"splg")
            self.assertIn((0, 0, 1, 2), splg_vis, f"{rel} splg missing t=0 hide wep2")
            self.assertIn((0, 0, 0, 8), splg_vis, f"{rel} splg missing t=0 restore wep8")
            self.assertIn((0, 0, 0, 7), splg_vis, f"{rel} splg missing t=0 restore wep7")

            # Check all 9 custom motion clips (q3d0..2, q3h0..2, q3a0..2) for finite transforms & positive scale
            motions = {name: raw for kind, name, raw in rows if kind == 0x2B and name.startswith(b"q3")}
            self.assertEqual(len(motions), 9, f"Expected 9 q3* motion sections in {rel}")
            for mname, mraw in motions.items():
                d = mraw[16:]
                _, joints, frames, _ = struct.unpack_from("<HHHf", d)
                self.assertGreater(joints, 0)
                self.assertGreater(frames, 0)
                for row_i in range(joints):
                    st = 10 + 84 * row_i + 4
                    for g_idx, width in enumerate((4, 3, 3)):
                        offs = struct.unpack_from(f"<{width}i", d, st)
                        consts = struct.unpack_from(f"<{width}f", d, st + width * 4)
                        st += 8 * width
                        if any(v < 0 for v in offs):
                            break
                        for off, cval in zip(offs, consts):
                            vals = struct.unpack_from(f"<{frames}f", d, 10 + 4 * off) if off else (cval,)
                            for v in vals:
                                self.assertTrue(math.isfinite(v), f"Non-finite value in {rel} {mname!r}")
                                if g_idx == 2:
                                    self.assertGreater(v, 0.0, f"Non-positive bone scale in {rel} {mname!r}")


if __name__ == "__main__":
    unittest.main()
