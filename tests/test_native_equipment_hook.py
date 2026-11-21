import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
NATIVE_DIR = ROOT / "native" / "crystaljobs"
CS_DIR = ROOT / "addons" / "ashita4" / "crystalsocket"


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
            "CrystalJobsReplaceWeaponRules",
            "CrystalJobsClearWeaponRules",
            "CrystalJobsGetWeaponStatus",
        ):
            self.assertIn(sym, header)

        def_text = (NATIVE_DIR / "crystaljobs.def").read_text(encoding="utf-8")
        build_cmd = (NATIVE_DIR / "build.cmd").read_text(encoding="utf-8")
        for exp in (
            "CrystalJobsReplaceWeaponRules@8",
            "CrystalJobsClearWeaponRules@0",
            "CrystalJobsGetWeaponStatus@8",
        ):
            self.assertIn(exp, def_text)
            self.assertIn(exp, build_cmd)

    def test_crystaljobs_cpp_wires_hook_24_and_relocation(self):
        cpp = (NATIVE_DIR / "crystaljobs.cpp").read_text(encoding="utf-8")
        self.assertIn("soul_sub_weapon_detour{0x133D56", cpp)
        self.assertIn("rva == 0xEB5D0", cpp)
        self.assertIn("base + 0x133D5B", cpp)
        self.assertIn("base + 0x133D65", cpp)
        self.assertIn("base + 0x6229C0", cpp)
        self.assertIn("static_assert(sizeof(CrystalJobsWeaponRule) == 24)", cpp)
        self.assertIn("static_assert(sizeof(CrystalJobsWeaponStatus) == 36)", cpp)
        self.assertIn("sizeof(patches) / sizeof(*patches)) + 3", cpp)
        self.assertIn("CRYSTALJOBS_CAP_SOUL_SUB_WEAPON", cpp)

        selftest = (NATIVE_DIR / "selftest.cpp").read_text(encoding="utf-8")
        self.assertIn("weapon_rule_checks();", selftest)
        self.assertIn("wpn_st.expected_hooks == 24", selftest)
        self.assertIn("vis_st.expected_hooks == 24", selftest)
        self.assertIn("act_st.expected_hooks == 24", selftest)

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


if __name__ == "__main__":
    unittest.main()
