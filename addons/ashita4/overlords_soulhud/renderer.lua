local M = {}

local okBit, bit = pcall(require, 'bit')

local function bitBor(...)
    if okBit and bit and bit.bor then
        return bit.bor(...)
    end
    local acc = 0
    for i = 1, select('#', ...) do
        local v = tonumber(select(i, ...)) or 0
        local p, out, a, b = 1, 0, acc, v
        while a > 0 or b > 0 do
            local ra, rb = a % 2, b % 2
            if ra == 1 or rb == 1 then out = out + p end
            a = (a - ra) / 2
            b = (b - rb) / 2
            p = p * 2
        end
        acc = out
    end
    return acc
end

local PALETTE = {
    navy      = 0xFF361B10,
    dark      = 0xFF221008,
    silver    = 0xFFAD9789,
    edge      = 0xFF523929,
    text      = 0xFFE2E8E9,
    secondary = 0xFFB8A89C,
    muted     = 0xFF7B6557,
    track     = 0xFF1A0C06,
    accent    = 0xFFD9C38C,
    ready     = 0xFF66CC77,
    warn      = 0xFF4455EE,
    unavail   = 0xFF554840,
}

local function applyAlpha(abgr, alphaMul)
    local a = math.floor(abgr / 16777216) % 256
    local rgb = abgr % 16777216
    local na = math.max(0, math.min(255, math.floor(a * alphaMul + 0.5)))
    return na * 16777216 + rgb
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function isWarning(res, st, ctx)
    if type(res.warnWhen) == 'function' then
        local ok, w = pcall(res.warnWhen, ctx, st, res)
        if ok then return w == true end
    end
    if res.warnThreshold ~= nil then
        local cur = tonumber(st.current) or 0
        if res.warnMode == 'low' then
            return cur <= res.warnThreshold
        elseif res.warnMode == 'high' then
            return cur >= res.warnThreshold
        end
    end
    return false
end

local function isVisible(res, st, ctx, cfg, soulKey, settingsMod)
    if cfg.layout == 'compact' and not res.compact then
        return false
    end
    if not settingsMod.isElementVisible(cfg, soulKey, res.id) then
        return false
    end
    if type(res.visibleWhen) == 'function' and cfg.mode ~= 'show' then
        local ok, vis = pcall(res.visibleWhen, ctx, st, res)
        if ok and not vis then
            return false
        end
    end
    return true
end

local function formatValue(res, st, ctx)
    if type(res.format) == 'function' then
        local ok, txt = pcall(res.format, st, ctx, res)
        if ok and txt ~= nil then
            return tostring(txt)
        end
    end
    local t = res.type
    if t == 'stack' or t == 'gauge' then
        return string.format('%d/%d', math.floor(st.current or 0), math.floor(res.max or 1))
    elseif t == 'charges' then
        local c = math.floor(st.charges or st.current or 0)
        local mc = math.floor(res.maxCharges or res.max or 1)
        if (st.remaining or 0) > 0 then
            return string.format('%d/%d (%ds)', c, mc, math.ceil(st.remaining))
        end
        return string.format('%d/%d', c, mc)
    elseif t == 'cooldown' then
        if (st.remaining or 0) > 0 then
            return string.format('%ds', math.ceil(st.remaining))
        end
        return 'READY'
    elseif t == 'timer' then
        if (st.remaining or 0) > 0 then
            return string.format('%ds', math.ceil(st.remaining))
        end
        return st.active and 'ACTIVE' or 'IDLE'
    elseif t == 'toggle' then
        return st.active and 'ON' or 'OFF'
    elseif t == 'counter' then
        return tostring(math.floor(st.current or 0))
    end
    return st.text ~= '' and st.text or (st.active and 'ACTIVE' or 'IDLE')
end

local function drawSegmented(dl, x, y, w, h, cur, maxVal, fillCol, trackCol, edgeCol)
    local count = math.max(1, math.min(10, math.floor(maxVal)))
    local gap = 3
    local segW = (w - gap * (count - 1)) / count
    for i = 1, count do
        local sx = x + (i - 1) * (segW + gap)
        local filled = i <= cur
        dl:AddRectFilled({ sx, y }, { sx + segW, y + h }, filled and fillCol or trackCol, 2)
        dl:AddRect({ sx, y }, { sx + segW, y + h }, edgeCol, 2, nil, 1)
    end
end

local function drawBar(dl, x, y, w, h, ratio, fillCol, trackCol, edgeCol)
    local r = clamp(ratio, 0, 1)
    dl:AddRectFilled({ x, y }, { x + w, y + h }, trackCol, 2)
    if r > 0 then
        dl:AddRectFilled({ x, y }, { x + math.max(2, w * r), y + h }, fillCol, 2)
    end
    dl:AddRect({ x, y }, { x + w, y + h }, edgeCol, 2, nil, 1)
end

