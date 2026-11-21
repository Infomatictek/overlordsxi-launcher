-- Pure-Lua state, Soul gating, 0x0028 action decoding, and auto-facing logic
-- for COR Flintlock (job 17, branch 1) Phase 1 dual-pistol support.
-- Client-only and visual-only; never modifies combat, equipment, or non-Flintlock Souls.

local M = {}

M.COR_JOB_ID = 17
M.FLINTLOCK_BRANCH = 1
M.FLINTLOCK_SOUL = 'flintlock'
M.FIREARM_SKILLS = {
    [26] = true, -- Marksmanship (guns/crossbows; narrowed by gun/cannon check when item metadata available)
}

local function read_u32_le(data, offset)
    local b1, b2, b3, b4 = data:byte(offset, offset + 3)
    if not b4 then return nil end
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function read_u16_le(data, offset)
    local b1, b2 = data:byte(offset, offset + 1)
    if not b2 then return nil end
    return b1 + b2 * 256
end

-- Unpack little-endian bitfield from 1-based byte string, 0-based bit offset.
function M.unpack_bits(data, bit_offset, bit_len)
    if type(data) ~= 'string' or bit_offset < 0 or bit_len <= 0 or bit_len > 32 then
        return nil
    end
    local value = 0
    local mul = 1
    for i = 0, bit_len - 1 do
        local pos = bit_offset + i
        local byte_idx = math.floor(pos / 8) + 1
        local b = data:byte(byte_idx)
        if not b then return nil end
        local bit_idx = pos % 8
        local bit_val = math.floor(b / (2 ^ bit_idx)) % 2
        if bit_val == 1 then
            value = value + mul
        end
        mul = mul * 2
    end
    return value
end

-- Decode SoulspireXI 0x1FC ('OXHD') HUD packet for fallback Soul identity.
function M.decode_soul_packet(data, expected_job)
    if type(data) ~= 'string' or #data < 16 or #data > 4096 or data:sub(5, 8) ~= 'OXHD' then
        return nil
    end
    local version, unlocked, packet_job, key_len, kv_lo, kv_hi = data:byte(9, 14)
    if version ~= 1 or (unlocked ~= 0 and unlocked ~= 1)
        or not packet_job or packet_job < 1 or packet_job > 22
        or not key_len or key_len > 64 or not kv_lo or not kv_hi then
        return nil
    end
    if expected_job ~= nil and packet_job ~= expected_job then
        return nil
    end
    if #data < 16 + key_len + kv_lo + kv_hi * 256 then
        return nil
    end
    if key_len == 0 then
        return { job = packet_job, branch = 0, soul = nil }
    end
    local soul = data:sub(17, 16 + key_len):lower()
    if not soul:match('^[%w_%-]+$') then
        return nil
    end
    local branch = 0
    if packet_job == M.COR_JOB_ID then
        if soul == 'flintlock' then branch = 1
        elseif soul == 'gambler' then branch = 2
        elseif soul == 'buccaneer' then branch = 3
        end
    end
    return { job = packet_job, branch = branch, soul = soul }
end

-- Resolve active Soul from crystaljobs.dll status struct.
function M.is_flintlock_from_crystaljobs(status, job, character_id)
    if type(status) ~= 'table' or type(job) ~= 'number' or type(character_id) ~= 'number' then
        return false
    end
    if character_id <= 0 or job ~= M.COR_JOB_ID then
        return false
    end
    return status.enabled == 1
        and status.known == 1
        and status.character_id == character_id
        and status.job == M.COR_JOB_ID
        and status.branch == M.FLINTLOCK_BRANCH
end

-- Parse outgoing 0x01A action packet for ranged attack (category == 0x10).
-- Layout: [1..4]=header, [5..8]=target_id (u32), [9..10]=target_idx (u16), [11..12]=category (u16).
function M.parse_outgoing_ra_target(data)
    if type(data) ~= 'string' or #data < 12 then
        return nil
    end
    local category = read_u16_le(data, 11)
    if category ~= 0x10 then
        return nil
    end
    local target_id = read_u32_le(data, 5)
    if not target_id or target_id == 0 then
        return nil
    end
    return target_id
end

-- Parse incoming 0x0028 action packet header + first target ID.
-- Bit layout per Ashita/XiPackets 0x0028:
--   byte 6..9 (bits 40..71): actor_id (32 bits)
--   bits 72..81: target_count (10 bits)
--   bits 82..85: category (4 bits)
--   bits 86..117: param (32 bits)
--   bits 118..149: recast (32 bits)
--   bits 150..181: targets[1].id (32 bits)
function M.parse_action_packet(data)
    if type(data) ~= 'string' or #data < 23 then
        return nil
    end
    local actor_id = M.unpack_bits(data, 40, 32)
    local target_count = M.unpack_bits(data, 72, 10)
    local category = M.unpack_bits(data, 82, 4)
    local param = M.unpack_bits(data, 86, 32)
    local first_target_id = nil
    if target_count and target_count >= 1 then
        first_target_id = M.unpack_bits(data, 150, 32)
    end
    return {
        actor_id = actor_id,
        target_count = target_count or 0,
        category = category,
        param = param or 0,
        target_id = first_target_id,
    }
end

-- Compute FFXI horizontal yaw (radians) facing from (me_x, me_z) to (target_x, target_z).
function M.compute_facing_yaw(me_x, me_z, target_x, target_z)
    if type(me_x) ~= 'number' or type(me_z) ~= 'number'
        or type(target_x) ~= 'number' or type(target_z) ~= 'number' then
        return nil
    end
    local dx = target_x - me_x
    local dz = target_z - me_z
    if (dx * dx + dz * dz) <= 0.0001 then
        return nil
    end
    return -math.atan2(dz, dx)
