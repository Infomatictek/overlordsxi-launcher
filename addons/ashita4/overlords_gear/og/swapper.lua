--[[
* OverlordsXI Gear Manager (overlords_gear) - Standalone Packet Equipment Swapper
* Handles 0x050/0x051 equip packets, 0x053 lockstyle packets, 0x01A action
* interception (Precast/Midcast/WS/JA/Ranged), 0x028 action completion, and
* Idle/Engaged/Resting/Movement state transitions with post-zone safety hold.
--]]

local bit = require('bit')
local db  = require('og.db')

local swapper = {}

local internalEquip = {} -- slotIdx -> { Bag = bagId, Index = itemIdx, Id = itemId, Timer = os.clock() }
local isInjecting1A = false
local lastPos       = { x = nil, y = nil, z = nil, moving = false, movingSince = nil, moveUntil = 0 }

swapper.Zone = {
    Holding   = true,
    Leaving   = false,
    EnteredAt = os.clock(),
    MovedAt   = nil,
}

swapper.ActiveAction = nil -- { Type = 'Spell'|'WS'|'JA'|'Ranged', Name = ..., EndsAt = os.clock(), SetName = ... }
swapper.LastEquippedSetName = '---'

function swapper.OnZoneIn()
    swapper.Zone.Holding   = true
    swapper.Zone.Leaving   = false
    swapper.Zone.EnteredAt = os.clock()
    swapper.Zone.MovedAt   = nil
    swapper.ActiveAction   = nil
    internalEquip          = {}
    lastPos = { x = nil, y = nil, z = nil, moving = false, movingSince = nil, moveUntil = 0 }
end

function swapper.OnZoneOut()
    swapper.OnZoneIn()
    swapper.Zone.Leaving = true
end

function swapper.OnPositionPacket()
    if swapper.Zone.Holding and not swapper.Zone.Leaving and swapper.Zone.MovedAt == nil then
        swapper.Zone.MovedAt = os.clock()
    end
end

function swapper.IsZoneHolding(zoneWaitSec)
    if not swapper.Zone.Holding then return false end
    local waitSec = tonumber(zoneWaitSec) or 6
    local now = os.clock()
    if swapper.Zone.MovedAt ~= nil and (now - swapper.Zone.MovedAt) >= waitSec then
        swapper.Zone.Holding = false
        return false
    end
    -- Fallback if player hasn't moved after 18s + waitSec
    if not swapper.Zone.Leaving and (now - swapper.Zone.EnteredAt) >= (waitSec + 18) then
        swapper.Zone.Holding = false
        return false
    end
    return true
end

function swapper.ZoneHoldRemaining(zoneWaitSec)
    if not swapper.Zone.Holding then return 0 end
    local waitSec = tonumber(zoneWaitSec) or 6
    local now = os.clock()
    if swapper.Zone.MovedAt ~= nil then
        return math.max(0, waitSec - (now - swapper.Zone.MovedAt))
    end
    return waitSec
end

-- Check what is currently in `slotIdx` (1..16), honoring short packet cache
local function getCurrentSlotState(inv, slotIdx)
    local now = os.clock()
    local cached = internalEquip[slotIdx]
    if cached and now < cached.Timer then
        return cached.Bag, cached.Index, cached.Id
    end
    internalEquip[slotIdx] = nil
    if not inv then return 0, 0, 0 end

    local eq = inv:GetEquippedItem(slotIdx - 1)
    if not eq or not eq.Index or eq.Index == 0 then
        return 0, 0, 0
    end
    local bagId = bit.rshift(bit.band(eq.Index, 0xFF00), 8)
    local itemIdx = bit.band(eq.Index, 0x00FF)
    if itemIdx == 0 then return 0, 0, 0 end

    local item = inv:GetContainerItem(bagId, itemIdx)
    if not item or not item.Id or item.Id == 0 or item.Id == 65535 or (item.Count or 0) == 0 then
        return 0, 0, 0
    end
    return bagId, itemIdx, item.Id
end

