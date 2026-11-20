--[[
* SoulspireXI Gear Manager (soulspire_gear) - Inventory, Wardrobe & Augment Reader
* Scans equippable and storage bags, decodes item augments, and resolves
* SoulspireXI equip eligibility (including Crystal Spec weapon unlocks).
--]]

local bit = require('bit')
local db  = require('og.db')

local bags = {}

-- Vanilla BLM-equippable scythes usable without Lv.10+ Necromancer crystal
local VANILLA_BLM_SCYTHES = {
    [16779] = true, -- Pitchfork
    [16780] = true, -- Pitchfork +1
    [16797] = true, -- Ark Scythe
}

-- Mezzotint (Delve / Geas Fete) augment index mapping matching server item_equipment.cpp
local MEZZOTINT = {
    [2]   = { 'HP' },          [3]   = { 'HP', 256 },
    [4]   = { 'MP' },          [5]   = { 'MP', 256 },
    [8]   = { 'ATT' },         [9]   = { 'ATT', 256 },
    [10]  = { 'RATT' },        [11]  = { 'RATT', 256 },
    [12]  = { 'ACC' },         [13]  = { 'ACC', 256 },
    [14]  = { 'RACC' },        [15]  = { 'RACC', 256 },
    [16]  = { 'DEF' },         [17]  = { 'DEF', 256 },
    [18]  = { 'EVA' },         [19]  = { 'EVA', 256 },
    [20]  = { 'MATT' },        [21]  = { 'MATT', 256 },
    [22]  = { 'MDEF' },        [23]  = { 'MDEF', 256 },
    [24]  = { 'MACC' },        [25]  = { 'MACC', 256 },
    [26]  = { 'MEVA' },        [27]  = { 'MEVA', 256 },
    [28]  = { 'DMG_RATING' },  [29]  = { 'DMG_RATING', 256 },
    [128] = { 'MATT', 0, 1, true },
    [129] = { 'MACC', 0, 1, true },
    [130] = { 'ATT',  0, 1, true },
    [131] = { 'ACC',  0, 1, true },
    [185] = { 'STORETP' },
    [186] = { 'DOUBLE_ATTACK' },
    [187] = { 'SNAPSHOT' },
    [188] = { 'DMGPHYS',  0, -100 },
    [189] = { 'DMGMAGIC', 0, -100 },
    [191] = { 'STR' }, [192] = { 'DEX' }, [193] = { 'VIT' }, [194] = { 'AGI' },
    [195] = { 'INT' }, [196] = { 'MND' }, [197] = { 'CHR' },
}

local function decodeMezzotint(extra)
    local mods, pet = {}, {}
    for i = 0, 2 do
        local idx = struct.unpack('B', extra, 7 + i * 2)
        local val = struct.unpack('B', extra, 8 + i * 2) + 1
        local m = MEZZOTINT[idx]
        local mid = (m ~= nil) and db.ModId(m[1]) or nil
        if mid ~= nil and idx ~= 0 then
            local v = (val + (m[2] or 0)) * (m[3] or 1)
            if m[4] then
                pet[0] = pet[0] or {}
                pet[0][mid] = (pet[0][mid] or 0) + v
            else
                mods[mid] = (mods[mid] or 0) + v
            end
        end
    end
    return mods, pet
end

local function decodeAugments(item)
    if item == nil or item.Extra == nil or #item.Extra < 12 then
        return nil, nil
    end
    local augType = struct.unpack('B', item.Extra, 1)
    if augType ~= 2 and augType ~= 3 then
        return nil, nil
    end
    local augFlag = struct.unpack('B', item.Extra, 2)
    if augType == 2 and bit.band(augFlag, 0x20) ~= 0 then
        return decodeMezzotint(item.Extra)
    end
    if bit.band(augFlag, 0x20) ~= 0 or augFlag == 131 or bit.band(augFlag, 0x08) ~= 0 or bit.band(augFlag, 0x80) ~= 0 then
        return nil, nil
    end

    local count = (bit.band(augFlag, 0x40) ~= 0) and 4 or 5
    local raw = item.Extra:totable()
    local augTable = db.Augments()
    local mods, pet = {}, {}

    for i = 1, count do
        local aid = ashita.bits.unpack_be(raw, 16 * i, 11)
        local lvl = ashita.bits.unpack_be(raw, (16 * i) + 11, 5)
        for _, a in ipairs(augTable[aid] or {}) do
            local v = ((a.v > 0) and (a.v + lvl) or (a.v - lvl)) * math.max(a.m or 1, 1)
            if a.pet ~= nil then
                pet[a.pet] = pet[a.pet] or {}
                pet[a.pet][a.mod] = (pet[a.pet][a.mod] or 0) + v
            else
                mods[a.mod] = (mods[a.mod] or 0) + v
            end
        end
    end
    return mods, pet
end

local function getItemResourceName(resMgr, itemId, fallback)
    if resMgr ~= nil then
        local res = resMgr:GetItemById(itemId)
        if res ~= nil and res.Name ~= nil and res.Name[1] ~= nil and res.Name[1] ~= '' then
            return res.Name[1], res
        end
    end
    return fallback or ('Item #' .. tostring(itemId)), nil
end

function bags.CanWear(serverItem, resItem, who)
    if serverItem == nil or who == nil then return false end
    if (serverItem.level or 0) > (who.Level or 1) then
        return false
    end
    if (serverItem.su or 0) > (who.SuLevel or 0) then
        return false
    end

    local jobMask = bit.lshift(1, (who.Job or 1) - 1)
    if bit.band(serverItem.jobs or 0, jobMask) == 0 then
        return false
    end

    -- SoulspireXI BLM Scythe rule: non-vanilla scythes require Lv.10+ Necromancer crystal
    if who.Job == 4 and serverItem.skill == 7 and not VANILLA_BLM_SCYTHES[serverItem.id] then
        if who.SpecKey ~= 'necromancer' or (who.Level or 1) < 10 then
            return false
        end
    end

    -- Race / gender check if client resource carries Races bitmask
    if resItem ~= nil and resItem.Races ~= nil and resItem.Races > 0 and who.Race ~= nil and who.Race > 0 then
        local raceMask = bit.lshift(1, who.Race)
        if bit.band(resItem.Races, raceMask) == 0 then
            return false
        end
    end

    return true
