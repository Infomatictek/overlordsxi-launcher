local debuffHandler = {}

debuffHandler.enemies = {}
debuffHandler.serverSynced = false

local thTags = {}

local NO_TIMER_MARKER = 4294967295 -- 0xFFFFFFFF
local OP_HELLO = 0
local OP_ENTITY_SNAPSHOT = 1
local OP_ENTITY_CLEAR = 2

local deathMes = T{
    [6] = true,   -- defeated
    [20] = true,  -- falls to the ground
    [97] = true,  -- was defeated by
    [113] = true, -- falls to the ground (variation)
    [406] = true, -- falls to the ground (alt)
    [605] = true, -- falls to the ground (alt)
    [646] = true, -- falls to the ground (alt)
}

local reusableDebuffIds = {}
local reusableDebuffTimes = {}

local function readU16(data, offset)
    local b1, b2 = data:byte(offset, offset + 1)
    return b1 + b2 * 256
end

local function readU32(data, offset)
    local b1, b2, b3, b4 = data:byte(offset, offset + 3)
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
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

debuffHandler.HandleActionPacket = function(actionPacket)
    -- All debuffs and durations come exclusively from authoritative server packets (0x1FE).
    -- Only optional visual Treasure Hunter tagging (no timer) is tracked from action messages.
    if not (config and config.createTargetHudOnMobs and config.createTargetHudOnMobs.add_effect_of_th_tag) then
        return
    end

    if actionPacket == nil or actionPacket.Targets == nil then
        return
    end

    for _, target in pairs(actionPacket.Targets) do
        if target ~= nil and target.Actions ~= nil and target.Id ~= nil then
            for _, action in pairs(target.Actions) do
                local addEffect = action.AdditionalEffect
                if addEffect ~= nil and (addEffect.Message == 603 or addEffect.Message == 608) then
                    thTags[target.Id] = true
                end
            end
        end
    end
end

debuffHandler.HandleZonePacket = function(e)
    debuffHandler.enemies = {}
    thTags = {}
end

debuffHandler.HandleMessagePacket = function(basic)
    if basic == nil or basic.target == nil then
        return
    end

    if deathMes[basic.message] then
        debuffHandler.enemies[basic.target] = nil
        thTags[basic.target] = nil
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
        debuffHandler.enemies[entity.ServerId] = nil
    end
end

debuffHandler.GetActiveDebuffs = function(serverId)
    local serverEntries = debuffHandler.enemies[serverId]
    local showTh = (thTags[serverId] == true) and config and config.createTargetHudOnMobs and config.createTargetHudOnMobs.add_effect_of_th_tag

    if serverEntries == nil and not showTh then
        return nil
    end

    for i = 1, #reusableDebuffIds do
        reusableDebuffIds[i] = nil
        reusableDebuffTimes[i] = nil
    end

    local count = 0
    local now = os.clock()

    if serverEntries ~= nil then
        for i = 1, #serverEntries do
            local entry = serverEntries[i]
            if entry.noTimer then
                count = count + 1
                reusableDebuffIds[count] = entry.iconId
                reusableDebuffTimes[count] = -1
            else
                local remaining = entry.expiryClock - now
                if remaining >= -1.5 then
                    count = count + 1
                    reusableDebuffIds[count] = entry.iconId
                    reusableDebuffTimes[count] = math.max(0, math.ceil(remaining))
                end
            end
        end
    end

    if showTh then
        count = count + 1
        reusableDebuffIds[count] = 1001
        reusableDebuffTimes[count] = -1
    end

    if count == 0 then
        return nil
    end

    return reusableDebuffIds, reusableDebuffTimes
end

debuffHandler.HasActiveDebuffs = function(serverId)
    local ids = debuffHandler.GetActiveDebuffs(serverId)
    return ids ~= nil and #ids > 0
end

debuffHandler.IsServerSynced = function()
    return debuffHandler.serverSynced
end

return debuffHandler
