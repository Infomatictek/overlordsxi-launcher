--[[
* SoulspireXI Soul HUD - Crystal Job Gauge renderer.
*
* A frameless, transparent canvas drawn entirely with the window draw list: D3D8 .png sprites
* (assets/ui/*.png built by tools/build_soulhud_assets.py), role-tinted gradient fills and
* crisp 1px drop-shadowed text. No stock ImGui window chrome, progress bars or key/value lists.
*
*   [ Medallion 56 ] [ pips row   : facet-cut stack gems + label          ]
*   [  + ABR badge ] [ gauge bar  : tapered frame + gradient fill + gloss ]
*   [ status sub-strip: 28px custom status icons in gold rings w/ badges/timers/tooltips        ]
--]]

local okIcons, icons = pcall(require, 'ox_icons')
if not okIcons then icons = nil end
local roster    = require('soulhud_roster')
local layoutMod = require('soulhud_layout')
local okTips, tips = pcall(require, 'soulhud_tips')
if not okTips then tips = nil end

local okBit, bit = pcall(require, 'bit')

local M = {}

-- ---------------------------------------------------------------------------------------------
-- geometry (unscaled px; every value is multiplied by cfg.scale)
-- ---------------------------------------------------------------------------------------------
local MED        = 56    -- medallion
local SPINE_X    = 62    -- spine starts right of the medallion
local PIP        = 22
local PIP_PITCH  = 24
local PIP_Y      = 3
local BAR_W, BAR_H = 220, 22
local BAR_Y      = 29
local TROUGH     = { x0 = 15, y0 = 5, x1 = 205, y1 = 17 }
local STRIP_Y    = 60
local RING       = 36
local ICON       = 28
local RING_PITCH = 38
-- Status strip rows: ring + countdown text drawn BELOW the ring + small gap. Every row (and the window)
-- is sized from these numbers, so nothing drawn in the strip can fall outside the ImGui clip rect.
local TIMER_H    = 11    -- countdown label height under each ring
local ROW_GAP    = 3
local ROW_H      = RING + TIMER_H + ROW_GAP
local MAX_ROWS   = 4     -- wrapped buff rows; further effects are summarised as "+N"
local BOTTOM_PAD = 6     -- bottom margin (window padding is 0, so it is part of the content size)
local TIP_WRAP   = 350   -- px, hover tooltip wrap width
local PILL_H     = 22

-- ---------------------------------------------------------------------------------------------
-- colour helpers (packed ABGR, as ImGui draw lists expect)
-- ---------------------------------------------------------------------------------------------
local function abgr(r, g, b, a)
    return (a or 255) * 16777216 + b * 65536 + g * 256 + r
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function rgbOf(c)
    return c[1], c[2], c[3]
end

local function mixRgb(a, b, t)
    return {
        math.floor(a[1] + (b[1] - a[1]) * t), math.floor(a[2] + (b[2] - a[2]) * t), math.floor(a[3] + (b[3] - a[3]) * t),
    }
end

local function col(c, alpha)
    return abgr(c[1], c[2], c[3], math.floor(clamp((alpha or 1) * 255, 0, 255) + 0.5))
end

local function vec4(c, alpha)
    return { c[1] / 255, c[2] / 255, c[3] / 255, alpha or 1 }
end

local WHITE = { 255, 255, 255 }
local BLACK = { 0, 0, 0 }

local ROLES = {
    tank    = { body = { 62, 112, 214 }, gold = { 214, 172, 78 }, deep = { 10, 22, 52 } },
    healer  = { body = { 52, 196, 128 }, gold = { 222, 212, 160 }, deep = { 8, 40, 30 } },
    support = { body = { 150, 92, 220 }, gold = { 196, 152, 64 }, deep = { 28, 14, 54 } },
    damage  = { body = { 214, 48, 66 }, gold = { 232, 142, 54 }, deep = { 44, 8, 16 } },
}

local TEXT      = { 226, 232, 233 }   -- crystalsocket palette: text
local TEXT_DIM  = { 184, 168, 156 }   -- secondary
local WARN      = { 238, 85, 68 }
local TROUGH_BG = { 10, 6, 8 }

local GEM_FOR_ROLE = layoutMod.ROLE_GEM

-- ---------------------------------------------------------------------------------------------
-- per-addon animation state
-- ---------------------------------------------------------------------------------------------
local anim = { disp = {}, peak = {}, lastClock = nil, lastPos = nil, movedAt = -10, popupOpen = false }

function M.reset()
    anim.disp, anim.peak, anim.lastClock = {}, {}, nil
end

-- ---------------------------------------------------------------------------------------------
-- imgui helpers
-- ---------------------------------------------------------------------------------------------
local function toXY(a, b)
    if type(a) == 'table' then return a[1] or a.x or 0, a[2] or a.y or 0 end
    return a or 0, b or 0
end

local function fontScale(imgui, f)
    if imgui.SetWindowFontScale then imgui.SetWindowFontScale(f) end
end

-- Count UTF-8 visual characters (so multi-byte symbols like '•' don't inflate fallback width).
local function utf8Len(str)
    local _, count = tostring(str or ''):gsub('[^\128-\191]', '')
    return count
end

local function textSize(imgui, str, fs)
    local scale = fs or 1.0
    local nChars = utf8Len(str)
    local ok, w, h = pcall(function() return toXY(imgui.CalcTextSize(str)) end)
    if ok and type(w) == 'number' and w > 0 then
        return w, (type(h) == 'number' and h > 0) and h or math.floor(13 * scale + 0.5)
    end
    -- Ashita v4's imgui.CalcTextSize(str) returns two numbers (w, h). When fallback is needed,
    -- ProggyClean default ImGui font is 7px/char at scale 1.0, scaled by SetWindowFontScale(fs).
    return math.floor(nChars * 7.0 * scale + 0.5), math.floor(13 * scale + 0.5)
end

-- Fit `str` into `maxW` pixels at font scale `fs`, truncating with '..' if necessary.
local function fitText(imgui, str, maxW, fs)
    str = tostring(str or '')
    if maxW <= 0 or str == '' then return '' end
    fontScale(imgui, fs)
    local w = textSize(imgui, str, fs)
    if w <= maxW then
        fontScale(imgui, 1.0)
        return str
    end
    local n = #str
    while n > 1 do
        n = n - 1
        local cand = str:sub(1, n):gsub('%s+$', '') .. '..'
        if textSize(imgui, cand, fs) <= maxW then
            fontScale(imgui, 1.0)
            return cand
        end
    end
    fontScale(imgui, 1.0)
    return ''
end

-- Crisp 1px drop-shadowed text. align: 'l' | 'r' | 'c'.
local function text(imgui, dl, x, y, color, str, fs, align, alpha)
    fontScale(imgui, fs)
    local w, h = textSize(imgui, str, fs)
    if align == 'r' then x = x - w elseif align == 'c' then x = x - w / 2 end
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    dl:AddText({ x + 1, y + 1 }, col(BLACK, 0.85 * (alpha or 1)), str)
    dl:AddText({ x, y }, color, str)
    fontScale(imgui, 1.0)
    return w, h
end

local function gradRect(dl, x0, y0, x1, y1, ctop, cbot)
    if dl.AddRectFilledMultiColor then
        dl:AddRectFilledMultiColor({ x0, y0 }, { x1, y1 }, ctop, ctop, cbot, cbot)
    else
        dl:AddRectFilled({ x0, y0 }, { x1, y1 }, cbot)
    end
end

local function image(dl, tex, x0, y0, x1, y1, tint)
    if tex ~= nil then
        dl:AddImage(tex, { x0, y0 }, { x1, y1 }, { 0, 0 }, { 1, 1 }, tint or 0xFFFFFFFF)
        return true
    end
    return false
end

-- Hover tooltip styled with the crystalsocket navy / gold palette.
--   lines: { { text, color }, { head = 'Section', text = '...', color }, { sep = true } }
--   opts : { weapon = 'Polearm + Buckler', subtitle = 'Tank Soul Crystal' }
-- Text is wrapped at ~350px and drawn unformatted (a stray % in the copy is safe).
local function tipText(imgui, str)
    str = tostring(str or '')
    if imgui.TextUnformatted then
        imgui.TextUnformatted(str)
    else
        imgui.Text((str:gsub('%%', '%%%%')))
    end
end

local function styledTooltip(imgui, accent, title, lines, opts)
    local pushed = 0
    local function pc(idx, v)
        if idx ~= nil then imgui.PushStyleColor(idx, v); pushed = pushed + 1 end
    end
    pc(ImGuiCol_PopupBg, { 0.07, 0.085, 0.15, 0.96 })
    pc(ImGuiCol_Border, vec4(accent, 1.0))
    pc(ImGuiCol_Text, vec4(TEXT, 1.0))
    imgui.BeginTooltip()
    local wrapped = false
    if imgui.PushTextWrapPos then wrapped = pcall(imgui.PushTextWrapPos, TIP_WRAP) end
    imgui.TextColored(vec4(accent, 1.0), title)
    if opts and opts.subtitle then imgui.TextColored(vec4(TEXT_DIM, 1.0), opts.subtitle) end
    if opts and opts.weapon then
        imgui.TextColored(vec4({ 232, 200, 110 }, 1.0), 'Weapon: ' .. opts.weapon)
    end
    local needSep = (opts and (opts.weapon or opts.subtitle)) and true or false
    for _, ln in ipairs(lines or {}) do
        if ln.sep then
            if imgui.Separator then imgui.Separator() end
            needSep = false
        else
            if needSep and imgui.Separator then imgui.Separator() end
            needSep = false
            if ln.head then imgui.TextColored(vec4(accent, 1.0), ln.head) end
            if ln.color then
                imgui.PushStyleColor(ImGuiCol_Text or 0, vec4(ln.color, 1.0))
                tipText(imgui, ln.text)
                imgui.PopStyleColor(1)
            else
                tipText(imgui, ln.text)
            end
        end
    end
    if wrapped and imgui.PopTextWrapPos then imgui.PopTextWrapPos() end
    imgui.EndTooltip()
    if pushed > 0 then imgui.PopStyleColor(pushed) end
end

local function measure(imgui, str, fs)
    fontScale(imgui, fs)
    local w, h = textSize(imgui, str, fs)
    fontScale(imgui, 1.0)
    return w, h
end

-- Screen size (so the HUD can never sit off-screen). Returns 0, 0 when unavailable.
local function displaySize(imgui)
    local ok, w, h = pcall(function()
        local io = imgui.GetIO()
        local ds = io and io.DisplaySize
        if ds == nil then return 0, 0 end
        return toXY(ds)
    end)
    if ok and type(w) == 'number' and type(h) == 'number' then return w, h end
    return 0, 0
end
local function fmtTime(rem)
    rem = math.max(0, math.ceil(rem))
    if rem >= 3600 then return ('%dh'):format(math.floor(rem / 3600)) end
    if rem >= 60 then return ('%dm'):format(math.floor(rem / 60)) end
    return ('%ds'):format(rem)
end

local function powerBadge(power)
    power = tonumber(power) or 0
    if power <= 0 then return '' end
    if power <= 5 then return ('x%d'):format(power) end
    return ('%d%%'):format(math.min(power, 999))
end

-- ---------------------------------------------------------------------------------------------
-- quick options popup (left-click while unlocked, or right-click on the medallion)
-- ---------------------------------------------------------------------------------------------
local POPUP_ID = '##ox_soulhud_opts'

local function drawOptions(imgui, cfg, callbacks, palette)
    local pushed = 0
    local function pc(idx, v)
        if idx ~= nil then imgui.PushStyleColor(idx, v); pushed = pushed + 1 end
    end
    pc(ImGuiCol_PopupBg, { 0.07, 0.085, 0.15, 0.97 })
    pc(ImGuiCol_Border, vec4(palette.gold, 1.0))
    pc(ImGuiCol_Text, vec4(TEXT, 1.0))
    pc(ImGuiCol_Header, vec4(palette.body, 0.35))
    pc(ImGuiCol_HeaderHovered, vec4(palette.body, 0.65))
    pc(ImGuiCol_HeaderActive, vec4(palette.body, 0.85))

    if imgui.BeginPopup(POPUP_ID) then
        imgui.TextColored(vec4(palette.gold, 1.0), 'Crystal Job Gauge')
        imgui.Separator()
        if imgui.Selectable(cfg.locked and 'Unlock Position' or 'Lock Position') then
            cfg.locked = not cfg.locked
            if callbacks.onSave then callbacks.onSave() end
        end
        for _, sv in ipairs({ 0.8, 1.0, 1.25 }) do
            local label = ('Scale %.2gx%s'):format(sv, math.abs((cfg.scale or 1) - sv) < 0.01 and '  *' or '')
            if imgui.Selectable(label) then
                cfg.scale = sv
                if callbacks.onSave then callbacks.onSave() end
            end
        end
        if imgui.Selectable('Shared Party Buffs: ' .. (cfg.showShared ~= false and 'On' or 'Off')) then
            cfg.showShared = not (cfg.showShared ~= false)
            if callbacks.onSave then callbacks.onSave() end
        end
        if imgui.Selectable('Auto-hide in Menus: ' .. (cfg.autoHideOnMenu ~= false and 'On' or 'Off')) then
            cfg.autoHideOnMenu = not (cfg.autoHideOnMenu ~= false)
            if callbacks.onSave then callbacks.onSave() end
        end
        if imgui.Selectable('Soul Header Pill: ' .. (cfg.pill ~= false and 'On' or 'Off')) then
            cfg.pill = not (cfg.pill ~= false)
            if callbacks.onSave then callbacks.onSave() end
        end
        if imgui.Selectable('More Settings...') then
            if callbacks.onToggleConfig then callbacks.onToggleConfig() end
        end
        imgui.EndPopup()
    end
    if pushed > 0 then imgui.PopStyleColor(pushed) end
end

-- ---------------------------------------------------------------------------------------------
-- bar value text / smoothing
-- ---------------------------------------------------------------------------------------------
local function barValueText(bar, cur, max)
    if cur <= 0.0001 and bar.idle then return bar.idle end
    if bar.right and bar.right ~= '' then return bar.right end
    local f = bar.fmt
    if f == 'sec' then return fmtTime(cur) end
    if f == 'frac' then return ('%d/%d'):format(math.floor(cur + 0.5), math.floor(max + 0.5)) end
    if f == 'pct' then return ('%d%%'):format(math.floor(cur / math.max(max, 0.0001) * 100 + 0.5)) end
    return tostring(math.floor(cur + 0.5))
end

-- ---------------------------------------------------------------------------------------------
-- main entry
--   ctx = { soulKey, kv, def, rt, buffs, now, syncAt, cfg, callbacks, resetPos, onResetPosApplied, demo,
--           level, boost }
-- ---------------------------------------------------------------------------------------------
function M.render(imgui, ctx)
    local entry = roster.get(ctx.soulKey)
    if entry == nil then return end

    local cfg, now = ctx.cfg, ctx.now
    local s = cfg.scale or 1.0
    local alpha = cfg.opacity or 0.92
    local pal = ROLES[entry.role] or ROLES.support

    local dt = anim.lastClock and clamp(now - anim.lastClock, 0, 0.1) or 0.016
    anim.lastClock = now

    local data = layoutMod.build(entry.key, ctx.kv, ctx.def, ctx.rt, entry.role)
    local tctx = { kv = ctx.kv or {}, lvl = tonumber(ctx.level) or 0, boost = ctx.boost }

    -- status icons to show
    local buffs = {}
    for _, b in ipairs(ctx.buffs or {}) do
        local expired = b.expiresAt and now > b.expiresAt + 0.5
        local hidden = (cfg.showShared == false) and b.entry and b.entry.isShared
        if not expired and not hidden then buffs[#buffs + 1] = b end
    end

    -- ------------------------------------------------------------------ exact window metrics
    -- Strip wraps into rows of `perRow` rings (as wide as the gauge spine); each row reserves
    -- ring + countdown text under the ring + gap. The window is sized from these, never a fixed cap.
    local perRow = math.max(1, math.floor((SPINE_X + BAR_W + (RING_PITCH - RING)) / RING_PITCH))
    local hiddenCount = 0
    if #buffs > perRow * MAX_ROWS then
        hiddenCount = #buffs - perRow * MAX_ROWS
        for i = #buffs, perRow * MAX_ROWS + 1, -1 do buffs[i] = nil end
    end
    local rows = math.ceil(#buffs / perRow)
    local cols = math.min(#buffs, perRow)

    local stripW = (cols > 0) and (cols * RING_PITCH - (RING_PITCH - RING)) or 0
    local totalW = math.max(SPINE_X + BAR_W, stripW)
    local totalH = (rows > 0) and (STRIP_Y + rows * ROW_H + BOTTOM_PAD) or (MED + BOTTOM_PAD)
    local W, H = totalW * s, totalH * s

    -- ------------------------------------------------------------------ keep the window on-screen
    local forcePos = ctx.resetPos == true
    local dw, dh = displaySize(imgui)
    if dw > 0 and dh > 0 then
        local nx = math.floor(clamp(cfg.x, 0, math.max(0, dw - W)) + 0.5)
        local ny = math.floor(clamp(cfg.y, 0, math.max(0, dh - H)) + 0.5)
        if nx ~= cfg.x or ny ~= cfg.y then
            cfg.x, cfg.y = nx, ny
            forcePos = true
            if ctx.callbacks and ctx.callbacks.onMove then ctx.callbacks.onMove() end
        end
    end

    local flagList = {
        ImGuiWindowFlags_NoTitleBar or 1, ImGuiWindowFlags_NoScrollbar or 8, ImGuiWindowFlags_NoCollapse or 32,
        ImGuiWindowFlags_NoBackground or 128, ImGuiWindowFlags_AlwaysAutoResize or 64,
        ImGuiWindowFlags_NoSavedSettings or 256, ImGuiWindowFlags_NoFocusOnAppearing or 4096,
        ImGuiWindowFlags_NoResize or 2, ImGuiWindowFlags_NoScrollWithMouse or 16,
        cfg.locked and (ImGuiWindowFlags_NoMove or 4) or 0,
    }
    local flags = 0
    for _, f in ipairs(flagList) do
        flags = (okBit and bit.bor(flags, f)) or (flags + f)
    end

    if ctx.resetPos and ctx.onResetPosApplied then ctx.onResetPosApplied() end
    imgui.SetNextWindowPos({ cfg.x, cfg.y }, forcePos and (ImGuiCond_Always or 1) or (ImGuiCond_FirstUseEver or 4))
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding or 1, { 0, 0 })

    if imgui.Begin('SoulspireSoulHUD##gauge', nil, flags) then
        local wx, wy = toXY(imgui.GetWindowPos())
        if not cfg.locked and (math.floor(wx + 0.5) ~= cfg.x or math.floor(wy + 0.5) ~= cfg.y) then
            cfg.x, cfg.y = math.floor(wx + 0.5), math.floor(wy + 0.5)
            anim.movedAt = now
            if ctx.callbacks and ctx.callbacks.onMove then ctx.callbacks.onMove() end
        end
        wx, wy = math.floor(wx), math.floor(wy)

        -- Exact bounding box of everything drawn below (header, gauges, wrapped strip rows, timers, margin).
        imgui.SetCursorScreenPos({ wx, wy })
        imgui.Dummy({ W, H })

        local dl = imgui.GetWindowDrawList()
        local tint = col(WHITE, alpha)
        local gold = col(pal.gold, alpha)
        local textCol = col(TEXT, alpha)
        local dimCol = col(TEXT_DIM, alpha)

        -- =========================================================== Left anchor: Soul Medallion
        local mx, my, ms = wx, wy, MED * s
        image(dl, icons and icons.ui('socket_' .. entry.role), mx, my, mx + ms, my + ms, tint)

        local cs = 32 * s
        local ccx, ccy = mx + ms / 2, my + ms / 2 - 1.2 * s
        local crystal = icons and icons.crystal(entry.key) or nil
        if not image(dl, crystal, ccx - cs / 2, ccy - cs / 2, ccx + cs / 2, ccy + cs / 2, tint) then
            -- facet-cut fallback crystal for Souls without bundled art
            local r = 13 * s
            local body = col(pal.body, alpha)
            local lite = col(mixRgb(pal.body, WHITE, 0.45), alpha)
            local dark = col(mixRgb(pal.body, BLACK, 0.55), alpha)
            dl:AddTriangleFilled({ ccx, ccy - r }, { ccx + r * 0.7, ccy }, { ccx, ccy + r * 0.2 }, lite)
            dl:AddTriangleFilled({ ccx, ccy - r }, { ccx - r * 0.7, ccy }, { ccx, ccy + r * 0.2 }, body)
            dl:AddTriangleFilled({ ccx - r * 0.7, ccy }, { ccx + r * 0.7, ccy }, { ccx, ccy + r * 1.1 }, dark)
            dl:AddTriangleFilled({ ccx - r * 0.7, ccy }, { ccx, ccy + r * 0.2 }, { ccx, ccy + r * 1.1 }, body)
        end

        -- 3-letter badge tucked into the bottom rim plate
        text(imgui, dl, mx + ms / 2, my + 45.6 * s, gold, entry.abr, 0.68 * s, 'c', alpha)

        -- Soul identity tooltip (role, signature weapon, how it plays / scales). Used by the medallion,
        -- the header pill and the name row.
        local function soulTip(withHint)
            local info = tips and tips.soul(entry, tctx) or nil
            local lines = info and info.lines or {}
            if withHint then
                lines[#lines + 1] = { sep = true }
                lines[#lines + 1] = {
                    text = ctx.demo and 'Demo preview' or (cfg.locked and 'Locked: /soulhud lock to unlock' or 'Click / right-click: quick options'),
                    color = TEXT_DIM,
                }
            end
            styledTooltip(imgui, pal.gold, entry.name .. '  (' .. entry.abr .. ')', lines, {
                subtitle = (roster.ROLE_LABEL[entry.role] or 'Soul') .. ' Soul Crystal',
                weapon = info and info.weapon or nil,
            })
        end

        imgui.SetCursorScreenPos({ mx, my })
        imgui.Dummy({ ms, ms })
        local medHovered = imgui.IsItemHovered()
        if medHovered then
            soulTip(true)
            local released = false
            pcall(function() released = imgui.IsMouseReleased(0) end)
            local rclick = false
            pcall(function() rclick = imgui.IsMouseClicked(1) end)
            if rclick or (released and not cfg.locked and (now - anim.movedAt) > 0.3) then
                imgui.OpenPopup(POPUP_ID)
            end
        end
        drawOptions(imgui, cfg, ctx.callbacks or {}, pal)

        -- =========================================================== Center spine: top row
        local sx = wx + SPINE_X * s
        local rowY = wy + PIP_Y * s
        local gemKey = data.pips and data.pips.gem or (GEM_FOR_ROLE[entry.role] or 'gold')

        if data.pips then
            local p = data.pips
            local pulse = 0.5 + 0.5 * math.sin(now * 6)
            if p.badge then
                local x0, y0, x1, y1 = sx, rowY, sx + BAR_W * s, rowY + PILL_H * s
                local rad = PILL_H * s / 2
                dl:AddRectFilled({ x0, y0 }, { x1, y1 }, col(pal.deep, alpha * 0.92), rad)
                dl:AddRect({ x0, y0 }, { x1, y1 }, p.glow and gold or col(pal.body, alpha * 0.85), rad)
                local innerW = (BAR_W - 20) * s
                local rTxt = tostring(p.right or '')
                local rW = 0
                if rTxt ~= '' then
                    rTxt = fitText(imgui, rTxt, innerW * 0.46, 0.72 * s)
                    rW = measure(imgui, rTxt, 0.72 * s)
                    text(imgui, dl, x1 - 10 * s, y0 + 5 * s, p.glow and gold or col(pal.body, alpha), rTxt, 0.72 * s, 'r', alpha)
                end
                local lMaxW = innerW - (rW > 0 and (rW + 8 * s) or 0)
                local lTxt = fitText(imgui, p.label, lMaxW, 0.78 * s)
                text(imgui, dl, x0 + 10 * s, y0 + 4 * s, p.glow and gold or textCol, lTxt, 0.78 * s, 'l', alpha)
            else
                for i = 1, p.max do
                    local gx = sx + 2 * s + (i - 1) * PIP_PITCH * s
                    local lit = i <= p.cur
                    if lit and p.glow then
                        dl:AddCircleFilled({ gx + PIP * s / 2, rowY + PIP * s / 2 }, (11 + 3 * pulse) * s,
                            col(mixRgb(pal.gold, WHITE, 0.2), alpha * (0.18 + 0.22 * pulse)), 20)
                    end
                    image(dl, icons and icons.ui(lit and ('gem_' .. gemKey) or 'gem_empty'),
                        gx, rowY, gx + PIP * s, rowY + PIP * s, tint)
                end
                local pipsEndX = sx + (2 + p.max * PIP_PITCH + 2) * s
                local rightEdgeX = sx + (BAR_W - 6) * s
                local availW = math.max(24 * s, rightEdgeX - pipsEndX)
                local lab = p.right or ('%s %d/%d'):format(string.upper(p.label), p.cur, p.max)
                lab = fitText(imgui, lab, availW, 0.74 * s)
                text(imgui, dl, rightEdgeX, rowY + 5 * s, (p.glow or p.cur >= p.max) and gold or dimCol, lab, 0.74 * s, 'r', alpha)
            end
            imgui.SetCursorScreenPos({ sx, rowY })
            imgui.Dummy({ BAR_W * s, PIP * s })
            if imgui.IsItemHovered() then
                local lines = tips and tips.element(entry.key, 'pips', tctx) or nil
                local headTitle = p.badge and (p.label .. (p.right and ('  •  ' .. p.right) or ''))
                    or ('%s  %d / %d'):format(p.label, p.cur, p.max)
                styledTooltip(imgui, pal.gold, headTitle,
                    lines or { { text = p.right or ('%d / %d'):format(p.cur, p.max) } })
            end
        else
            local roleStr = string.upper(roster.ROLE_LABEL[entry.role] or '')
            local hitW = BAR_W * s
            local showPill = cfg.pill ~= false and not data.bar and (ctx.demo or tctx.lvl >= 10)
            if showPill then
                -- Compact Soul header pill for Souls that have no custom gauge yet.
                local nameW = measure(imgui, entry.name, 1.0 * s)
                local roleW = measure(imgui, roleStr, 0.78 * s)
                local pillW = math.min(BAR_W * s, nameW + roleW + 34 * s)
                local x0, y0, x1, y1 = sx, rowY, sx + pillW, rowY + PILL_H * s
                local rad = PILL_H * s / 2
                dl:AddRectFilled({ x0, y0 }, { x1, y1 }, col(pal.deep, alpha * 0.92), rad)
                dl:AddRect({ x0, y0 }, { x1, y1 }, col(pal.gold, alpha), rad)
                text(imgui, dl, x0 + 11 * s, y0 + 3 * s, gold, entry.name, 1.0 * s, 'l', alpha)
                text(imgui, dl, x1 - 11 * s, y0 + 5 * s, col(pal.body, alpha), roleStr, 0.78 * s, 'r', alpha)
                hitW = pillW
            else
                text(imgui, dl, sx + 4 * s, rowY + 3 * s, gold, entry.name, 1.0 * s, 'l', alpha)
                text(imgui, dl, sx + (BAR_W - 6) * s, rowY + 5 * s, col(pal.body, alpha), roleStr, 0.78 * s, 'r', alpha)
            end
            imgui.SetCursorScreenPos({ sx, rowY })
            imgui.Dummy({ hitW, PILL_H * s })
            if imgui.IsItemHovered() then soulTip(false) end
        end

        -- =========================================================== Center spine: middle bar
        if data.bar then
            local b = data.bar
            local bx, by = sx, wy + BAR_Y * s
            local key = entry.key .. ':' .. b.key

            -- raw -> effective current (countdown timers tick between server pushes)
            local cur = tonumber(b.cur) or 0
            if b.countdown and cur > 0 then
                cur = math.max(0, cur - (now - (ctx.syncAt or now)))
            end
            local mxv = b.max
            if mxv == nil then
                local pk = anim.peak[key] or 0
                if (tonumber(b.cur) or 0) <= 0 then pk = 0 end
                pk = math.max(pk, tonumber(b.cur) or 0)
                anim.peak[key] = pk
                mxv = math.max(1, pk)
            end

            local target = clamp(cur / mxv, 0, 1)
            local disp = anim.disp[key]
            if disp == nil then disp = target end
            disp = disp + (target - disp) * math.min(1, dt * 9)
            if math.abs(target - disp) < 0.0015 then disp = target end
            anim.disp[key] = disp

            local tx0, ty0 = bx + TROUGH.x0 * s, by + TROUGH.y0 * s
            local tx1, ty1 = bx + TROUGH.x1 * s, by + TROUGH.y1 * s

            dl:AddRectFilled({ tx0, ty0 }, { tx1, ty1 }, col(TROUGH_BG, alpha))

            local fx = tx0 + (tx1 - tx0) * disp
            if disp > 0.002 then
                local base = pal.body
                local pulseMul = 1.0
                if b.warn then
                    base = WARN
                    pulseMul = 0.78 + 0.22 * math.sin(now * 9)
                end
                local light = mixRgb(base, WHITE, 0.38)
                local dark = mixRgb(base, BLACK, 0.5)
                local midY = (ty0 + ty1) / 2
                gradRect(dl, tx0, ty0, fx, midY, col(light, alpha * pulseMul), col(base, alpha * pulseMul))
                gradRect(dl, tx0, midY, fx, ty1, col(base, alpha * pulseMul), col(dark, alpha * pulseMul))
                dl:AddRectFilled({ math.max(tx0, fx - 1.2 * s), ty0 }, { fx, ty1 }, col(mixRgb(base, WHITE, 0.75), alpha * 0.9))
            end

            if b.notches and b.notches > 1 then
                for i = 1, b.notches - 1 do
                    local nx = math.floor(tx0 + (tx1 - tx0) * i / b.notches)
                    dl:AddRectFilled({ nx, ty0 }, { nx + math.max(1, s * 0.9), ty1 }, col(BLACK, alpha * 0.7))
                end
            end

            image(dl, icons and icons.ui('bar_frame'), bx, by, bx + BAR_W * s, by + BAR_H * s, tint)
            image(dl, icons and icons.ui('bar_gloss_overlay'), bx, by, bx + BAR_W * s, by + BAR_H * s, tint)

            local ty = by + (TROUGH.y0 + 1.1) * s
            local labCol = b.warn and col(mixRgb(WARN, WHITE, 0.35), alpha) or textCol
            local innerBarW = (tx1 - tx0) - 8 * s
            local valTxt = fitText(imgui, barValueText(b, cur, mxv), innerBarW * 0.48, 0.74 * s)
            local valW = measure(imgui, valTxt, 0.74 * s)
            local labMaxW = math.max(20 * s, innerBarW - valW - 8 * s)
            local labTxt = fitText(imgui, b.label, labMaxW, 0.74 * s)
            text(imgui, dl, tx0 + 4 * s, ty, labCol, labTxt, 0.74 * s, 'l', alpha)
            text(imgui, dl, tx1 - 4 * s, ty, labCol, valTxt, 0.74 * s, 'r', alpha)

            imgui.SetCursorScreenPos({ bx, by })
            imgui.Dummy({ BAR_W * s, BAR_H * s })
            if imgui.IsItemHovered() then
                local lines = tips and tips.element(entry.key, 'bar', tctx) or nil
                styledTooltip(imgui, b.warn and WARN or pal.gold,
                    ('%s  %s'):format(b.label, barValueText(b, cur, mxv)),
                    lines or { { text = barValueText(b, cur, mxv) .. (b.fmt == 'sec' and '' or ('  /  ' .. math.floor(mxv + 0.5))) } })
            end
        end

        -- =========================================================== Bottom sub-strip: status icons
        if #buffs > 0 then
            local ringTex = icons and icons.ui('buff_ring_gold') or nil
            for i, b in ipairs(buffs) do
                local colIdx = (i - 1) % perRow
                local rowIdx = math.floor((i - 1) / perRow)
                local ix = wx + colIdx * RING_PITCH * s
                local iy = wy + (STRIP_Y + rowIdx * ROW_H) * s
                local entryB = b.entry
                local isDebuff = entryB and entryB.isDebuff
                local rem = b.expiresAt and math.max(0, b.expiresAt - now) or nil

                local iconTex = icons and icons.custom(b.iconId) or nil
                local o = (RING - ICON) / 2 * s
                if not image(dl, iconTex, ix + o, iy + o, ix + o + ICON * s, iy + o + ICON * s, tint) then
                    dl:AddRectFilled({ ix + o, iy + o }, { ix + o + ICON * s, iy + o + ICON * s }, col(pal.deep, alpha))
                end
                image(dl, ringTex, ix, iy, ix + RING * s, iy + RING * s,
                    isDebuff and col({ 255, 120, 110 }, alpha) or tint)

                local badge = powerBadge(b.power)
                if badge ~= '' then
                    text(imgui, dl, ix + (RING - 4) * s, iy + 3.5 * s, gold, badge, 0.72 * s, 'r', alpha)
                end
                -- countdown sits UNDER the ring, inside this row's reserved TIMER_H band
                if rem then
                    text(imgui, dl, ix + RING * s / 2, iy + (RING + 0.5) * s, textCol, fmtTime(rem), 0.7 * s, 'c', alpha)
                end

                -- hit box covers ring + timer band
                imgui.SetCursorScreenPos({ ix, iy })
                imgui.Dummy({ RING * s, (RING + TIMER_H) * s })
                if imgui.IsItemHovered() then
                    local title, lines
                    if tips then
                        title, lines = tips.buff(b, now, fmtTime)
                    else
                        title = entryB and entryB.name or ('Effect #' .. tostring(b.iconId))
                        lines = { { text = entryB and entryB.tooltip or '' } }
                        if rem then lines[#lines + 1] = { text = 'Remaining: ' .. fmtTime(rem), color = TEXT_DIM } end
                    end
                    if (tonumber(b.power) or 0) > 0 then
                        lines[#lines + 1] = { text = 'Potency: ' .. powerBadge(b.power), color = pal.gold }
                    end
                    styledTooltip(imgui, isDebuff and WARN or pal.gold, title, lines)
                end
            end
            if hiddenCount > 0 then
                text(imgui, dl, sx + (BAR_W - 6) * s, wy + 51.5 * s, dimCol, ('+%d more'):format(hiddenCount), 0.62 * s, 'r', alpha)
            end
        end

        -- Trailing marker: guarantees the layout cursor ends at the exact bottom edge (incl. margin).
        imgui.SetCursorScreenPos({ wx, wy + H - 1 })
        imgui.Dummy({ W, 1 })
    end
    imgui.End()
    imgui.PopStyleVar(1)
end

return M
