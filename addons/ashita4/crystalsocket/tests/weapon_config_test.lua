-- Run from the crystalsocket directory: luajit tests/weapon_config_test.lua
package.path = './?.lua;' .. package.path

local bit = require('bit')

local sent_packets = {}
local equipped_main = { Index = 0 }
local bags = {}

local ITEMS = {
    -- Dagger (Skill 2, Slots=3, All jobs, Lv1)
    [20568] = { Name = { 'Wind Knife +1' }, Skill = 2, Slots = 3, Jobs = 0x7FFFFE, Level = 1, ShieldSize = 0 },
    -- Second Dagger (Skill 2, Slots=3, All jobs, Lv1)
    [16449] = { Name = { 'Bronze Dagger' }, Skill = 2, Slots = 3, Jobs = 0x7FFFFE, Level = 1, ShieldSize = 0 },
    -- Sword (Skill 3, Slots=3, BRD+WAR, Lv1)
    [16534] = { Name = { 'Onion Sword' }, Skill = 3, Slots = 3, Jobs = bit.bor(bit.lshift(1, 10), bit.lshift(1, 1)), Level = 1, ShieldSize = 0 },
    -- High-level Sword (Lv24, BRD)
    [17650] = { Name = { 'Nadrs' }, Skill = 3, Slots = 3, Jobs = bit.lshift(1, 10), Level = 24, ShieldSize = 0 },
    -- Club (Skill 11, Slots=3, All jobs, Lv1) -> MUST BE EXCLUDED for BRD Adventurer
    [17137] = { Name = { 'Ash Club +1' }, Skill = 11, Slots = 3, Jobs = 0x7FFFFE, Level = 1, ShieldSize = 0 },
    -- Shield (Size 1, Slots=2, All jobs, Lv1)
    [28651] = { Name = { 'Metal Slime Shield' }, Skill = 0, Slots = 2, Jobs = 0x7FFFFE, Level = 1, ShieldSize = 1 },
    -- Size-3 Shield (Slots=2, All jobs, Lv1) -> allowed for BRD Adventurer (1H+Shield), excluded for WAR Spartan
    [12299] = { Name = { 'Kite Shield' }, Skill = 0, Slots = 2, Jobs = 0x7FFFFE, Level = 1, ShieldSize = 3 },
    -- 2H Polearm (Skill 8, Slots=1, WAR, Lv7)
    [16859] = { Name = { 'Bronze Spear +1' }, Skill = 8, Slots = 1, Jobs = bit.lshift(1, 1), Level = 7, ShieldSize = 0 },
}

local function make_index(container, slot)
    return bit.bor(bit.lshift(container, 8), slot)
end

