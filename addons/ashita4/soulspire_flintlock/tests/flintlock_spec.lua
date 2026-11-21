package.path = './?.lua;./addons/ashita4/soulspire_flintlock/?.lua;' .. package.path

local State = require('flintlock_state')
local PivotConfig = require('pivot_config')

local function eq(actual, expected, label)
    if actual ~= expected then
        error(string.format('%s: expected %s, got %s', label, tostring(expected), tostring(actual)), 2)
    end
end

local function make_oxhd(job, soul)
    local key = soul or ''
    return string.char(0xFC, 0x01, 0x00, 0x00)
        .. 'OXHD'
        .. string.char(1, 1, job, #key, 0, 0, 0, 0)
        .. key
end

local function make_0x1a(target_id, category)
    local b1 = target_id % 256
    local b2 = math.floor(target_id / 256) % 256
    local b3 = math.floor(target_id / 65536) % 256
    local b4 = math.floor(target_id / 16777216) % 256
    local c1 = category % 256
    local c2 = math.floor(category / 256) % 256
    return string.char(0x1A, 0x00, 0x00, 0x00, b1, b2, b3, b4, 0x00, 0x00, c1, c2)
end

-- Build a minimal 0x0028 bitpacked action packet (24 bytes).
local function make_0x28(actor_id, target_count, category, param, target1_id)
    local bits = {}
    for i = 0, 191 do bits[i] = 0 end
    local function put(offset, len, val)
        for i = 0, len - 1 do
            bits[offset + i] = math.floor(val / (2 ^ i)) % 2
        end
    end
    put(40, 32, actor_id)
    put(72, 10, target_count)
    put(82, 4, category)
    put(86, 32, param)
    put(118, 32, 0)
    put(150, 32, target1_id or 0)
    local bytes = {}
    for byte_i = 0, 23 do
        local v = 0
        for b = 0, 7 do
            if bits[byte_i * 8 + b] == 1 then
                v = v + (2 ^ b)
            end
        end
        bytes[#bytes + 1] = string.char(v)
    end
    return table.concat(bytes)
end

-- 1. Soul gating: ONLY COR (17) branch 1 (flintlock) activates Flintlock mode.
do
    local s = State.new()
    s:update_context(1001, 17, { enabled = 1, known = 1, character_id = 1001, job = 17, branch = 1 })
    eq(s.flintlock_active, true, 'COR Flintlock activates')

    -- COR Gambler (branch 2) -> inactive
    s:update_context(1001, 17, { enabled = 1, known = 1, character_id = 1001, job = 17, branch = 2 })
    eq(s.flintlock_active, false, 'COR Gambler stays inactive')

    -- COR Buccaneer (branch 3) -> inactive
    s:update_context(1001, 17, { enabled = 1, known = 1, character_id = 1001, job = 17, branch = 3 })
    eq(s.flintlock_active, false, 'COR Buccaneer stays inactive')

    -- RNG Sniper (job 11, branch 1) -> inactive
    s:update_context(1001, 11, { enabled = 1, known = 1, character_id = 1001, job = 11, branch = 1 })
    eq(s.flintlock_active, false, 'RNG Sniper stays inactive')

    -- Fallback 0x1FC OXHD packet when crystaljobs is unavailable
    s:on_soul_packet(make_oxhd(17, 'flintlock'), 17)
    s:update_context(1001, 17, nil)
    eq(s.flintlock_active, true, 'OXHD fallback activates Flintlock')

    s:on_soul_packet(make_oxhd(17, 'gambler'), 17)
    s:update_context(1001, 17, nil)
    eq(s.flintlock_active, false, 'OXHD fallback deactivates on Gambler')
end

-- 2. Ranged attack auto-facing: active ONLY for COR Flintlock + firearm + local actor.
do
    local s = State.new()
    s:update_context(5001, 17, { enabled = 1, known = 1, character_id = 5001, job = 17, branch = 1 })

    local req_tid = s:record_outgoing_ra(make_0x1a(9001, 0x10))
    eq(req_tid, 9001, '0x01A category 0x10 records target')

    -- Ready packet (category 12) where server names actor as target -> uses requested_target
    local ready = State.parse_action_packet(make_0x28(5001, 1, 12, 0, 5001))
    eq(ready.actor_id, 5001, '0x0028 actor_id')
    eq(ready.category, 12, '0x0028 category 12')
    eq(s:resolve_auto_face_target(ready, true), 9001, 'Flintlock ready resolves requested target')

    -- Interrupt/cancel (param 0x7073) -> ignored
    s:record_outgoing_ra(make_0x1a(9001, 0x10))
    local cancel = State.parse_action_packet(make_0x28(5001, 1, 12, 0x7073, 5001))
    eq(s:resolve_auto_face_target(cancel, true), nil, 'Cancel 0x7073 ignored')

    -- Release packet (category 2) -> faces target directly
    local release = State.parse_action_packet(make_0x28(5001, 1, 2, 0, 9002))
    eq(s:resolve_auto_face_target(release, true), 9002, 'Flintlock release faces target')

    -- Non-firearm -> ignored
    eq(s:resolve_auto_face_target(release, false), nil, 'Non-firearm ignored')

    -- Another player -> ignored
    local other = State.parse_action_packet(make_0x28(7777, 1, 2, 0, 9002))
    eq(s:resolve_auto_face_target(other, true), nil, 'Other actor ignored')

    -- Switch to Gambler -> ignored
    s:update_context(5001, 17, { enabled = 1, known = 1, character_id = 5001, job = 17, branch = 2 })
    eq(s:resolve_auto_face_target(release, true), nil, 'Gambler does not auto-face')

    -- Zone reset clears pending requested target
    s:update_context(5001, 17, { enabled = 1, known = 1, character_id = 5001, job = 17, branch = 1 })
    s:record_outgoing_ra(make_0x1a(9005, 0x10))
    s:reset('zone')
    eq(s.requested_target, nil, 'Zone reset clears requested target')
end

-- 3. Firearm classifier & facing angle math
do
    eq(State.is_firearm_item({ skill = 26, name = 'Silver Gun' }), true, 'Silver Gun is firearm')
    eq(State.is_firearm_item({ skill = 26, name = 'Death Penalty' }), true, 'Death Penalty is firearm')
    eq(State.is_firearm_item({ skill = 26, name = 'Ziska\'s Crossbow' }), false, 'Crossbow is not firearm')
    eq(State.is_firearm_item({ skill = 25, name = 'Yoichinoyumi' }), false, 'Archery bow is not firearm')

    local yaw_east = State.compute_facing_yaw(0, 0, 10, 0)
    assert(math.abs(yaw_east - 0) < 1e-6, 'Facing east yaw is 0')
    local yaw_north = State.compute_facing_yaw(0, 0, 0, 10)
    assert(math.abs(yaw_north - (-math.pi / 2)) < 1e-6, 'Facing north yaw is -pi/2')
    eq(State.compute_facing_yaw(5, 5, 5, 5), nil, 'Zero distance returns nil')
end

-- 4. Pivot INI reversible toggling
do
    local base_ini = table.concat({
        '[settings]',
        'root_path=C:\\Ashita\\polplugins\\DATs',
        'debug_log=false',
        '',
        '[overlays]',
        '0=soulspirexi',
        '',
        '[cache]',
        'enabled=false',
    }, '\n') .. '\n'

    eq(PivotConfig.is_flintlock_enabled(base_ini), false, 'Base INI has Flintlock disabled')

    local enabled_ini, err1 = PivotConfig.set_flintlock_enabled(base_ini, true)
    assert(enabled_ini and not err1, 'Enable Flintlock succeeds')
    eq(PivotConfig.is_flintlock_enabled(enabled_ini), true, 'Enabled INI has Flintlock active')
    local ovs = PivotConfig.parse_overlays(enabled_ini)
    eq(ovs[1], 'flintlock-akimbo-compact', 'Flintlock overlay has priority 0')
    eq(ovs[2], 'soulspirexi', 'Base soulspirexi overlay preserved at priority 1')

    local reverted_ini, err2 = PivotConfig.set_flintlock_enabled(enabled_ini, false)
    assert(reverted_ini and not err2, 'Disable Flintlock succeeds')
    eq(PivotConfig.is_flintlock_enabled(reverted_ini), false, 'Reverted INI has Flintlock disabled')
    local ovs2 = PivotConfig.parse_overlays(reverted_ini)
    eq(#ovs2, 1, 'Reverted overlay list has 1 entry')
    eq(ovs2[1], 'soulspirexi', 'Base soulspirexi overlay restored at priority 0')
end

print('soulspire_flintlock tests: OK')
