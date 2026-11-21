import pathlib
import re
import struct
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
NATIVE_DIR = ROOT / "native" / "crystaljobs"
CS_DIR = ROOT / "addons" / "ashita4" / "crystalsocket"
SHIPPED_DLL = ROOT / "plugins" / "ashita4" / "crystaljobs.dll"


def parse_pe32_exports(path: pathlib.Path):
    data = path.read_bytes()
    if data[:2] != b"MZ":
        raise AssertionError("Missing MZ DOS signature")
    pe_off = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe_off : pe_off + 4] != b"PE\x00\x00":
        raise AssertionError("Missing PE signature")
    machine, num_sections, _, _, _, opt_size, chars = struct.unpack_from("<HHIIIHH", data, pe_off + 4)
    opt_off = pe_off + 24
    magic = struct.unpack_from("<H", data, opt_off)[0]
    export_rva, export_size = struct.unpack_from("<II", data, opt_off + 96)

    sections = []
    sec_off = opt_off + opt_size
    for i in range(num_sections):
        off = sec_off + i * 40
        vsize, vaddr, rsize, rptr = struct.unpack_from("<IIII", data, off + 8)
        sections.append((vaddr, max(vsize, rsize), rptr))

    def rva_to_off(rva: int) -> int:
        for vaddr, span, rptr in sections:
            if vaddr <= rva < vaddr + span:
                return rptr + (rva - vaddr)
        raise AssertionError(f"Unmapped RVA 0x{rva:x}")

    names = []
    if export_rva and export_size:
        exp_off = rva_to_off(export_rva)
        num_names = struct.unpack_from("<I", data, exp_off + 24)[0]
        names_rva = struct.unpack_from("<I", data, exp_off + 32)[0]
        names_off = rva_to_off(names_rva)
        for i in range(num_names):
            name_rva = struct.unpack_from("<I", data, names_off + i * 4)[0]
            name_off = rva_to_off(name_rva)
            end = data.index(b"\x00", name_off)
            names.append(data[name_off:end].decode("ascii"))
    return machine, magic, chars, names


