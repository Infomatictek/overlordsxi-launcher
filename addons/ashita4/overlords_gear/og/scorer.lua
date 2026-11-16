--[[
* OverlordsXI Gear Manager (overlords_gear) - Cap-Aware Set Builder & Scorer
* Multi-pass coordinate-ascent solver with Haste/DT/FC caps, set bonuses,
* latents, multi-slot encumbrance checks, storage upgrade scanner, and weapon advisor.
--]]

local bit = require('bit')
local db  = require('og.db')

local scorer = {}

-- Server basis-point conversions (100 server units = 1% in human units)
local UNIT_SCALE = {
    HASTE_GEAR  = 100,
    HASTE_MAGIC = 100,
    DMG         = 100,
    DMGPHYS     = 100,
    DMGPHYS_II  = 100,
    DMGMAGIC    = 100,
    DMGMAGIC_II = 100,
    DMGBREATH   = 100,
    DMGRANGE    = 100,
    UDMGPHYS    = 100,
    UDMGMAGIC   = 100,
    PDT         = 100,
    MDT         = 100,
}

-- Virtual composite stats sharing a single server cap (-50% = -5000 basis points)
local VIRTUAL_STATS = {
    PDT = { 'DMG', 'DMGPHYS' },
    MDT = { 'DMG', 'DMGMAGIC' },
}

local DYNAMIS_ZONES = {
    [39] = true, [40] = true, [41] = true, [42] = true, [134] = true, [135] = true,
    [185] = true, [186] = true, [187] = true, [188] = true,
    [294] = true, [295] = true, [296] = true, [297] = true,
}

local function latentHolds(lat, mode, who)
    if not who then return false end
    local lid, p = lat.lat, lat.p
    if lid == 8  then return who.Sub == p end
    if lid == 62 then return who.Job == p end
    if lid == 50 then return (who.Level or 99) < p end
    if lid == 51 then return (who.Level or 0) > p end
    if lid == 23 then return who.Zone == p end
    if lid == 48 then return DYNAMIS_ZONES[who.Zone or 0] == true end
    if lid == 10 then return mode.Drawn == true end
    if lid == 11 then return mode.Drawn == false end
    return false
end

