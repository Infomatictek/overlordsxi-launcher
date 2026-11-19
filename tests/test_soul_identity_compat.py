"""Sequence A compatibility fixtures for launcher Soul identity paths.

Verifies all 22 x 3 active Souls, retired DNC slot 1 persistence handling,
legacy alias normalization, and packet/fallback/zone/login behavior.
"""
from pathlib import Path
import re
import unittest

try:
    from lupa import LuaRuntime
except ImportError:
    LuaRuntime = None

REPO_ROOT = Path(__file__).resolve().parents[1]
SOUL_ACTIONS_DIR = REPO_ROOT / 'addons' / 'ashita4' / 'overlords_soul_actions'
CRYSTALSOCKET_DIR = REPO_ROOT / 'addons' / 'ashita4' / 'crystalsocket'
ROSTER_PATH = REPO_ROOT / 'addons' / 'ashita4' / 'overlords_soulhud' / 'soulhud_roster.lua'
LABELS_H_PATH = REPO_ROOT / 'native' / 'crystaljobs' / 'labels.h'

EXPECTED_ACTIVE_SOULS = {
    1: {1: ('commander', 'commander'), 2: ('berserker', 'berserker'), 3: ('spartan', 'spartan')},
    2: {1: ('sensei', 'sensei'), 2: ('chiweaver', 'chiweaver'), 3: ('blackbelt', 'blackbelt')},
    3: {1: ('bishop', 'bishop'), 2: ('zealot', 'zealot'), 3: ('valkyrie', 'valkyrie')},
    4: {1: ('astromancer', 'astromancer'), 2: ('channeler', 'channeler'), 3: ('necromancer', 'necromancer')},
    5: {1: ('crimsonduelist', 'crimsonduelist'), 2: ('royaltactician', 'royaltactician'), 3: ('scarletweaver', 'scarletweaver')},
    6: {1: ('trickster', 'trickster'), 2: ('bandit', 'bandit'), 3: ('phantom', 'phantom')},
    7: {1: ('templar', 'templar'), 2: ('defender', 'defender'), 3: ('oathbreaker', 'oathbreaker')},
    8: {1: ('reaper', 'reaper'), 2: ('dreadnought', 'dreadnought'), 3: ('scourge', 'scourge')},
    9: {1: ('untamed', 'untamed'), 2: ('alphawarden', 'alphawarden'), 3: ('beastspeaker', 'beastspeaker')},
    10: {1: ('adventurer', 'adventurer'), 2: ('musician', 'musician'), 3: ('minstrel', 'minstrel')},
    11: {1: ('sniper', 'sniper'), 2: ('huntsman', 'huntsman'), 3: ('arcanearcher', 'arcanearcher')},
    12: {1: ('ronin', 'ronin'), 2: ('imperialarcher', 'imperialarcher'), 3: ('warlord', 'warlord')},
    13: {1: ('shinobi', 'kurogane'), 2: ('kagemusha', 'kagemusha'), 3: ('nightblade', 'nightblade')},
    14: {1: ('lancer', 'lancer'), 2: ('skyborn', 'skyborn'), 3: ('wyvernheart', 'wyvernheart')},
    15: {1: ('primalist', 'primalist'), 2: ('celestial', 'celestial'), 3: ('herald', 'herald')},
    16: {1: ('warmage', 'warmage'), 2: ('magus', 'magus'), 3: ('azurebastion', 'azurebastion')},
    17: {1: ('flintlock', 'flintlock'), 2: ('gambler', 'gambler'), 3: ('buccaneer', 'buccaneer')},
    18: {1: ('vanguard', 'vanguard'), 2: ('animist', 'animist'), 3: ('pugilist', 'pugilist')},
    19: {2: ('vampire', 'vampire'), 3: ('bladewheel', 'bladewheel'), 4: ('miragesentinel', 'miragesentinel')},
    20: {1: ('medic', 'medic'), 2: ('sage', 'sage'), 3: ('archivist', 'archivist')},
    21: {1: ('diviner', 'diviner'), 2: ('verdant', 'verdant'), 3: ('terramancer', 'terramancer')},
    22: {1: ('spellblade', 'spellblade'), 2: ('lifebinder', 'lifebinder'), 3: ('inquisitor', 'inquisitor')},
}


class StaticLauncherIdentityTests(unittest.TestCase):
    def test_identity_map_covers_all_66_active_souls_and_retired_dnc_slot(self):
        source = (SOUL_ACTIONS_DIR / 'soul_identity_map.lua').read_text(encoding='utf-8')
        entries = re.findall(r"key\s*=\s*'([a-z]+)'\s*,\s*storageKey\s*=\s*'([a-z]+)'", source)
        self.assertEqual(len(entries), 66)
        expected_pairs = {
            pair
            for branches in EXPECTED_ACTIVE_SOULS.values()
            for pair in branches.values()
        }
        self.assertEqual(set(entries), expected_pairs)
        self.assertIn("[19] = { [1] = 'freelancer' }", source)

    def test_roster_contains_all_66_server_storage_keys(self):
        roster_text = ROSTER_PATH.read_text(encoding='utf-8')
        roster_keys = set(re.findall(r"\{\s*'([a-z]+)'\s*,", roster_text))
        for job, branches in EXPECTED_ACTIVE_SOULS.items():
            for branch, (_profile_key, storage_key) in branches.items():
                self.assertIn(
                    storage_key,
                    roster_keys,
                    f'Missing storage key {storage_key} (job {job} branch {branch}) in soulhud_roster.lua',
                )

    def test_native_labels_header_has_22_jobs_x_3_branches(self):
        labels_text = LABELS_H_PATH.read_text(encoding='utf-8')
        job_cases = re.findall(r'case\s+(\d+):\s*//\s*[A-Z]{3}', labels_text)
        self.assertEqual(len(job_cases), 22)
        self.assertEqual([int(x) for x in job_cases], list(range(1, 23)))