class NativeEquipmentHookTests(unittest.TestCase):
    def test_layout_contains_verified_sub_weapon_signatures(self):
        layout = (NATIVE_DIR / "layout.h").read_text(encoding="utf-8")
        self.assertIn("{0x133D56, {0x68, 0x8b, 0x00, 0x00, 0x00, 0xe8, 0x60, 0x75, 0xff, 0xff", layout)
        self.assertIn("{0xEB5D0, {0x8b, 0x15, 0x48, 0x0f, 0x4e, 0x10", layout)
        self.assertIn("{0x15D210, {0xb8, 0xac, 0x15, 0x00, 0x00, 0xe8, 0x76, 0x65, 0x1b, 0x00", layout)

    def test_crystaljobs_header_and_exports_define_weapon_rule_abi(self):
        header = (NATIVE_DIR / "crystaljobs.h").read_text(encoding="utf-8")
        for sym in (
            "CRYSTALJOBS_CAP_SOUL_SUB_WEAPON",
            "CRYSTALJOBS_WEAPON_MODE_DUAL_1H",
            "typedef struct CrystalJobsWeaponRule",
            "typedef struct CrystalJobsWeaponStatus",
            "typedef struct CrystalJobsHookDiagnostics",
            "CrystalJobsReplaceWeaponRules",
            "CrystalJobsClearWeaponRules",
            "CrystalJobsGetWeaponStatus",
            "CrystalJobsGetHookDiagnostics",
        ):
            self.assertIn(sym, header)

        def_text = (NATIVE_DIR / "crystaljobs.def").read_text(encoding="utf-8")
        build_cmd = (NATIVE_DIR / "build.cmd").read_text(encoding="utf-8")
        for exp in (
            "CrystalJobsReplaceWeaponRules@8",
            "CrystalJobsClearWeaponRules@0",
            "CrystalJobsGetWeaponStatus@8",
            "CrystalJobsGetHookDiagnostics@8",
        ):
            self.assertIn(exp, def_text)
            self.assertIn(exp, build_cmd)

    def test_crystaljobs_cpp_wires_hook_24_and_relocation(self):
        cpp = (NATIVE_DIR / "crystaljobs.cpp").read_text(encoding="utf-8")
        self.assertIn("soul_sub_weapon_detour{0x133D56", cpp)
        self.assertIn("soul_sub_menu_filter_detour{0x21DF85", cpp)
        self.assertIn("soul_sub_2h_main_detour{0x133DD3", cpp)
        self.assertIn("rva == 0xEB5D0", cpp)
        self.assertIn("base + 0x133D5B", cpp)
        self.assertIn("base + 0x133D65", cpp)
        self.assertIn("base + 0x6229C0", cpp)
        self.assertIn("static_assert(sizeof(CrystalJobsWeaponRule) == 24)", cpp)
        self.assertIn("static_assert(sizeof(CrystalJobsWeaponStatus) == 36)", cpp)
        self.assertIn("static_assert(sizeof(CrystalJobsHookDiagnostics) == 60)", cpp)
        self.assertIn("static_assert(kExpectedHooks == 26u)", cpp)
        self.assertIn("collect_hook_state(", cpp)
        self.assertIn("CrystalJobsGetHookDiagnostics", cpp)
        self.assertIn("CRYSTALJOBS_CAP_SOUL_SUB_WEAPON", cpp)
        self.assertIn("CRYSTALJOBS_CAP_SOUL_SUB_2H", cpp)

        selftest = (NATIVE_DIR / "selftest.cpp").read_text(encoding="utf-8")
        self.assertIn("weapon_rule_checks();", selftest)
        self.assertIn("wpn_st.expected_hooks == 26", selftest)
        self.assertIn("vis_st.expected_hooks == 26", selftest)
        self.assertIn("act_st.expected_hooks == 26", selftest)
        self.assertIn("CrystalJobsGetHookDiagnostics", selftest)

    def test_crystalsocket_removed_custom_equipment_picker_and_preserves_soul_ui(self):
        self.assertFalse((CS_DIR / "buckler.lua").exists(), "Legacy buckler.lua must be removed")

        ui_lua = (CS_DIR / "ui.lua").read_text(encoding="utf-8")
        for forbidden in ("##crystal_buckler", "open_buckler", "close_buckler", "SUB_NATIVE_SLOT", "WeaponConfig"):
            self.assertNotIn(forbidden, ui_lua)
        # Soul Crystal UI must remain intact
        for required in ("##crystal_socket", "##crystal_collection", "draw_crystal_tooltip", "Remove crystal"):
            self.assertIn(required, ui_lua)

        cs_lua = (CS_DIR / "crystalsocket.lua").read_text(encoding="utf-8")
        self.assertIsNone(re.search(r"/equip%s\+sub", cs_lua), "crystalsocket.lua must not intercept /equip sub")
        self.assertIn("labels:sync_weapon_rules(native_weapon_rules)", cs_lua)

        wc_lua = (CS_DIR / "weapon_config.lua").read_text(encoding="utf-8")
        self.assertNotIn("AddOutgoingPacket", wc_lua, "weapon_config.lua must not inject raw 0x050 packets")
        self.assertIn("function W.native_rules()", wc_lua)

    def test_shipped_crystaljobs_dll_is_x86_pe32_with_all_21_exports(self):
        self.assertTrue(SHIPPED_DLL.is_file(), "Missing plugins/ashita4/crystaljobs.dll")
        machine, magic, chars, exports = parse_pe32_exports(SHIPPED_DLL)
        self.assertEqual(machine, 0x014C, "crystaljobs.dll must be Win32 x86 (IMAGE_FILE_MACHINE_I386)")
        self.assertEqual(magic, 0x010B, "crystaljobs.dll must be PE32")
        self.assertNotEqual(chars & 0x2000, 0, "crystaljobs.dll must have IMAGE_FILE_DLL characteristic")
        expected_exports = [
            "CrystalJobsClearActiveSoul",
            "CrystalJobsClearCatalog",
            "CrystalJobsClearVisibility",
            "CrystalJobsClearWeaponRules",
            "CrystalJobsGetActionStatus",
            "CrystalJobsGetHookDiagnostics",
            "CrystalJobsGetStatus",
            "CrystalJobsGetVisibilityStatus",
            "CrystalJobsGetWeaponStatus",
            "CrystalJobsInitialize",
            "CrystalJobsReplaceCatalog",
            "CrystalJobsReplaceVisibility",
            "CrystalJobsReplaceWeaponRules",
            "CrystalJobsSetActionRowLimit",
            "CrystalJobsSetActiveSoul",
            "CrystalJobsSetState",
            "CrystalJobsShutdown",
            "CrystalJobsUpsertAction",
            "expCreatePlugin",
            "expDestroyPlugin",
            "expGetInterfaceVersion",
        ]
        self.assertEqual(len(exports), 21, f"Expected 21 PE exports, found {len(exports)}: {exports}")
        self.assertEqual(sorted(exports), sorted(expected_exports))

    def test_automated_packaging_workflow_and_dll_verifier_safeguards(self):
        import importlib.util

        spec = importlib.util.spec_from_file_location(
            "verify_crystaljobs_dll",
            ROOT / "scripts" / "verify-crystaljobs-dll.py",
        )
        mod = importlib.util.module_from_spec(spec)
        assert spec.loader is not None
        spec.loader.exec_module(mod)

        # Must reject the legacy 24-hook DLL when 26-hook validation is active,
        # and accept the fresh 26-hook DLL once staged in CI.
        summary = mod.verify_dll(SHIPPED_DLL, require_26_hooks=False)
        self.assertEqual(summary["export_count"], 21)
        if summary["sha256"] == mod.STALE_24_HOOK_SHA256:
            with self.assertRaises(ValueError):
                mod.verify_dll(SHIPPED_DLL, require_26_hooks=True)
        else:
            strict = mod.verify_dll(SHIPPED_DLL, require_26_hooks=True)
            self.assertTrue(strict["has_26_hook_sigs"])

        wf = (ROOT / ".github" / "workflows" / "build-launcher.yml").read_text(encoding="utf-8")
        for required in (
            "package-verified-launcher:",
            "needs: [verify-manifest, build-crystaljobs, build-and-test]",
            "actions/download-artifact@",
            "name: crystaljobs-win-x86",
            "scripts/verify-crystaljobs-dll.py",
            "scripts/update-launcher-manifest.py",
            "scripts/verify-launcher-manifest.py",
            "name: SoulspireXI-Verified-Package-win-x64",
        ):
            self.assertIn(required, wf)


if __name__ == "__main__":
    unittest.main()