-- Send 0x050 (single slot) or 0x051 (multi-slot equipset) for a 16-slot table `slots[slotIdx] = piece`
function swapper.EquipSlots(slots, lockedSlots, setName)
    if not slots then return false end
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    local pktMgr = AshitaCore:GetPacketManager()
    if not inv or not pktMgr then return false end

    lockedSlots = lockedSlots or {}
    local changes = {}
    local now = os.clock()

    for slotIdx = 1, 16 do
        if not lockedSlots[slotIdx] then
            local target = slots[slotIdx]
            if target and target.Bag ~= nil and target.Index ~= nil and target.Index > 0 then
                local curBag, curIdx, curId = getCurrentSlotState(inv, slotIdx)
                if curBag ~= target.Bag or curIdx ~= target.Index or curId ~= target.Id then
                    -- Verify item is still in that bag/index
                    local item = inv:GetContainerItem(target.Bag, target.Index)
                    if item and item.Id == target.Id and (item.Count or 0) > 0 then
                        changes[#changes + 1] = {
                            SlotIdx   = slotIdx,
                            SlotId    = slotIdx - 1,
                            Bag       = target.Bag,
                            Index     = target.Index,
                            Id        = target.Id,
                            BlockMask = target.BlockMask or 0,
                        }
                    end
                end
            end
        end
    end

    if #changes == 0 then
        if setName then swapper.LastEquippedSetName = setName end
        return false
    end

    if #changes == 1 then
        local c = changes[1]
        local pkt = { 0x00, 0x00, 0x00, 0x00, c.Index, c.SlotId, c.Bag, 0x00 }
        pktMgr:AddOutgoingPacket(0x50, pkt)
        internalEquip[c.SlotIdx] = { Bag = c.Bag, Index = c.Index, Id = c.Id, Timer = now + 2.00 }
    else
        local pkt = {}
        for i = 1, 72 do pkt[i] = 0x00 end
        pkt[5] = #changes
        for idx, c in ipairs(changes) do
            local offset = 4 + (idx * 4) + 1
            pkt[offset]     = c.Index
            pkt[offset + 1] = c.SlotId
            pkt[offset + 2] = c.Bag
            internalEquip[c.SlotIdx] = { Bag = c.Bag, Index = c.Index, Id = c.Id, Timer = now + 2.00 }
        end
        pktMgr:AddOutgoingPacket(0x51, pkt)
    end

    if setName then
        swapper.LastEquippedSetName = setName
    end
    return true
end

-- Equip a single piece into a specific slot (1..16), e.g. from the Weapon Advisor tab
function swapper.EquipSinglePiece(piece, slotIdx)
    if not piece or not piece.Equippable then return false end
    local slots = { [slotIdx] = piece }
    return swapper.EquipSlots(slots, {}, 'Manual: ' .. tostring(piece.Name))
end

-- Lock visual appearance to a set's visible slots (1..9: Main..Feet) via 0x053 packet
function swapper.LockStyleSet(slots)
    if not slots then return false end
    local pktMgr = AshitaCore:GetPacketManager()
    if not pktMgr then return false end

    local pkt = {}
    for i = 1, 136 do pkt[i] = 0x00 end
    pkt[6] = 3
    pkt[7] = 1

    local count = 0
    for s = 1, 9 do
        local p = slots[s]
        if p and p.Bag ~= nil and p.Index ~= nil and p.Id ~= nil and p.Id > 0 then
            local offset = 8 + (count * 8) + 1
            pkt[offset]     = p.Index
            pkt[offset + 1] = s - 1
            pkt[offset + 2] = p.Bag
            pkt[offset + 4] = bit.band(p.Id, 0xFF)
            pkt[offset + 5] = bit.rshift(p.Id, 8)
            count = count + 1
            pkt[5] = count
        end
    end

    if count > 0 then
        pktMgr:AddOutgoingPacket(0x53, pkt)
        return true
    end
    return false
end

-- Merge an overlay set's slots on top of a base set's slots
local function mergeSetSlots(baseSlots, overlaySlots, respectOverrides)
    local out = {}
    for s = 1, 16 do
        out[s] = baseSlots and baseSlots[s] or nil
    end
    if overlaySlots then
        for s = 1, 16 do
            if overlaySlots[s] and not (respectOverrides and respectOverrides[s]) then
                out[s] = overlaySlots[s]
            end
        end
    end
    return out
end

