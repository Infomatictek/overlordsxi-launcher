--[[
* SoulspireXI Gear Manager (soulspire_gear) - State, Frame-Sliced Builder & Persistence
* Manages active sets, user slot overrides, custom sets, incremental rebuilds,
* disk persistence, and /og command handling.
--]]

local chat    = require('chat')
local db      = require('og.db')
local bags    = require('og.bags')
local jobs    = require('og.jobs')
local scorer  = require('og.scorer')
local swapper = require('og.swapper')
local ox_sync = require('og.ox_sync')

local state = {
    Who            = nil,
    WearablePieces = {},
    StoragePieces  = {},
    CurrentEquip   = {},
    WeaponRanks    = {},
    Upgrades       = {},
    Sets           = {},       -- setName -> built/custom set record
    SetOrder       = {},       -- ordered list of setNames
    UserOverrides  = {},       -- setName -> { [slotIdx] = { Id = ..., Name = ... } }
    CustomSets     = {},       -- setName -> { [slotIdx] = { Id = ..., Name = ... } }
    BuildQueue     = nil,      -- frame-sliced build queue
    BuiltAt        = nil,
    LastBagHash    = 0,
    LastBagCheck   = 0,
    LastConflictCheck = 0,
    LastSwapTick   = 0,
    ConflictAddon  = nil,

    Toggles = {
        DT      = 'Off',     -- 'Off' | 'All' | 'PDT' | 'MDT'
        TP      = 'Default', -- 'Default' | 'Hybrid' | 'Acc' | 'Tank'
        Idle    = 'Auto',    -- 'Auto' | 'Normal' | 'DT' | 'Regen' | 'Refresh'
        Nuke    = 'Power',   -- 'Power' | 'Acc'
        Burst   = false,
        Kite    = false,
        TH      = false,
        Dress   = false,
        Paused  = false,
        WearSet = nil,
    },

    Prefs = {
        ZoneWait       = 6,
        AutoMoveGear   = true,
        LockedSlots    = {},
        LockstyleByJob = {},
    },
}

local function msg(text)
    print(chat.header('soulspire_gear') .. chat.message(text))
end

local function errMsg(text)
    print(chat.header('soulspire_gear') .. chat.error(text))
end

state.Print    = msg
state.PrintErr = errMsg

-- ========================= Disk Serialization =========================