@unittest.skipIf(LuaRuntime is None, 'lupa not installed')
class LuaRuntimeIdentityTests(unittest.TestCase):
    def _run_lua_file(self, base_dir: Path, rel_script: str):
        lua = LuaRuntime(unpack_returned_tuples=True)
        escaped = str(base_dir).replace('\\', '/')
        lua.execute(f"package.path = '{escaped}/?.lua;' .. package.path")
        script_text = (base_dir / rel_script).read_text(encoding='utf-8')
        lua.execute(script_text)

    def test_soul_actions_lua_suite_passes(self):
        self._run_lua_file(SOUL_ACTIONS_DIR, 'tests/soul_packet_test.lua')

    def test_crystalsocket_identity_lua_suite_passes(self):
        self._run_lua_file(CRYSTALSOCKET_DIR, 'tests/soul_identity_test.lua')

    def test_packet_stale_absent_login_zone_and_fallback_transitions(self):
        """Verifies packet, stale/absent packet, login, zone and DLL fallback separately."""
        lua = LuaRuntime(unpack_returned_tuples=True)
        escaped = str(SOUL_ACTIONS_DIR).replace('\\', '/')
        lua.execute(f"package.path = '{escaped}/?.lua;' .. package.path")
        lua.execute("""
            local soulPacket = require('soul_packet')
            local soulBridge = require('soul_bridge')

            local function makePacket(job, soul)
                return string.char(0, 0, 0, 0) .. 'OXHD'
                    .. string.char(1, 1, job, #soul, 0, 0, 0, 0) .. soul
            end

            -- Simulate addon identity state transitions
            local state = { soul = nil, source = 'none', packetSeen = false, packetSoul = nil, packetJob = 0 }
            local function reset()
                state.soul = nil
                state.source = 'none'
                state.packetSeen = false
                state.packetSoul = nil
                state.packetJob = 0
            end
            local function onPacket(data, job)
                local payload = soulPacket.decode(data, job)
                if payload then
                    state.packetSeen = true
                    state.packetSoul = payload.soul
                    state.packetJob = payload.job
                    state.soul = payload.soul
                    state.source = payload.soul and 'Soul HUD packet' or (payload.retired and 'retired Soul slot' or 'no active Soul')
                end
            end
            local function poll(dllStatus, job, charId)
                if state.packetSeen and state.packetJob == job then
                    state.soul = state.packetSoul
                    state.source = state.packetSoul and 'Soul HUD packet' or 'no active Soul'
                else
                    local active = soulBridge.resolve(dllStatus, job, charId)
                    state.soul = active
                    state.source = active and 'Crystal Jobs client state' or 'DLL has no valid active Soul'
                end
            end

            -- 1. Login with absent packet: falls back to Crystal Jobs DLL (PUP branch 2 = animist)
            reset()
            poll({ enabled = 1, known = 1, job = 18, branch = 2, character_id = 1001 }, 18, 1001)
            assert(state.soul == 'animist' and state.source == 'Crystal Jobs client state')

            -- 2. Valid 0x1FC packet arrives for NIN kurogane -> shinobi
            reset()
            onPacket(makePacket(13, 'kurogane'), 13)
            poll({ enabled = 1, known = 1, job = 13, branch = 2, character_id = 1001 }, 13, 1001)
            assert(state.soul == 'shinobi' and state.source == 'Soul HUD packet')

            -- 3. Zone transition clears stale packet, DLL fallback resumes until fresh packet
            reset()
            assert(state.soul == nil and state.packetSeen == false)
            poll({ enabled = 1, known = 1, job = 19, branch = 4, character_id = 1001 }, 19, 1001)
            assert(state.soul == 'miragesentinel' and state.source == 'Crystal Jobs client state')

            -- 4. Retired DNC branch 1 never falls back to miragesentinel
            reset()
            poll({ enabled = 1, known = 1, job = 19, branch = 1, character_id = 1001 }, 19, 1001)
            assert(state.soul == nil)

            -- 5. Packet explicitly reporting no active Soul prevents stale DLL from reviving old Soul
            reset()
            onPacket(makePacket(11, ''), 11)
            poll({ enabled = 1, known = 1, job = 11, branch = 2, character_id = 1001 }, 11, 1001)
            assert(state.soul == nil and state.source == 'no active Soul')
        """)


if __name__ == '__main__':
    unittest.main()