-- Resolve which Midcast set to use for a spell resource
local function resolveSpellMidcastSet(spell, state)
    if not spell then return 'Idle' end
    local name = (spell.Name and spell.Name[1]) or ''
    local lower = string.lower(name)
    local skill = spell.Skill or 0

    -- Direct spell name match in built/custom sets
    local clean = db.CleanSetKey(name)
    if state.Sets[clean] then return clean end

    if string.find(lower, '^cure') or string.find(lower, '^curaga') or string.find(lower, '^cura') then
        return 'Cure'
    elseif string.find(lower, '^cursna') or string.find(lower, 'na$') or lower == 'erase' then
        return 'Cursna'
    elseif lower == 'stoneskin' then
        return 'Stoneskin'
    elseif string.find(lower, '^phalanx') then
        return 'Phalanx'
    elseif string.find(lower, '^regen') then
        return 'Regen'
    elseif string.find(lower, '^refresh') then
        return 'Refresh'
    elseif string.find(lower, 'helix') then
        return state.Toggles.Burst and 'Burst' or 'Helix'
    elseif string.find(lower, '^drain') or string.find(lower, '^aspir') then
        return 'DrainAspir'
    elseif string.find(lower, '^utsusemi') or string.find(lower, ': ichi$') or string.find(lower, ': ni$') or string.find(lower, ': san$') then
        if string.find(lower, '^utsusemi') or string.find(lower, '^migawari') or string.find(lower, '^monomi') or string.find(lower, '^tonko') then
            return 'Ninjutsu_Buff'
        elseif string.find(lower, '^katon') or string.find(lower, '^hyoton') or string.find(lower, '^huton') or string.find(lower, '^doton') or string.find(lower, '^raiton') or string.find(lower, '^suiton') then
            return 'Ninjutsu_Nuke'
        else
            return 'Ninjutsu_Debuff'
        end
    elseif string.find(lower, '^indi%-') or string.find(lower, '^geo%-') then
        return 'Geomancy'
    elseif lower == 'runic bolt' or lower == 'runic sever' then
        if state.Toggles.Burst and state.Sets.Burst then return 'Burst' end
        if state.Toggles.Nuke == 'Acc' and state.Sets.Nuke_Acc then return 'Nuke_Acc' end
        return 'Nuke'
    end

    -- Skill-based fallback (32=Divine, 33=Healing, 34=Enhancing, 35=Enfeebling, 36=Elemental, 37=Dark, 38=Summoning, 39=Ninjutsu, 40=Singing, 43=Blue, 44=Geomancy)
    if skill == 32 then return 'Divine'
    elseif skill == 33 then return 'Cure'
    elseif skill == 34 then return 'Enhancing'
    elseif skill == 35 then return 'Enfeebling'
    elseif skill == 36 then
        if state.Toggles.Burst and state.Sets.Burst then return 'Burst' end
        if state.Toggles.Nuke == 'Acc' and state.Sets.Nuke_Acc then return 'Nuke_Acc' end
        return 'Nuke'
    elseif skill == 37 then return 'Dark'
    elseif skill == 38 then return 'Pet_Idle'
    elseif skill == 39 then return 'Ninjutsu_Buff'
    elseif skill == 40 or skill == 41 or skill == 42 then
        if spell.Targets and bit.band(spell.Targets, 0x20) ~= 0 then
            return 'Song_Debuff'
        end
        return 'Song'
    elseif skill == 43 then return 'Blue_Physical'
    elseif skill == 44 then return 'Geomancy'
    end

    return 'Midcast_Interrupt'
end

-- Resolve Precast set for a spell
local function resolveSpellPrecastSet(spell, state)
    if not spell then return 'Precast' end
    local name = (spell.Name and spell.Name[1]) or ''
    local lower = string.lower(name)
    local skill = spell.Skill or 0

    if (string.find(lower, '^cure') or string.find(lower, '^curaga')) and state.Sets.Cure_Precast then
        return 'Cure_Precast'
    elseif skill == 34 and state.Sets.Enhancing_Precast then
        return 'Enhancing_Precast'
    elseif (skill == 40 or skill == 41 or skill == 42) and state.Sets.Song_Precast then
        return 'Song_Precast'
    end
    return 'Precast'
end