end

local function readContainer(inv, resMgr, itemsDb, containerId, isEquippableBag, intoList)
    local maxCount = 80
    if inv.GetContainerCountMax ~= nil then
        local ok, c = pcall(inv.GetContainerCountMax, inv, containerId)
        if ok and type(c) == 'number' and c > 0 then
            maxCount = math.min(c, 80)
        end
    end

    for idx = 1, maxCount do
        local item = inv:GetContainerItem(containerId, idx)
        if item ~= nil and item.Id ~= nil and item.Id > 0 and item.Id ~= 65535 and (item.Count or 0) > 0 then
            local srv = itemsDb[item.Id]
            if srv ~= nil and (srv.slot or 0) > 0 then
                local dispName, resItem = getItemResourceName(resMgr, item.Id, nil)
                local mods = {}
                for k, v in pairs(srv.mods or {}) do
                    mods[k] = v
                end
                local pet = {}
                for ptype, pmods in pairs(srv.pet or {}) do
                    pet[ptype] = {}
                    for k, v in pairs(pmods) do
                        pet[ptype][k] = v
                    end
                end

                local augMods, augPet = decodeAugments(item)
                local hasAug = false
                if augMods ~= nil then
                    for k, v in pairs(augMods) do
                        mods[k] = (mods[k] or 0) + v
                        hasAug = true
                    end
                end
                if augPet ~= nil then
                    for ptype, pmods in pairs(augPet) do
                        pet[ptype] = pet[ptype] or {}
                        for k, v in pairs(pmods) do
                            pet[ptype][k] = (pet[ptype][k] or 0) + v
                            hasAug = true
                        end
                    end
                end

                intoList[#intoList + 1] = {
                    Id          = item.Id,
                    UniqueKey   = string.format('%d:%d', containerId, idx),
                    Name        = dispName,
                    Bag         = containerId,
                    BagName     = db.BAG_NAMES[containerId] or ('Bag ' .. tostring(containerId)),
                    Index       = idx,
                    Equippable  = isEquippableBag,
                    Level       = srv.level or 1,
                    SuLevel     = srv.su or 0,
                    Jobs        = srv.jobs or 0,
                    SlotMask    = srv.slot or 0,
                    BlockMask   = srv.rslot or 0,
                    Skill       = srv.skill or 0,
                    Dmg         = srv.dmg or 0,
                    Delay       = srv.delay or 0,
                    Shield      = srv.shield or 0,
                    Mods        = mods,
                    PetMods     = pet,
                    HasAugment  = hasAug,
                    ServerItem  = srv,
                    ResItem     = resItem,
                }
            end
        end
    end
end

-- Scan all equippable bags (and optionally storage bags) for items the player can wear
function bags.Scan(who, includeStorage)
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    local resMgr = AshitaCore:GetResourceManager()
    if inv == nil then return {}, {} end

    local itemsDb = db.Items()
    local rawEquippable = {}
    for _, bagId in ipairs(db.EQUIPPABLE_BAGS) do
        readContainer(inv, resMgr, itemsDb, bagId, true, rawEquippable)
    end

    local wearable = {}
    for _, piece in ipairs(rawEquippable) do
        piece.ServerItem.id = piece.Id
        if bags.CanWear(piece.ServerItem, piece.ResItem, who) then
            wearable[#wearable + 1] = piece
        end
    end

    local storageWearable = {}
    if includeStorage then
        local rawStorage = {}
        for _, bagId in ipairs(db.STORAGE_BAGS) do
            readContainer(inv, resMgr, itemsDb, bagId, false, rawStorage)
        end
        for _, piece in ipairs(rawStorage) do
            piece.ServerItem.id = piece.Id
            if bags.CanWear(piece.ServerItem, piece.ResItem, who) then
                storageWearable[#storageWearable + 1] = piece
            end
        end
    end

    return wearable, storageWearable
end

-- Returns currently equipped items indexed by slot index (1..16)
function bags.GetCurrentEquipment()
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    local resMgr = AshitaCore:GetResourceManager()
    local itemsDb = db.Items()
    local equipped = {}
    if inv == nil then return equipped end

    for _, s in ipairs(db.SLOTS) do
        local eq = inv:GetEquippedItem(s.slotId)
        if eq ~= nil and eq.Index ~= nil and eq.Index > 0 then
            local bagId = math.floor(eq.Index / 256)
            local itemIdx = eq.Index % 256
            if itemIdx > 0 then
                local item = inv:GetContainerItem(bagId, itemIdx)
                if item ~= nil and item.Id ~= nil and item.Id > 0 and item.Id ~= 65535 then
                    local srv = itemsDb[item.Id]
                    local dispName = getItemResourceName(resMgr, item.Id, nil)
                    equipped[s.index] = {
                        Id      = item.Id,
                        Name    = dispName,
                        Bag     = bagId,
                        BagName = db.BAG_NAMES[bagId] or ('Bag ' .. tostring(bagId)),
                        Index   = itemIdx,
                        Skill   = srv and srv.skill or 0,
                        Dmg     = srv and srv.dmg or 0,
                        Delay   = srv and srv.delay or 0,
                        SlotKey = s.key,
                    }
                end
            end
        end
    end
    return equipped
end

return bags