AshitaCore = {
    GetMemoryManager = function()
        return {
            GetInventory = function()
                return {
                    GetEquippedItem = function(_, slot)
                        if slot == 0 then return equipped_main end
                        return { Index = 0 }
                    end,
                    GetContainerCountMax = function(_, container)
                        return bags[container] and #bags[container] or 0
                    end,
                    GetContainerItem = function(_, container, index)
                        return bags[container] and bags[container][index] or nil
                    end,
                }
            end,
        }
    end,
    GetResourceManager = function()
        return {
            GetItemById = function(_, id) return ITEMS[id] end,
        }
    end,
    GetPacketManager = function()
        return {
            AddOutgoingPacket = function(_, id, data)
                sent_packets[#sent_packets + 1] = { id = id, data = data }
            end,
        }
    end,
}

local WC = require('weapon_config')

local function brd_snapshot(active_id, lvl)
    return {
        current_job = 10,
        current_lvl = lvl or 10,
        active = active_id,
        catalog = {
            entries = {
                { id = 1, key = 'adventurer' },
                { id = 2, key = 'musician' },
                { id = 3, key = 'minstrel' },
            },
        },
    }
end

-- Setup Rin's Wardrobe 1 (container 8): Wind Knife +1 (slot 2), Onion Sword (slot 3), Ash Club +1 (slot 4),
-- Metal Slime Shield (slot 5), Nadrs Lv24 (slot 6), Bronze Dagger (slot 7), Kite Shield (slot 8)
bags = {
    [8] = {
        [1] = { Id = 0 },
        [2] = { Id = 20568 },
        [3] = { Id = 16534 },
        [4] = { Id = 17137 },
        [5] = { Id = 28651 },
        [6] = { Id = 17650 },
        [7] = { Id = 16449 },
        [8] = { Id = 12299 },
    },
}
equipped_main = { Index = make_index(8, 2) } -- Wind Knife +1 in Main

-- 1. BRD10 Adventurer with Dagger in Main -> active & lists Onion Sword, Bronze Dagger, Shields (NOT Wind Knife +1, Ash Club +1, or Lv24 Nadrs)
local adv10 = brd_snapshot(1, 10)
local rule = WC.active_rule(adv10)
assert(rule ~= nil and rule.mode == 'dual_1h' and rule.title == 'Sub: Offhand', 'BRD10 Adventurer should be active')

local list = WC.list(adv10)
local by_id = {}
for _, item in ipairs(list) do by_id[item.id] = item end
assert(by_id[16534] ~= nil, 'Onion Sword must be listed as offhand')
assert(by_id[16449] ~= nil, 'Bronze Dagger must be listed as offhand')
assert(by_id[28651] ~= nil, 'Metal Slime Shield must be listed')
assert(by_id[12299] ~= nil, 'Kite Shield must be listed for 1H+Shield')
assert(by_id[20568] == nil, 'Main-equipped Wind Knife +1 instance must NOT be duplicated in Sub list')
assert(by_id[17137] == nil, 'Club (Ash Club +1) must NOT be listed for BRD Adventurer')
assert(by_id[17650] == nil, 'Lv24 Nadrs must NOT be listed at Lv10')

-- 2. BRD9 Adventurer -> inactive (below min_level 10)
assert(not WC.active(brd_snapshot(1, 9)), 'BRD9 Adventurer must not activate below Lv10')

-- 3. BRD10 Musician / Unsocketed -> inactive (preserves vanilla client behavior)
assert(not WC.active(brd_snapshot(2, 10)), 'BRD10 Musician must not activate')
assert(not WC.active(brd_snapshot(0, 10)), 'Unsocketed BRD10 must not activate')

-- 4. BRD10 Adventurer with Club in Main -> inactive
equipped_main = { Index = make_index(8, 4) } -- Ash Club +1
assert(not WC.active(adv10), 'BRD10 Adventurer with Club in Main must not activate')

-- 5. /equip sub command emits raw 0x050 packet for Onion Sword and unequip
equipped_main = { Index = make_index(8, 2) } -- Wind Knife +1
sent_packets = {}
assert(WC.command('/equip sub "Onion Sword"', adv10) == true, 'Command must be consumed for BRD10 Adventurer')
assert(#sent_packets == 1 and sent_packets[1].id == 0x50, 'Must send 0x050 equip packet')
assert(sent_packets[1].data[5] == 3 and sent_packets[1].data[6] == 1 and sent_packets[1].data[7] == 8,
    'Packet must target index=3, slot=1(Sub), container=8(Wardrobe1)')

assert(WC.command('/equip sub none', adv10) == true, 'Unequip sub must be consumed')
assert(#sent_packets == 2 and sent_packets[2].data[5] == 0 and sent_packets[2].data[6] == 1,
    'Unequip packet must send index=0, slot=1(Sub)')

-- 6. Backward compatibility: WAR10 Spartan with Polearm in Main lists ONLY Size-1 Buckler
bags[0] = {
    [1] = { Id = 16859 }, -- Bronze Spear +1
    [2] = { Id = 28651 }, -- Size-1 shield
    [3] = { Id = 12299 }, -- Size-3 shield
}
equipped_main = { Index = make_index(0, 1) }
local war10 = {
    current_job = 1,
    current_lvl = 10,
    active = 3,
    catalog = { entries = { { id = 3, key = 'spartan' } } },
}
local war_rule = WC.active_rule(war10)
assert(war_rule ~= nil and war_rule.title == 'Sub: Buckler', 'WAR10 Spartan Polearm must activate Buckler rule')
local war_list = WC.list(war10)
local war_ids = {}
for _, item in ipairs(war_list) do war_ids[item.id] = true end
assert(war_ids[28651] == true, 'WAR Spartan must list Size-1 Buckler')
assert(war_ids[12299] == nil, 'WAR Spartan must NOT list Size-3 Kite Shield')

print('Crystal Socket weapon_config tests passed.')