-- Build a locked-slot mask for action swaps that preserves Main/Sub/Range weapons (slots 1..3) so TP is never wiped
local function actionLockedSlots(baseLocks)
    local locks = { [1] = true, [2] = true, [3] = true }
    if baseLocks then
        for k, v in pairs(baseLocks) do
            if v then locks[k] = true end
        end
    end
    return locks
end

-- Handle outgoing packets (0x15 position, 0x1A action)
-- IMPORTANT: Never set e.blocked = true on 0x1A packets; queue 0x50/0x51 alongside the native 0x1A packet.
function swapper.HandlePacketOut(e, state)
    if e.id == 0x15 then
        swapper.OnPositionPacket()
        return
    end

    if e.id ~= 0x1A then return end
    if isInjecting1A then return end
    if not state or state.Toggles.Dress or state.Toggles.Paused then return end
    if swapper.IsZoneHolding(state.Prefs.ZoneWait) then return end

    local raw = e.data
    if type(raw) ~= 'string' or #raw < 16 then return end

    local category = struct.unpack('H', raw, 0x0A + 1)
    local actionId = struct.unpack('H', raw, 0x0C + 1)
    local resMgr   = AshitaCore:GetResourceManager()
    local pktMgr   = AshitaCore:GetPacketManager()
    if not resMgr or not pktMgr then return end

    local now   = os.clock()
    local locks = actionLockedSlots(state.Prefs.LockedSlots)

    -- Category 0x03: Cast Spell
    if category == 0x03 then
        local spell   = resMgr:GetSpellById(actionId)
        local preName = resolveSpellPrecastSet(spell, state)
        local midName = resolveSpellMidcastSet(spell, state)
        local preSet  = state.Sets[preName] or state.Sets.Precast
        local midSet  = state.Sets[midName] or state.Sets.Midcast_Interrupt or state.Sets.Idle

        local castSec = 2.5
        if spell and spell.CastTime and spell.CastTime > 0 then
            local fc = (preSet and preSet.Totals and preSet.Totals.FastCast) or 0
            castSec = ((spell.CastTime * 0.25) * (100 - math.min(80, fc))) / 100 + 0.6
        end

        local midSlots = midSet and midSet.Slots or nil
        if midSlots and state.Toggles.TH and state.Sets.TH then
            midSlots = mergeSetSlots(midSlots, state.Sets.TH.Slots)
        end

        if preSet and castSec > 0.8 then
            swapper.EquipSlots(preSet.Slots, locks, preSet.Label or preName)
        elseif midSlots then
            swapper.EquipSlots(midSlots, locks, (midSet and midSet.Label) or midName)
            midSlots = nil
        end

        swapper.ActiveAction = {
            Type        = 'Spell',
            Name        = (spell and spell.Name and spell.Name[1]) or ('Spell #' .. tostring(actionId)),
            SetName     = midName,
            MidSlots    = midSlots,
            MidLabel    = (midSet and midSet.Label) or midName,
            MidAt       = now + 0.15,
            MidEquipped = (midSlots == nil),
            EndsAt      = now + math.max(1.2, castSec),
        }
        return
    end

    -- Category 0x07: Weaponskill
    if category == 0x07 then
        local abil = resMgr:GetAbilityById(actionId)
        local wsName = (abil and abil.Name and abil.Name[1]) or ''
        local wsSetKey = 'WS_' .. db.CleanSetKey(wsName)
        local wsSet = state.Sets[wsSetKey] or state.Sets.WS_Default

        if wsSet then
            swapper.EquipSlots(wsSet.Slots, locks, wsSet.Label or wsSetKey)
            swapper.ActiveAction = {
                Type    = 'WS',
                Name    = wsName ~= '' and wsName or ('WS #' .. tostring(actionId)),
                SetName = wsSet.Name,
                EndsAt  = now + 1.8,
            }
        end
        return
    end

    -- Category 0x09: Job Ability
    if category == 0x09 then
        local abil = resMgr:GetAbilityById(actionId + 0x200)
        local jaName = (abil and abil.Name and abil.Name[1]) or ''
        local jaSetKey = 'JA_' .. db.CleanSetKey(jaName)
        local jaSet = state.Sets[jaSetKey]

        if jaSet then
            swapper.EquipSlots(jaSet.Slots, locks, jaSet.Label or jaSetKey)
            swapper.ActiveAction = {
                Type    = 'JA',
                Name    = jaName,
                SetName = jaSet.Name,
                EndsAt  = now + 1.4,
            }
        end
        return
    end

    -- Category 0x10: Ranged Attack
    if category == 0x10 then
        local preSet = state.Sets.Preshot
        local midSet = state.Sets.Midshot
        if preSet or midSet then
            if preSet then
                swapper.EquipSlots(preSet.Slots, locks, preSet.Label or 'Preshot')
            elseif midSet then
                swapper.EquipSlots(midSet.Slots, locks, midSet.Label or 'Midshot')
            end
            swapper.ActiveAction = {
                Type        = 'Ranged',
                Name        = 'Ranged Attack',
                SetName     = 'Midshot',
                MidSlots    = (preSet and midSet) and midSet.Slots or nil,
                MidLabel    = (midSet and midSet.Label) or 'Midshot',
                MidAt       = now + 0.15,
                MidEquipped = not (preSet and midSet),
                EndsAt      = now + 2.8,
            }
        end
        return
    end