-- Compile a Mode definition into server mod keys, weights, caps, and relevant gear set bonuses
function scorer.CompileMode(mode)
    local c = {
        Name     = mode.Name,
        Label    = mode.Label or mode.Name,
        Category = mode.Category or 'General',
        Drawn    = mode.Drawn,
        w        = {},
        cap      = {},
        parts    = {},
        keyLabel = {},
        hasPet   = false,
        sets     = {},
        setOf    = {},
    }

    local function resolveKey(statName, isPet)
        if VIRTUAL_STATS[statName] and not isPet then
            local k = 'v' .. statName
            c.keyLabel[k] = statName
            return k, UNIT_SCALE[statName] or 1
        end
        local mid = db.ModId(statName)
        if not mid then return nil, 1 end
        local k = (isPet and 'p' or 'm') .. tostring(mid)
        c.keyLabel[k] = (isPet and ('Pet:' .. statName) or statName)
        return k, UNIT_SCALE[statName] or 1
    end

    for statName, weight in pairs(mode.Stats or {}) do
        local k, scale = resolveKey(statName, false)
        if k and weight ~= 0 then
            c.w[k] = (c.w[k] or 0) + (weight / scale)
        end
    end
    for statName, weight in pairs(mode.Pet or {}) do
        local k, scale = resolveKey(statName, true)
        if k and weight ~= 0 then
            c.w[k] = (c.w[k] or 0) + (weight / scale)
            c.hasPet = true
        end
    end
    for statName, capVal in pairs(mode.Caps or {}) do
        local k, scale = resolveKey(statName, false)
        if k then
            c.cap[k] = capVal * scale
        end
    end
    for statName, capVal in pairs(mode.PetCaps or {}) do
        local k, scale = resolveKey(statName, true)
        if k then
            c.cap[k] = capVal * scale
        end
    end

    -- Map component server mods into virtual stats (PDT, MDT)
    for vName, modNames in pairs(VIRTUAL_STATS) do
        local vk = 'v' .. vName
        if c.w[vk] ~= nil then
            for _, mName in ipairs(modNames) do
                local mid = db.ModId(mName)
                if mid then
                    c.parts[mid] = c.parts[mid] or {}
                    table.insert(c.parts[mid], vk)
                end
            end
        end
    end

    -- Index gear sets that grant any stat weighted by this mode
    for setId, gs in pairs(db.GearSets() or {}) do
        local activeMods = {}
        for _, m in ipairs(gs.mods or {}) do
            local keys = {}
            local mk = 'm' .. tostring(m.mod)
            if c.w[mk] then keys[#keys + 1] = mk end
            for _, vk in ipairs(c.parts[m.mod] or {}) do
                keys[#keys + 1] = vk
            end
            if #keys > 0 then
                activeMods[#activeMods + 1] = { keys = keys, v = m.v }
            end
        end
        if #activeMods > 0 then
            local members = {}
            for _, iid in ipairs(gs.items or {}) do
                members[iid] = true
            end
            local entry = {
                id      = setId,
                min     = gs.min or 2,
                max     = gs.max or 0,
                req     = gs.req,
                mods    = activeMods,
                members = members,
            }
            c.sets[#c.sets + 1] = entry
            for _, iid in ipairs(gs.items or {}) do
                c.setOf[iid] = c.setOf[iid] or {}
                table.insert(c.setOf[iid], entry)
            end
        end
    end

    return c
end

-- Extract the relevant stat vector for a single piece under compiled mode `c`
function scorer.PieceVector(piece, c, who)
    local vec = {}
    local hasAny = false

    local function addMod(mid, val)
        if val == 0 then return end
        local mk = 'm' .. tostring(mid)
        if c.w[mk] then
            vec[mk] = (vec[mk] or 0) + val
            hasAny = true
        end
        local vlist = c.parts[mid]
        if vlist then
            for i = 1, #vlist do
                local vk = vlist[i]
                vec[vk] = (vec[vk] or 0) + val
                hasAny = true
            end
        end
    end

    for mid, val in pairs(piece.Mods or {}) do
        addMod(mid, val)
    end

    local latList = db.Latents()[piece.Id]
    if latList then
        for i = 1, #latList do
            local l = latList[i]
            if latentHolds(l, c, who) then
                addMod(l.mod, l.v)
            end
        end
    end

    if c.hasPet and piece.PetMods then
        for _, pmods in pairs(piece.PetMods) do
            for mid, val in pairs(pmods) do
                local pk = 'p' .. tostring(mid)
                if c.w[pk] then
                    vec[pk] = (vec[pk] or 0) + val
                    hasAny = true
                end
            end
        end
    end

    -- Very small tie-breaker for item level / defense so equal-scored pieces pick higher tier
    local defVal = piece.Mods and piece.Mods[1] or 0
    local tieBreak = (piece.Level or 1) * 0.0005 + defVal * 0.0002
    if c.setOf[piece.Id] then
        hasAny = true
    end

    return vec, hasAny, tieBreak
end

local function applyCap(val, capVal)
    if capVal == nil then return val end
    if capVal < 0 then
        return math.max(val, capVal)
    else
        return math.min(val, capVal)
    end
end

-- Score a 16-slot selection table `chosen[slotIdx] = piece`
local function evaluateSetScore(chosen, pieceVecs, pieceTies, c)
    local sums = {}
    local tieSum = 0

    for slotIdx = 1, 16 do
        local p = chosen[slotIdx]
        if p then
            tieSum = tieSum + (pieceTies[p.UniqueKey] or 0)
            local v = pieceVecs[p.UniqueKey]
            if v then
                for k, amount in pairs(v) do
                    sums[k] = (sums[k] or 0) + amount
                end
            end
        end
    end

    -- Check active gear set bonuses
    if #c.sets > 0 then
        for i = 1, #c.sets do
            local gs = c.sets[i]
            local count = 0
            local hasReq = (gs.req == nil)
            for slotIdx = 1, 16 do
                local p = chosen[slotIdx]
                if p and gs.members[p.Id] then
                    count = count + 1
                    if gs.req == p.Id then hasReq = true end
                end
            end
            if hasReq and count >= gs.min then
                local effCount = (gs.max and gs.max > 0) and math.min(count, gs.max) or count
                local mult = effCount - gs.min + 1
                for _, m in ipairs(gs.mods) do
                    for _, k in ipairs(m.keys) do
                        sums[k] = (sums[k] or 0) + m.v * mult
                    end
                end
            end
        end
    end

    local total = tieSum
    for k, rawVal in pairs(sums) do
        local w = c.w[k]
        if w then
            local capped = applyCap(rawVal, c.cap[k])
            total = total + capped * w
        end
    end
    return total
end

-- Check if placing `candidate` in `slotIdx` conflicts with paired ring/ear or multi-slot blocks
local function canPlaceInSlot(candidate, slotIdx, chosen, lockedSlots)
    local slotDef = db.SLOT_BY_INDEX[slotIdx]
    if not slotDef then return false end
    if bit.band(candidate.SlotMask or 0, slotDef.mask) == 0 then
        return false
    end

    -- Check paired Ear / Ring uniqueness
    if slotDef.pairSlot then
        local other = chosen[slotDef.pairSlot]
        if other then
            if other.UniqueKey == candidate.UniqueKey then
                return false
            end
            if other.Id == candidate.Id then
                local isRare = other.ResItem and other.ResItem.Flags and bit.band(other.ResItem.Flags, 0x8000) ~= 0
                if isRare then return false end
            end
        end
    end

    -- Check if candidate's BlockMask conflicts with a locked slot
    local bmask = candidate.BlockMask or 0
    if bmask ~= 0 then
        for s = 1, 16 do
            if s ~= slotIdx and lockedSlots[s] then
                local sMask = db.SLOT_BY_INDEX[s].mask
                if bit.band(bmask, sMask) ~= 0 then
                    return false
                end
            end
        end
    end

    -- Check if any locked piece blocks this slot
    for s = 1, 16 do
        if s ~= slotIdx and lockedSlots[s] and chosen[s] then
            local ob = chosen[s].BlockMask or 0
            if bit.band(ob, slotDef.mask) ~= 0 then
                return false
            end
        end
    end

    return true
end

-- Build a complete set for `mode` from `wearablePieces`, honoring `userOverrides` and `globalLockedSlots`
function scorer.BuildSet(mode, wearablePieces, who, userOverrides, globalLockedSlots)
    local c = scorer.CompileMode(mode)
    userOverrides = userOverrides or {}
    globalLockedSlots = globalLockedSlots or {}

    local pieceVecs = {}
    local pieceTies = {}
    local bySlot    = {}
    local byId      = {}
    for s = 1, 16 do bySlot[s] = {} end

    for i = 1, #wearablePieces do
        local p = wearablePieces[i]
        byId[p.Id] = byId[p.Id] or p
        local vec, _, tie = scorer.PieceVector(p, c, who)
        pieceVecs[p.UniqueKey] = vec
        pieceTies[p.UniqueKey] = tie
        for s = 5, 16 do
            if bit.band(p.SlotMask or 0, db.SLOT_BY_INDEX[s].mask) ~= 0 then
                table.insert(bySlot[s], p)
            end
        end
    end

    local chosen = {}
    local locked = {}

    -- 1. Apply explicit per-set user overrides first (can include Main/Sub/Range/Ammo or Armor)
    for s = 1, 16 do
        if globalLockedSlots[s] then
            locked[s] = true
        else
            local ov = userOverrides[s] or userOverrides[db.SLOT_BY_INDEX[s].key]
            if ov then
                if ov == 'none' or ov.Id == 0 then
                    locked[s] = true
                else
                    local targetId = type(ov) == 'table' and ov.Id or tonumber(ov)
                    local targetName = type(ov) == 'table' and ov.Name or (type(ov) == 'string' and ov or nil)
                    for _, p in ipairs(wearablePieces) do
                        if (targetId and p.Id == targetId) or (targetName and string.lower(p.Name) == string.lower(targetName)) then
                            if bit.band(p.SlotMask or 0, db.SLOT_BY_INDEX[s].mask) ~= 0 then
                                chosen[s] = p
                                locked[s] = true
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    -- 2. Initial greedy pass across unlocked armor slots (5..16)
    for _, s in ipairs(db.ARMOR_SLOTS) do
        if not locked[s] then
            local bestPiece = nil
            local bestScore = -1e9
            for _, cand in ipairs(bySlot[s]) do
                if canPlaceInSlot(cand, s, chosen, locked) then
                    local displaced = {}
                    local bmask = cand.BlockMask or 0
                    if bmask ~= 0 then
                        for os = 5, 16 do
                            if os ~= s and chosen[os] and bit.band(bmask, db.SLOT_BY_INDEX[os].mask) ~= 0 then
                                displaced[os] = chosen[os]
                                chosen[os] = nil
                            end
                        end
                    end
                    for os = 5, 16 do
                        if os ~= s and chosen[os] and bit.band(chosen[os].BlockMask or 0, db.SLOT_BY_INDEX[s].mask) ~= 0 then
                            displaced[os] = chosen[os]
                            chosen[os] = nil
                        end
                    end

                    chosen[s] = cand
                    local sc = evaluateSetScore(chosen, pieceVecs, pieceTies, c)
                    if sc > bestScore then
                        bestScore = sc
                        bestPiece = cand
                    end
                    chosen[s] = nil
                    for os, dp in pairs(displaced) do
                        chosen[os] = dp
                    end
                end
            end
            if bestPiece and bestScore > 0 then
                local bmask = bestPiece.BlockMask or 0
                for os = 5, 16 do
                    if os ~= s and chosen[os] then
                        if bit.band(bmask, db.SLOT_BY_INDEX[os].mask) ~= 0 or bit.band(chosen[os].BlockMask or 0, db.SLOT_BY_INDEX[s].mask) ~= 0 then
                            chosen[os] = nil
                        end
                    end
                end
                chosen[s] = bestPiece
            end
        end
    end

    -- 3. Coordinate-ascent refinement rounds (handles Haste/DT/FC caps & set bonuses)
    for _ = 1, 3 do
        local changed = false
        for _, s in ipairs(db.ARMOR_SLOTS) do
            if not locked[s] then
                local curPiece = chosen[s]
                local bestPiece = curPiece
                local bestScore = evaluateSetScore(chosen, pieceVecs, pieceTies, c)

                -- Also test leaving slot empty if current piece has negative contribution
                chosen[s] = nil
                local emptyScore = evaluateSetScore(chosen, pieceVecs, pieceTies, c)
                if emptyScore > bestScore + 1e-6 then
                    bestScore = emptyScore
                    bestPiece = nil
                    changed = true
                end

                for _, cand in ipairs(bySlot[s]) do
                    if cand ~= curPiece and canPlaceInSlot(cand, s, chosen, locked) then
                        local displaced = {}
                        local bmask = cand.BlockMask or 0
                        for os = 5, 16 do
                            if os ~= s and chosen[os] then
                                if bit.band(bmask, db.SLOT_BY_INDEX[os].mask) ~= 0 or bit.band(chosen[os].BlockMask or 0, db.SLOT_BY_INDEX[s].mask) ~= 0 then
                                    displaced[os] = chosen[os]
                                    chosen[os] = nil
                                end
                            end
                        end

                        chosen[s] = cand
                        local sc = evaluateSetScore(chosen, pieceVecs, pieceTies, c)
                        if sc > bestScore + 1e-6 then
                            bestScore = sc
                            bestPiece = cand
                            changed = true
                        end
                        chosen[s] = nil
                        for os, dp in pairs(displaced) do
                            chosen[os] = dp
                        end
                    end
                end

                if bestPiece then
                    local bmask = bestPiece.BlockMask or 0
                    for os = 5, 16 do
                        if os ~= s and chosen[os] then
                            if bit.band(bmask, db.SLOT_BY_INDEX[os].mask) ~= 0 or bit.band(chosen[os].BlockMask or 0, db.SLOT_BY_INDEX[s].mask) ~= 0 then
                                chosen[os] = nil
                            end
                        end
                    end
                end
                chosen[s] = bestPiece
            end
        end
        if not changed then break end
    end

    -- 4. Compute per-slot explanation & total stats summary
    local explain = {}
    for s = 1, 16 do
        local p = chosen[s]
        if p then
            local vec = pieceVecs[p.UniqueKey] or {}
            local singleScore = 0
            local statNotes = {}
            for k, val in pairs(vec) do
                local w = c.w[k]
                if w then
                    local contrib = val * w
                    singleScore = singleScore + contrib
                    local lbl = c.keyLabel[k] or k
                    local scale = UNIT_SCALE[lbl] or 1
                    local dispVal = val / scale
                    statNotes[#statNotes + 1] = {
                        label   = lbl,
                        val     = dispVal,
                        contrib = contrib,
                    }
                end
            end
            table.sort(statNotes, function(a, b) return math.abs(a.contrib) > math.abs(b.contrib) end)
            local topParts = {}
            for i = 1, math.min(#statNotes, 4) do
                local st = statNotes[i]
                local sign = (st.val >= 0) and '+' or ''
                topParts[#topParts + 1] = string.format('%s %s%s', st.label, sign, tostring(st.val))
            end
            explain[s] = {
                Score      = singleScore,
                Summary    = (#topParts > 0) and table.concat(topParts, ', ') or string.format('Lv.%d DEF', p.Level or 1),
                IsOverride = locked[s] and userOverrides[s] ~= nil,
            }
        end
    end

    local totals = scorer.ComputeTotals(chosen, who, c)

    return {
        Name      = mode.Name,
        Label     = mode.Label or mode.Name,
        Category  = mode.Category or 'General',
        Mode      = mode,
        Compiled  = c,
        Slots     = chosen,
        Explain   = explain,
        Totals    = totals,
        SetScore  = evaluateSetScore(chosen, pieceVecs, pieceTies, c),
    }
end

-- Compute human-readable stat totals across a 16-slot set
function scorer.ComputeTotals(chosen, who, compiledMode)
    local raw = {}
    local function add(mid, val)
        raw[mid] = (raw[mid] or 0) + val
    end
    for s = 1, 16 do
        local p = chosen[s]
        if p and p.Mods then
            for mid, val in pairs(p.Mods) do
                add(mid, val)
            end
            local latList = db.Latents()[p.Id]
            if latList then
                for _, l in ipairs(latList) do
                    if latentHolds(l, compiledMode or {}, who) then
                        add(l.mod, l.v)
                    end
                end
            end
        end
    end

    local function m(name)
        local id = db.ModId(name)
        return (id and raw[id]) or 0
    end

    local dmg   = m('DMG')
    local pdt   = math.max(-50, (dmg + m('DMGPHYS')) / 100)
    local mdt   = math.max(-50, (dmg + m('DMGMAGIC')) / 100)
    local haste = math.min(25, m('HASTE_GEAR') / 100)

    return {
        DEF      = m('DEF'),
        HP       = m('HP'),
        MP       = m('MP'),
        STR      = m('STR'),
        DEX      = m('DEX'),
        VIT      = m('VIT'),
        AGI      = m('AGI'),
        INT      = m('INT'),
        MND      = m('MND'),
        CHR      = m('CHR'),
        ACC      = m('ACC'),
        ATT      = m('ATT'),
        RACC     = m('RACC'),
        RATT     = m('RATT'),
        MACC     = m('MACC'),
        MATT     = m('MATT'),
        MEVA     = m('MEVA'),
        EVA      = m('EVA'),
        Haste    = haste,
        PDT      = pdt,
        MDT      = mdt,
        StoreTP  = m('STORETP'),
        DA       = m('DOUBLE_ATTACK'),
        TA       = m('TRIPLE_ATTACK'),
        Crit     = m('CRITHITRATE'),
        FastCast = m('FASTCAST'),
        CurePot  = math.min(50, m('CURE_POTENCY')),
        Refresh  = m('REFRESH') + m('FAERIE_REFRESH'),
        Regen    = m('REGEN'),
        Enmity   = m('ENMITY'),
    }
end

-- Scan non-equippable Storage bags for items that would upgrade any built set
function scorer.FindStorageUpgrades(builtSets, storagePieces, who)
    local upgrades = {}
    if not storagePieces or #storagePieces == 0 then return upgrades end

    for _, setEntry in ipairs(builtSets or {}) do
        local c = setEntry.Compiled
        if c then
            for _, sp in ipairs(storagePieces) do
                local vec, hasAny, tie = scorer.PieceVector(sp, c, who)
                if hasAny then
                    local candScore = tie
                    for k, val in pairs(vec) do
                        local w = c.w[k]
                        if w then
                            candScore = candScore + applyCap(val, c.cap[k]) * w
                        end
                    end

                    for _, s in ipairs(db.ARMOR_SLOTS) do
                        if bit.band(sp.SlotMask or 0, db.SLOT_BY_INDEX[s].mask) ~= 0 then
                            local cur = setEntry.Slots[s]
                            local curScore = (setEntry.Explain[s] and setEntry.Explain[s].Score) or 0
                            local gain = candScore - curScore
                            if gain > 0.5 and (not cur or cur.Id ~= sp.Id) then
                                upgrades[#upgrades + 1] = {
                                    Piece     = sp,
                                    BagName   = sp.BagName,
                                    SetName   = setEntry.Label or setEntry.Name,
                                    SlotKey   = db.SLOT_BY_INDEX[s].key,
                                    Current   = cur and cur.Name or '(Empty)',
                                    ScoreGain = gain,
                                }
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(upgrades, function(a, b) return a.ScoreGain > b.ScoreGain end)
    return upgrades
end

-- Rank weapons/shields/ranged/ammo in bags for the Weapon Advisor tab
function scorer.RankWeapons(wearablePieces, storagePieces, who)
    local list = {}
    local all = {}
    for _, p in ipairs(wearablePieces or {}) do all[#all + 1] = p end
    for _, p in ipairs(storagePieces or {}) do all[#all + 1] = p end

    for _, p in ipairs(all) do
        local isWep = bit.band(p.SlotMask or 0, 0x000F) ~= 0
        if isWep then
            local dps = 0
            if (p.Dmg or 0) > 0 and (p.Delay or 0) > 0 then
                dps = (p.Dmg * 60.0) / p.Delay
            end
            local statBonus = 0
            for mid, val in pairs(p.Mods or {}) do
                if mid == 1198 then -- FAERIE_REFRESH (Orphic Egg)
                    statBonus = statBonus + 25
                elseif mid >= 8 and mid <= 14 then
                    statBonus = statBonus + val * 0.5
                elseif mid == 23 or mid == 24 or mid == 25 or mid == 26 or mid == 28 or mid == 30 then
                    statBonus = statBonus + val * 0.4
                end
            end
            -- Spec weapon synergy bonus
            local specNote = nil
            if who then
                if who.Job == 2 and who.SpecKey == 'sensei' and p.Skill == 12 then
                    statBonus = statBonus + 18
                    specNote = 'Sensei Staff'
                elseif who.Job == 4 and who.SpecKey == 'necromancer' and p.Skill == 7 then
                    statBonus = statBonus + 18
                    specNote = 'Necromancer Scythe'
                elseif who.Job == 19 and who.SpecKey == 'bladewheel' and p.Skill == 27 then
                    statBonus = statBonus + 18
                    specNote = 'Bladewheel Chakram'
                elseif who.Job == 20 and p.Id == 18256 then
                    statBonus = statBonus + 25
                    specNote = 'Eos/Titania Refresh'
                end
            end

            local slotType = 'Main'
            if bit.band(p.SlotMask, 0x0001) ~= 0 then
                slotType = 'Main'
            elseif bit.band(p.SlotMask, 0x0002) ~= 0 then
                slotType = 'Sub'
            elseif bit.band(p.SlotMask, 0x0004) ~= 0 then
                slotType = 'Range'
            elseif bit.band(p.SlotMask, 0x0008) ~= 0 then
                slotType = 'Ammo'
            end

            list[#list + 1] = {
                Piece    = p,
                SlotType = slotType,
                Skill    = db.SKILL_NAMES[p.Skill] or (p.Shield and p.Shield > 0 and 'Shield' or 'Grip / Misc'),
                DPS      = dps,
                Rating   = dps * 2.0 + statBonus + (p.Level or 1) * 0.25,
                SpecNote = specNote,
            }
        end
    end

    table.sort(list, function(a, b) return a.Rating > b.Rating end)
    return list
end

return scorer
