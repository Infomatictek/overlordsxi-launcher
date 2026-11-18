--[[
* OverlordsXI - debuffed (Ashita v4)
*
* Enemy-bar style panel that shows the buffs and debuffs on your current target.
*
* Data sources (in priority order):
*   1. [OXMOB]|<mobServerId>|<part>/<parts>|<effectId>:<iconId>:<power>:<sub>:<isDebuff>:<remSec>,...
*      Authoritative live stream from the OverlordsXI server (silent 0x017, blocked from the chat log).
*   2. 0x028 (action) / 0x029 (message) parsing as an instant fallback for the first ~3 seconds
*      and for servers/mobs that never send [OXMOB] data.
*
* Commands:
*   /debuffed [toggle|show|hide|lock|unlock|size <12-48>|buffs|reset]
--]]

addon.name    = 'debuffed'
addon.author  = 'OverlordsXI'
addon.version = '1.0.0'
addon.desc    = 'Target buff/debuff panel with native custom status icons for OverlordsXI.'
addon.link    = 'https://github.com/Infomatictek/overlordsxi-launcher'

pcall(require, 'common')
local okImgui, imgui = pcall(require, 'imgui')
local okSettings, settings = pcall(require, 'settings')
local okBit, bit = pcall(require, 'bit')

local okCat, catalog = pcall(require, 'status_catalog')
if not okCat then catalog = { byEffectId = {}, byIconId = {}, list = {} } end
local okIcons, icons = pcall(require, 'ox_icons')
if not okIcons then icons = nil end

local PROTO_TAG = '[OXMOB]|'
local MOB_ID_MIN = 0x01000000
local OX_FRESH_SEC = 10.0       -- [OXMOB] data younger than this is authoritative over 0x028 guesses

local defaults = {
    iconSize  = 18,
    locked    = false,
    visible   = true,
    showBuffs = true,
    x         = 520,
    y         = 260,
}
local cfg = {}
for k, v in pairs(defaults) do cfg[k] = v end
local cfgHandle = nil

if okSettings and settings then
    pcall(function()
        cfgHandle = settings.load(T and T(defaults) or defaults)
        cfg = cfgHandle
        settings.register('settings', 'debuffed_settings_update', function(s)
            if s ~= nil then cfg = s end
        end)
    end)
end

local function saveCfg()
    if okSettings and settings then pcall(settings.save) end
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local pendingReset = false
local mobs      = {}   -- [serverId] = { name=, effects = { [effectId] = eff }, oxAt = 0 }
local partial   = {}   -- [serverId] = { parts = {}, expect = n }
local wearPending = nil

local function now() return os.clock() end

local function getMob(id)
    local m = mobs[id]
    if m == nil then
        m = { name = '', effects = {}, oxAt = 0 }
        mobs[id] = m
    end
    return m
end

local function clearMob(id)
    mobs[id] = nil
    partial[id] = nil
end

local DEFAULT_DURATION = {
    [2] = 60, [3] = 90, [4] = 120, [5] = 180, [6] = 120, [7] = 30, [10] = 5, [11] = 60,
    [12] = 60, [13] = 120, [19] = 90, [21] = 60,
}

local function statusName(effectId)
    local c = catalog.byEffectId[effectId]
    if c ~= nil then return c.name, c.tooltip end
    local name = nil
    pcall(function()
        name = AshitaCore:GetResourceManager():GetString('buffs.names', effectId)
    end)
    if name == nil or name == '' then name = ('Status %d'):format(effectId) end
    return name, nil
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
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

