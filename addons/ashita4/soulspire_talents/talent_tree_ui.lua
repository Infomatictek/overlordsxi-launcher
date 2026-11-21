-- SoulspireXI Weapon Skill Talent Tree UI (Classic RPG Overhaul v3.0)
--
-- Visual specification:
--   - Official SoulspireXI website palette (site/styles.css)
--   - Diablo II / Classic WoW dark-fantasy engraved panels & connected nodes
--   - Three-Branch layout with SOUL as the visual centerpiece:
--       [ DAMAGE (Gold) ]   [ ★ SOUL (Violet Centerpiece) ★ ]   [ UTILITY (Cyan) ]
--   - Hover tooltips derived from authoritative server NODE metadata
--   - Compact footprint designed for actual FFXI client resolutions (1060x680 default)
local imgui = require('imgui')
local okArt, artMod = pcall(require, 'art')
local art   = (okArt and type(artMod) == 'table') and artMod or { draw = function() return false end, clear = function() end }
local T     = require('talent_theme')
local S     = require('talent_state')

local UI = {}

local COL_TEXT      = ImGuiCol_Text or 0
local CHILD_NONE    = ImGuiChildFlags_None or 0
local CHILD_BORDERS = ImGuiChildFlags_Borders or ImGuiChildFlags_Border or 1
local WIN_NO_SCROLL = ImGuiWindowFlags_NoScrollbar or 8

local function xy(a, b)
    if type(a) == 'table' then return a[1] or a.x or 0, a[2] or a.y or 0 end
    return a or 0, b or 0
end

local function drawText(str, col)
    local s = tostring(str or '')
    if col and imgui.PushStyleColor then imgui.PushStyleColor(COL_TEXT, col) end
    if imgui.TextUnformatted then
        imgui.TextUnformatted(s)
    else
        imgui.Text((s:gsub('%%', '%%%%')))
    end
    if col and imgui.PopStyleColor then imgui.PopStyleColor() end
end

local function textAt(x, y, str, col)
    imgui.SetCursorScreenPos({ x, y })
    drawText(str, col)
end

local function trunc(str, maxChars)
    local s = tostring(str or '')
    if #s <= maxChars then return s end
    return s:sub(1, math.max(1, maxChars - 2)) .. '..'
end

local function drawPill(dl, x, y, w, h, label, fillCol, borderCol, textCol)
    dl:AddRectFilled({ x, y }, { x + w, y + h }, T.u32(fillCol, imgui), h * 0.45)
    dl:AddRect({ x, y }, { x + w, y + h }, T.u32(borderCol, imgui), h * 0.45, 0, 1.1)
    textAt(x + 8, y + math.floor((h - 16) * 0.5), label, textCol)
end