end

-- Handle incoming packets (0x0A Zone In, 0x0B Zone Out, 0x28 Action Complete)
function swapper.HandlePacketIn(e, state)
    if e.id == 0x0A then
        swapper.OnZoneIn()
        return
    elseif e.id == 0x0B then
        swapper.OnZoneOut()
        return
    elseif e.id == 0x28 and swapper.ActiveAction ~= nil then
        local raw = e.data
        if type(raw) == 'string' and #raw >= 12 and state and state.Who and state.Who.ServerId then
            local actorId = struct.unpack('I', raw, 0x05 + 1)
            if actorId == state.Who.ServerId then
                local actType = ashita.bits.unpack_be(e.data_raw, 10, 2, 4)
                -- 2=Ranged finish, 3=WS finish, 4=Magic finish, 6=JA finish, 11=MobSkill
                if actType == 2 or actType == 3 or actType == 4 or actType == 6 then
                    swapper.ActiveAction.EndsAt = math.min(swapper.ActiveAction.EndsAt, os.clock() + 0.15)
                end
            end
        end
    end
end

-- Check if the player is currently moving
local function updatePlayerMovement()
    local ent = AshitaCore:GetMemoryManager():GetEntity()
    local party = AshitaCore:GetMemoryManager():GetParty()
    if not ent or not party then return false end

    local myIdx = party:GetMemberTargetIndex(0)
    if not myIdx or myIdx == 0 then return false end

    local x = ent:GetLocalPositionX(myIdx)
    local y = ent:GetLocalPositionY(myIdx)
    local z = ent:GetLocalPositionZ(myIdx)
    local now = os.clock()

    if lastPos.x ~= nil then
        local dx = x - lastPos.x
        local dy = y - lastPos.y
        local dz = z - lastPos.z
        local distSq = dx * dx + dy * dy + dz * dz
        if distSq > 0.04 then
            if not lastPos.moving then lastPos.movingSince = now end
            lastPos.moving = true
            lastPos.moveUntil = now + 0.65
        elseif now > lastPos.moveUntil then
            lastPos.moving = false
            lastPos.movingSince = nil
        end
    end
    lastPos.x, lastPos.y, lastPos.z = x, y, z
    return lastPos.moving
end

