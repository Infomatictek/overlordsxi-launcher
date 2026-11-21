"""Regression tests for client DAT spell eligibility, visibility policy, and helpwind text safety."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
DAT_114 = ROOT / "dat-overlay/ROM/118/114.DAT"
SOUL_ACTIONS_TSV = ROOT / "addons/ashita4/soulspire_soul_actions/data/soul_actions.tsv"
VISIBILITY_TSV = ROOT / "addons/ashita4/soulspire_soul_actions/data/visibility.tsv"
CRYSTALJOBS_CPP = ROOT / "native/crystaljobs/crystaljobs.cpp"
ACTIONS_H = ROOT / "native/crystaljobs/actions.h"


def _rol(byte: int, shift: int) -> int:
    return ((byte << shift) | (byte >> (8 - shift))) & 0xFF


def _decode_dat_spell_job_level(dat_bytes: bytes, spell_id: int, job_id: int) -> int:
    off = 0x28730 + spell_id * 100
    raw = dat_bytes[off : off + 100]
    for shift in range(8):
        rec_id = _rol(raw[0], shift) | (_rol(raw[1], shift) << 8)
        if rec_id == spell_id and _rol(raw[99], shift) == 0xFF:
            lo = _rol(raw[0x0E + job_id * 2], shift)
            hi = _rol(raw[0x0E + job_id * 2 + 1], shift)
            return lo | (hi << 8)
    raise AssertionError(f"Could not decode spell {spell_id} in 114.DAT")


class SoulSpellClientAuditTests(unittest.TestCase):
    def test_utsusemi_ni_not_globally_lowered_in_114_dat(self):
        dat = DAT_114.read_bytes()
        # Job 13 = NIN. Must remain vanilla Lv.37 so Lv.10 /NIN subjobs do not see it.
        self.assertEqual(_decode_dat_spell_job_level(dat, 339, 13), 37)

    def test_soul_actions_tsv_is_pure_ascii_printable(self):
        lines = SOUL_ACTIONS_TSV.read_text(encoding="utf-8").splitlines()
        bad = []
        for idx, line in enumerate(lines, start=1):
            if not line or line.startswith("#"):
                continue
            for ch in line:
                code = ord(ch)
                if ch != "\t" and (code < 0x20 or code > 0x7E):
                    bad.append((idx, ch, hex(code)))
        self.assertEqual(bad, [], f"Non-ASCII/control characters in soul_actions.tsv: {bad}")

    def test_visibility_policy_has_terramancer_shinobi_kagemusha_rules(self):
        rows = set()
        for line in VISIBILITY_TSV.read_text(encoding="utf-8").splitlines():
            if not line or line.startswith("#"):
                continue
            rows.add(tuple(line.split("\t")))
        self.assertIn(("terramancer", "spell", "159", "10", "unlock"), rows)
        self.assertIn(("terramancer", "spell", "160", "10", "unlock"), rows)
        self.assertIn(("terramancer", "spell", "161", "30", "unlock"), rows)
        self.assertIn(("shinobi", "spell", "338", "10", "unlock"), rows)
        self.assertIn(("shinobi", "spell", "339", "37", "unlock"), rows)
        self.assertIn(("kagemusha", "spell", "339", "10", "unlock"), rows)

    def test_crystaljobs_detours_can_use_spell_and_formats_descriptions(self):
        cpp = CRYSTALJOBS_CPP.read_text(encoding="utf-8")
        hdr = ACTIONS_H.read_text(encoding="utf-8")
        self.assertIn("can_use_spell_detour{0x22CDE0", cpp)
        self.assertIn("can_use_spell_detour.install(base, &original_can_show_spell)", cpp)
        self.assertIn("can_use_spell_detour.restore()", cpp)
        self.assertIn("missing_spell_bit_detour.install(base)", cpp)
        self.assertIn("missing_spell_bit_detour.restore()", cpp)
        self.assertIn("{0x22E64D, reinterpret_cast<void*>(&menu_spell_elig_hook)}", cpp)
        self.assertIn("original_spell_elig = reinterpret_cast<uintptr_t>(base + 0x1021A0)", cpp)
        self.assertIn("format_action_description(", cpp)
        self.assertIn("format_action_description(", hdr)
        self.assertIn("ch < 0x20u || ch >= 0x7Fu", hdr)


if __name__ == "__main__":
    unittest.main()
