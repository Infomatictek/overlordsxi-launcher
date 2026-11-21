-- Synthetic Draw-List Capture Harness for SoulspireXI WS Talent UI (Phase 9)
-- Executes the ACTUAL talent_tree_ui.render(st, actions) against a faithful
-- ImGui layout & draw-list recorder, outputting JSON draw lists for all 10
-- required visual verification states.
--
-- NOTE: Output images rendered from these draw lists are synthetic renderer
-- previews from the live Lua UI engine, NOT live FFXI gameplay captures.

local addonDir = arg and arg[1] or '.'
local outDir   = arg and arg[2] or '/tmp/previews'
package.path   = addonDir .. '/?.lua;' .. addonDir .. '/?/init.lua;' .. package.path

local bit = require('bit')

-- Minimal JSON encoder
local function jsonEscape(s)
    return (tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t'))
end

local function toJson(v)
    local tv = type(v)
    if tv == 'nil' then return 'null'
    elseif tv == 'boolean' then return v and 'true' or 'false'
    elseif tv == 'number' then
        if v ~= v or v == math.huge or v == -math.huge then return '0' end
        return string.format('%.2f', v):gsub('%.00$', '')
    elseif tv == 'string' then return '"' .. jsonEscape(v) .. '"'
    elseif tv == 'table' then
        local isArr = true
        local maxI = 0
        for k, _ in pairs(v) do
            if type(k) ~= 'number' or k < 1 or math.floor(k) ~= k then
                isArr = false
                break
            end
            if k > maxI then maxI = k end
        end
        local parts = {}
        if isArr and maxI > 0 then
            for i = 1, maxI do
                parts[#parts + 1] = toJson(v[i])
            end
            return '[' .. table.concat(parts, ',') .. ']'
        else
            for k, val in pairs(v) do
                parts[#parts + 1] = '"' .. jsonEscape(k) .. '":' .. toJson(val)
            end
            return '{' .. table.concat(parts, ',') .. '}'
        end
    end
    return 'null'
end

-- Recorder state (reset per scenario)
local cmds = {}
local overlayCmds = {}
local hitboxes = {}
local tooltipCmds = {}
local inTooltip = false
local tipX, tipY, tipW, tipCursorY = 0, 0, 332, 0
local itemWidthStack = {}
local hoverTargetId = nil
local hoveredAnchor = nil
local lastItemId = nil
local curX, curY = 12, 12
local lastItemX, lastItemY, lastItemW, lastItemH = 12, 12, 0, 0
local childStack = {}
local winW, winH = 1060, 680
local textColorStack = { { 0.95, 0.96, 0.98, 1.0 } }

local function abgrToHex(c)
    if type(c) == 'table' then
        local r = math.floor(math.max(0, math.min(1, c[1] or 1)) * 255 + 0.5)
        local g = math.floor(math.max(0, math.min(1, c[2] or 1)) * 255 + 0.5)
        local b = math.floor(math.max(0, math.min(1, c[3] or 1)) * 255 + 0.5)
        local a = math.floor(math.max(0, math.min(1, c[4] or 1)) * 255 + 0.5)
        return { r, g, b, a }
    end
    local n = tonumber(c) or 0xFFFFFFFF
    local r = bit.band(n, 0xFF)
    local g = bit.band(bit.rshift(n, 8), 0xFF)
    local b = bit.band(bit.rshift(n, 16), 0xFF)
    local a = bit.band(bit.rshift(n, 24), 0xFF)
    return { r, g, b, a }
end

local function pushCmd(cmd)
    if inTooltip then
        tooltipCmds[#tooltipCmds + 1] = cmd
    else
        cmds[#cmds + 1] = cmd
    end
end

local function recordItem(x, y, w, h, id)
    lastItemX, lastItemY, lastItemW, lastItemH = x, y, w, h
    lastItemId = id
    curY = y + h + 4
    curX = (#childStack > 0) and childStack[#childStack].x or 12
    if id then
        hitboxes[#hitboxes + 1] = { id = id, x = x, y = y, w = w, h = h }
        if hoverTargetId and id == hoverTargetId then
            hoveredAnchor = { x = x, y = y, w = w, h = h }
        end
    end
end

local mockDl = {
    AddRectFilled = function(_, p1, p2, col, r)
        pushCmd({ op = 'rect_fill', x1 = p1[1], y1 = p1[2], x2 = p2[1], y2 = p2[2], col = abgrToHex(col), r = r or 0 })
    end,
    AddRectFilledMultiColor = function(_, p1, p2, c1, c2, c3, c4)
        pushCmd({ op = 'rect_grad', x1 = p1[1], y1 = p1[2], x2 = p2[1], y2 = p2[2],
            c1 = abgrToHex(c1), c2 = abgrToHex(c2), c3 = abgrToHex(c3), c4 = abgrToHex(c4) })
    end,
    AddRect = function(_, p1, p2, col, r, _, thick)
        pushCmd({ op = 'rect', x1 = p1[1], y1 = p1[2], x2 = p2[1], y2 = p2[2], col = abgrToHex(col), r = r or 0, t = thick or 1 })
    end,
    AddLine = function(_, p1, p2, col, thick)
        pushCmd({ op = 'line', x1 = p1[1], y1 = p1[2], x2 = p2[1], y2 = p2[2], col = abgrToHex(col), t = thick or 1 })
    end,
    AddCircle = function(_, c, rad, col, _, thick)
        pushCmd({ op = 'circle', cx = c[1], cy = c[2], rad = rad, col = abgrToHex(col), t = thick or 1 })
    end,
    AddCircleFilled = function(_, c, rad, col)
        pushCmd({ op = 'circle_fill', cx = c[1], cy = c[2], rad = rad, col = abgrToHex(col) })
    end,
    AddQuad = function(_, p1, p2, p3, p4, col, thick)
        pushCmd({ op = 'poly', pts = { p1, p2, p3, p4 }, col = abgrToHex(col), t = thick or 1 })
    end,
    AddQuadFilled = function(_, p1, p2, p3, p4, col)
        pushCmd({ op = 'poly_fill', pts = { p1, p2, p3, p4 }, col = abgrToHex(col) })
    end,
    AddTriangle = function(_, p1, p2, p3, col, thick)
        pushCmd({ op = 'poly', pts = { p1, p2, p3 }, col = abgrToHex(col), t = thick or 1 })
    end,
    AddTriangleFilled = function(_, p1, p2, p3, col)
        pushCmd({ op = 'poly_fill', pts = { p1, p2, p3 }, col = abgrToHex(col) })
    end,
    AddText = function(_, p, col, text)
        pushCmd({ op = 'text', x = p[1], y = p[2], col = abgrToHex(col), text = tostring(text or '') })
    end,
    AddImage = function(_, id, p1, p2)
        pushCmd({ op = 'image', name = tostring(id), x1 = p1[1], y1 = p1[2], x2 = p2[1], y2 = p2[2] })
    end,
}

-- Provide mock art so emblem & node PNG names are captured cleanly
package.loaded['art'] = {
    draw = function(_, name, x, y, w, h)
        local path = addonDir .. '/assets/' .. tostring(name) .. '.png'
        local f = io.open(path, 'rb')
        if f then
            f:close()
            pushCmd({ op = 'image', name = tostring(name), x1 = x, y1 = y, x2 = x + w, y2 = y + h })
            return true
        end
        return false
    end,
    clear = function() end,
}

local function currentBounds()
    if #childStack > 0 then
        local c = childStack[#childStack]
        return c.x, c.y, c.w, c.h
    end
    return 12, 12, winW - 24, winH - 24
end

package.loaded['imgui'] = {
    SetNextWindowSizeConstraints = function() end,
    SetNextWindowSize = function() end,
    PushStyleVar = function() end,
    PopStyleVar = function() end,
    PushStyleColor = function(idx, col)
        if idx == 0 then textColorStack[#textColorStack + 1] = col end
    end,
    PopStyleColor = function(n)
        for _ = 1, (n or 1) do
            if #textColorStack > 1 then table.remove(textColorStack) end
        end
    end,
    Begin = function()
        pushCmd({ op = 'rect_fill', x1 = 0, y1 = 0, x2 = winW, y2 = winH, col = { 7, 11, 20, 255 }, r = 6 })
        pushCmd({ op = 'rect', x1 = 1, y1 = 1, x2 = winW - 1, y2 = winH - 1, col = { 59, 70, 100, 230 }, r = 6, t = 1 })
        curX, curY = 12, 12
        return true
    end,
    End = function() end,
    BeginChild = function(_, size)
        local bx, by, bw, bh = currentBounds()
        local w = (size and size[1] and size[1] > 0) and size[1] or math.max(10, (bx + bw) - curX)
        local h = (size and size[2] and size[2] > 0) and size[2] or math.max(10, (by + bh) - curY)
        local x, y = curX, curY
        childStack[#childStack + 1] = {
            x = x + 4, y = y + 4, w = w - 8, h = h - 8,
            ox = x, oy = y, ow = w, oh = h,
        }
        curX, curY = x + 4, y + 4
        return true
    end,
    EndChild = function()
        local c = table.remove(childStack)
        if c then
            recordItem(c.ox, c.oy, c.ow, c.oh, nil)
        end
    end,
    GetWindowDrawList = function() return mockDl end,
    GetCursorScreenPos = function() return { curX, curY } end,
    SetCursorScreenPos = function(p) curX, curY = p[1], p[2] end,
    GetContentRegionAvail = function()
        local bx, by, bw, bh = currentBounds()
        return { math.max(0, (bx + bw) - curX), math.max(0, (by + bh) - curY) }
    end,
    InvisibleButton = function(id, size)
        local w = (size and size[1]) or 10
        local h = (size and size[2]) or 10
        recordItem(curX, curY, w, h, id)
        return false
    end,
    IsItemHovered = function()
        return hoverTargetId ~= nil and lastItemId == hoverTargetId
    end,
    IsItemClicked = function() return false end,
    IsMouseClicked = function() return false end,
    Button = function(label, size)
        local clean = tostring(label):gsub('##.*$', '')
        local w = (size and size[1] and size[1] > 0) and size[1] or (#clean * 7 + 16)
        local h = (size and size[2] and size[2] > 0) and size[2] or 22
        local x, y = curX, curY
        pushCmd({ op = 'rect_fill', x1 = x, y1 = y, x2 = x + w, y2 = y + h, col = { 24, 34, 60, 245 }, r = 4 })
        pushCmd({ op = 'rect', x1 = x, y1 = y, x2 = x + w, y2 = y + h, col = { 82, 98, 138, 220 }, r = 4, t = 1 })
        pushCmd({ op = 'text', x = x + math.max(6, (w - #clean * 6) * 0.5), y = y + (h - 10) * 0.5,
            col = { 241, 245, 249, 255 }, text = clean })
        recordItem(x, y, w, h, label)
        return false
    end,
    SameLine = function(_, spacing)
        curX = lastItemX + lastItemW + (spacing or 8)
        curY = lastItemY
    end,
    Dummy = function(size)
        recordItem(curX, curY, (size and size[1]) or 0, (size and size[2]) or 0, nil)
    end,
    TextUnformatted = function(s)
        local str = tostring(s or '')
        local col = abgrToHex(textColorStack[#textColorStack])
        if inTooltip then
            pushCmd({ op = 'text', x = tipX + 10, y = tipCursorY, col = col, text = str })
            tipCursorY = tipCursorY + 15
        else
            pushCmd({ op = 'text', x = curX, y = curY, col = col, text = str })
            recordItem(curX, curY, #str * 6.5, 13, nil)
        end
    end,
    TextWrapped = function(s)
        local str = tostring(s or '')
        local col = abgrToHex(textColorStack[#textColorStack])
        local maxChars = inTooltip and 44 or 40
        local lines = {}
        local line = ''
        for word in str:gmatch('%S+') do
            if #line == 0 then
                line = word
            elseif #line + 1 + #word <= maxChars then
                line = line .. ' ' .. word
            else
                lines[#lines + 1] = line
                line = word
            end
        end
        if #line > 0 then lines[#lines + 1] = line end
        for _, ln in ipairs(lines) do
            if inTooltip then
                pushCmd({ op = 'text', x = tipX + 10, y = tipCursorY, col = col, text = ln })
                tipCursorY = tipCursorY + 14
            else
                pushCmd({ op = 'text', x = curX, y = curY, col = col, text = ln })
                recordItem(curX, curY, #ln * 6.5, 13, nil)
            end
        end
    end,
    CalcTextSize = function(s) return { #(tostring(s or '')) * 6.2, 12 } end,
    BeginTooltip = function()
        inTooltip = true
        tooltipCmds = {}
        local tw = 332
        local ax = hoveredAnchor and (hoveredAnchor.x + hoveredAnchor.w + 12) or (winW * 0.52)
        local ay = hoveredAnchor and hoveredAnchor.y or 140
        if ax + tw > winW - 8 then ax = (hoveredAnchor and hoveredAnchor.x or winW * 0.5) - tw - 12 end
        if ay + 220 > winH - 8 then ay = winH - 230 end
        tipX, tipY, tipW = math.max(10, ax), math.max(10, ay), tw
        tipCursorY = tipY + 10
    end,
    EndTooltip = function()
        inTooltip = false
        local tipH = math.max(60, (tipCursorY - tipY) + 10)
        overlayCmds[#overlayCmds + 1] = { op = 'rect_fill', x1 = tipX, y1 = tipY, x2 = tipX + tipW, y2 = tipY + tipH, col = { 10, 15, 28, 252 }, r = 6 }
        overlayCmds[#overlayCmds + 1] = { op = 'rect', x1 = tipX, y1 = tipY, x2 = tipX + tipW, y2 = tipY + tipH, col = { 232, 189, 112, 240 }, r = 6, t = 1.5 }
        for _, tc in ipairs(tooltipCmds) do
            overlayCmds[#overlayCmds + 1] = tc
        end
        tooltipCmds = {}
    end,
    SetNextWindowBgAlpha = function() end,
    PushTextWrapPos = function() end,
    PopTextWrapPos = function() end,
    PushItemWidth = function(w) itemWidthStack[#itemWidthStack + 1] = w end,
    PopItemWidth = function() table.remove(itemWidthStack) end,
    InputTextWithHint = function(_, hint)
        local bx, _, bw, _ = currentBounds()
        local pw = itemWidthStack[#itemWidthStack]
        local w = (pw and pw > 0) and pw or math.max(80, bw - 4)
        local x, y, h = curX, curY, 22
        pushCmd({ op = 'rect_fill', x1 = x, y1 = y, x2 = x + w, y2 = y + h, col = { 11, 16, 29, 245 }, r = 4 })
        pushCmd({ op = 'rect', x1 = x, y1 = y, x2 = x + w, y2 = y + h, col = { 59, 70, 100, 210 }, r = 4, t = 1 })
        pushCmd({ op = 'text', x = x + 8, y = y + 5, col = { 100, 116, 139, 255 }, text = tostring(hint or '') })
        recordItem(x, y, w, h, 'search')
        return false
    end,
    InputText = function() return false end,
    Checkbox = function(label, val)
        local x, y = curX, curY
        pushCmd({ op = 'rect_fill', x1 = x, y1 = y + 2, x2 = x + 14, y2 = y + 16, col = { 15, 22, 41, 245 }, r = 3 })
        pushCmd({ op = 'rect', x1 = x, y1 = y + 2, x2 = x + 14, y2 = y + 16, col = { 96, 112, 148, 220 }, r = 3, t = 1 })
        pushCmd({ op = 'text', x = x + 20, y = y + 3, col = { 203, 213, 225, 255 }, text = tostring(label):gsub('##.*$', '') })
        recordItem(x, y, 140, 18, label)
        return false
    end,
    PushID = function() end,
    PopID = function() end,
    Spacing = function() curY = curY + 4 end,
    Separator = function()
        if inTooltip then
            pushCmd({ op = 'line', x1 = tipX + 8, y1 = tipCursorY, x2 = tipX + tipW - 8, y2 = tipCursorY, col = { 71, 85, 105, 180 }, t = 1 })
            tipCursorY = tipCursorY + 6
        else
            local bx, _, bw, _ = currentBounds()
            pushCmd({ op = 'line', x1 = bx, y1 = curY + 2, x2 = bx + bw, y2 = curY + 2, col = { 59, 70, 100, 180 }, t = 1 })
            curY = curY + 6
        end
    end,
    BeginGroup = function() end,
    EndGroup = function() end,
    GetWindowPos = function() return { 0, 0 } end,
    GetWindowSize = function() return { winW, winH } end,
    GetMousePos = function() return { 0, 0 } end,
    PushFont = function() end,
    PopFont = function() end,
}

local State = require('talent_state')
local UI    = require('talent_tree_ui')

local fakeNow = 100.0
local function nowFn() return fakeNow end
local noopActions = {
    requestSync = function() end,
    selectWs    = function() end,
    invest      = function() end,
    refund      = function() end,
    resetWs     = function() end,
    resetAll    = function() end,
}

local function buildBerserker(mode)
    local st = State.newState()
    st.open[1] = true
    local lvl = (mode == 'locked') and 25 or 75
    local avail = (mode == 'unallocated') and 15 or ((mode == 'partial') and 11 or ((mode == 'full') and 2 or 3))
    local spent = (mode == 'unallocated') and 0 or ((mode == 'partial') and 4 or ((mode == 'full') and 13 or 2))
    State.handleProtoLine(st, string.format('META|WAR|%d|%d|%d|%d|6|0|Berserker|berserker|Damage', lvl, avail, spent, avail + spent), nowFn)
    State.handleProtoLine(st, 'SPENT_BEGIN', nowFn)
    if spent > 0 then
        State.handleProtoLine(st, string.format('SPENT|84:%d:1,80:2:1', spent), nowFn)
    end
    State.handleProtoLine(st, 'SPENT_END', nowFn)
    State.handleProtoLine(st, 'CAT_BEGIN', nowFn)
    State.handleProtoLine(st, 'CAT|80:6:Iron Tempest:physical,81:6:Sturmwind:physical,82:6:Keen Edge:physical,84:6:Raging Rush:physical,64:5:Raging Axe:physical,68:5:Mistral Axe:physical', nowFn)
    State.handleProtoLine(st, 'CAT_END', nowFn)
    State.handleProtoLine(st, string.format('WS|84|Raging Rush|Great Axe|physical|%d|3-hit physical crit weapon skill', spent), nowFn)

    local r = {
        d1 = (mode == 'unallocated') and 0 or ((mode == 'full') and 3 or ((mode == 'locked') and 1 or 2)),
        d2 = (mode == 'full') and 2 or ((mode == 'partial') and 1 or 0),
        d3 = (mode == 'full') and 2 or 0,
        d4 = (mode == 'full') and 1 or 0,
        u1 = (mode == 'full') and 2 or 0,
        u2 = (mode == 'full') and 1 or 0,
        u3 = 0, u4 = 0,
        s1 = (mode == 'unallocated') and 0 or ((mode == 'full') and 2 or ((mode == 'locked') and 1 or 1)),
        s2 = (mode == 'full') and 1 or 0,
        s3 = (mode == 'full') and 1 or 0,
        s4 = (mode == 'full') and 1 or 0,
        sc = (mode == 'full') and 1 or 0,
    }
    local function cl(reqLvl, reqPts, curR, maxR, reqMet)
        return (lvl >= reqLvl and spent >= reqPts and curR < maxR and avail > 0 and reqMet) and 1 or 0
    end

    State.handleProtoLine(st, string.format('NODE|84|dmg_t1|1|1|%d|3|%d|0||0|Savage Edge|Increases weapon skill damage by 10%% (+5%% per rank).|1|0|0||1|damage||Next rank: +15%% weapon skill damage.', r.d1, cl(1,0,r.d1,3,true)), nowFn)
    State.handleProtoLine(st, string.format('NODE|84|dmg_t2|2|1|%d|2|%d|2|dmg_t1|1|Brutal Crit|Increases critical hit rate by 8%% on this WS.|20|0|0||2|damage||Next rank: +16%% critical hit rate.', r.d2, cl(20,2,r.d2,2,r.d1>=1)), nowFn)
    State.handleProtoLine(st, string.format('NODE|84|dmg_t3|3|1|%d|2|%d|4|dmg_t2|1|Cleaving Blow|Ignores 15%% of target physical defense.|40|0|0||3|damage||Next rank: Ignores 30%% physical defense.', r.d3, cl(40,4,r.d3,2,r.d2>=1)), nowFn)
    State.handleProtoLine(st, string.format('NODE|84|dmg_t4|4|1|%d|1|%d|6|dmg_t3|1|Executioner Apex|Deals +35%% bonus damage against targets below 40%% HP.|60|0|0||4|damage||', r.d4, cl(60,6,r.d4,1,r.d3>=1)), nowFn)

    State.handleProtoLine(st, string.format('NODE|84|util_t1|1|2|%d|3|%d|0||0|Steady Grip|Grants +15 Accuracy during weapon skill execution.|1|0|0||5|utility||Next rank: +30 Accuracy.', r.u1, cl(1,0,r.u1,3,true)), nowFn)
    State.handleProtoLine(st, string.format('NODE|84|util_t2|2|2|%d|2|%d|2|util_t1|1|Momentum Return|Refunds 120 TP when landing a hit.|20|0|0||6|utility||Next rank: Refunds 240 TP.', r.u2, cl(20,2,r.u2,2,r.u1>=1)), nowFn)
    State.handleProtoLine(st, string.format('NODE|84|util_t3|3|2|%d|2|%d|4|util_t2|1|Shattering Stagger|Applies Defense Down (-10%%) for 15 seconds.|40|0|0||7|utility||Next rank: -20%% Defense Down.', r.u3, cl(40,4,r.u3,2,r.u2>=1)), nowFn)
    State.handleProtoLine(st, string.format('NODE|84|util_t4|4|2|%d|1|%d|6|util_t3|1|Tactical Mastery|Reduces next Soul Action cooldown by 10s.|60|0|0||8|utility||', r.u4, cl(60,6,r.u4,1,r.u3>=1)), nowFn)

    State.handleProtoLine(st, string.format('NODE|84|soul_t1|1|3|%d|3|%d|0||0|Fury Conduit|Generates +12 Rage on weapon skill hit.|1|0|0||9|soul||Next rank: Generates +24 Rage.', r.s1, cl(1,0,r.s1,3,true)), nowFn)
    State.handleProtoLine(st, string.format('NODE|84|soul_t2|2|3|%d|2|%d|2|soul_t1|1|Bloodlust Surge|Extends active Berserk duration by 4 seconds.|20|0|0||10|soul||Next rank: Extends duration by 8 seconds.', r.s2, cl(20,2,r.s2,2,r.s1>=1)), nowFn)
    State.handleProtoLine(st, string.format('NODE|84|soul_t3|3|3|%d|2|%d|4|soul_t2|1|Rampage Echo|Consuming 50+ Rage grants a 25%% follow-up strike.|40|0|0||11|soul||Next rank: 50%% follow-up strike.', r.s3, cl(40,4,r.s3,2,r.s2>=1)), nowFn)
    State.handleProtoLine(st, string.format('NODE|84|soul_t4|4|3|%d|1|%d|6|soul_t3|1|Unstoppable Avatar|Weapon skill triggers Peak Fury for 12 seconds.|60|0|0||12|soul||', r.s4, cl(60,6,r.s4,1,r.s3>=1)), nowFn)

    State.handleProtoLine(st, string.format('NODE|84|sc_1|5|1|%d|1|%d|3||0|Fragmentation Link|Adds Fragmentation skillchain property.|30|1|11|Fragmentation|13|skillchain||', r.sc, cl(30,3,r.sc,1,true)), nowFn)
    State.handleProtoLine(st, string.format('WS_END|84|%d|%d', avail, spent > 0 and 1 or 0), nowFn)
    st.selectedWsId = 84
    return st
end

local function buildEvolution()
    local st = State.newState()
    st.open[1] = true
    State.handleProtoLine(st, 'META|MNK|75|8|2|10|1|0|Blackbelt|blackbelt|Damage', nowFn)
    State.handleProtoLine(st, 'SPENT_BEGIN', nowFn)
    State.handleProtoLine(st, 'SPENT|1:2:1', nowFn)
    State.handleProtoLine(st, 'SPENT_END', nowFn)
    State.handleProtoLine(st, 'CAT_BEGIN', nowFn)
    State.handleProtoLine(st, 'CAT|1:1:Combo:physical,2:1:Shoulder Tackle:physical,3:1:One Inch Punch:physical,8:1:Asuran Fists:physical', nowFn)
    State.handleProtoLine(st, 'CAT_END', nowFn)
    State.handleProtoLine(st, 'WS|1|Combo|Hand-to-Hand|physical|2|5-Stage Mutually Exclusive Evolution WS', nowFn)
    State.handleProtoLine(st, 'NODE|1|e_co_force|1|1|1|1|0|0||0|Crushing Force|Boosts Combo base fTP by +0.35.|1|0|0||1|evolution|evo_stage_1|', nowFn)
    State.handleProtoLine(st, 'NODE|1|e_co_tempo|1|2|0|1|0|0||0|Fluid Tempo|Refunds 150 TP after Combo.|1|0|0||2|evolution|evo_stage_1|', nowFn)
    State.handleProtoLine(st, 'NODE|1|e_co_hits|2|1|0|1|0|1||0|Twin Impact|Adds a 4th strike at 50% potency.|15|0|0||3|evolution|evo_stage_2|', nowFn)
    State.handleProtoLine(st, 'NODE|1|e_co_focus|2|2|1|1|0|1||0|Chi Focus|Generates +25 Chi on hit.|15|0|0||4|evolution|evo_stage_2|', nowFn)
    State.handleProtoLine(st, 'NODE|1|e_co_open|3|1|0|1|1|2||0|Shatter Guard|Applies Defense Down on hit.|30|0|0||5|evolution|evo_stage_3|', nowFn)
    State.handleProtoLine(st, 'NODE|1|e_co_edge|3|2|0|1|1|2||0|Keen Edge|Increases crit damage by +20%.|30|0|0||6|evolution|evo_stage_3|', nowFn)
    State.handleProtoLine(st, 'NODE|1|e_co_break|4|1|0|1|0|3||0|Guard Break|Ignores 30% physical defense.|50|0|0||7|evolution|evo_stage_4|', nowFn)
    State.handleProtoLine(st, 'NODE|1|e_co_flow|4|2|0|1|0|3||0|Inner Flow|Reduces Chakra cooldown by 10s.|50|0|0||8|evolution|evo_stage_4|', nowFn)
    State.handleProtoLine(st, 'NODE|1|e_co_storm|5|1|0|1|0|4||0|Tempest Barrage|Capstone: Unleashes rapid flurry.|70|0|0||9|evolution|evo_stage_5|', nowFn)
    State.handleProtoLine(st, 'NODE|1|e_co_window|5|2|0|1|0|4||0|Transcendent Window|Capstone: Doubles Chi gain for 15s.|70|0|0||10|evolution|evo_stage_5|', nowFn)
    State.handleProtoLine(st, 'WS_END|1|8|1', nowFn)
    st.selectedWsId = 1
    return st
end

local function buildBladewheel()
    local st = State.newState()
    st.open[1] = true
    State.handleProtoLine(st, 'META|NIN|75|9|3|12|2|27|Bladewheel|bladewheel|Damage', nowFn)
    State.handleProtoLine(st, 'SPENT_BEGIN', nowFn)
    State.handleProtoLine(st, 'SPENT|224:2:1,19:1:1', nowFn)
    State.handleProtoLine(st, 'SPENT_END', nowFn)
    State.handleProtoLine(st, 'CAT_BEGIN', nowFn)
    State.handleProtoLine(st, 'CAT|224:27:Pinwheel Toss:ranged,225:27:Shuriken Barrage:ranged,226:27:Razor Vortex:ranged,16:2:Wasp Sting:physical,19:2:Viper Bite:physical,23:2:Dancing Edge:physical,128:9:Blade: Rin:physical', nowFn)
    State.handleProtoLine(st, 'CAT_END', nowFn)
    State.handleProtoLine(st, 'WS|224|Pinwheel Toss|Throwing|ranged|2|Custom SoulspireXI Throwing WS', nowFn)
    State.handleProtoLine(st, 'NODE|224|dmg_t1|1|1|1|3|1|0||0|Serrated Disk|Increases Throwing WS damage by 12%.|1|0|0||1|damage||Next rank: +24% damage.', nowFn)
    State.handleProtoLine(st, 'NODE|224|dmg_t2|2|1|0|2|1|2|dmg_t1|1|Ricochet Arc|Bounces to a nearby target for 40% damage.|20|0|0||2|damage||Next rank: 65% bounce damage.', nowFn)
    State.handleProtoLine(st, 'NODE|224|dmg_t3|3|1|0|2|0|4|dmg_t2|1|Gale Pierce|Ignores 20% ranged defense.|40|0|0||3|damage||', nowFn)
    State.handleProtoLine(st, 'NODE|224|dmg_t4|4|1|0|1|0|6|dmg_t3|1|Cyclone Finisher|Capstone: Doubles bleed ticks on crit.|60|0|0||4|damage||', nowFn)
    State.handleProtoLine(st, 'NODE|224|util_t1|1|2|0|3|1|0||0|Wind Sight|+20 Ranged Accuracy on throw.|1|0|0||5|utility||', nowFn)
    State.handleProtoLine(st, 'NODE|224|util_t2|2|2|0|2|0|2|util_t1|1|Quick Draw|Refunds 100 TP on hit.|20|0|0||6|utility||', nowFn)
    State.handleProtoLine(st, 'NODE|224|util_t3|3|2|0|2|0|4|util_t2|1|Crippling Edge|Applies Slow for 12s.|40|0|0||7|utility||', nowFn)
    State.handleProtoLine(st, 'NODE|224|util_t4|4|2|0|1|0|6|util_t3|1|Shadow Step|Grants brief Evasion boost.|60|0|0||8|utility||', nowFn)
    State.handleProtoLine(st, 'NODE|224|soul_t1|1|3|1|3|1|0||0|Spinning Momentum|Builds +15 Blade Momentum.|1|0|0||9|soul||Next rank: +30 Blade Momentum.', nowFn)
    State.handleProtoLine(st, 'NODE|224|soul_t2|2|3|0|2|1|2|soul_t1|1|Twin Shuriken|Consumes Momentum for a bonus throw.|20|0|0||10|soul||', nowFn)
    State.handleProtoLine(st, 'NODE|224|soul_t3|3|3|0|2|0|4|soul_t2|1|Whirling Guard|Extends Utsusemi shadow synergy.|40|0|0||11|soul||', nowFn)
    State.handleProtoLine(st, 'NODE|224|soul_t4|4|3|0|1|0|6|soul_t3|1|Tempest Sovereign|Capstone: Triggers Blade Flurry.|60|0|0||12|soul||', nowFn)
    State.handleProtoLine(st, 'WS_END|224|9|1', nowFn)
    st.selectedWsId = 224
    return st
end

local scenarios = {
    { name = '01_unallocated',         w = 1060, h = 680, hover = nil,            st = buildBerserker('unallocated') },
    { name = '02_partially_invested',  w = 1060, h = 680, hover = nil,            st = buildBerserker('partial') },
    { name = '03_fully_developed',     w = 1060, h = 680, hover = nil,            st = buildBerserker('full') },
    { name = '04_locked_prerequisites',w = 1060, h = 680, hover = '##node_dmg_t3',st = buildBerserker('locked') },
    { name = '05_mutually_exclusive',  w = 1060, h = 680, hover = '##node_e_co_tempo', st = buildEvolution() },
    { name = '06_tooltip_damage',      w = 1060, h = 680, hover = '##node_dmg_t1',st = buildBerserker('partial') },
    { name = '07_tooltip_utility',     w = 1060, h = 680, hover = '##node_util_t1',st = buildBerserker('partial') },
    { name = '08_tooltip_soul',        w = 1060, h = 680, hover = '##node_soul_t1',st = buildBerserker('partial') },
    { name = '09_weapon_selector',     w = 1060, h = 680, hover = nil,            st = buildBladewheel() },
    { name = '10_compact_860x580',     w = 860,  h = 580, hover = nil,            st = buildBerserker('partial') },
}

for _, sc in ipairs(scenarios) do
    cmds = {}
    overlayCmds = {}
    itemWidthStack = {}
    hitboxes = {}
    tooltipCmds = {}
    inTooltip = false
    hoveredAnchor = nil
    lastItemId = nil
    childStack = {}
    curX, curY = 12, 12
    lastItemX, lastItemY, lastItemW, lastItemH = 12, 12, 0, 0
    winW, winH = sc.w, sc.h
    hoverTargetId = sc.hover

    UI.render(sc.st, noopActions)
    for _, oc in ipairs(overlayCmds) do
        cmds[#cmds + 1] = oc
    end

    local payload = toJson({
        name = sc.name,
        width = sc.w,
        height = sc.h,
        hover = sc.hover,
        cmdCount = #cmds,
        hitboxes = hitboxes,
        commands = cmds,
    })
    local outPath = outDir .. '/' .. sc.name .. '.json'
    local f = assert(io.open(outPath, 'w'))
    f:write(payload)
    f:close()
    print(string.format('[CAPTURE] %s (%dx%d): %d draw cmds, %d hitboxes', sc.name, sc.w, sc.h, #cmds, #hitboxes))
end
