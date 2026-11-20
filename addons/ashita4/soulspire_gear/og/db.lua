--[[
* SoulspireXI Gear Manager (soulspire_gear) - Database & Constants Loader
* Loads generated SoulspireXI server item, mod, latent, augment, gearset, and WS tables.
--]]

local db = {}

local cache = {
    mods         = nil,
    items        = nil,
    latents      = nil,
    augments     = nil,
    gearsets     = nil,
    weaponskills = nil,
    wsByName     = nil,
}

-- Ashita v4 Equipment Slot Definitions (0-indexed in memory, 1-indexed in Lua tables)
db.SLOTS = {
    { index = 1,  slotId = 0,  mask = 0x0001, key = 'Main',  label = 'Main Hand', isWeapon = true  },
    { index = 2,  slotId = 1,  mask = 0x0002, key = 'Sub',   label = 'Sub / Grip', isWeapon = true  },
    { index = 3,  slotId = 2,  mask = 0x0004, key = 'Range', label = 'Ranged',     isWeapon = true  },
    { index = 4,  slotId = 3,  mask = 0x0008, key = 'Ammo',  label = 'Ammo',       isWeapon = true  },
    { index = 5,  slotId = 4,  mask = 0x0010, key = 'Head',  label = 'Head',       isWeapon = false },
    { index = 6,  slotId = 5,  mask = 0x0020, key = 'Body',  label = 'Body',       isWeapon = false },
    { index = 7,  slotId = 6,  mask = 0x0040, key = 'Hands', label = 'Hands',      isWeapon = false },
    { index = 8,  slotId = 7,  mask = 0x0080, key = 'Legs',  label = 'Legs',       isWeapon = false },
    { index = 9,  slotId = 8,  mask = 0x0100, key = 'Feet',  label = 'Feet',       isWeapon = false },
    { index = 10, slotId = 9,  mask = 0x0200, key = 'Neck',  label = 'Neck',       isWeapon = false },
    { index = 11, slotId = 10, mask = 0x0400, key = 'Waist', label = 'Waist',      isWeapon = false },
    { index = 12, slotId = 11, mask = 0x0800, key = 'Ear1',  label = 'Left Ear',   isWeapon = false, pairSlot = 13 },
    { index = 13, slotId = 12, mask = 0x1000, key = 'Ear2',  label = 'Right Ear',  isWeapon = false, pairSlot = 12 },
    { index = 14, slotId = 13, mask = 0x2000, key = 'Ring1', label = 'Left Ring',  isWeapon = false, pairSlot = 15 },
    { index = 15, slotId = 14, mask = 0x4000, key = 'Ring2', label = 'Right Ring', isWeapon = false, pairSlot = 14 },
    { index = 16, slotId = 15, mask = 0x8000, key = 'Back',  label = 'Back',       isWeapon = false },
}

db.SLOT_BY_KEY = {}
db.SLOT_BY_INDEX = {}
for _, s in ipairs(db.SLOTS) do
    db.SLOT_BY_KEY[s.key] = s
    db.SLOT_BY_KEY[string.lower(s.key)] = s
    db.SLOT_BY_INDEX[s.index] = s
end

-- Armor-only slot indices (5..16) built automatically by set builder
db.ARMOR_SLOTS = { 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }

db.JOB_ABBR = {
    [1]  = 'WAR', [2]  = 'MNK', [3]  = 'WHM', [4]  = 'BLM', [5]  = 'RDM', [6]  = 'THF',
    [7]  = 'PLD', [8]  = 'DRK', [9]  = 'BST', [10] = 'BRD', [11] = 'RNG', [12] = 'SAM',
    [13] = 'NIN', [14] = 'DRG', [15] = 'SMN', [16] = 'BLU', [17] = 'COR', [18] = 'PUP',
    [19] = 'DNC', [20] = 'SCH', [21] = 'GEO', [22] = 'RUN',
}

db.JOB_NAME = {
    [1]  = 'Warrior',      [2]  = 'Monk',         [3]  = 'White Mage',  [4]  = 'Black Mage',
    [5]  = 'Red Mage',     [6]  = 'Thief',        [7]  = 'Paladin',     [8]  = 'Dark Knight',
    [9]  = 'Beastmaster',  [10] = 'Bard',         [11] = 'Ranger',      [12] = 'Samurai',
    [13] = 'Ninja',        [14] = 'Dragoon',      [15] = 'Summoner',    [16] = 'Blue Mage',
    [17] = 'Corsair',      [18] = 'Puppetmaster', [19] = 'Dancer',      [20] = 'Scholar',
    [21] = 'Geomancer',    [22] = 'Rune Fencer',
}