-- Periodic state tick (equips Midcast when due, or Idle / Engaged / Resting when no action is in flight)
function swapper.Tick(state)
    if not state or state.Toggles.Dress or state.Toggles.Paused then return end
    if swapper.IsZoneHolding(state.Prefs.ZoneWait) then return end

    local now = os.clock()
    if swapper.ActiveAction ~= nil then
        if not swapper.ActiveAction.MidEquipped and swapper.ActiveAction.MidSlots and now >= (swapper.ActiveAction.MidAt or 0) then
            swapper.ActiveAction.MidEquipped = true
            swapper.EquipSlots(swapper.ActiveAction.MidSlots, actionLockedSlots(state.Prefs.LockedSlots), swapper.ActiveAction.MidLabel)
        end
        if now < swapper.ActiveAction.EndsAt then
            return
        end
        swapper.ActiveAction = nil
    end

    -- If user locked a full set via /og wear <set>
    if state.Toggles.WearSet and state.Sets[state.Toggles.WearSet] then
        local wSet = state.Sets[state.Toggles.WearSet]
        swapper.EquipSlots(wSet.Slots, state.Prefs.LockedSlots, 'Wear: ' .. (wSet.Label or wSet.Name))
        return
    end

    local party = AshitaCore:GetMemoryManager():GetParty()
    local ent   = AshitaCore:GetMemoryManager():GetEntity()
    if not party or not ent then return end

    local myIdx = party:GetMemberTargetIndex(0)
    if not myIdx or myIdx == 0 then return end

    local status = ent:GetStatus(myIdx) -- 0 = Idle, 1 = Engaged, 33 = Resting
    local hpp    = party:GetMemberHPPercent(0) or 100
    local mpp    = party:GetMemberMPPercent(0) or 100
    local moving = updatePlayerMovement()

    -- Determine base standing/combat set
    local targetSet = nil
    local label = nil

    if status == 33 and state.Sets.Resting then
        targetSet = state.Sets.Resting
        label = targetSet.Label
    elseif status == 1 then
        -- Engaged
        local tpMode = state.Toggles.TP or 'Default'
        if tpMode == 'Hybrid' and state.Sets.TP_Hybrid then
            targetSet = state.Sets.TP_Hybrid
        elseif tpMode == 'Acc' and state.Sets.TP_Acc then
            targetSet = state.Sets.TP_Acc
        elseif tpMode == 'Tank' and state.Sets.Tank_Engaged then
            targetSet = state.Sets.Tank_Engaged
        else
            targetSet = state.Sets.TP_Default or state.Sets.Idle
        end
        label = targetSet and targetSet.Label or 'Engaged'
    else
        -- Idle
        local idleMode = state.Toggles.Idle or 'Auto'
        if idleMode == 'DT' and state.Sets.Idle_DT then
            targetSet = state.Sets.Idle_DT
        elseif idleMode == 'Regen' and state.Sets.Idle_Regen then
            targetSet = state.Sets.Idle_Regen
        elseif idleMode == 'Refresh' and state.Sets.Idle_Refresh then
            targetSet = state.Sets.Idle_Refresh
        elseif idleMode == 'Auto' then
            if mpp < 75 and (party:GetMemberMP(0) or 0) > 0 and state.Sets.Idle_Refresh then
                targetSet = state.Sets.Idle_Refresh
            elseif hpp < 80 and state.Sets.Idle_Regen then
                targetSet = state.Sets.Idle_Regen
            else
                targetSet = state.Sets.Idle
            end
        else
            targetSet = state.Sets.Idle
        end
        label = targetSet and targetSet.Label or 'Idle'
    end

    if not targetSet then return end
    local finalSlots = targetSet.Slots

    -- Apply active overlays (DT Mode, Kite / Movement, Treasure Hunter)
    if state.Toggles.DT == 'All' and state.Sets.DT then
        finalSlots = state.Sets.DT.Slots
        label = 'DT (All)'
    elseif state.Toggles.DT == 'PDT' and state.Sets.DT_Physical then
        finalSlots = state.Sets.DT_Physical.Slots
        label = 'DT (Physical)'
    elseif state.Toggles.DT == 'MDT' and state.Sets.DT_Magic then
        finalSlots = state.Sets.DT_Magic.Slots
        label = 'DT (Magic)'
    end

    if state.Toggles.Kite and state.Sets.Movement then
        finalSlots = mergeSetSlots(finalSlots, state.Sets.Movement.Slots)
        label = label .. ' + Kite'
    elseif status == 0 and moving and lastPos.movingSince and (now - lastPos.movingSince) >= 1.25
        and state.Prefs.AutoMoveGear and state.Sets.Movement then
        local userIdleOverrides = state.UserOverrides and state.UserOverrides.Idle
        finalSlots = mergeSetSlots(finalSlots, state.Sets.Movement.Slots, userIdleOverrides)
        label = label .. ' + Move'
    end

    if status == 1 and state.Toggles.TH and state.Sets.TH then
        finalSlots = mergeSetSlots(finalSlots, state.Sets.TH.Slots)
        label = label .. ' + TH'
    end

    swapper.EquipSlots(finalSlots, state.Prefs.LockedSlots, label)
end

return swapper