local function drawRadial(dl, cx, cy, radius, ratio, fillCol, trackCol)
    dl:AddCircleFilled({ cx, cy }, radius, trackCol, 16)
    local r = clamp(ratio, 0, 1)
    if r >= 0.99 then
        dl:AddCircle({ cx, cy }, radius - 1, fillCol, 16, 2)
    elseif r > 0 then
        dl:PathClear()
        dl:PathArcTo({ cx, cy }, radius - 1, -math.pi * 0.5, -math.pi * 0.5 + (math.pi * 2 * r), 16)
        dl:PathStroke(fillCol, false, 2)
    else
        dl:AddCircle({ cx, cy }, radius - 1, fillCol, 16, 1)
    end
end

function M.renderHud(imgui, soulDef, rt, ctx, cfg, settingsMod, callbacks)
    if not imgui or not soulDef or not rt then
        return
    end

    local s = cfg.scale or 1.0
    local alpha = cfg.opacity or 0.92
    local isCompact = cfg.layout == 'compact'

    local visibleRes = {}
    for _, res in ipairs(soulDef.resources or {}) do
        local st = rt.values[res.id] or {}
        if isVisible(res, st, ctx, cfg, soulDef.key, settingsMod) then
            visibleRes[#visibleRes + 1] = { res = res, st = st }
        end
    end

    local winW = (isCompact and 236 or 276) * s
    local headerH = 22 * s
    local rowH = (isCompact and 20 or 26) * s
    local pad = 8 * s
    local bodyH = math.max(18 * s, #visibleRes * rowH + pad)
    local winH = headerH + bodyH + 4 * s

    local flags = bitBor(
        ImGuiWindowFlags_NoTitleBar or 1,
        ImGuiWindowFlags_NoResize or 2,
        ImGuiWindowFlags_NoScrollbar or 8,
        ImGuiWindowFlags_NoCollapse or 32,
        ImGuiWindowFlags_NoBackground or 128,
        cfg.locked and (ImGuiWindowFlags_NoMove or 4) or 0
    )

    if ctx.resetPosPending then
        imgui.SetNextWindowPos({ cfg.x, cfg.y }, ImGuiCond_Always or 1)
        ctx.resetPosPending = false
    else
        imgui.SetNextWindowPos({ cfg.x, cfg.y }, ImGuiCond_FirstUseEver or 4)
    end
    imgui.SetNextWindowSize({ winW, winH }, ImGuiCond_Always or 1)

    if imgui.Begin('OverlordsSoulHUD##main', true, flags) then
        local wx, wy = imgui.GetWindowPos()
        if not cfg.locked and (math.floor(wx + 0.5) ~= cfg.x or math.floor(wy + 0.5) ~= cfg.y) then
            cfg.x = math.floor(wx + 0.5)
            cfg.y = math.floor(wy + 0.5)
            if callbacks and callbacks.onMove then callbacks.onMove() end
        end

        local dl = imgui.GetWindowDrawList()
        local bgCol = applyAlpha(PALETTE.dark, alpha)
        local hdrCol = applyAlpha(PALETTE.navy, alpha)
        local edgeCol = applyAlpha(PALETTE.edge, alpha)
        local silverCol = applyAlpha(PALETTE.silver, alpha)
        local textCol = applyAlpha(PALETTE.text, alpha)
        local mutedCol = applyAlpha(PALETTE.muted, alpha)
        local trackCol = applyAlpha(PALETTE.track, alpha)
        local accentCol = applyAlpha(soulDef.accentColor or PALETTE.accent, alpha)

        -- Outer frame & header
        dl:AddRectFilled({ wx, wy }, { wx + winW, wy + winH }, bgCol, 5)
        dl:AddRectFilled({ wx, wy }, { wx + winW, wy + headerH }, hdrCol, 5)
        dl:AddRect({ wx, wy }, { wx + winW, wy + winH }, edgeCol, 5, nil, 1)
        dl:AddLine({ wx + 1, wy + headerH }, { wx + winW - 1, wy + headerH }, silverCol, 1)

        local title = string.format('%s • %s', soulDef.jobAbr ~= '' and soulDef.jobAbr or 'SOUL', soulDef.name)
        dl:AddText({ wx + pad, wy + 4 * s }, accentCol, title)

        if ctx.stale or not ctx.synced then
            local tag = ctx.synced and 'STALE' or 'LOCAL'
            dl:AddText({ wx + winW - 78 * s, wy + 4 * s }, applyAlpha(PALETTE.warn, alpha), tag)
        end

        -- Interactive header buttons (Layout + Config)
        imgui.SetCursorScreenPos({ wx + winW - 42 * s, wy + 2 * s })
        if imgui.SmallButton(isCompact and 'C' or 'E') then
            cfg.layout = isCompact and 'expanded' or 'compact'
            if callbacks and callbacks.onSave then callbacks.onSave() end
        end
        imgui.SameLine(0, 2)
        if imgui.SmallButton('*') then
            if callbacks and callbacks.onToggleConfig then callbacks.onToggleConfig() end
        end

        -- Resource rows
        local ry = wy + headerH + 4 * s
        if #visibleRes == 0 then
            dl:AddText({ wx + pad, ry + 2 * s }, mutedCol, 'No active mechanics')
        else
            for _, item in ipairs(visibleRes) do
                local res, st = item.res, item.st
                local warn = isWarning(res, st, ctx)
                local baseCol = warn and (res.warnColor or PALETTE.warn) or (res.color or accentCol)
                local col = applyAlpha(baseCol, alpha)
                local label = isCompact and (res.shortLabel or res.label) or res.label
                local valStr = formatValue(res, st, ctx)

                dl:AddText({ wx + pad, ry + 2 * s }, warn and col or textCol, label)

                local barX = wx + (isCompact and 76 or 106) * s
                local barW = winW - (isCompact and 138 or 178) * s
                local barH = 8 * s
                local barY = ry + (isCompact and 5 or 7) * s

                if res.type == 'stack' then
                    drawSegmented(dl, barX, barY, barW, barH, st.current or 0, res.max or 1, col, trackCol, edgeCol)
                elseif res.type == 'charges' then
                    drawSegmented(dl, barX, barY, barW, barH, st.charges or st.current or 0, res.maxCharges or res.max or 1, col, trackCol, edgeCol)
                elseif res.type == 'gauge' then
                    local span = math.max(1, (res.max or 1) - (res.min or 0))
                    local ratio = ((st.current or 0) - (res.min or 0)) / span
                    drawBar(dl, barX, barY, barW, barH, ratio, col, trackCol, edgeCol)
                elseif res.type == 'cooldown' then
                    local dur = math.max(1, st.duration or res.duration or 1)
                    local rem = math.max(0, st.remaining or 0)
                    local ratio = rem <= 0 and 1 or (1 - clamp(rem / dur, 0, 1))
                    local drawCol = rem <= 0 and applyAlpha(PALETTE.ready, alpha) or col
                    if res.style == 'radial' then
                        drawRadial(dl, barX + 7 * s, ry + (isCompact and 9 or 11) * s, 6 * s, ratio, drawCol, trackCol)
                    else
                        drawBar(dl, barX, barY, barW, barH, ratio, drawCol, trackCol, edgeCol)
                    end
                elseif res.type == 'timer' then
                    local dur = math.max(1, st.duration or res.duration or 1)
                    local rem = math.max(0, st.remaining or 0)
                    drawBar(dl, barX, barY, barW, barH, rem / dur, col, trackCol, edgeCol)
                elseif res.type == 'toggle' or res.type == 'combo' or res.type == 'status' then
                    local dotCol = st.active and col or applyAlpha(PALETTE.unavail, alpha)
                    dl:AddCircleFilled({ barX + 5 * s, ry + (isCompact and 9 or 11) * s }, 4 * s, dotCol, 10)
                end

                dl:AddText({ wx + winW - (isCompact and 58 or 68) * s, ry + 2 * s }, warn and col or textCol, valStr)
                ry = ry + rowH
            end
        end
    end
    imgui.End()
end

function M.renderConfig(imgui, soulDef, cfg, settingsMod, callbacks)
    if not imgui or not callbacks.isConfigOpen() then
        return
    end

    imgui.SetNextWindowSize({ 320, 360 }, ImGuiCond_FirstUseEver or 4)
    local open = { true }
    if imgui.Begin('Overlords Soul HUD Config', open, 0) then
        if imgui.Checkbox('Lock Position', { cfg.locked }) then
            cfg.locked = not cfg.locked
            settingsMod.save(cfg)
        end

        local modes = { 'auto', 'show', 'hide' }
        local modeIdx = 1
        for i, m in ipairs(modes) do if cfg.mode == m then modeIdx = i end end
        if imgui.BeginCombo('Visibility Mode', cfg.mode) then
            for _, m in ipairs(modes) do
                if imgui.Selectable(m, cfg.mode == m) then
                    cfg.mode = m
                    settingsMod.save(cfg)
                end
            end
            imgui.EndCombo()
        end

        local layouts = { 'compact', 'expanded' }
        if imgui.BeginCombo('Layout', cfg.layout) then
            for _, l in ipairs(layouts) do
                if imgui.Selectable(l, cfg.layout == l) then
                    cfg.layout = l
                    settingsMod.save(cfg)
                end
            end
            imgui.EndCombo()
        end

        local scaleArr = { cfg.scale }
        if imgui.SliderFloat('Scale', scaleArr, 0.75, 2.0, '%.2f') then
            cfg.scale = scaleArr[1]
            settingsMod.save(cfg)
        end

        local opArr = { cfg.opacity }
        if imgui.SliderFloat('Opacity', opArr, 0.25, 1.0, '%.2f') then
            cfg.opacity = opArr[1]
            settingsMod.save(cfg)
        end

        if soulDef then
            imgui.Separator()
            imgui.Text(('Elements (%s):'):format(soulDef.name))
            for _, res in ipairs(soulDef.resources or {}) do
                local vis = settingsMod.isElementVisible(cfg, soulDef.key, res.id)
                if imgui.Checkbox(res.label .. '##' .. res.id, { vis }) then
                    settingsMod.setElementVisible(cfg, soulDef.key, res.id, not vis)
                    settingsMod.save(cfg)
                end
            end
        end
    end
    imgui.End()
    if not open[1] then
        callbacks.setConfigOpen(false)
    end
end

return M
