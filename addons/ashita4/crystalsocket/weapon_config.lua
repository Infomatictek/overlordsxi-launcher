-- SoulspireXI: Reusable Soul-specific offhand weapon configuration for Ashita v4.
--
-- The stock FFXI client filters offhand weapons by hardcoded vanilla Dual Wield
-- jobs (NIN/DNC/THF/BLU) and locks the Sub slot under 2H weapons. This module
-- provides a data-driven per-Soul Sub-slot selector and '/equip sub' dispatcher
-- that sends raw 0x050 packets to the authoritative server.
--
-- Performance: inventory is scanned ONLY on demand (opening the Sub picker or
-- running '/equip sub'), never per-frame.
-- Safety: the server (soulspire_weapon_config.lua + patch 0072) remains 100%
-- authoritative and rejects any unauthorized equipment packet.
local bit = require('bit')

local W = {}

W.containers = { 0, 8, 10, 11, 12, 13, 14, 15, 16 } -- Inventory, Wardrobe 1-8
W.SUB_NATIVE_SLOT = 5 -- Equipment grid, column-major: Row 1, Col 2 = Sub

W.JOBS = {
    WAR = 1,
    BRD = 10,
}

W.SKILLS = {
    HAND_TO_HAND = 1,
    DAGGER       = 2,
    SWORD        = 3,
    GREAT_SWORD  = 4,
    AXE          = 5,
    GREAT_AXE    = 6,
    SCYTHE       = 7,
    POLEARM      = 8,
    KATANA       = 9,
    GREAT_KATANA = 10,
    CLUB         = 11,
    STAFF        = 12,
}

-- Declarative per-Soul weapon rules keyed by [job_id][spec_key].
-- Only explicitly configured Souls override the stock Sub-slot menu; all other
-- Souls preserve normal vanilla FFXI Equipment menu and /equip sub behavior.
W.RULES = {
    -- Phase 4 first vertical slice: BRD Adventurer (Dagger / Sword Dual Wield)
    [W.JOBS.BRD] = {
        adventurer = {
            title         = 'Sub: Offhand',
            min_level     = 10,
            mode          = 'dual_1h',
            main_skills   = { [W.SKILLS.DAGGER] = true, [W.SKILLS.SWORD] = true },
            sub_skills    = { [W.SKILLS.DAGGER] = true, [W.SKILLS.SWORD] = true },
            allow_shields = true,
            empty_msg     = 'No Dagger, Sword, or Shield matching "%s" found.',
        },
    },
    -- Existing WAR Spartan / Gladiator: 2H Polearm + Size-1 Buckler
    [W.JOBS.WAR] = {
        spartan = {
            title         = 'Sub: Buckler',
            min_level     = 10,
            mode          = 'twohand_shield',
            main_skills   = { [W.SKILLS.POLEARM] = true },
            sub_skills    = {},
            allow_shields = true,
            shield_size   = 1,
            empty_msg     = 'No Size-1 Buckler matching "%s" found.',
        },
        gladiator = {
            title         = 'Sub: Buckler',
            min_level     = 10,
            mode          = 'twohand_shield',
            main_skills   = { [W.SKILLS.POLEARM] = true },
            sub_skills    = {},
            allow_shields = true,
            shield_size   = 1,
            empty_msg     = 'No Size-1 Buckler matching "%s" found.',
        },
    },
}

local function try(fn, ...)
    local ok, a = pcall(fn, ...)
    if ok then return a end
    return nil
end

local function res_name(res)
    if not res then return nil end
    local n = try(function() return res.Name[1] end)
    if type(n) ~= 'string' or n == '' then
        n = try(function() return res.LogNameSingular[1] end)
    end
    return type(n) == 'string' and n or nil
end

local function active_key(snapshot)
    if not snapshot or not snapshot.active or snapshot.active <= 0 then return nil end
    local entries = snapshot.catalog and snapshot.catalog.entries or {}
    for _, e in ipairs(entries) do
        if e.id == snapshot.active then return e.key end
    end
    return nil
end

-- Returns { container, index, id } for the item currently in Main (slot 0), or nil.
local function main_equipped()
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    local eq = try(function() return inv:GetEquippedItem(0) end)
    if not eq then return nil end
    local index = bit.band(eq.Index, 0x00FF)
    local container = bit.rshift(eq.Index, 8)
    if index == 0 then return nil end
    local item = try(function() return inv:GetContainerItem(container, index) end)
    if not item or item.Id == 0 or item.Id == 65535 then return nil end
    return { container = container, index = index, id = item.Id }
end