local function extractPayload(msg)
    if type(msg) ~= 'string' or msg == '' then return nil end
    local idx = string.find(msg, PROTO_TAG, 1, true)
    if not idx then return nil end
    local payload = string.sub(msg, idx + #PROTO_TAG):gsub('[%z\r\n]+$', '')
    return payload
end

-- ---------------------------------------------------------------------------
-- [OXMOB] authoritative stream
-- ---------------------------------------------------------------------------
local function applyOxEntries(mobId, entries)
    local m = getMob(mobId)
    local t = now()
    local fresh = {}
    for _, e in ipairs(entries) do
        local old = m.effects[e.effectId]
        e.since = old and old.since or t
        e.expiresAt = (e.rem > 0) and (t + e.rem) or nil
        e.estimated = false
        fresh[e.effectId] = e
    end
    m.effects = fresh
    m.oxAt = t
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

    local entries = {}
    for i = 1, total do
        local chunk = buf.chunks[i] or ''
        if chunk ~= '' then
            for _, item in ipairs(splitChar(chunk, ',')) do
                local f = splitChar(item, ':')
                local effectId = tonumber(f[1])
                if effectId ~= nil then
                    entries[#entries + 1] =
                    {
                        effectId = effectId,
                        iconId   = tonumber(f[2]) or effectId,
                        power    = tonumber(f[3]) or 0,
                        sub      = tonumber(f[4]) or 0,
                        isDebuff = (tonumber(f[5]) or 0) == 1,
                        rem      = tonumber(f[6]) or 0,
                    }
                end
            end
        end
    end
    partial[mobId] = nil
    applyOxEntries(mobId, entries)
end

-- ---------------------------------------------------------------------------
-- 0x028 / 0x029 fallback parsing
-- ---------------------------------------------------------------------------
local Reader = {}
Reader.__index = Reader

local function newReader(data, bytePos)
    return setmetatable({ d = data, pos = bytePos, bit = 0 }, Reader)
end

function Reader:read(nbits)
    local ret = 0
    local mul = 1
    for _ = 1, nbits do
        local byte = string.byte(self.d, self.pos + 1) or 0
        local v = math.floor(byte / (2 ^ self.bit)) % 2
        ret = ret + v * mul
        mul = mul * 2
        self.bit = self.bit + 1
        if self.bit == 8 then self.bit = 0; self.pos = self.pos + 1 end
    end
    return ret
end

-- Messages where `param` of the action result is the status effect id that landed on the target.
local DEBUFF_LAND = {
    [82] = true, [127] = true, [141] = true, [236] = true, [237] = true, [242] = true, [267] = true,
    [268] = true, [270] = true, [271] = true, [277] = true, [278] = true, [279] = true, [280] = true,
    [282] = true, [283] = true,
}
local BUFF_LAND = { [186] = true, [194] = true, [230] = true, [266] = true }

local function parseAction(data)
    if type(data) ~= 'string' or #data < 28 then return end
    local r = newReader(data, 4)
    local _actor   = r:read(32)
    local trgSum   = r:read(6)
    local _resSum  = r:read(4)
    local cmdNo    = r:read(4)
    local _cmdArg  = r:read(32)
    local _info    = r:read(32)
    if trgSum > 16 then return end
    if cmdNo ~= 4 and cmdNo ~= 6 and cmdNo ~= 3 and cmdNo ~= 11 and cmdNo ~= 14 then return end

    local t = now()
    for _ = 1, trgSum do
        local targetId  = r:read(32)
        local resultSum = r:read(4)
        for _ = 1, resultSum do
            r:read(3); r:read(2); r:read(12); r:read(5); r:read(5)
            local value   = r:read(17)
            local message = r:read(10)
            r:read(31)
            if r:read(1) > 0 then r:read(6); r:read(4); r:read(17); r:read(10) end
            if r:read(1) > 0 then r:read(6); r:read(4); r:read(14); r:read(10) end

            if targetId >= MOB_ID_MIN and (DEBUFF_LAND[message] or BUFF_LAND[message]) and value > 0 and value < 1024 then
                local m = getMob(targetId)
                -- Authoritative data wins while it is fresh.
                if (t - (m.oxAt or 0)) > OX_FRESH_SEC then
                    local dur = DEFAULT_DURATION[value]
                    local c = catalog.byEffectId[value]
                    m.effects[value] =
                    {
                        effectId  = value,
                        iconId    = c and c.iconId or value,
                        power     = 0,
                        sub       = 0,
                        isDebuff  = DEBUFF_LAND[message] == true,
                        rem       = dur or 0,
                        since     = t,
                        expiresAt = dur and (t + dur) or nil,
                        estimated = true,
                    }
                end
            end
        end
    end
end

local WEAR_MESSAGES  = { [64] = true, [204] = true, [206] = true }
local DEATH_MESSAGES = { [6] = true, [20] = true, [113] = true, [406] = true, [605] = true, [646] = true }

local function u32(d, off)
    local a, b, c, e = string.byte(d, off + 1, off + 4)
    return (a or 0) + (b or 0) * 256 + (c or 0) * 65536 + (e or 0) * 16777216
end

local function parseMessage(data)
    if type(data) ~= 'string' or #data < 0x1A then return end
    local target  = u32(data, 0x08)
    local param   = u32(data, 0x0C)
    local message = (string.byte(data, 0x19) or 0) + (string.byte(data, 0x1A) or 0) * 256
    message = message % 32768

    if WEAR_MESSAGES[message] then
        local m = mobs[target]
        if m ~= nil then m.effects[param] = nil end
    elseif DEATH_MESSAGES[message] then
        clearMob(target)
    end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
ashita.events.register('packet_in', 'debuffed_packet_in', function(e)
    if e == nil then return end

    if e.id == 0x00B then
        mobs, partial = {}, {}
        return
    end

    if e.id == 0x017 then
        for _, raw in ipairs({ e.data, e.data_modified }) do
            if type(raw) == 'string' and #raw >= 25 then
                local msg = string.sub(raw, 24):match('^([^%z]*)')
                local payload = extractPayload(msg)
                if payload then
                    e.blocked = true
                    pcall(handleOxPayload, payload)
                    return
                end
            end
        end
    elseif e.id == 0x028 then
        pcall(parseAction, e.data)
    elseif e.id == 0x029 then
        pcall(parseMessage, e.data)
    end
end)

ashita.events.register('text_in', 'debuffed_text_in', function(e)
    if e == nil then return end
    local payload = extractPayload(e.message_modified) or extractPayload(e.message)
    if payload then
        e.blocked = true
        pcall(handleOxPayload, payload)
    end
end)

ashita.events.register('command', 'debuffed_command', function(e)
    if e == nil or type(e.command) ~= 'string' then return end
    local args = {}
    for token in string.gmatch(e.command, '%S+') do args[#args + 1] = token end
    if #args == 0 or string.lower(args[1]) ~= '/debuffed' then return end
    e.blocked = true

    local sub = string.lower(args[2] or 'toggle')
    if sub == 'toggle' then cfg.visible = not cfg.visible
    elseif sub == 'show' then cfg.visible = true
    elseif sub == 'hide' then cfg.visible = false
    elseif sub == 'lock' then cfg.locked = true
    elseif sub == 'unlock' then cfg.locked = false
    elseif sub == 'buffs' then cfg.showBuffs = not cfg.showBuffs
    elseif sub == 'size' then
        local n = tonumber(args[3])
        if n then cfg.iconSize = math.max(12, math.min(48, math.floor(n))) end
    elseif sub == 'reset' then
        for k, v in pairs(defaults) do cfg[k] = v end
        pendingReset = true
    end
    saveCfg()
    print(('[debuffed] visible=%s locked=%s size=%d buffs=%s'):format(
        tostring(cfg.visible), tostring(cfg.locked), cfg.iconSize, tostring(cfg.showBuffs)))
end)

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------
local function targetInfo()
    local ok, id, name = pcall(function()
        local mem = AshitaCore:GetMemoryManager()
        local tgt = mem:GetTarget()
        if tgt == nil then return 0, '' end
        local sub = tgt:GetIsSubTargetActive() ~= 0
        local idx = tgt:GetTargetIndex(sub and 1 or 0)
        if idx == nil or idx == 0 then return 0, '' end
        local ent = mem:GetEntity()
        return ent:GetServerId(idx) or 0, ent:GetName(idx) or ''
    end)
    if ok then return id or 0, name or '' end
    return 0, ''
end

local function badgeFor(eff, entry)
    local p = eff.power or 0
    if entry == nil or p <= 0 then return '' end
    if eff.isDebuff then
        return p <= 100 and ('-%d%%'):format(p) or ''
    end
    if p <= 5 then return ('x%d'):format(p) end
    return ('+%d%%'):format(math.min(p, 999))
end

local function timerFor(eff, t)
    if eff.expiresAt ~= nil then
        local rem = math.max(0, eff.expiresAt - t)
        local s = ('%ds'):format(math.ceil(rem))
        return eff.estimated and ('~' .. s) or s
    end
    if eff.estimated and eff.since then
        return ('+%ds'):format(math.floor(t - eff.since))
    end
    return '--'
end

local function drawEffect(eff, size, t)
    local tex, entry = nil, nil
    if icons then tex, entry = icons.forEffect(catalog, eff.effectId, eff.iconId) end
    local name, tip = statusName(eff.effectId)
    local badge = badgeFor(eff, entry)
    local timer = timerFor(eff, t)

    local color = eff.isDebuff and { 1.0, 0.55, 0.55, 1.0 } or { 0.60, 1.0, 0.70, 1.0 }

    if tex ~= nil then
        imgui.Image(tex, { size, size })
        imgui.SameLine()
    end
    local label = name
    if badge ~= '' then label = label .. ' ' .. badge end
    imgui.TextColored(color, label)
    imgui.SameLine()
    imgui.Text(timer)

    return name, tip, eff
end

local expired = {}

ashita.events.register('d3d_present', 'debuffed_present', function()
    if not (okImgui and imgui) or not cfg.visible then return end

    local id, name = targetInfo()
    if id == 0 or id < MOB_ID_MIN then return end
    local m = mobs[id]
    if m == nil then return end
    m.name = name

    local t = now()
    local debuffs, buffs = {}, {}
    for eid, eff in pairs(m.effects) do
        if eff.expiresAt ~= nil and t > eff.expiresAt + 1.0 then
            expired[#expired + 1] = eid
        elseif eff.isDebuff then
            debuffs[#debuffs + 1] = eff
        else
            buffs[#buffs + 1] = eff
        end
    end
    for i = #expired, 1, -1 do m.effects[expired[i]] = nil; expired[i] = nil end

    if #debuffs == 0 and (#buffs == 0 or not cfg.showBuffs) then return end
    table.sort(debuffs, function(a, b) return a.effectId < b.effectId end)
    table.sort(buffs, function(a, b) return a.effectId < b.effectId end)

    local flags = 0
    if okBit then
        flags = bit.bor(ImGuiWindowFlags_AlwaysAutoResize or 64, ImGuiWindowFlags_NoTitleBar or 1,
                        ImGuiWindowFlags_NoSavedSettings or 256)
        if cfg.locked then flags = bit.bor(flags, ImGuiWindowFlags_NoMove or 4) end
    end

    imgui.SetNextWindowBgAlpha(0.75)
    if pendingReset or not cfg.locked then
        imgui.SetNextWindowPos({ cfg.x, cfg.y }, pendingReset and (ImGuiCond_Always or 1) or (ImGuiCond_FirstUseEver or 4))
        pendingReset = false
    end

    if imgui.Begin('debuffed##ox', true, flags) then
        local size = math.max(12, math.min(48, cfg.iconSize or 18))
        imgui.TextColored({ 0.85, 0.80, 0.55, 1.0 }, name ~= '' and name or ('Mob %X'):format(id))
        if m.oxAt > 0 and (t - m.oxAt) <= OX_FRESH_SEC then
            imgui.SameLine(); imgui.TextColored({ 0.5, 0.8, 1.0, 1.0 }, '[live]')
        end

        if #debuffs > 0 then
            imgui.Separator()
            for _, eff in ipairs(debuffs) do
                local nm, tip = drawEffect(eff, size, t)
                if imgui.IsItemHovered() then
                    imgui.SetTooltip((tip and (nm .. '\n' .. tip)) or nm)
                end
            end
        end
        if cfg.showBuffs and #buffs > 0 then
            imgui.Separator()
            for _, eff in ipairs(buffs) do
                local nm, tip = drawEffect(eff, size, t)
                if imgui.IsItemHovered() then
                    imgui.SetTooltip((tip and (nm .. '\n' .. tip)) or nm)
                end
            end
        end

        if not cfg.locked then
            local px, py = imgui.GetWindowPos()
            if type(px) == 'table' then px, py = px[1], px[2] end
            if px and (math.abs(px - cfg.x) > 0.5 or math.abs(py - cfg.y) > 0.5) then
                cfg.x, cfg.y = px, py
            end
        end
    end
    imgui.End()
end)

ashita.events.register('unload', 'debuffed_unload', function()
    saveCfg()
end)
