local debuffHandler = {}

debuffHandler.enemies = {}      -- [serverId] = entries from the native OXKE (0x1FE) server stream
debuffHandler.oxmob = {}        -- [serverId] = { at = clock, entries = {...} } from [OXMOB] 0x017 packets
debuffHandler.fallback = {}     -- [serverId] = { [effectId] = entry } from 0x028/0x029 (pre-sync / untargeted adds)
debuffHandler.serverSynced = false

local okCat, catalog = pcall(require, 'status_catalog')
if not okCat or type(catalog) ~= 'table' then
    catalog = { byEffectId = {}, byIconId = {}, list = {} }
end
debuffHandler.catalog = catalog

local thTags = {}

local NO_TIMER_MARKER = 4294967295 -- 0xFFFFFFFF
local OP_HELLO = 0
local OP_ENTITY_SNAPSHOT = 1
local OP_ENTITY_CLEAR = 2

local PROTO_TAG = '[OXMOB]|'
local MOB_ID_MIN = 0x01000000

local deathMes = T{
    [6] = true,   -- defeated
    [20] = true,  -- falls to the ground
    [97] = true,  -- was defeated by
    [113] = true, -- falls to the ground (variation)
    [406] = true, -- falls to the ground (alt)
    [605] = true, -- falls to the ground (alt)
    [646] = true, -- falls to the ground (alt)
}

-- Wear-off messages; `param` is the status effect id.
local wearMes = T{ [64] = true, [204] = true, [206] = true }

-- Action result messages where the result `Param` is the status id that landed on the target.
local debuffLandMes = T{
    [82] = true, [127] = true, [141] = true, [236] = true, [237] = true, [242] = true, [267] = true,
    [268] = true, [270] = true, [271] = true, [277] = true, [278] = true, [279] = true, [280] = true,
    [282] = true, [283] = true,
}
local buffLandMes = T{ [186] = true, [194] = true, [230] = true, [266] = true }

local defaultDuration = { [2] = 60, [3] = 90, [4] = 120, [5] = 180, [6] = 120, [7] = 30, [10] = 5, [11] = 60,
    [12] = 60, [13] = 120, [19] = 90, [21] = 60 }

local reusableDebuffIds = {}
local reusableDebuffTimes = {}
local reusableDebuffBadges = {}
local reusableDebuffEffects = {}
local reusableDebuffFlags = {}   -- 1 = debuff, 0 = buff, nil = unknown (native OXKE entry)
local reusableMerged = {}

local OX_FRESH_SEC = 10.0
local partial = {}   -- [mobId] = { chunks = {}, expect = n }

local function readU16(data, offset)
    local b1, b2 = data:byte(offset, offset + 1)
    return b1 + b2 * 256
end

