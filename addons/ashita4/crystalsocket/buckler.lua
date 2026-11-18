-- WAR Spartan/Gladiator: 2H Polearm + Size-1 Buckler sub-slot support.
-- The stock client locks the Sub slot under a two-handed weapon, so equips are
-- sent as raw 0x050 packets. The server (charutils::CanEquipPolearmBuckler)
-- remains authoritative and rejects anything that is not a Size-1 Buckler.
local bit = require('bit')

local B = {}

B.keys = { spartan = true, gladiator = true }
B.containers = { 0, 8, 10, 11, 12, 13, 14, 15, 16 } -- Inventory, Wardrobe 1-8
B.WAR = 1
B.POLEARM = 8
B.SUB_NATIVE_SLOT = 5 -- Equipment grid, column-major: Row 1, Col 2 = Sub

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

-- Item id currently in Main (slot 0), or nil.
local function main_item_id()
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    local eq = try(function() return inv:GetEquippedItem(0) end)
    if not eq then return nil end
    local index = bit.band(eq.Index, 0x00FF)
    local container = bit.rshift(eq.Index, 8)
    if index == 0 then return nil end
    local item = try(function() return inv:GetContainerItem(container, index) end)
    if not item or item.Id == 0 or item.Id == 65535 then return nil end
    return item.Id
end

-- True: WAR + Spartan/Gladiator crystal active + Polearm (Skill 8) in Main.
function B.active(snapshot)
    if not snapshot or snapshot.current_job ~= B.WAR then return false end
    local key = active_key(snapshot)
    if not key or not B.keys[key:lower()] then return false end
    local id = main_item_id()
    if not id then return false end
    local res = try(function() return AshitaCore:GetResourceManager():GetItemById(id) end)
    return res ~= nil and res.Skill == B.POLEARM
end

local function is_size1_shield(res)
    local size = try(function() return res.ShieldSize end)
    if type(size) == 'number' then return size == 1 end
    -- ShieldSize unavailable: fall back to "armor that fits the Sub slot".
    local slots = try(function() return res.Slots end)
    return type(slots) == 'number' and bit.band(slots, 2) ~= 0 and (res.Skill == nil or res.Skill == 0)
end

-- Carried Size-1 shields usable by WAR at <= current level.
function B.list(snapshot)
    local out = {}
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    local resources = AshitaCore:GetResourceManager()
    local lvl = snapshot and snapshot.current_lvl or 99
    for _, container in ipairs(B.containers) do
        local max = try(function() return inv:GetContainerCountMax(container) end) or 0
        for index = 1, max do
            local item = try(function() return inv:GetContainerItem(container, index) end)
            if item and item.Id ~= 0 and item.Id ~= 65535 then
                local res = try(function() return resources:GetItemById(item.Id) end)
                if res and is_size1_shield(res)
                    and bit.band(res.Jobs or 0, bit.lshift(1, B.WAR)) ~= 0
                    and (res.Level or 0) <= lvl then
                    out[#out + 1] = { name = res_name(res) or ('Item ' .. item.Id), id = item.Id,
                        index = index, container = container }
                end
            end
        end
    end
    return out
end

-- Raw C2S 0x050 equip: index, equip slot (1 = Sub), container. Index 0 = unequip.
function B.equip(entry)
    local index = entry and entry.index or 0
    local container = entry and entry.container or 0
    AshitaCore:GetPacketManager():AddOutgoingPacket(0x50, { 0x50, 0x04, 0x00, 0x00, index, 0x01, container, 0x00 })
end

-- Handles '/equip sub <name|none>'. Returns true if the command was consumed.
function B.command(cmd, snapshot)
    local arg = cmd:match('^/equip%s+sub%s*(.-)%s*$')
    if arg == nil or not B.active(snapshot) then return false end
    arg = arg:gsub('^["\']', ''):gsub('["\']$', '')
    local lower = arg:lower()
    if lower == '' or lower == 'none' then
        B.equip(nil)
        return true
    end
    local list, found = B.list(snapshot), nil
    for _, e in ipairs(list) do
        if e.name:lower() == lower then found = e; break end
    end
    if not found then
        for _, e in ipairs(list) do
            if e.name:lower():find(lower, 1, true) then found = e; break end
        end
    end
    if found then
        B.equip(found)
    else
        print('[crystalsocket] No Size-1 Buckler matching "' .. arg .. '" found.')
    end
    return true
end

return B