-- Run from the crystalsocket directory: luajit tests/weapon_config_test.lua
package.path = './?.lua;' .. package.path

local bit = require('bit')
local ffi = require('ffi')
local WC = require('weapon_config')
local Labels = require('job_labels')
local UI = require('ui')

-- 1. Declarative skill mask helper
local dagger_bit = bit.lshift(1, WC.SKILLS.DAGGER)
local sword_bit  = bit.lshift(1, WC.SKILLS.SWORD)
assert(WC.skill_mask({ WC.SKILLS.DAGGER, WC.SKILLS.SWORD }) == bit.bor(dagger_bit, sword_bit),
    'skill_mask must set Dagger (bit 2) and Sword (bit 3)')
assert(WC.skill_mask({}) == 0, 'empty skill_mask must return 0')
assert(WC.skill_mask({ 0, 32, -1, 2.5 }) == 0, 'out-of-range skills must be ignored')

-- 2. Native weapon rules export (BRD Adventurer dual_1h + WAR Berserker dual_2h)
local rules = WC.native_rules()
assert(#rules == 2, 'Expected 2 native rules (BRD Adventurer dual_1h + WAR Berserker dual_2h)')
local brd_adv = rules[1]
assert(brd_adv.job == 10, 'BRD job id must be 10')
assert(brd_adv.branch == 1, 'Adventurer branch must be 1')
assert(brd_adv.min_effective_level == 10, 'BRD Adventurer min level must be 10')
assert(brd_adv.mode == WC.MODES.DUAL_1H, 'mode must be DUAL_1H (1)')
assert(brd_adv.main_skill_mask == bit.bor(dagger_bit, sword_bit), 'main_skill_mask must allow Dagger + Sword')
assert(brd_adv.sub_skill_mask == bit.bor(dagger_bit, sword_bit), 'sub_skill_mask must allow Dagger + Sword')
assert(brd_adv.main_item_id == 0 and brd_adv.sub_item_id == 0, 'item_id overrides default to 0 (any Dagger/Sword)')

local ga_bit = bit.lshift(1, WC.SKILLS.GREAT_AXE)
local war_ber = rules[2]
assert(war_ber.job == 1, 'WAR job id must be 1')
assert(war_ber.branch == 2, 'Berserker branch must be 2')
assert(war_ber.min_effective_level == 10, 'WAR Berserker min level must be 10')
assert(war_ber.mode == WC.MODES.DUAL_2H, 'mode must be DUAL_2H (2)')
assert(war_ber.main_skill_mask == ga_bit and war_ber.sub_skill_mask == ga_bit, 'WAR Berserker must allow Great Axe + Great Axe')

-- Ensure legacy custom Sub-slot picker / packet injection helpers were removed.
assert(WC.list == nil and WC.equip == nil and WC.command == nil and WC.SUB_NATIVE_SLOT == nil,
    'weapon_config must not expose custom Sub picker or 0x050 injection helpers')

-- 3. Labels:sync_weapon_rules marshals exact 24-byte CrystalJobsWeaponRule structs
local labels = Labels.new(function() return function() return 0 end end)
local captured_count = 0
local captured_first = nil
local captured_second = nil
local ok, err = labels:sync_weapon_rules(rules, function(buf, count)
    captured_count = count
    assert(count == 2)
    assert(ffi.sizeof(buf[0]) == 24, 'CrystalJobsWeaponRule must be 24 bytes')
    captured_first = {
        size = tonumber(buf[0].size),
        job = tonumber(buf[0].job),
        branch = tonumber(buf[0].branch),
        min_effective_level = tonumber(buf[0].min_effective_level),
        mode = tonumber(buf[0].mode),
        main_skill_mask = tonumber(buf[0].main_skill_mask),
        sub_skill_mask = tonumber(buf[0].sub_skill_mask),
        main_item_id = tonumber(buf[0].main_item_id),
        sub_item_id = tonumber(buf[0].sub_item_id),
        reserved = tonumber(buf[0].reserved),
    }
    captured_second = {
        size = tonumber(buf[1].size),
        job = tonumber(buf[1].job),
        branch = tonumber(buf[1].branch),
        min_effective_level = tonumber(buf[1].min_effective_level),
        mode = tonumber(buf[1].mode),
        main_skill_mask = tonumber(buf[1].main_skill_mask),
        sub_skill_mask = tonumber(buf[1].sub_skill_mask),
    }
    return 0
end)
assert(ok == true and err == nil, 'sync_weapon_rules must succeed when native replace returns 0')
assert(labels.weapon_rules_synced == true and labels.weapon_rules_count == 2)
assert(captured_count == 2)
assert(captured_first.size == 24)
assert(captured_first.job == 10 and captured_first.branch == 1)
assert(captured_first.min_effective_level == 10 and captured_first.mode == 1)
assert(captured_first.main_skill_mask == 12 and captured_first.sub_skill_mask == 12)
assert(captured_first.main_item_id == 0 and captured_first.sub_item_id == 0 and captured_first.reserved == 0)
assert(captured_second.size == 24 and captured_second.job == 1 and captured_second.branch == 2)
assert(captured_second.mode == 2 and captured_second.main_skill_mask == ga_bit and captured_second.sub_skill_mask == ga_bit)

-- Failure return code resets synced state cleanly
local fail_ok, fail_err = labels:sync_weapon_rules(rules, function() return 1 end)
assert(fail_ok == false and fail_err ~= nil and labels.weapon_rules_synced == false)

-- 4. UI must NOT intercept native Sub slot (slot 5) Enter, while keeping Soul Crystal navigation intact
local mock_state = {
    open = false,
    loaded = true,
    pending = false,
    active = 1,
    current_job = 10,
    current_lvl = 10,
    owned_mask = 0xFF,
    catalog = {
        job_name = 'Bard',
        entries = {
            { id = 1, key = 'adventurer', name = 'Adventurer' },
            { id = 2, key = 'musician', name = 'Musician' },
            { id = 3, key = 'minstrel', name = 'Minstrel' },
        },
    },
}
function mock_state:snapshot() return self end
function mock_state:cancel() self.open = false end
function mock_state:show() self.open = true; return true end

local scaling = { scale_w = function(v) return v end, scale_h = function(v) return v end }
local ui = UI.new({}, mock_state, function() return true end, scaling)

-- Pressing Enter on native Sub slot (selected=5) must return false (handled natively by FFXI)
local sub_nav = { window = 100, cursor = 5, selected = 5 }
assert(ui:key('enter', 1, sub_nav) == false, 'UI must NOT intercept Enter on native Sub slot (5)')
assert(ui.buckler == nil and ui.open_buckler == nil and ui.close_buckler == nil,
    'UI must not contain legacy buckler/offhand picker state or methods')

-- Pressing Down from bottom row (slot 4 = Legs) still focuses the Soul Crystal socket
local bottom_nav = { window = 100, cursor = 4, selected = 4 }
assert(ui:key('down', 2, bottom_nav) == true and ui.focused == true,
    'Down from bottom equipment row must still focus Soul Crystal socket')
assert(ui:key('enter', 3, bottom_nav) == true and mock_state.open == true,
    'Enter while focused on Soul Crystal socket must open Soul Crystal list')
assert(ui:key('back', 4, bottom_nav) == true and mock_state.open == false,
    'Back must close Soul Crystal list')
assert(ui:key('back', 5, bottom_nav) == true and ui.focused == false,
    'Back must return focus to native Equipment menu')

-- 5. Per-hook diagnostics FFI struct (60 bytes) and human-readable formatting
local diag_ok = labels:hook_diagnostics(function(buf, sz)
    assert(sz == 60, 'CrystalJobsHookDiagnostics must be 60 bytes')
    buf[0].size = 60
    buf[0].version = 1
    buf[0].total_hooks = 24
    buf[0].expected_hooks = 24
    buf[0].installed_mask = 0xFFFFFF
    buf[0].site_set_mask = 0xFFFFFF
    buf[0].capabilities = 0x3FFF
    buf[0].ffxi_base = 0x04860000
    buf[0].ffxi_timestamp = 0x6ae818b4
    buf[0].ffxi_image_size = 0x00c17000
    buf[0].init_stage = 6
    buf[0].failed_rva = 0
    buf[0].failed_index = 0xFFFFFFFF
    return 0
end)
assert(diag_ok ~= nil and diag_ok.total_hooks == 24 and diag_ok.expected_hooks == 24)
local lines_ok = Labels.format_hook_diagnostics(diag_ok)
assert(lines_ok[1]:find('sub_weapon_hook=OK', 1, true) ~= nil, '24/24 diag must report sub_weapon_hook=OK')
assert(lines_ok[3] == 'missing_hooks=[none]', '24/24 diag must report no missing hooks')

-- Simulate 21/24 where the 3 PrologueDetours are missing (1 overwritten, 2 not installed)
local diag_21 = labels:hook_diagnostics(function(buf, sz)
    assert(sz == 60)
    buf[0].size = 60
    buf[0].version = 1
    buf[0].total_hooks = 21
    buf[0].expected_hooks = 24
    buf[0].installed_mask = 0x1FFFFF -- bits 0..20 installed; bits 21..23 missing
    buf[0].site_set_mask = 0x9FFFFF  -- bit 23 was installed then overwritten
    buf[0].capabilities = 0x0FFF
    buf[0].ffxi_base = 0x04860000
    buf[0].ffxi_timestamp = 0x6ae818b4
    buf[0].ffxi_image_size = 0x00c17000
    buf[0].init_stage = 6
    buf[0].failed_rva = 0x133D56
    buf[0].failed_index = 23
    buf[0].observed_bytes[0] = 0xE9
    buf[0].observed_bytes[1] = 0x11
    return 0
end)
assert(diag_21 ~= nil and diag_21.total_hooks == 21)
local lines_21 = Labels.format_hook_diagnostics(diag_21)
assert(lines_21[1]:find('installed=21/24', 1, true) ~= nil)
assert(lines_21[1]:find('sub_weapon_hook=MISSING', 1, true) ~= nil)
assert(lines_21[3]:find('0x22CDE0 can_use_spell_detour:not_installed', 1, true) ~= nil)
assert(lines_21[3]:find('0x22CB44 missing_spell_bit_detour:not_installed', 1, true) ~= nil)
assert(lines_21[3]:find('0x133D56 soul_sub_weapon_detour:overwritten', 1, true) ~= nil)
assert(lines_21[4]:find('rva=0x133D56 observed=E9 11', 1, true) ~= nil)

print('Crystal Socket native weapon_config & UI tests passed.')