local function is_shield(res, required_size)
    local size = try(function() return res.ShieldSize end)
    if type(size) == 'number' and size > 0 then
        if required_size ~= nil then
            return size == required_size
        end
        return true
    end
    -- Fallback if ShieldSize field is unavailable on older resource structs.
    local slots = try(function() return res.Slots end)
    if type(slots) == 'number' and bit.band(slots, 2) ~= 0 and (res.Skill == nil or res.Skill == 0) then
        return required_size == nil or required_size == 1
    end
    return false
end

local function is_allowed_sub_item(res, rule)
    if not res or not rule then return false end

    local skill = tonumber(res.Skill) or 0
    if skill > 0 and rule.sub_skills and rule.sub_skills[skill] then
        -- 1H dual-wield weapons must have Sub slot bit (0x0002).
        local slots = tonumber(res.Slots) or 0
        if rule.mode == 'dual_1h' and bit.band(slots, 2) == 0 then
            return false
        end
        return true
    end

    if rule.allow_shields and is_shield(res, rule.shield_size) then
        return true
    end

    return false
end

-- Returns the active Soul weapon rule table if the current job, active Soul,
-- effective level, and equipped main-hand weapon match a configured rule; else nil.
function W.active_rule(snapshot)
    if not snapshot or not snapshot.current_job then return nil end
    local job_rules = W.RULES[snapshot.current_job]
    if not job_rules then return nil end

    local key = active_key(snapshot)
    if not key then return nil end
    local rule = job_rules[key:lower()]
    if not rule then return nil end

    local lvl = tonumber(snapshot.current_lvl) or 0
    if lvl < (rule.min_level or 10) then return nil end

    local main = main_equipped()
    if not main then return nil end
    local res = try(function() return AshitaCore:GetResourceManager():GetItemById(main.id) end)
    if not res then return nil end
    if not (rule.main_skills and rule.main_skills[tonumber(res.Skill) or 0]) then
        return nil
    end

    return rule, main
end

function W.active(snapshot)
    return W.active_rule(snapshot) ~= nil
end

-- Scans Inventory and Wardrobes 1-8 on demand for eligible Sub items matching the active Soul rule.
function W.list(snapshot)
    local out = {}
    local rule, main = W.active_rule(snapshot)
    if not rule then return out end

    local inv = AshitaCore:GetMemoryManager():GetInventory()
    local resources = AshitaCore:GetResourceManager()
    local job = snapshot.current_job
    local lvl = tonumber(snapshot.current_lvl) or 99

    for _, container in ipairs(W.containers) do
        local max = try(function() return inv:GetContainerCountMax(container) end) or 0
        for index = 1, max do
            -- Never offer the exact item instance already equipped in Main.
            if not (main and main.container == container and main.index == index) then
                local item = try(function() return inv:GetContainerItem(container, index) end)
                if item and item.Id ~= 0 and item.Id ~= 65535 then
                    local res = try(function() return resources:GetItemById(item.Id) end)
                    if res
                        and is_allowed_sub_item(res, rule)
                        and bit.band(res.Jobs or 0, bit.lshift(1, job)) ~= 0
                        and (res.Level or 0) <= lvl then
                        out[#out + 1] = {
                            name      = res_name(res) or ('Item ' .. item.Id),
                            id        = item.Id,
                            index     = index,
                            container = container,
                            skill     = tonumber(res.Skill) or 0,
                        }
                    end
                end
            end
        end
    end
    return out
end

-- Raw C2S 0x050 equip: index, equip slot (1 = Sub), container. Index 0 = unequip.
function W.equip(entry)
    local index = entry and entry.index or 0
    local container = entry and entry.container or 0
    AshitaCore:GetPacketManager():AddOutgoingPacket(0x50, { 0x50, 0x04, 0x00, 0x00, index, 0x01, container, 0x00 })
end

-- Handles '/equip sub <name|none>'. Returns true if the command was consumed.
function W.command(cmd, snapshot)
    local arg = cmd:match('^/equip%s+sub%s*(.-)%s*$')
    if arg == nil then return false end
    local rule = W.active_rule(snapshot)
    if not rule then return false end

    arg = arg:gsub('^["\']', ''):gsub('["\']$', '')
    local lower = arg:lower()
    if lower == '' or lower == 'none' then
        W.equip(nil)
        return true
    end

    local list, found = W.list(snapshot), nil
    for _, e in ipairs(list) do
        if e.name:lower() == lower then found = e; break end
    end
    if not found then
        for _, e in ipairs(list) do
            if e.name:lower():find(lower, 1, true) then found = e; break end
        end
    end

    if found then
        W.equip(found)
    else
        local fmt = rule.empty_msg or 'No valid offhand matching "%s" found.'
        print('[crystalsocket] ' .. fmt:format(arg))
    end
    return true
end

return W
