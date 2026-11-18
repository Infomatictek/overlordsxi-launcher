--[[
* OverlordsXI Soul HUD - custom buff strip + chat name substitution.
*
*   - Parses `ox_buffs=<iconId>:<power>:<remSec>,...` from the server HUD key/value stream.
*   - Renders a strip of cached assets/status_icons/*.png for active custom player buffs plus virtual
*     Soul resources (hud_*.png) with stack badges, timers and ImGui hover tooltips.
*   - Substitutes the custom status name into 0x029 wear-off / gain chat lines for 789 and 815+.
--]]

local okIcons, icons = pcall(require, 'ox_icons')
if not okIcons then icons = nil end
local okCat, catalog = pcall(require, 'status_catalog')
if not okCat then catalog = { byEffectId = {}, byIconId = {}, list = {} } end
local okBit, bit = pcall(require, 'bit')

local M = {}

M.buffs = {}   -- list of { iconId, power, rem, expiresAt, entry }

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

function M.parse(raw, now)
    local list = {}
    if type(raw) == 'string' and raw ~= '' then
        for _, item in ipairs(splitChar(raw, ',')) do
            local f = splitChar(item, ':')
            local iconId = tonumber(f[1])
            if iconId ~= nil then
                local rem = tonumber(f[3]) or 0
                list[#list + 1] =
                {
                    iconId    = iconId,
                    power     = tonumber(f[2]) or 0,
                    rem       = rem,
                    expiresAt = rem > 0 and (now + rem) or nil,
                    entry     = catalog.byIconId[iconId],
                }
            end
        end
    end
    M.buffs = list
end

function M.applyKv(kvMap, now)
    M.parse(kvMap and kvMap.ox_buffs or '', now)
end

local function badge(power)
    if power <= 0 then return '' end
    if power <= 5 then return ('x%d'):format(power) end
    return ('+%d%%'):format(math.min(power, 999))
end

local function drawSlot(imgui, tex, size, text, tip)
    if tex ~= nil then
        imgui.Image(tex, { size, size })
    else
        imgui.Dummy({ size, size })
    end
    if imgui.IsItemHovered() and tip and tip ~= '' then
        imgui.SetTooltip(tip)
    end
    -- Stack badge / timer text under the icon.
    if text ~= '' then
        imgui.Text(text)
    else
        imgui.Text(' ')
    end
end

-- Resource types that make sense as a virtual icon when active.
local VIRTUAL_TYPES = { stack = true, gauge = true, timer = true, counter = true, charges = true }

function M.render(imgui, soulDef, runtime, cfg, now)
    -- Drop buffs whose server-reported timer has run out (server re-syncs on gain/lose).
    for i = #M.buffs, 1, -1 do
        local b = M.buffs[i]
        if b.expiresAt and now > b.expiresAt + 0.5 then table.remove(M.buffs, i) end
    end

    local virtual = {}
    if soulDef and runtime and runtime.values then
        for _, res in ipairs(soulDef.resources or {}) do
            local st = runtime.values[res.id]
            if st and VIRTUAL_TYPES[res.type] then
                local cur = tonumber(st.current) or 0
                if st.active or cur > 0 then
                    virtual[#virtual + 1] = { res = res, st = st, cur = cur }
                end
            end
        end
    end

    if #M.buffs == 0 and #virtual == 0 then return end

    local size = math.floor(28 * (cfg and cfg.scale or 1.0))
    local flags = 0
    if okBit then
        flags = bit.bor(ImGuiWindowFlags_AlwaysAutoResize or 64, ImGuiWindowFlags_NoTitleBar or 1,
                        ImGuiWindowFlags_NoSavedSettings or 256, ImGuiWindowFlags_NoFocusOnAppearing or 4096)
    end
    imgui.SetNextWindowBgAlpha(0.55 * (cfg and cfg.opacity or 1.0))
    imgui.SetNextWindowPos({ 520, 640 }, ImGuiCond_FirstUseEver or 4)
    if imgui.Begin('ox_buffstrip##ox', true, flags) then
        local first = true
        for _, b in ipairs(M.buffs) do
            local tex = icons and icons.custom(b.iconId) or nil
            local rem = b.expiresAt and math.max(0, b.expiresAt - now) or nil
            local txt = badge(b.power)
            if rem then txt = (txt ~= '' and (txt .. ' ') or '') .. ('%ds'):format(math.ceil(rem)) end
            local tip = nil
            if b.entry then
                tip = b.entry.name .. '\n' .. b.entry.tooltip
                if rem then tip = tip .. ('\nRemaining: %ds'):format(math.ceil(rem)) end
            end
            if not first then imgui.SameLine() end
            first = false
            imgui.BeginGroup()
            drawSlot(imgui, tex, size, txt, tip)
            imgui.EndGroup()
        end

        for _, v in ipairs(virtual) do
            local res, st = v.res, v.st
            local tex = icons and (icons.hud(soulDef.key) or icons.hud(res.type)) or nil
            local txt = ''
            if res.type == 'stack' or res.type == 'counter' or res.type == 'charges' then
                txt = ('x%d'):format(math.floor(v.cur))
            elseif res.type == 'gauge' then
                txt = tostring(math.floor(v.cur))
            end
            if (st.remaining or 0) > 0 then
                txt = (txt ~= '' and (txt .. ' ') or '') .. ('%ds'):format(math.ceil(st.remaining))
            end
            if not first then imgui.SameLine() end
            first = false
            imgui.BeginGroup()
            drawSlot(imgui, tex, size, txt, res.label or res.id)
            imgui.EndGroup()
        end
    end
    imgui.End()
end

-- ---------------------------------------------------------------------------
-- 0x029 chat-log substitution for custom status names (789, 815+)
-- ---------------------------------------------------------------------------
local WEAR = { [64] = true, [204] = true, [206] = true }
local GAIN = { [75] = false, [230] = true, [237] = true, [266] = true }

local pending = nil  -- { name=, kind=, at= }

local function u32(d, off)
    local a, b, c, e = string.byte(d, off + 1, off + 4)
    return (a or 0) + (b or 0) * 256 + (c or 0) * 65536 + (e or 0) * 16777216
end

function M.notePacket029(data)
    if type(data) ~= 'string' or #data < 0x1A then return end
    local param = u32(data, 0x0C)
    local message = ((string.byte(data, 0x19) or 0) + (string.byte(data, 0x1A) or 0) * 256) % 32768
    local entry = catalog.byEffectId[param]
    if entry == nil then return end
    if WEAR[message] then
        pending = { name = entry.name, kind = 'wear', at = os.clock() }
    elseif GAIN[message] then
        pending = { name = entry.name, kind = 'gain', at = os.clock() }
    end
end

-- Returns the substituted message, or nil when no change applies.
function M.fixChatLine(msg)
    if pending == nil or type(msg) ~= 'string' then return nil end
    if (os.clock() - pending.at) > 1.5 then pending = nil; return nil end

    local name = pending.name
    local out, n
    if pending.kind == 'wear' then
        out, n = msg:gsub("'s%s+effect wears off", function() return "'s " .. name .. ' effect wears off' end, 1)
    else
        out, n = msg:gsub('effect of%s*%.', function() return 'effect of ' .. name .. '.' end, 1)
    end
    if n > 0 then
        pending = nil
        return out
    end
    return nil
end

return M