local function serialize(val, indent)
    indent = indent or ''
    if type(val) == 'table' then
        local lines = {}
        local keys = {}
        for k in pairs(val) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local v = val[k]
            local keyStr = (type(k) == 'number') and ('[' .. k .. ']') or ('[' .. string.format('%q', tostring(k)) .. ']')
            lines[#lines + 1] = indent .. '    ' .. keyStr .. ' = ' .. serialize(v, indent .. '    ') .. ','
        end
        if #lines == 0 then return '{}' end
        return '{\n' .. table.concat(lines, '\n') .. '\n' .. indent .. '}'
    elseif type(val) == 'string' then
        return string.format('%q', val)
    elseif type(val) == 'number' or type(val) == 'boolean' then
        return tostring(val)
    end
    return 'nil'
end

local function prefsFolder()
    return string.format('%sconfig\\addons\\soulspire_gear', AshitaCore:GetInstallPath())
end

local function prefsPath()
    return prefsFolder() .. '\\prefs.lua'
end

local function profileFolder(who)
    if not who or not who.Name or who.Name == '' then return nil end
    return string.format('%s\\profiles\\%s_%u', prefsFolder(), who.Name, who.ServerId or 0)
end

local function profilePath(who)
    local folder = profileFolder(who)
    if not folder then return nil end
    local jobAbbr = db.JOB_ABBR[who.Job or 1] or 'WAR'
    return string.format('%s\\%s.lua', folder, jobAbbr)
end

function state.SavePrefs()
    local folder = prefsFolder()
    if not ashita.fs.exists(folder) then
        ashita.fs.create_directory(folder)
    end
    local f = io.open(prefsPath(), 'w')
    if f then
        f:write('-- SoulspireXI Gear Manager global preferences\nreturn ' .. serialize(state.Prefs) .. '\n')
        f:close()
    end
end

function state.LoadPrefs()
    local chunk = loadfile(prefsPath())
    if chunk then
        local ok, saved = pcall(chunk)
        if ok and type(saved) == 'table' then
            for k, v in pairs(saved) do
                state.Prefs[k] = v
            end
        end
    end
end

function state.SaveJobProfile()
    if not state.Who then return end
    local folder = profileFolder(state.Who)
    local path   = profilePath(state.Who)
    if not folder or not path then return end
    if not ashita.fs.exists(folder) then
        ashita.fs.create_directory(folder)
    end
    local payload = {
        UserOverrides = state.UserOverrides,
        CustomSets    = state.CustomSets,
        SpecOverride  = ox_sync.State.OverrideSpec[state.Who.Job],
    }
    local f = io.open(path, 'w')
    if f then
        f:write('-- SoulspireXI Gear Manager job profile\nreturn ' .. serialize(payload) .. '\n')
        f:close()
    end
end

function state.LoadJobProfile(who)
    state.UserOverrides = {}
    state.CustomSets    = {}
    local path = profilePath(who)
    if not path then return end
    local chunk = loadfile(path)
    if chunk then
        local ok, saved = pcall(chunk)
        if ok and type(saved) == 'table' then
            state.UserOverrides = saved.UserOverrides or {}
            state.CustomSets    = saved.CustomSets or {}
            if saved.SpecOverride and who and who.Job then
                ox_sync.State.OverrideSpec[who.Job] = saved.SpecOverride
            end
        end
    end
end

-- ========================= Player Identity & Bag Hash =========================

function state.ReadPlayerIdentity()
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    local party  = AshitaCore:GetMemoryManager():GetParty()
    local ent    = AshitaCore:GetMemoryManager():GetEntity()
    if not player or not party then return nil end

    local job = player:GetMainJob()
    if not job or job == 0 then return nil end
    local sub = player:GetSubJob() or 0
    local getLvl = player.GetMainJobLevel or player.GetMainLevel
    local level = (getLvl and getLvl(player)) or 1
    if level <= 0 then level = 1 end

    local name = party:GetMemberName(0) or 'Player'
    local srvId = party:GetMemberServerId(0) or 0
    local zone = party:GetMemberZone(0) or 0
    local myIdx = party:GetMemberTargetIndex(0) or 0
    local race = (ent and myIdx > 0 and ent:GetRace(myIdx)) or 0

    local specEntry = ox_sync.GetActiveSpec(job, level)

    return {
        Name     = name,
        ServerId = srvId,
        Job      = job,
        JobAbbr  = db.JOB_ABBR[job] or 'WAR',
        Sub      = sub,
        SubAbbr  = db.JOB_ABBR[sub] or 'NONE',
        Level    = level,
        SuLevel  = 0,
        Zone     = zone,
        Race     = race,
        SpecId   = specEntry and specEntry.id or 0,
        SpecKey  = specEntry and specEntry.key or nil,
        SpecName = specEntry and specEntry.name or nil,
        SpecRole = specEntry and specEntry.role or nil,
    }
end

local function computeEquippableBagHash()
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    if not inv then return 0 end
    local h = 0
    for _, bagId in ipairs(db.EQUIPPABLE_BAGS) do
        for idx = 1, 80 do
            local item = inv:GetContainerItem(bagId, idx)
            if item and item.Id and item.Id > 0 and item.Id ~= 65535 and (item.Count or 0) > 0 then
                h = h + (bagId * 100003) + (idx * 1009) + item.Id
            end
        end
    end
    for slotId = 0, 3 do
        local eq = inv:GetEquippedItem(slotId)
        if eq and eq.Index then
            h = h + (slotId + 1) * 7919 * eq.Index
        end
    end
    return h
end

-- ========================= Frame-Sliced Set Rebuilder =========================

local function materializeCustomSet(setName, slotDefs, wearablePieces, who)
    local chosen = {}
    local explain = {}
    for s = 1, 16 do
        local ov = slotDefs[s] or slotDefs[db.SLOT_BY_INDEX[s].key]
        if ov then
            local targetId = type(ov) == 'table' and ov.Id or tonumber(ov)
            local targetName = type(ov) == 'table' and ov.Name or (type(ov) == 'string' and ov or nil)
            for _, p in ipairs(wearablePieces) do
                local idMatches = (targetId and p.Id == targetId) or
                    (not targetId and targetName and string.lower(p.Name) == string.lower(targetName))
                if idMatches and bit.band(p.SlotMask or 0, db.SLOT_BY_INDEX[s].mask) ~= 0 then
                    local exact = type(ov) == 'table' and ov.Bag == p.Bag and ov.Index == p.Index
                    if exact then
                        chosen[s] = p
                        break
                    end
                    -- Fall back to an equivalent copy only if the original bag/index moved.
                    if not chosen[s] then chosen[s] = p end
                end
            end
        end
    end
    for s, p in pairs(chosen) do
        explain[s] = { Score = 0, Summary = 'Custom Saved Piece', IsOverride = true }
    end
    return {
        Name     = setName,
        Label    = 'Custom: ' .. setName,
        Category = 'Custom Sets',
        IsCustom = true,
        Slots    = chosen,
        Explain  = explain,
        Totals   = scorer.ComputeTotals(chosen, who, nil),
        SetScore = 0,
    }
end

function state.StartRebuild(announce)
    local who = state.ReadPlayerIdentity()
    if not who then return end

    local jobChanged = (state.Who == nil) or (state.Who.Job ~= who.Job) or (state.Who.ServerId ~= who.ServerId)
    state.Who = who
    if jobChanged then
        state.LoadJobProfile(who)
        -- Re-read active spec in case profile loaded a SpecOverride
        local specEntry = ox_sync.GetActiveSpec(who.Job, who.Level)
        who.SpecId   = specEntry and specEntry.id or 0
        who.SpecKey  = specEntry and specEntry.key or nil
        who.SpecName = specEntry and specEntry.name or nil
        who.SpecRole = specEntry and specEntry.role or nil
    end

    state.CurrentEquip = bags.GetCurrentEquipment()
    state.LastBagHash = computeEquippableBagHash()
    state.WearablePieces, state.StoragePieces = bags.Scan(who, true)
    state.WeaponRanks = scorer.RankWeapons(state.WearablePieces, state.StoragePieces, who)

    local plannedModes = jobs.PlanSets(who, state.CurrentEquip)
    state.BuildQueue = {
        Modes    = plannedModes,
        Index    = 1,
        TempSets = {},
        TempOrder= {},
        Announce = announce == true,
    }
end

-- Rebuild a single set immediately (e.g. when the user changes a slot override in the UI)
function state.RebuildSingleSet(setName)
    if not state.Who then return end
    if state.CustomSets[setName] then
        state.Sets[setName] = materializeCustomSet(setName, state.CustomSets[setName], state.WearablePieces, state.Who)
        return
    end
    local existing = state.Sets[setName]
    if existing and existing.Mode then
        local built = scorer.BuildSet(
            existing.Mode,
            state.WearablePieces,
            state.Who,
            state.UserOverrides[setName],
            state.Prefs.LockedSlots,
            state.CurrentEquip
        )
        state.Sets[setName] = built
    end
end

local function stepBuildQueue()
    local q = state.BuildQueue
    if not q then return end

    local batchEnd = math.min(#q.Modes, q.Index + 2)
    for i = q.Index, batchEnd do
        local m = q.Modes[i]
        local built = scorer.BuildSet(
            m,
            state.WearablePieces,
            state.Who,
            state.UserOverrides[m.Name],
            state.Prefs.LockedSlots,
            state.CurrentEquip
        )
        q.TempSets[m.Name] = built
        q.TempOrder[#q.TempOrder + 1] = m.Name
    end
    q.Index = batchEnd + 1

    if q.Index > #q.Modes then
        -- Append user Custom Sets
        for cName, cSlots in pairs(state.CustomSets) do
            if not q.TempSets[cName] then
                q.TempOrder[#q.TempOrder + 1] = cName
            end
            q.TempSets[cName] = materializeCustomSet(cName, cSlots, state.WearablePieces, state.Who)
        end

        state.Sets      = q.TempSets
        state.SetOrder  = q.TempOrder
        state.BuiltAt   = os.clock()
        state.BuildQueue = nil

        -- Compute storage upgrades across key sets
        local keySets = {}
        for _, sName in ipairs({ 'Idle', 'TP_Default', 'DT', 'WS_Default', 'Precast', 'Cure', 'Nuke' }) do
            if state.Sets[sName] then keySets[#keySets + 1] = state.Sets[sName] end
        end
        state.Upgrades = scorer.FindStorageUpgrades(keySets, state.StoragePieces, state.Who)

        -- Re-apply saved lockstyle if configured for this job
        local lockSet = state.Prefs.LockstyleByJob[state.Who.JobAbbr]
        if lockSet and state.Sets[lockSet] then
            swapper.LockStyleSet(state.Sets[lockSet].Slots)
        end

        if q.Announce then
            local specStr = state.Who.SpecName and (' [' .. state.Who.SpecName .. ']') or ''
            msg(string.format(
                'Built %d sets for %s Lv.%d%s from %d wearable items.',
                #state.SetOrder, state.Who.JobAbbr, state.Who.Level, specStr, #state.WearablePieces
            ))
        end
    end
end

-- Check if conflicting swapper addons (luashitacast / vanagear) are loaded
local function checkConflictingAddons()
    local pm = AshitaCore:GetPluginManager()
    if not pm or not pm.IsLoaded then return nil end
    for _, name in ipairs({ 'luashitacast', 'vanagear' }) do
        local ok, loaded = pcall(pm.IsLoaded, pm, name)
        if ok and loaded then
            return name
        end
    end
    return nil
end

-- Main per-frame tick
function state.Tick()
    if swapper.IsZoneHolding(state.Prefs.ZoneWait) then
        return
    end

    local now = os.clock()

    -- Check for conflicting addons periodically
    if (now - state.LastConflictCheck) >= 2.5 then
        state.LastConflictCheck = now
        local conflict = checkConflictingAddons()
        if conflict ~= state.ConflictAddon then
            state.ConflictAddon = conflict
            if conflict then
                errMsg(string.format('%s is currently loaded! Type "/addon unload %s" so both addons do not fight over equipment slots.', conflict, conflict))
            end
        end
    end

    -- Step any active frame-sliced build queue
    if state.BuildQueue ~= nil then
        stepBuildQueue()
        return
    end

    -- Full inventory hash visits every equippable bag slot; keep it off the hot path.
    -- Soul, job and level updates are also event-triggered where supported.
    -- Poll only as a fallback, no more than once every 5 seconds.
    if (now - state.LastBagCheck) >= 5.0 then
        state.LastBagCheck = now
        local who = state.ReadPlayerIdentity()
        if who then
            local bHash = computeEquippableBagHash()
            local prev  = state.Who
            local identityChanged = (prev == nil)
                or (prev.Job ~= who.Job)
                or (prev.Sub ~= who.Sub)
                or (prev.Level ~= who.Level)
                or (prev.SpecKey ~= who.SpecKey)
                or (prev.Zone ~= who.Zone)

            if identityChanged or bHash ~= state.LastBagHash then
                state.LastBagHash = bHash
                state.StartRebuild(false)
                return
            end
        end
    end

    -- Run equipment swapper tick every 0.20s
    if not state.ConflictAddon and (now - state.LastSwapTick) >= 0.20 then
        state.LastSwapTick = now
        swapper.Tick(state)
    end
end

-- Save currently worn equipment into a set (either an existing set's overrides or a new Custom Set)
function state.SaveCurrentEquipmentToSet(setName)
    if not setName or setName == '' then return false end
    local cur = bags.GetCurrentEquipment()
    local savedSlots = {}
    for s = 1, 16 do
        if cur[s] then
            savedSlots[s] = { Id = cur[s].Id, Name = cur[s].Name, Bag = cur[s].Bag, Index = cur[s].Index }
        end
    end

    if state.Sets[setName] and not state.Sets[setName].IsCustom then
        state.UserOverrides[setName] = savedSlots
        state.RebuildSingleSet(setName)
    else
        state.CustomSets[setName] = savedSlots
        if not state.Sets[setName] then
            state.SetOrder[#state.SetOrder + 1] = setName
        end
        state.Sets[setName] = materializeCustomSet(setName, savedSlots, state.WearablePieces, state.Who)
    end

    state.Toggles.Dress = false
    state.SaveJobProfile()
    return true
end

-- ========================= Slash Command Handler (/og, /ogear) =========================

local function cycleValue(current, list)
    for i, v in ipairs(list) do
        if string.lower(v) == string.lower(tostring(current)) then
            return list[(i % #list) + 1]
        end
    end
    return list[1]
end

function state.HandleCommand(e, ui)
    local args = e.command:args()
    if #args == 0 then return end
    local root = string.lower(args[1])
    if root ~= '/og' and root ~= '/ogear' then return end

    e.blocked = true

    if #args == 1 then
        if ui then
            ui.Open[1] = not ui.Open[1]
        end
        return
    end

    local sub = string.lower(args[2])
    local arg3 = args[3]

    if sub == 'build' or sub == 'rebuild' then
        state.StartRebuild(true)
    elseif sub == 'dt' then
        local map = { off = 'Off', all = 'All', dt = 'All', pdt = 'PDT', physical = 'PDT', mdt = 'MDT', magic = 'MDT' }
        if arg3 and map[string.lower(arg3)] then
            state.Toggles.DT = map[string.lower(arg3)]
        else
            state.Toggles.DT = cycleValue(state.Toggles.DT, { 'Off', 'All', 'PDT', 'MDT' })
        end
        msg('Damage Taken Mode: ' .. state.Toggles.DT)
    elseif sub == 'tp' or sub == 'melee' or sub == 'engaged' then
        local map = { default = 'Default', normal = 'Default', hybrid = 'Hybrid', dt = 'Hybrid', acc = 'Acc', accuracy = 'Acc', tank = 'Tank' }
        if arg3 and map[string.lower(arg3)] then
            state.Toggles.TP = map[string.lower(arg3)]
        else
            state.Toggles.TP = cycleValue(state.Toggles.TP, { 'Default', 'Hybrid', 'Acc', 'Tank' })
        end
        msg('Engaged TP Mode: ' .. state.Toggles.TP)
    elseif sub == 'idle' then
        local map = { auto = 'Auto', normal = 'Normal', default = 'Normal', dt = 'DT', regen = 'Regen', refresh = 'Refresh' }
        if arg3 and map[string.lower(arg3)] then
            state.Toggles.Idle = map[string.lower(arg3)]
        else
            state.Toggles.Idle = cycleValue(state.Toggles.Idle, { 'Auto', 'Normal', 'DT', 'Regen', 'Refresh' })
        end
        msg('Idle Mode: ' .. state.Toggles.Idle)
    elseif sub == 'nuke' then
        local map = { power = 'Power', dmg = 'Power', acc = 'Acc', accuracy = 'Acc' }
        if arg3 and map[string.lower(arg3)] then
            state.Toggles.Nuke = map[string.lower(arg3)]
        else
            state.Toggles.Nuke = (state.Toggles.Nuke == 'Power') and 'Acc' or 'Power'
        end
        msg('Elemental Nuke Mode: ' .. state.Toggles.Nuke)
    elseif sub == 'burst' or sub == 'mb' then
        if arg3 == 'on' then state.Toggles.Burst = true
        elseif arg3 == 'off' then state.Toggles.Burst = false
        else state.Toggles.Burst = not state.Toggles.Burst end
        msg('Magic Burst Mode: ' .. (state.Toggles.Burst and 'ON' or 'OFF'))
    elseif sub == 'kite' or sub == 'move' then
        if arg3 == 'on' then state.Toggles.Kite = true
        elseif arg3 == 'off' then state.Toggles.Kite = false
        else state.Toggles.Kite = not state.Toggles.Kite end
        msg('Kite / Movement Lock: ' .. (state.Toggles.Kite and 'ON' or 'OFF'))
    elseif sub == 'th' then
        if arg3 == 'on' then state.Toggles.TH = true
        elseif arg3 == 'off' then state.Toggles.TH = false
        else state.Toggles.TH = not state.Toggles.TH end
        msg('Treasure Hunter Overlay: ' .. (state.Toggles.TH and 'ON' or 'OFF'))
    elseif sub == 'spec' then
        if not state.Who then return end
        local choice = arg3 and string.lower(arg3) or 'auto'
        ox_sync.State.OverrideSpec[state.Who.Job] = choice
        state.SaveJobProfile()
        state.StartRebuild(true)
    elseif sub == 'dress' then
        state.Toggles.Dress = not state.Toggles.Dress
        msg(state.Toggles.Dress
            and 'Dressing mode ON: auto-swapping paused. Equip what you want, then "/og save <SetName>".'
            or 'Dressing mode OFF: auto-swapping resumed.')
    elseif sub == 'save' then
        if not arg3 or arg3 == '' then
            errMsg('Usage: /og save <SetName>')
            return
        end
        if state.SaveCurrentEquipmentToSet(arg3) then
            msg('Saved currently equipped gear to set "' .. arg3 .. '" and resumed swapping.')
        end
    elseif sub == 'wear' then
        if not arg3 or string.lower(arg3) == 'off' or string.lower(arg3) == 'none' then
            state.Toggles.WearSet = nil
            msg('Released held set; normal state swapping resumed.')
        else
            for k, s in pairs(state.Sets) do
                if string.lower(k) == string.lower(arg3) then
                    state.Toggles.WearSet = k
                    swapper.EquipSlots(s.Slots, state.Prefs.LockedSlots, 'Wear: ' .. (s.Label or k))
                    msg('Holding set "' .. k .. '" (use "/og wear off" to release).')
                    return
                end
            end
            errMsg('Set not found: ' .. tostring(arg3))
        end
    elseif sub == 'equip' then
        if not arg3 then
            errMsg('Usage: /og equip <SetName>')
            return
        end
        for k, s in pairs(state.Sets) do
            if string.lower(k) == string.lower(arg3) then
                swapper.EquipSlots(s.Slots, state.Prefs.LockedSlots, s.Label or k)
                msg('Equipped set "' .. k .. '" once.')
                return
            end
        end
        errMsg('Set not found: ' .. tostring(arg3))
    elseif sub == 'look' or sub == 'lockstyle' then
        if not state.Who then return end
        if not arg3 or string.lower(arg3) == 'off' then
            state.Prefs.LockstyleByJob[state.Who.JobAbbr] = nil
            state.SavePrefs()
            AshitaCore:GetChatManager():QueueCommand(1, '/lockstyle off')
            msg('Unlocked visual appearance for ' .. state.Who.JobAbbr .. '.')
        else
            for k, s in pairs(state.Sets) do
                if string.lower(k) == string.lower(arg3) then
                    state.Prefs.LockstyleByJob[state.Who.JobAbbr] = k
                    state.SavePrefs()
                    swapper.LockStyleSet(s.Slots)
                    msg('Locked appearance for ' .. state.Who.JobAbbr .. ' to set "' .. k .. '".')
                    return
                end
            end
            errMsg('Set not found: ' .. tostring(arg3))
        end
    elseif sub == 'upgrades' then
        if #state.Upgrades == 0 then
            msg('No upgrades found in your non-equippable storage bags.')
        else
            msg(string.format('Found %d upgrade(s) in storage bags:', math.min(#state.Upgrades, 10)))
            for i = 1, math.min(#state.Upgrades, 10) do
                local u = state.Upgrades[i]
                msg(string.format('  [%s] %s -> %s (%s, +%.1f pts over %s)',
                    u.BagName, u.Piece.Name, u.SetName, u.SlotKey, u.ScoreGain, u.Current))
            end
        end
    else
        msg('Commands: /og, /og build, /og dt [off|all|pdt|mdt], /og tp [default|hybrid|acc|tank], /og idle [auto|normal|dt|regen|refresh], /og burst, /og kite, /og th, /og wear <set>|off, /og dress, /og save <set>, /og look <set>|off, /og upgrades')
    end
end

return state