-- Classic WoW-style floating dark-fantasy hover tooltip
local function renderHoverTooltip(st, node)
    local tip = S.buildTooltipModel(st, node)
    local br = T.BRANCHES[tip.branch] or T.BRANCHES.damage

    if imgui.PushStyleColor then
        imgui.PushStyleColor(ImGuiCol_PopupBg or 4, T.COLORS.abyss)
        imgui.PushStyleColor(ImGuiCol_Border or 5, br.accent)
    end
    if imgui.BeginTooltip then
        imgui.BeginTooltip()
        if imgui.PushTextWrapPos then imgui.PushTextWrapPos(340) end

        -- Title + Rank
        drawText(tip.name, br.accent)
        imgui.SameLine()
        drawText(string.format('  [%d/%d]', tip.rank, tip.maxRank),
            tip.rank >= tip.maxRank and T.COLORS.gold or T.COLORS.textSecond)

        -- Branch & Status subtitle
        drawText(string.format('%s  ·  Tier %d  ·  %s', tip.branchLabel, tip.tier, tip.statusLabel), T.COLORS.textMuted)
        if tip.soulMechanic then
            drawText('Soul Mechanic: ' .. tip.soulMechanic, T.COLORS.violet)
        end

        imgui.Separator()

        -- Current Rank Effect
        if tip.rank > 0 then
            drawText('Current Effect:', T.COLORS.goldWarm)
            drawText(tip.currentEffect, T.COLORS.textPrimary)
        else
            drawText('Effect:', T.COLORS.goldWarm)
            drawText(tip.currentEffect, T.COLORS.textPrimary)
        end

        -- Next Rank Preview (so player knows exact change BEFORE clicking)
        if tip.nextEffect ~= '' and tip.rank > 0 and tip.rank < tip.maxRank then
            imgui.Spacing()
            drawText(string.format('Next Rank (%d/%d):', tip.rank + 1, tip.maxRank), T.COLORS.cyan)
            drawText(tip.nextEffect, T.COLORS.textSecond)
        end

        -- Prerequisites
        if #tip.prereqs > 0 then
            imgui.Spacing()
            for _, pr in ipairs(tip.prereqs) do
                drawText((pr.met and '[OK] ' or '[X] ') .. pr.text, pr.met and T.COLORS.emerald or T.COLORS.rose)
            end
        end

        -- Mutual Exclusion Warning
        if tip.excluded then
            imgui.Spacing()
            drawText('Mutually Exclusive: Locked by ' .. tostring(tip.excludedBy or 'another choice'), T.COLORS.rose)
        elseif node.exclusiveGroup then
            imgui.Spacing()
            drawText('Exclusive Choice: Only one talent may be chosen in this stage.', T.COLORS.goldWarm)
        end

        -- Controls Hint
        imgui.Spacing()
        imgui.Separator()
        if S.isPending(st) then
            drawText('Awaiting server confirmation...', T.COLORS.gold)
        else
            local hints = {}
            if tip.canLearn then hints[#hints + 1] = 'Left-Click: Invest 1 pt' end
            if tip.canRefund then hints[#hints + 1] = 'Right-Click: Refund 1 pt' end
            if #hints == 0 then hints[#hints + 1] = 'Requirements not met' end
            drawText(table.concat(hints, '  |  '), T.COLORS.textMuted)
        end

        if imgui.PopTextWrapPos then imgui.PopTextWrapPos() end
        imgui.EndTooltip()
    end
    if imgui.PopStyleColor then imgui.PopStyleColor(2) end
end

-- Header Bar: SoulspireXI Emblem, Active Soul + Role, Job/Lv, Points, 4-WS Mastery, Selected WS
local function renderHeader(st, actions, winX, winY, winW)
    local dl = imgui.GetWindowDrawList()
    local h = 62
    T.drawEngravedPanel(dl, imgui, winX, winY, winW, h, T.COLORS.surface, T.COLORS.borderGold, T.COLORS.goldWarm, 6)

    -- Official SoulspireXI Emblem (from site/assets/logo.png)
    local ex, ey, es = winX + 10, winY + 9, 44
    dl:AddRectFilled({ ex - 1, ey - 1 }, { ex + es + 1, ey + es + 1 }, T.u32(T.COLORS.abyss, imgui), 6)
    if not art.draw(dl, 'soulspire_emblem', ex, ey, es, es) then
        T.drawNodeGlyph(dl, imgui, ex + es * 0.5, ey + es * 0.5, 16, 'soul', 4, T.COLORS.violet, false)
    end
    dl:AddRect({ ex - 1, ey - 1 }, { ex + es + 1, ey + es + 1 }, T.u32(T.COLORS.borderGold, imgui), 6, 0, 1.3)

    -- Soul Name + Job/Level + Role Badge
    local soulTitle = (st.soulMeta and st.soulMeta.name) or st.specName or 'Base'
    local roleColor = T.ROLE_COLORS[st.role] or T.COLORS.gold
    textAt(ex + es + 12, winY + 10, string.upper(soulTitle), T.COLORS.gold)
    textAt(ex + es + 12, winY + 34,
        string.format('%s Lv.%d  ·  %s', st.jobKey, st.jobLevel, st.role),
        roleColor)

    -- Selected WS Badge (center-left)
    local wsName = (st.wsDetail and st.wsDetail.name) or 'Select a Weapon Skill'
    local wsMeta = (st.wsDetail and string.format('%s  ·  %d/%d pts', st.wsDetail.skillName, st.wsDetail.spent or 0, S.MAX_WS_POINTS)) or ''
    local midX = winX + math.max(250, math.floor(winW * 0.27))
    textAt(midX, winY + 10, wsName, T.COLORS.textPrimary)
    textAt(midX, winY + 34, wsMeta, T.COLORS.cyan)

    -- Right Metrics: Available Points, Invested, 4-WS Mastery + Sync button
    local rightX = winX + winW - 325
    drawPill(dl, rightX, winY + 9, 126, 22,
        string.format('Avail: %d pts', st.avail),
        st.avail > 0 and T.COLORS.goldDeep or T.COLORS.stoneDark,
        st.avail > 0 and T.COLORS.gold or T.COLORS.borderMetal,
        st.avail > 0 and T.COLORS.gold or T.COLORS.textMuted)

    drawPill(dl, rightX + 132, winY + 9, 118, 22,
        string.format('Spent: %d/%d', st.spent, st.earned),
        T.COLORS.stoneDark, T.COLORS.borderMetal, T.COLORS.textSecond)

    local invWs = S.countInvestedWs(st)
    drawPill(dl, rightX, winY + 34, 152, 20,
        string.format('Mastered WSs: %d/%d', invWs, S.MAX_MASTERED_WS),
        T.COLORS.violetDeep, T.COLORS.violetCryst, T.COLORS.textPrimary)

    imgui.SetCursorScreenPos({ winX + winW - 66, winY + 18 })
    if imgui.Button('Sync##ox_sync', { 56, 26 }) then
        actions.sync()
    end

    return h
end

-- Left Sidebar: Strictly Eligible Weapon Skills Grouped by Primary & Signature Families
local function renderWeaponSelector(st, actions, w, h)
    local dl = imgui.GetWindowDrawList()
    local sx, sy = xy(imgui.GetCursorScreenPos())
    T.drawEngravedPanel(dl, imgui, sx, sy, w, h, T.COLORS.surface, T.COLORS.borderMetal, T.COLORS.borderGold, 6)

    textAt(sx + 12, sy + 10, 'ELIGIBLE WEAPONS', T.COLORS.goldWarm)
    if st.soulMeta and st.soulMeta.mechanic then
        textAt(sx + 12, sy + 28, trunc(st.soulMeta.mechanic, 26), T.COLORS.violet)
    end

    -- Compact search + Invested filter
    imgui.SetCursorScreenPos({ sx + 10, sy + 50 })
    imgui.PushItemWidth(w - 20)
    imgui.InputTextWithHint('##ws_search', 'Filter weapon skills...', st.searchBuf, 48)
    imgui.PopItemWidth()

    imgui.SetCursorScreenPos({ sx + 10, sy + 78 })
    imgui.Checkbox('Invested only##ws_inv', st.investedOnly)

    local listY = sy + 106
    imgui.SetCursorScreenPos({ sx + 6, listY })
    if imgui.BeginChild('##ws_list_scroll', { w - 12, math.max(80, h - 114) }, CHILD_NONE) then
        local query = string.lower(st.searchBuf[1] or '')
        local invOnly = st.investedOnly[1] == true

        if #st.weaponGroups == 0 then
            drawText(st.synced and 'No eligible weapon skills.' or 'Syncing with server...', T.COLORS.textMuted)
        else
            for _, grp in ipairs(st.weaponGroups) do
                -- Family Header Pill
                local gx, gy = xy(imgui.GetCursorScreenPos())
                local cdl = imgui.GetWindowDrawList()
                local isPrim = (grp.tierLabel == 'Primary')
                local hdrCol = isPrim and T.COLORS.goldWarm or T.COLORS.cyan
                cdl:AddRectFilled({ gx, gy }, { gx + w - 26, gy + 22 }, T.u32(T.COLORS.elevated, imgui), 4)
                cdl:AddLine({ gx, gy + 22 }, { gx + w - 26, gy + 22 }, T.u32(hdrCol, imgui), 1.2)
                T.drawWeaponGlyph(cdl, imgui, gx + 12, gy + 11, grp.skillId, hdrCol)
                textAt(gx + 24, gy + 3, string.format('%s (%s)', grp.skillName, grp.tierLabel), hdrCol)
                imgui.SetCursorScreenPos({ gx, gy + 26 })

                for _, ws in ipairs(grp.weapons) do
                    local pts = st.spentByWs[ws.id] or 0
                    local matchQ = (query == '' or string.find(string.lower(ws.name), query, 1, true) ~= nil)
                    local matchI = (not invOnly) or pts > 0
                    if matchQ and matchI then
                        local rx, ry = xy(imgui.GetCursorScreenPos())
                        local rw, rh = w - 26, 26
                        local isSel = (st.selectedWsId == ws.id)
                        local isUnl = st.unlockedByWs[ws.id] == true

                        imgui.InvisibleButton('##ws_row_' .. tostring(ws.id), { rw, rh })
                        local hov = imgui.IsItemHovered()
                        if imgui.IsItemClicked(0) and not isSel then
                            actions.selectWs(ws.id)
                        end

                        local rowFill = isSel and T.COLORS.cardHover or (hov and T.COLORS.card or T.COLORS.stoneDark)
                        local rowBord = isSel and T.COLORS.gold or (isUnl and T.COLORS.borderCyan or T.COLORS.borderSubtle)
                        cdl:AddRectFilled({ rx, ry }, { rx + rw, ry + rh }, T.u32(rowFill, imgui), 4)
                        cdl:AddRect({ rx, ry }, { rx + rw, ry + rh }, T.u32(rowBord, imgui), 4, 0, isSel and 1.4 or 0.9)
                        if isSel then
                            cdl:AddRectFilled({ rx + 1, ry + 3 }, { rx + 4, ry + rh - 3 }, T.u32(T.COLORS.gold, imgui), 1)
                        end

                        textAt(rx + 9, ry + 5, trunc(ws.name, 19), isSel and T.COLORS.gold or (isUnl and T.COLORS.textPrimary or T.COLORS.textSecond))
                        if pts > 0 then
                            local pStr = string.format('%d', pts)
                            textAt(rx + rw - 24, ry + 5, pStr, isUnl and T.COLORS.emerald or T.COLORS.goldWarm)
                        end
                        imgui.SetCursorScreenPos({ rx, ry + rh + 3 })
                    end
                end
                imgui.Spacing()
            end
        end
    end
    imgui.EndChild()
end

-- Render a single framed 56x56 RPG Talent Node Tile with WoW-style Rank Badge
local function renderNodeTile(dl, st, actions, node, cx, cy, tileSize, brStyle, pending)
    local half = tileSize * 0.5
    local x, y = math.floor(cx - half), math.floor(cy - half)
    local excluded = S.isExcludedByPeer(st.wsDetail, node)
    local isMax = (node.rank or 0) >= (node.maxRank or 1) and (node.maxRank or 1) > 0
    local isLearned = (node.rank or 0) > 0
    local isAvail = (not isMax) and (not excluded) and node.canLearn
    local isLocked = (not isLearned) and (not isAvail)

    -- Hitbox
    imgui.SetCursorScreenPos({ x, y })
    imgui.InvisibleButton('##node_' .. tostring(node.key), { tileSize, tileSize })
    local hov = imgui.IsItemHovered()
    if imgui.IsItemClicked(0) and not pending then
        if isAvail then
            actions.invest(st.wsDetail.id, node.slot or node.idx)
        end
    elseif imgui.IsItemClicked(1) and not pending then
        if isLearned then
            actions.refund(st.wsDetail.id, node.slot or node.idx)
        end
    end

    -- Outer Soul centerpiece / active glow
    if isLearned or (hov and isAvail) then
        dl:AddRectFilled({ x - 3, y - 3 }, { x + tileSize + 3, y + tileSize + 3 }, T.u32(brStyle.glow, imgui), 8)
    end

    -- Frame & Fill
    local bgCol = isMax and T.COLORS.nodeMaxBg or (isLearned and T.COLORS.nodeLearnBg or (isAvail and T.COLORS.nodeAvailBg or T.COLORS.nodeLockedBg))
    local bordCol = excluded and T.COLORS.rose
        or (isMax and T.COLORS.gold
        or (isLearned and brStyle.accent
        or (isAvail and (hov and T.COLORS.textPrimary or brStyle.accentAlt)
        or T.COLORS.borderMetal)))
    local bordThick = (isLearned or hov) and 2.2 or 1.3

    dl:AddRectFilled({ x, y }, { x + tileSize, y + tileSize }, T.u32(bgCol, imgui), 6)
    dl:AddRect({ x, y }, { x + tileSize, y + tileSize }, T.u32(bordCol, imgui), 6, 0, bordThick)

    -- Optional custom PNG icon, otherwise crisp procedural RPG branch emblem
    local tint = isLocked and T.u32({ 0.45, 0.48, 0.54, 0.85 }, imgui) or 0xFFFFFFFF
    if not art.draw(dl, 'node_' .. tostring(node.key), x + 4, y + 4, tileSize - 8, tileSize - 8, tint) then
        T.drawNodeGlyph(dl, imgui, cx, cy - 2, tileSize * 0.34, brStyle.key, node.tier, brStyle.accent, isLocked)
    end

    -- Mutually exclusive lock overlay ('X')
    if excluded then
        local rc = T.u32(T.COLORS.rose, imgui)
        dl:AddLine({ x + 10, y + 10 }, { x + tileSize - 10, y + tileSize - 10 }, rc, 2.2)
        dl:AddLine({ x + tileSize - 10, y + 10 }, { x + 10, y + tileSize - 10 }, rc, 2.2)
    end

    -- Classic WoW-style Bottom-Right Rank Badge
    local rankStr = isMax and 'MAX' or string.format('%d/%d', node.rank or 0, node.maxRank or 1)
    local bw = isMax and 34 or 28
    local bh = 16
    local bx, by = x + tileSize - bw + 3, y + tileSize - bh + 3
    local badgeBord = isMax and T.COLORS.gold or (isLearned and brStyle.accent or (isAvail and T.COLORS.emerald or T.COLORS.borderMetal))
    local badgeTxt = isMax and T.COLORS.gold or (isLearned and T.COLORS.textPrimary or (isAvail and T.COLORS.emerald or T.COLORS.textDim))
    dl:AddRectFilled({ bx, by }, { bx + bw, by + bh }, T.u32(T.COLORS.abyss, imgui), 4)
    dl:AddRect({ bx, by }, { bx + bw, by + bh }, T.u32(badgeBord, imgui), 4, 0, 1.1)
    textAt(bx + 4, by, rankStr, badgeTxt)

    -- Compact Node Label centered underneath tile
    local shortName = trunc(node.name, 16)
    local approxW = #shortName * 6.8
    textAt(math.floor(cx - approxW * 0.5), y + tileSize + 5, shortName,
        isLearned and brStyle.accent or (isAvail and T.COLORS.textPrimary or T.COLORS.textMuted))

    if hov then
        renderHoverTooltip(st, node)
    end
end

-- Center Three-Branch Connected Tree Canvas (Damage | SOUL Centerpiece | Utility)
local function renderThreeBranchCanvas(st, actions, w, h)
    local dl = imgui.GetWindowDrawList()
    local cx0, cy0 = xy(imgui.GetCursorScreenPos())
    local detail = st.wsDetail

    T.drawEngravedPanel(dl, imgui, cx0, cy0, w, h, T.COLORS.abyss, T.COLORS.borderMetal, T.COLORS.borderGold, 6)

    if not detail then
        textAt(cx0 + 24, cy0 + 24, st.synced and 'Select an eligible Weapon Skill on the left.' or 'Loading Soul talent trees...', T.COLORS.textMuted)
        return
    end

    local isEvo = S.isEvolutionTree(detail)
    local pending = S.isPending(st)

    -- Reserve bottom 44px for compact Skillchain Augment Strip
    local scBarH = 42
    local treeH = h - scBarH - 12
    local pad = 10

    if isEvo then
        -- 5-Stage Evolution Connected Tree (Combo #1 / Sanguine Blade #47)
        local hdrH = 38
        textAt(cx0 + 16, cy0 + 10, string.format('%s  —  5-STAGE EVOLUTION PATH', string.upper(detail.name)), T.COLORS.gold)
        dl:AddLine({ cx0 + 12, cy0 + hdrH }, { cx0 + w - 12, cy0 + hdrH }, T.u32(T.COLORS.borderGold, imgui), 1.1)

        local stageNodes = {}
        for _, n in ipairs(detail.nodes) do
            if (n.scTier or 0) == 0 then
                local stg = n.tier or 1
                stageNodes[stg] = stageNodes[stg] or {}
                stageNodes[stg][#stageNodes[stg] + 1] = n
            end
        end

        local rowH = math.floor((treeH - hdrH - 12) / 5)
        local leftX = cx0 + math.floor(w * 0.34)
        local rightX = cx0 + math.floor(w * 0.66)
        local midX = cx0 + math.floor(w * 0.50)

        -- Draw vertical spine & horizontal exclusive bars first
        for stg = 1, 5 do
            local ry = cy0 + hdrH + math.floor((stg - 0.5) * rowH) + 6
            textAt(cx0 + 16, ry - 8, string.format('STAGE %d', stg), T.COLORS.textMuted)
            if stg < 5 then
                local nextY = cy0 + hdrH + math.floor((stg + 0.5) * rowH) + 6
                dl:AddLine({ midX, ry }, { midX, nextY }, T.u32(T.COLORS.borderGold, imgui), 1.6)
            end
            local pair = stageNodes[stg] or {}
            if #pair >= 2 then
                local anyChosen = ((pair[1].rank or 0) > 0) or ((pair[2].rank or 0) > 0)
                local barCol = anyChosen and T.COLORS.rose or T.COLORS.borderMetal
                dl:AddLine({ leftX + 28, ry }, { rightX - 28, ry }, T.u32(barCol, imgui), 1.6)
                drawPill(dl, midX - 18, ry - 9, 36, 18, 'OR', T.COLORS.abyss, barCol, anyChosen and T.COLORS.rose or T.COLORS.goldWarm)
            end
        end

        for stg = 1, 5 do
            local ry = cy0 + hdrH + math.floor((stg - 0.5) * rowH) + 6
            local pair = stageNodes[stg] or {}
            if pair[1] then renderNodeTile(dl, st, actions, pair[1], leftX, ry, 50, T.BRANCHES.damage, pending) end
            if pair[2] then renderNodeTile(dl, st, actions, pair[2], rightX, ry, 50, T.BRANCHES.soul, pending) end
        end
    else
        -- Standard 3-Branch Classic RPG Layout:
        --   Visual Order: Left = DAMAGE (Gold) | Center = SOUL (Violet Centerpiece) | Right = UTILITY (Cyan)
        local colGap = 10
        local innerW = w - pad * 2 - colGap * 2
        local sideW  = math.floor(innerW * 0.305)
        local centerW = innerW - sideW * 2 -- Soul centerpiece slightly wider (~39%)

        local branchCols = {
            { branch = T.BRANCHES.damage,  serverCol = 1, x = cx0 + pad,                             w = sideW },
            { branch = T.BRANCHES.soul,    serverCol = 3, x = cx0 + pad + sideW + colGap,            w = centerW },
            { branch = T.BRANCHES.utility, serverCol = 2, x = cx0 + pad + sideW + centerW + colGap*2, w = sideW },
        }

        local colTop = cy0 + pad
        local colH = treeH - pad
        local hdrH = 46
        local tierAreaH = colH - hdrH - 8
        local tierStep = math.floor(tierAreaH / 4)

        -- 1. Draw the 3 Branch Panels (with Soul Violet Centerpiece framing)
        local colByServer = {}
        for _, bc in ipairs(branchCols) do
            colByServer[bc.serverCol] = bc
            local isSoul = bc.branch.centerpiece == true
            if isSoul then
                dl:AddRectFilled({ bc.x - 2, colTop - 2 }, { bc.x + bc.w + 2, colTop + colH + 2 }, T.u32(T.COLORS.violetGlow, imgui), 8)
            end
            T.drawEngravedPanel(dl, imgui, bc.x, colTop, bc.w, colH,
                bc.branch.panelBg,
                isSoul and T.COLORS.violet or T.COLORS.borderMetal,
                bc.branch.accent, 6)

            -- Branch Header Banner
            local sub = isSoul and ((st.soulMeta and st.soulMeta.mechanic) or bc.branch.subtitle) or bc.branch.subtitle
            local titleStr = isSoul and ('* ' .. bc.branch.title .. ' *') or bc.branch.title
            textAt(bc.x + 14, colTop + 8, titleStr, bc.branch.accent)
            textAt(bc.x + 14, colTop + 26, trunc(sub, isSoul and 30 or 22), T.COLORS.textMuted)
            dl:AddLine({ bc.x + 10, colTop + hdrH }, { bc.x + bc.w - 10, colTop + hdrH }, T.u32(bc.branch.accent, imgui), isSoul and 1.8 or 1.1)
        end

        -- Subtle horizontal Tier Gate Dividers across all 3 columns
        local tierLabels = { 'I', 'II', 'III', 'IV' }
        for tIdx = 1, 4 do
            local ty = colTop + hdrH + math.floor((tIdx - 1) * tierStep)
            if tIdx > 1 then
                dl:AddLine({ cx0 + pad + 4, ty }, { cx0 + w - pad - 4, ty }, T.u32(T.COLORS.borderSubtle, imgui), 1.0)
            end
            textAt(cx0 + pad + 6, ty + 4, 'T' .. tierLabels[tIdx], T.COLORS.textDim)
        end

        -- Compute exact screen positions for every non-SC node
        local isCompact = tierStep < 94
        local nodePos = {}
        local treeNodes = {}
        for _, n in ipairs(detail.nodes) do
            if (n.scTier or 0) == 0 then
                local bc = colByServer[n.col or 1]
                if bc then
                    local tier = math.max(1, math.min(4, n.tier or 1))
                    local tileSz = bc.branch.centerpiece and (isCompact and 48 or 56) or (isCompact and 44 or 52)
                    local nx = bc.x + math.floor(bc.w * 0.5)
                    local ny = colTop + hdrH + math.floor((tier - 0.5) * tierStep) - 6
                    nodePos[n.key] = { x = nx, y = ny, bc = bc, tileSz = tileSz }
                    treeNodes[#treeNodes + 1] = n
                end
            end
        end

        -- 2. Draw Genuine Progression Connection Lines BEFORE Node Tiles (below label to avoid text overlap)
        local edges = S.buildConnections(detail)
        for _, edge in ipairs(edges) do
            local p1 = nodePos[edge.from.key]
            local p2 = nodePos[edge.to.key]
            if p1 and p2 then
                local brStyle = p2.bc.branch
                local unlocked = (edge.from.rank or 0) > 0 and (edge.to.rank or 0) > 0
                local avail = (edge.from.rank or 0) > 0 and edge.to.canLearn
                local lCol = unlocked and brStyle.accent or (avail and brStyle.accentAlt or T.COLORS.lineLocked)
                local thick = unlocked and 2.6 or (avail and 2.0 or 1.4)
                local yStart = p1.y + math.floor(p1.tileSz * 0.5) + 19
                local yEnd   = p2.y - math.floor(p2.tileSz * 0.5) - 2
                if yStart < yEnd then
                    if unlocked then
                        dl:AddLine({ p1.x, yStart }, { p2.x, yEnd }, T.u32(brStyle.glow, imgui), 6.0)
                    end
                    dl:AddLine({ p1.x, yStart }, { p2.x, yEnd }, T.u32(lCol, imgui), thick)
                end
            end
        end

        -- 3. Draw Framed RPG Talent Nodes
        for _, n in ipairs(treeNodes) do
            local p = nodePos[n.key]
            renderNodeTile(dl, st, actions, n, p.x, p.y, p.tileSz, p.bc.branch, pending)
        end
    end

    -- Compact Skillchain Augment Strip along bottom of tree canvas
    local scY = cy0 + h - scBarH - 4
    dl:AddRectFilled({ cx0 + pad, scY }, { cx0 + w - pad, scY + scBarH }, T.u32(T.COLORS.surface, imgui), 5)
    dl:AddRect({ cx0 + pad, scY }, { cx0 + w - pad, scY + scBarH }, T.u32(T.COLORS.borderMetal, imgui), 5, 0, 1.0)
    textAt(cx0 + pad + 10, scY + 12, 'SKILLCHAINS:', T.COLORS.goldWarm)

    local scX = cx0 + pad + 112
    local scNodes = {}
    for _, n in ipairs(detail.nodes) do
        if (n.scTier or 0) > 0 then scNodes[#scNodes + 1] = n end
    end
    table.sort(scNodes, function(a, b) return (a.scTier or 0) < (b.scTier or 0) end)
    local chipW = math.min(220, math.floor((w - pad * 2 - 122) / math.max(1, #scNodes)) - 6)
    for _, sn in ipairs(scNodes) do
        local label = string.format('T%d: %s (%d/%d)', sn.scTier, (sn.scName ~= '' and sn.scName or 'None'), sn.rank or 0, sn.maxRank or 2)
        imgui.SetCursorScreenPos({ scX, scY + 8 })
        if imgui.Button(trunc(label, 28) .. '##sc_' .. tostring(sn.scTier), { chipW, 26 }) then
            if (sn.rank or 0) > 0 or isEvo then
                actions.cycleSc(detail.id, sn.scTier, 1)
            elseif sn.canLearn and not pending then
                actions.invest(detail.id, sn.slot or sn.idx)
            end
        end
        if imgui.IsItemHovered() then
            renderHoverTooltip(st, sn)
        end
        scX = scX + chipW + 6
    end
end

-- Compact Footer Bar: Reset WS, Reset All (with 2-step confirmation), Feedback Toast, Close
local function renderFooter(st, actions, winX, footY, winW)
    local dl = imgui.GetWindowDrawList()
    local h = 42
    T.drawEngravedPanel(dl, imgui, winX, footY, winW, h, T.COLORS.surface, T.COLORS.borderMetal, nil, 6)

    local now = os.clock()
    if st.confirmResetWs and (now - st.confirmResetWsAt) > 4.0 then st.confirmResetWs = false end
    if st.confirmResetAll and (now - st.confirmResetAt) > 4.0 then st.confirmResetAll = false end

    imgui.SetCursorScreenPos({ winX + 10, footY + 8 })
    if st.wsDetail then
        local lbl = st.confirmResetWs and 'Confirm Reset WS?' or 'Reset WS'
        if imgui.Button(lbl .. '##btn_rws', { st.confirmResetWs and 140 or 86, 26 }) then
            if st.confirmResetWs then
                st.confirmResetWs = false
                actions.resetWs(st.wsDetail.id)
            else
                st.confirmResetWs = true
                st.confirmResetWsAt = now
            end
        end
        imgui.SameLine()
    end

    local allLbl = st.confirmResetAll and 'Confirm Reset All?' or 'Reset All'
    if imgui.Button(allLbl .. '##btn_rall', { st.confirmResetAll and 144 or 86, 26 }) then
        if st.confirmResetAll then
            st.confirmResetAll = false
            actions.resetAll()
        else
            st.confirmResetAll = true
            st.confirmResetAt = now
        end
    end

    -- Server feedback toast
    if st.statusText and (now - (st.statusTime or 0)) <= 4.5 then
        local col = (st.statusKind == 'err' and T.COLORS.rose)
            or (st.statusKind == 'ok' and T.COLORS.emerald)
            or (st.statusKind == 'pending' and T.COLORS.gold)
            or T.COLORS.textSecond
        imgui.SameLine()
        drawText('   ' .. st.statusText, col)
    end

    imgui.SetCursorScreenPos({ winX + winW - 76, footY + 8 })
    if imgui.Button('Close##ox_close', { 66, 26 }) then
        st.open[1] = false
    end
end

function UI.render(st, actions)
    local winX, winY = xy(imgui.GetCursorScreenPos())
    local availW, availH = xy(imgui.GetContentRegionAvail())
    if availW < 760 then availW = 760 end
    if availH < 500 then availH = 500 end

    local hdrH = renderHeader(st, actions, winX, winY, availW)
    local footH = 42
    local gap = 8
    local bodyY = winY + hdrH + gap
    local bodyH = math.max(360, availH - hdrH - footH - gap * 2)
    local sideW = math.min(240, math.max(200, math.floor(availW * 0.22)))
    local treeW = availW - sideW - gap

    imgui.SetCursorScreenPos({ winX, bodyY })
    renderWeaponSelector(st, actions, sideW, bodyH)

    imgui.SetCursorScreenPos({ winX + sideW + gap, bodyY })
    renderThreeBranchCanvas(st, actions, treeW, bodyH)

    renderFooter(st, actions, winX, bodyY + bodyH + gap, availW)
end

function UI.unload()
    art.clear()
end

return UI