local function readU32(data, offset)
    local b1, b2, b3, b4 = data:byte(offset, offset + 3)
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function splitChar(str, sep)
    local out, start = {}, 1
    while true do
        local pos = string.find(str, sep, start, true)
        if not pos then out[#out + 1] = string.sub(str, start); break end
        out[#out + 1] = string.sub(str, start, pos - 1)
        start = pos + 1
    end
    return out
end

debuffHandler.HandleServerPacket = function(e)
    local data = e.data
    if type(data) ~= 'string' or #data < 16 then
        return false
    end

    if data:sub(5, 8) ~= 'OXKE' then
        return false
    end

    e.blocked = true

    local version, op, count = data:byte(9, 11)
    if version ~= 1 then
        return false
    end

    local entityServerId = readU32(data, 13)
    debuffHandler.serverSynced = true

    if op == OP_HELLO then
        return true
    end

    if op == OP_ENTITY_CLEAR or count == 0 then
        debuffHandler.enemies[entityServerId] = nil
        if op == OP_ENTITY_CLEAR then
            thTags[entityServerId] = nil
            debuffHandler.oxmob[entityServerId] = nil
            debuffHandler.fallback[entityServerId] = nil
        end
        return true
    end

    if op ~= OP_ENTITY_SNAPSHOT then
        return false
    end

    local expectedLen = 16 + count * 8
    if #data < expectedLen then
        return false
    end

    local now = os.clock()
    local entries = {}
    for i = 0, count - 1 do
        local offset = 17 + (i * 8)
        local iconId = readU16(data, offset)
        local effectId = readU16(data, offset + 2)
        local remainingMs = readU32(data, offset + 4)

        if iconId > 0 then
            local noTimer = (remainingMs == NO_TIMER_MARKER)
            entries[#entries + 1] = {
                iconId = iconId,
                effectId = effectId,
                noTimer = noTimer,
                expiryClock = noTimer and 0 or (now + (remainingMs / 1000.0)),
            }
        end
    end

    if #entries > 0 then
        debuffHandler.enemies[entityServerId] = entries
    else
        debuffHandler.enemies[entityServerId] = nil
    end

    return true
end

-- ---------------------------------------------------------------------------
-- [OXMOB]|<mobId>|<part>/<parts>|<effectId>:<iconId>:<power>:<sub>:<isDebuff>:<remSec>,...
-- ---------------------------------------------------------------------------
local function extractOxPayload(msg)
    if type(msg) ~= 'string' or msg == '' then return nil end
    local idx = string.find(msg, PROTO_TAG, 1, true)
    if not idx then return nil end
    return (string.sub(msg, idx + #PROTO_TAG):gsub('[%z\r\n]+$', ''))
end

local function applyOxEntries(mobId, parsed)
    local now = os.clock()
    local entries = {}
    for _, p in ipairs(parsed) do
        local cat = catalog.byEffectId[p.effectId]
        entries[#entries + 1] = {
            iconId = (cat and cat.iconId) or p.iconId,
            effectId = p.effectId,
            power = p.power,
            sub = p.sub,
            isDebuff = p.isDebuff,
            custom = cat ~= nil,
            noTimer = (p.rem <= 0),
            expiryClock = (p.rem > 0) and (now + p.rem) or 0,
        }
    end
    debuffHandler.oxmob[mobId] = { at = now, entries = entries }
    -- Authoritative data supersedes any 0x028 guesses for this mob.
    debuffHandler.fallback[mobId] = nil
end

local function handleOxPayload(payload)
    local parts = splitChar(payload, '|')
    if #parts < 3 then return end
    local mobId = tonumber(parts[1]) or 0
    if mobId == 0 then return end

    local idx, total = parts[2]:match('^(%d+)/(%d+)$')
    idx, total = tonumber(idx), tonumber(total)
    if idx == nil or total == nil then return end

    local buf = partial[mobId]
    if idx == 1 or buf == nil then
        buf = { chunks = {}, expect = total }
        partial[mobId] = buf
    end
    buf.chunks[idx] = parts[3] or ''
    if idx < total then return end

    local parsed = {}
    for i = 1, total do
        local chunk = buf.chunks[i] or ''
        if chunk ~= '' then
            for _, item in ipairs(splitChar(chunk, ',')) do
                local f = splitChar(item, ':')
                local effectId = tonumber(f[1])
                if effectId ~= nil then
                    parsed[#parsed + 1] = {
                        effectId = effectId,
                        iconId = tonumber(f[2]) or effectId,
                        power = tonumber(f[3]) or 0,
                        sub = tonumber(f[4]) or 0,
                        isDebuff = (tonumber(f[5]) or 0) == 1,
                        rem = tonumber(f[6]) or 0,
                    }
                end
            end
        end
    end
    partial[mobId] = nil
    applyOxEntries(mobId, parsed)
end

-- Call FIRST in packet_in. Returns true when the packet was an [OXMOB] frame (and blocks it).
debuffHandler.HandleOxMobPacket = function(e)
    if e == nil or e.id ~= 0x017 then return false end
    for _, raw in ipairs({ e.data, e.data_modified }) do
        if type(raw) == 'string' and #raw >= 25 then
            local msg = string.sub(raw, 24):match('^([^%z]*)')
            local payload = extractOxPayload(msg)
            if payload then
                e.blocked = true
                pcall(handleOxPayload, payload)
                return true
            end
        end
    end
    return false
end

-- text_in safety net so [OXMOB] never reaches the chat log.
debuffHandler.HandleOxMobText = function(e)
    if e == nil then return false end
    local payload = extractOxPayload(e.message_modified) or extractOxPayload(e.message)
    if payload then
        e.blocked = true
        pcall(handleOxPayload, payload)
        return true
    end
    return false
end

debuffHandler.HandleActionPacket = function(actionPacket)
    if actionPacket == nil or actionPacket.Targets == nil then
        return
    end

    local showTh = config and config.createTargetHudOnMobs and config.createTargetHudOnMobs.add_effect_of_th_tag
    local now = os.clock()

    for _, target in pairs(actionPacket.Targets) do
        if target ~= nil and target.Actions ~= nil and target.Id ~= nil then
            for _, action in pairs(target.Actions) do
                local addEffect = action.AdditionalEffect
                if showTh and addEffect ~= nil and (addEffect.Message == 603 or addEffect.Message == 608) then
                    thTags[target.Id] = true
                end

                -- Instant fallback: a status landed before (or without) an [OXMOB] frame.
                local msg, eff = action.Message, action.Param
                if target.Id >= MOB_ID_MIN and msg ~= nil and (debuffLandMes[msg] or buffLandMes[msg])
                    and eff ~= nil and eff > 0 and eff < 1024 then
                    local ox = debuffHandler.oxmob[target.Id]
                    if ox == nil or (now - ox.at) > OX_FRESH_SEC then
                        local fb = debuffHandler.fallback[target.Id]
                        if fb == nil then fb = {}; debuffHandler.fallback[target.Id] = fb end
                        local cat = catalog.byEffectId[eff]
                        local dur = defaultDuration[eff]
                        fb[eff] = {
                            iconId = (cat and cat.iconId) or eff,
                            effectId = eff,
                            power = 0,
                            sub = 0,
                            isDebuff = debuffLandMes[msg] == true,
                            custom = cat ~= nil,
                            noTimer = (dur == nil),
                            expiryClock = dur and (now + dur) or 0,
                        }
                    end
                end
            end
        end
    end
end

debuffHandler.HandleZonePacket = function(e)
    debuffHandler.enemies = {}
    debuffHandler.oxmob = {}
    debuffHandler.fallback = {}
    partial = {}
    thTags = {}
end

local function clearMob(id)
    debuffHandler.enemies[id] = nil
    debuffHandler.oxmob[id] = nil
    debuffHandler.fallback[id] = nil
    partial[id] = nil
    thTags[id] = nil
end

debuffHandler.HandleMessagePacket = function(basic)
    if basic == nil or basic.target == nil then
        return
    end

    if deathMes[basic.message] then
        clearMob(basic.target)
    elseif wearMes[basic.message] and basic.param ~= nil then
        local ox = debuffHandler.oxmob[basic.target]
        if ox ~= nil then
            for i = #ox.entries, 1, -1 do
                if ox.entries[i].effectId == basic.param then table.remove(ox.entries, i) end
            end
        end
        local fb = debuffHandler.fallback[basic.target]
        if fb ~= nil then fb[basic.param] = nil end
    end
end

debuffHandler.HandleUpdateEntity = function(entity, status)
    if entity == nil or status == nil then
        return
    end

    if status == 0 or status == 2 then
        thTags[entity.ServerId] = nil
    end
    if status == 2 then
        clearMob(entity.ServerId)
    end
end

local function liveRemaining(entry, now)
    if entry.noTimer then return -1, true end
    local remaining = entry.expiryClock - now
    if remaining >= -1.5 then
        return math.max(0, math.ceil(remaining)), true
    end
    return 0, false
end

local function badgeFor(entry)
    if not entry.custom then return nil end
    local p = entry.power or 0
    if p <= 0 then return nil end
    if entry.isDebuff then
        if p <= 100 then return string.format('-%d%%', p) end
        return nil
    end
    if p <= 5 then return string.format('x%d', p) end
    return string.format('+%d%%', math.min(p, 999))
end

-- Returns parallel arrays: iconIds, times (-1 = no timer), badges, effectIds, flags(1 debuff/0 buff/nil)
debuffHandler.GetActiveDebuffs = function(serverId)
    local serverEntries = debuffHandler.enemies[serverId]
    local ox = debuffHandler.oxmob[serverId]
    local fb = debuffHandler.fallback[serverId]
    local showTh = (thTags[serverId] == true) and config and config.createTargetHudOnMobs and config.createTargetHudOnMobs.add_effect_of_th_tag

    if serverEntries == nil and ox == nil and fb == nil and not showTh then
        return nil
    end

    for i = 1, #reusableDebuffIds do
        reusableDebuffIds[i] = nil
        reusableDebuffTimes[i] = nil
        reusableDebuffBadges[i] = nil
        reusableDebuffEffects[i] = nil
        reusableDebuffFlags[i] = nil
    end
    for k in pairs(reusableMerged) do reusableMerged[k] = nil end

    local count = 0
    local now = os.clock()

    local function push(entry)
        local remaining, alive = liveRemaining(entry, now)
        if not alive then return end
        count = count + 1
        reusableDebuffIds[count] = entry.iconId
        reusableDebuffTimes[count] = remaining
        reusableDebuffBadges[count] = badgeFor(entry) or false
        reusableDebuffEffects[count] = entry.effectId or 0
        if entry.isDebuff == nil then
            reusableDebuffFlags[count] = false
        else
            reusableDebuffFlags[count] = entry.isDebuff and 1 or 0
        end
    end

    -- Authoritative [OXMOB] entries win over native OXKE entries with the same effect id.
    local oxIds = {}
    if ox ~= nil then
        for i = 1, #ox.entries do
            local e = ox.entries[i]
            oxIds[e.effectId] = true
            push(e)
        end
    end

    if serverEntries ~= nil then
        for i = 1, #serverEntries do
            local entry = serverEntries[i]
            if not (entry.effectId and entry.effectId > 0 and oxIds[entry.effectId]) then
                push(entry)
            end
        end
    end

    -- 0x028 fallback only while no authoritative source has anything for this mob.
    if fb ~= nil and ox == nil and serverEntries == nil then
        for _, entry in pairs(fb) do
            push(entry)
        end
    end

    if showTh then
        count = count + 1
        reusableDebuffIds[count] = 1001
        reusableDebuffTimes[count] = -1
        reusableDebuffBadges[count] = false
        reusableDebuffEffects[count] = 0
        reusableDebuffFlags[count] = false
    end

    if count == 0 then
        return nil
    end

    return reusableDebuffIds, reusableDebuffTimes, reusableDebuffBadges, reusableDebuffEffects, reusableDebuffFlags
end

debuffHandler.HasActiveDebuffs = function(serverId)
    local ids = debuffHandler.GetActiveDebuffs(serverId)
    return ids ~= nil and #ids > 0
end

debuffHandler.IsServerSynced = function()
    return debuffHandler.serverSynced
end

return debuffHandler