db.SKILL_NAMES = {
    [1]  = 'Hand-to-Hand', [2]  = 'Dagger',       [3]  = 'Sword',        [4]  = 'Great Sword',
    [5]  = 'Axe',          [6]  = 'Great Axe',    [7]  = 'Scythe',       [8]  = 'Polearm',
    [9]  = 'Katana',       [10] = 'Great Katana', [11] = 'Club',         [12] = 'Staff',
    [25] = 'Archery',      [26] = 'Marksmanship', [27] = 'Throwing',
}

db.BAG_NAMES = {
    [0]  = 'Inventory',
    [1]  = 'Mog Safe',
    [2]  = 'Storage',
    [3]  = 'Temp',
    [4]  = 'Mog Locker',
    [5]  = 'Mog Satchel',
    [6]  = 'Mog Sack',
    [7]  = 'Mog Case',
    [8]  = 'Wardrobe',
    [9]  = 'Mog Safe 2',
    [10] = 'Wardrobe 2',
    [11] = 'Wardrobe 3',
    [12] = 'Wardrobe 4',
    [13] = 'Wardrobe 5',
    [14] = 'Wardrobe 6',
    [15] = 'Wardrobe 7',
    [16] = 'Wardrobe 8',
}

db.EQUIPPABLE_BAGS = { 0, 8, 10, 11, 12, 13, 14, 15, 16 }
db.STORAGE_BAGS    = { 1, 2, 4, 5, 6, 7, 9 }

local function loadDataFile(name)
    local paths = {}
    if AshitaCore and AshitaCore.GetInstallPath then
        paths[#paths + 1] = string.format('%saddons\\soulspire_gear\\data\\%s.lua', AshitaCore:GetInstallPath(), name)
    end
    if addon and addon.path then
        paths[#paths + 1] = string.format('%s\\data\\%s.lua', addon.path, name)
    end
    for _, path in ipairs(paths) do
        local chunk = loadfile(path)
        if chunk ~= nil then
            local ok, res = pcall(chunk)
            if ok and type(res) == 'table' then
                return res
            end
        end
    end
    local okReq, resReq = pcall(require, 'data.' .. name)
    if okReq and type(resReq) == 'table' then
        return resReq
    end
    return {}
end

function db.Mods()
    if cache.mods == nil then
        cache.mods = loadDataFile('mods')
        cache.mods.ById = cache.mods.ById or {}
        cache.mods.ByName = cache.mods.ByName or {}
    end
    return cache.mods
end

function db.ModId(name)
    return db.Mods().ByName[name]
end

function db.ModName(id)
    return db.Mods().ById[id]
end

function db.Items()
    if cache.items == nil then
        cache.items = loadDataFile('items')
    end
    return cache.items
end

function db.Item(itemId)
    return db.Items()[itemId]
end

function db.Latents()
    if cache.latents == nil then
        cache.latents = loadDataFile('latents')
    end
    return cache.latents
end

function db.Augments()
    if cache.augments == nil then
        cache.augments = loadDataFile('augments')
    end
    return cache.augments
end

function db.GearSets()
    if cache.gearsets == nil then
        cache.gearsets = loadDataFile('gearsets')
    end
    return cache.gearsets
end

function db.Weaponskills()
    if cache.weaponskills == nil then
        cache.weaponskills = loadDataFile('weaponskills')
        cache.wsByName = {}
        for _, ws in pairs(cache.weaponskills) do
            if ws.name then
                cache.wsByName[string.lower(ws.name)] = ws
                local clean = string.gsub(ws.name, '[^%w]', '')
                cache.wsByName[string.lower(clean)] = ws
            end
        end
    end
    return cache.weaponskills
end

function db.WeaponskillByName(name)
    db.Weaponskills()
    if not name then return nil end
    local lower = string.lower(tostring(name))
    return cache.wsByName[lower] or cache.wsByName[string.gsub(lower, '[^%w]', '')]
end

function db.CleanSetKey(name)
    return (string.gsub(tostring(name or ''), '[^%w_]', ''))
end

return db