end

-- Classify whether an equipped ranged weapon is a firearm (Gun/Cannon) vs Bow/Crossbow/Thrown.
-- Accepts either explicit range_type string ('Gun'/'Cannon') or item name/flags heuristic.
function M.is_firearm_item(item_info)
    if type(item_info) ~= 'table' then
        return false
    end
    if type(item_info.range_type) == 'string' then
        local rt = item_info.range_type:lower()
        return rt == 'gun' or rt == 'cannon'
    end
    -- Ashita v4 IItem resource: Skill == 26 (Marksmanship) and Ammo/Weapon type not Crossbow/Bolt.
    -- In FFXI item resources, firearm items use Skill == 26 and do not use crossbow/bolt names.
    if item_info.skill == 26 then
        local name = type(item_info.name) == 'string' and item_info.name:lower() or ''
        if name:find('crossbow', 1, true) or name:find('arbalest', 1, true)
            or name:find('ziska', 1, true) or name:find('xbow', 1, true)
            or name:find('bow', 1, true) then
            return false
        end
        return true
    end
    return false
end

function M.new()
    local self = {
        aim_enabled = true,
        character_id = 0,
        job = 0,
        branch = 0,
        soul = nil,
        flintlock_active = false,
        requested_target = nil,
        hud_fallback = nil,
        last_advisory_key = nil,
    }

    function self:reset(reason)
        self.requested_target = nil
        if reason == 'logout' or reason == 'character_change' then
            self.character_id = 0
            self.job = 0
            self.branch = 0
            self.soul = nil
            self.flintlock_active = false
            self.hud_fallback = nil
            self.last_advisory_key = nil
        end
    end

    function self:on_soul_packet(data, current_job)
        local decoded = M.decode_soul_packet(data, current_job)
        if decoded then
            self.hud_fallback = decoded
        end
        return decoded
    end

    function self:update_context(character_id, job, crystal_status)
        if type(character_id) ~= 'number' or character_id <= 0 or type(job) ~= 'number' or job <= 0 then
            self:reset('logout')
            return false
        end
        if self.character_id ~= 0 and self.character_id ~= character_id then
            self:reset('character_change')
        end

        local prev_active = self.flintlock_active
        self.character_id = character_id
        self.job = job

        if type(crystal_status) == 'table' and crystal_status.enabled == 1 and crystal_status.known == 1
            and crystal_status.character_id == character_id and crystal_status.job == job then
            self.branch = crystal_status.branch or 0
            self.flintlock_active = (job == M.COR_JOB_ID and self.branch == M.FLINTLOCK_BRANCH)
            self.soul = self.flintlock_active and M.FLINTLOCK_SOUL or nil
        elseif self.hud_fallback and self.hud_fallback.job == job then
            self.branch = self.hud_fallback.branch or 0
            self.soul = self.hud_fallback.soul
            self.flintlock_active = (job == M.COR_JOB_ID and self.branch == M.FLINTLOCK_BRANCH)
        else
            self.branch = 0
            self.soul = nil
            self.flintlock_active = false
        end

        if prev_active ~= self.flintlock_active then
            self.requested_target = nil
        end
        return prev_active ~= self.flintlock_active
    end

    function self:record_outgoing_ra(data)
        if not self.flintlock_active or not self.aim_enabled then
            return nil
        end
        local target_id = M.parse_outgoing_ra_target(data)
        if target_id then
            self.requested_target = target_id
        end
        return target_id
    end

    -- Decide whether to auto-face on a 0x0028 action packet and return target_id or nil.
    function self:resolve_auto_face_target(action, is_firearm)
        if not self.flintlock_active or not self.aim_enabled or not is_firearm then
            return nil
        end
        if type(action) ~= 'table' then
            return nil
        end
        if action.category ~= 12 and action.category ~= 2 then
            return nil
        end
        if self.character_id <= 0 or action.actor_id ~= self.character_id then
            return nil
        end

        local target_id = action.target_id
        if action.category == 12 and target_id == self.character_id then
            target_id = self.requested_target
        end
        self.requested_target = nil

        -- Ignore ranged attack cancel/interrupt (0x7073), matching upstream AkimboAim.lua.
        if action.category == 12 and ((action.param or 0) % 65536 == 0x7073) then
            return nil
        end
        if not target_id or target_id == 0 or target_id == self.character_id then
            return nil
        end
        return target_id
    end

    -- Non-spammy advisory when active Soul and session XIPivot overlay state disagree.
    function self:check_overlay_advisory(overlay_installed, overlay_enabled_at_boot)
        if self.character_id <= 0 or self.job <= 0 then
            return nil
        end
        local key = nil
        local msg = nil
        if self.flintlock_active and overlay_installed and not overlay_enabled_at_boot then
            key = 'flintlock_overlay_off'
            msg = 'COR Flintlock active: dual-pistol DAT overlay is installed but inactive this session. Run /flintlock overlay on (or enable in Launcher) and restart FFXI.'
        elseif not self.flintlock_active and overlay_enabled_at_boot and self.job == M.COR_JOB_ID then
            key = 'non_flintlock_cor_overlay_on'
            msg = 'Non-Flintlock COR Soul active while dual-pistol DAT overlay is loaded for this session. Run /flintlock overlay off and restart FFXI for vanilla single-gun visuals.'
        end
        if key and key ~= self.last_advisory_key then
            self.last_advisory_key = key
            return msg
        end
        if not key then
            self.last_advisory_key = nil
        end
        return nil
    end

    return self
end

return M
