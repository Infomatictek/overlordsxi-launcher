--[[
* OverlordsXI - Weaponskill Talent Tree Addon for Ashita v4
*
* Communicates silently with the LandSandBoat !talent command using
* [OXTAL]|... tagged 0x017 packets (blocked from the chat log).
*
* Commands:
*   /talents         - Toggle the talent tree window
*   /tal             - Alias for /talents
*   /talents sync    - Force resync catalog & points from server
--]]

addon.name    = 'overlords_talents'
addon.author  = 'OverlordsXI'
addon.version = '1.0.0'
addon.desc    = 'Per-weaponskill talent tree UI for OverlordsXI.'

require('common')
local bit   = require('bit')
local imgui = require('imgui')

local PROTO_TAG         = '[OXTAL]|'
local PACKET_C2S_ID     = 0x11F
local PACKET_S2C_ID     = 0x1FD
local OP_SYNC           = 1
local OP_STATE          = 2
local OP_WS             = 3
local OP_INVEST         = 4
local OP_REFUND         = 5
local OP_CYCLE_SC       = 6
local OP_RESET_WS       = 7
local OP_RESET_ALL      = 8
local CHILD_NONE        = ImGuiChildFlags_None or 0
local CHILD_BORDERS     = ImGuiChildFlags_Borders or ImGuiChildFlags_Border or 1
local COL_TEXT          = ImGuiCol_Text or 0
local COL_TEXT_DISABLED = { 0.62, 0.64, 0.68, 1.00 }

local function drawText(str)
    local s = tostring(str or '')
    if imgui.TextUnformatted then
        imgui.TextUnformatted(s)
    else
        imgui.Text((s:gsub('%%', '%%%%')))
    end
end

local function drawTextColored(col, str)
    local s = tostring(str or '')
    if imgui.TextUnformatted and imgui.PushStyleColor and imgui.PopStyleColor then
        imgui.PushStyleColor(COL_TEXT, col)
        local ok, err = pcall(imgui.TextUnformatted, s)
        imgui.PopStyleColor()
        if not ok then
            error(err)
        end
    else
        imgui.TextColored(col, (s:gsub('%%', '%%%%')))
    end
end

local function drawTextDisabled(str)
    drawTextColored(COL_TEXT_DISABLED, str)
end

local SKILL_LIST =
{
    { id = -1, name = 'Equipped' },
    { id = 0,  name = 'All Weapons' },
    { id = 1,  name = 'Hand-to-Hand' },
    { id = 2,  name = 'Dagger' },
    { id = 3,  name = 'Sword' },
    { id = 4,  name = 'Great Sword' },
    { id = 5,  name = 'Axe' },
    { id = 6,  name = 'Great Axe' },
    { id = 7,  name = 'Scythe' },
    { id = 8,  name = 'Polearm' },
    { id = 9,  name = 'Katana' },
    { id = 10, name = 'Great Katana' },
    { id = 11, name = 'Club' },
    { id = 12, name = 'Staff' },
    { id = 25, name = 'Archery' },
    { id = 26, name = 'Marksmanship' },
    { id = 27, name = 'Throwing' },
}

local state =
{
    open            = { false },
    synced          = false,
    syncRequestedAt = 0,
    jobKey          = '---',
    specName        = 'Base',
    jobLevel        = 1,
    avail           = 0,
    spent           = 0,
    earned          = 1,
    mainSkill       = 0,
    rangedSkill     = 0,
    catalog         = {},       -- ordered list of { id, skill, name, wsType }
    catalogById     = {},
    tempCatalog     = nil,
    spentByWs       = {},
    unlockedByWs    = {},
    tempSpent       = nil,
    tempUnlocked    = nil,
    selectedSkill   = -1,       -- -1 = Equipped
    selectedWsId    = nil,
    wsDetail        = nil,      -- { id, name, skillName, wsType, spent, orig, nodes = {} }
    tempWs          = nil,
    searchBuf       = { '' },
    investedOnly    = { false },
    confirmResetAll = false,
    confirmResetAt  = 0,
    statusText      = nil,
    statusTime      = 0,
    lastKnownJob    = nil,
    lastKnownLvl    = nil,
    lastAutoCheck   = 0,
    inspectedNodeKey = nil,
    renderError     = nil,
}

local function abgr(r, g, b, a)
    if imgui.ColorConvertFloat4ToU32 then
        return imgui.ColorConvertFloat4ToU32({ r, g, b, a or 1.0 })
    end
    local val = bit.bor(
        bit.lshift(math.floor((a or 1) * 255), 24),
        bit.lshift(math.floor(b * 255), 16),
        bit.lshift(math.floor(g * 255), 8),
        math.floor(r * 255)
    )
    if val < 0 then
        val = val + 4294967296
    end
    return val
end

local function toXY(a, b)
    if type(a) == 'table' then
        return a[1] or a.x or 0, a[2] or a.y or 0
    end
    return a or 0, b or 0
end

local function splitPipe(str)
    local out = {}
    local start = 1
    while true do
        local pos = string.find(str, '|', start, true)
        if not pos then
            table.insert(out, string.sub(str, start))
            break
        end
        table.insert(out, string.sub(str, start, pos - 1))
        start = pos + 1
    end
    return out
end

local function sendTalentPacket(op, wsId, arg1, arg2)
    local w = tonumber(wsId) or 0
    local a1 = (tonumber(arg1) or 0) % 256
    local a2 = (tonumber(arg2) or 0) % 256
    local pkt = string.char(0x1F, 0x09, 0x00, 0x00)
        .. 'OXTL'
        .. string.char(1, op % 256, w % 256, math.floor(w / 256) % 256, a1, a2, 0, 0)
    local bytes = { pkt:byte(1, #pkt) }
    AshitaCore:GetPacketManager():AddOutgoingPacket(PACKET_C2S_ID, bytes)
end

local function setStatus(msg)
    state.statusText = msg
    state.statusTime = os.clock()
end

local function requestWS(wsId)
    if wsId == nil then
        return
    end
    state.selectedWsId = wsId
    sendTalentPacket(OP_WS, wsId, 0, 0)
end

local function requestFullSync()
    state.syncRequestedAt = os.clock()
    sendTalentPacket(OP_SYNC, 0, 0, 0)
end

-----------------------------------
-- Protocol Parser
-----------------------------------
local function handleProtoLine(payload)
    local parts = splitPipe(payload)
    local kind = parts[1]

    if kind == 'META' then
        local prevJob  = state.jobKey
        local prevSpec = state.specName
        state.jobKey      = parts[2] or '---'
        state.jobLevel    = tonumber(parts[3]) or 1
        state.avail       = tonumber(parts[4]) or 0
        state.spent       = tonumber(parts[5]) or 0
        state.earned      = tonumber(parts[6]) or 1
        state.mainSkill   = tonumber(parts[7]) or 0
        state.rangedSkill = tonumber(parts[8]) or 0
        state.specName    = (parts[9] and parts[9] ~= '') and parts[9] or 'Base'
        if (prevJob ~= state.jobKey or prevSpec ~= state.specName) and state.selectedWsId ~= nil and state.open[1] then
            requestWS(state.selectedWsId)
        end
    elseif kind == 'SPENT_BEGIN' then
        state.tempSpent    = {}
        state.tempUnlocked = {}
    elseif kind == 'SPENT' then
        state.tempSpent    = state.tempSpent or {}
        state.tempUnlocked = state.tempUnlocked or {}
        if parts[2] and parts[2] ~= '' then
            for entry in string.gmatch(parts[2], '([^,]+)') do
                local wsId, pts, unl = string.match(entry, '^(%d+):(%d+):(%d+)$')
                if not wsId then
                    wsId, pts = string.match(entry, '^(%d+):(%d+)$')
                    unl = (tonumber(pts) or 0) > 0 and '1' or '0'
                end
                if wsId and pts then
                    local idNum = tonumber(wsId)
                    state.tempSpent[idNum]    = tonumber(pts)
                    state.tempUnlocked[idNum] = (tonumber(unl) or 0) == 1
                end
            end
        end
    elseif kind == 'SPENT_END' then
        if state.tempSpent ~= nil then
            state.spentByWs    = state.tempSpent
            state.unlockedByWs = state.tempUnlocked or {}
            state.tempSpent    = nil
            state.tempUnlocked = nil
        end
    elseif kind == 'CAT_BEGIN' then
        state.tempCatalog = {}
    elseif kind == 'CAT' then
        state.tempCatalog = state.tempCatalog or {}
        if parts[2] and parts[2] ~= '' then
            for entry in string.gmatch(parts[2], '([^,]+)') do
                local wsId, skillId, name, wsType = string.match(entry, '^(%d+):(%d+):(.+):([^:]+)$')
                if wsId then
                    table.insert(state.tempCatalog,
                    {
                        id     = tonumber(wsId),
                        skill  = tonumber(skillId),
                        name   = name,
                        wsType = wsType,
                    })
                end
            end
        end
    elseif kind == 'CAT_END' then
        if state.tempCatalog ~= nil then
            state.catalog = state.tempCatalog
            state.catalogById = {}
            for _, ws in ipairs(state.catalog) do
                state.catalogById[ws.id] = ws
            end
            state.tempCatalog = nil
            state.synced = true
            if state.selectedWsId == nil then
                for _, ws in ipairs(state.catalog) do
                    if ws.skill == state.mainSkill or ws.skill == state.rangedSkill then
                        requestWS(ws.id)
                        break
                    end
                end
            elseif state.wsDetail == nil or state.wsDetail.id ~= state.selectedWsId then
                requestWS(state.selectedWsId)
            end
        end
    elseif kind == 'WS' then
        state.tempWs =
        {
            id        = tonumber(parts[2]),
            name      = parts[3] or 'Unknown',
            skillName = parts[4] or '',
            wsType    = parts[5] or 'physical',
            spent     = tonumber(parts[6]) or 0,
            orig      = parts[7] or '',
            nodes     = {},
            byKey     = {},
        }
    elseif kind == 'NODE' then
        if state.tempWs ~= nil and tonumber(parts[2]) == state.tempWs.id then
            local nodeIdx = #state.tempWs.nodes + 1
            local node =
            {
                idx         = nodeIdx,
                key         = parts[3],
                tier        = tonumber(parts[4]) or 1,
                col         = tonumber(parts[5]) or 1,
                rank        = tonumber(parts[6]) or 0,
                maxRank     = tonumber(parts[7]) or 1,
                canLearn    = (tonumber(parts[8]) or 0) == 1,
                reqWsPoints = tonumber(parts[9]) or 0,
                reqKey      = parts[10] ~= '' and parts[10] or nil,
                reqRank     = tonumber(parts[11]) or 0,
                name        = parts[12] or parts[3],
                desc        = parts[13] or '',
                reqLevel    = tonumber(parts[14]) or 1,
                scTier      = tonumber(parts[15]) or 0,
                scId        = tonumber(parts[16]) or 0,
                scName      = parts[17] or '',
            }
            table.insert(state.tempWs.nodes, node)
            state.tempWs.byKey[node.key] = node
        end
    elseif kind == 'WS_END' then
        if state.tempWs ~= nil and tonumber(parts[2]) == state.tempWs.id then
            state.avail = tonumber(parts[3]) or state.avail
            state.wsDetail = state.tempWs
            state.tempWs = nil
        end
    elseif kind == 'ERR' then
        setStatus(parts[2] or 'Action failed.')
    end
end

-----------------------------------
-- Ashita Events
-----------------------------------
ashita.events.register('load', 'ox_talents_load', function()
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if player ~= nil and player:GetMainJob() > 0 then
        local getLvl = player.GetMainJobLevel or player.GetMainLevel
        state.lastKnownJob = player:GetMainJob()
        state.lastKnownLvl = getLvl and getLvl(player) or 1
    end
end)

ashita.events.register('command', 'ox_talents_cmd', function(e)
    local args = e.command:args()
    if #args == 0 then
        return
    end

    local cmd = string.lower(args[1])
    if cmd ~= '/talents' and cmd ~= '/tal' then
        return
    end

    e.blocked = true

    if args[2] ~= nil and string.lower(args[2]) == 'sync' then
        requestFullSync()
        setStatus('Syncing weaponskill talents from server...')
        return
    end

    state.open[1] = not state.open[1]
    if state.open[1] then
        if not state.synced then
            requestFullSync()
        else
            sendTalentPacket(OP_STATE, 0, 0, 0)
            if state.selectedWsId ~= nil then
                requestWS(state.selectedWsId)
            end
        end
    end
end)

ashita.events.register('packet_in', 'ox_talents_packet_in', function(e)
    if e.id == PACKET_S2C_ID then
        local buf = e.data_modified or e.data
        local sz  = e.size or (type(buf) == 'string' and #buf or 0)
        if type(buf) == 'string' and sz >= 12 and buf:sub(5, 8) == 'OXTL' then
            e.blocked = true
            local b11, b12 = buf:byte(11, 12)
            local payLen = (b11 or 0) + (b12 or 0) * 256
            if payLen > 0 and #buf >= 12 + payLen then
                local line = buf:sub(13, 12 + payLen)
                if line:sub(1, #PROTO_TAG) == PROTO_TAG then
                    line = line:sub(#PROTO_TAG + 1)
                end
                handleProtoLine(line)
            end
            return
        end
    end

    if e.id ~= 0x017 then
        return
    end

    if #e.data < 25 then
        return
    end

    local msg = string.sub(e.data, 24):match('^([^%z]*)')
    if msg == nil or string.sub(msg, 1, #PROTO_TAG) ~= PROTO_TAG then
        return
    end

    e.blocked = true
    handleProtoLine(string.sub(msg, #PROTO_TAG + 1))
end)

-----------------------------------
-- ImGui Tree Renderer
-----------------------------------
local function getFilteredCatalog()
    local list = {}
    local rawQuery = (state.searchBuf[1] or ''):gsub('%z.*$', '')
    local query = string.lower(rawQuery)
    local sk = state.selectedSkill

    for _, ws in ipairs(state.catalog) do
        local matchSkill = false
        if sk == 0 then
            matchSkill = true
        elseif sk == -1 then
            matchSkill = (ws.skill == state.mainSkill) or (state.rangedSkill ~= 0 and ws.skill == state.rangedSkill)
        else
            matchSkill = (ws.skill == sk)
        end

        if matchSkill then
            local spent = state.spentByWs[ws.id] or 0
            local matchInvested = (not state.investedOnly[1]) or (spent > 0)
            local matchQuery = (query == '') or (string.find(string.lower(ws.name), query, 1, true) ~= nil)
            if matchInvested and matchQuery then
                table.insert(list, ws)
            end
        end
    end

    return list
end

local function isWsUnlockedInDetail(detail)
    if detail == nil then
        return false
    end
    for _, node in ipairs(detail.nodes or {}) do
        if node.tier == 1 and (node.rank or 0) >= 1 then
            return true
        end
    end
    return state.unlockedByWs[detail.id] == true
end

-- FFXI / CrystalSocket-inspired Palette (packed ABGR for ImGui DrawList)
local THEME =
{
    bgDark       = 0xFF140D0A,
    bgPanel      = 0xFF21150F,
    bgCardMax    = 0xFF2B2213,
    bgCardActive = 0xFF1A2530,
    bgCardAvail  = 0xFF17271D,
    bgCardLocked = 0xFF171312,
    edge         = 0xFF523929,
    silver       = 0xFFAD9789,
    shadow       = 0x77000000,
    gold         = 0xFFD9C38C,
    goldBright   = 0xFFE8CA62,
    goldGlow     = 0x44E8CA62,
    cyan         = 0xFFEFBA52, -- ABGR: warm sky-azure (R=82,G=186,B=239)
    green        = 0xFF6EE072, -- ABGR: emerald (R=114,G=224,B=110)
    red          = 0xFF6868F0, -- ABGR: soft crimson (R=240,G=104,B=104)
    muted        = 0xFF7B6557,
    text         = 0xFFE2E8E9,
    secondary    = 0xFFB8A89C,
    linkInactive = 0x88523929,
    barBg        = 0xFF0E0907,
}

local function formatReadableDesc(raw)
    local s = tostring(raw or '')
    if s == '' then
        return 'No description available.'
    end
    s = s:gsub('NextWS', 'Next WS')
    s = s:gsub('CrDmg', 'Crit Dmg')
    s = s:gsub('DEF Ignored', 'DEF Ignore')
    s = s:gsub('DEF Ign', 'DEF Ignore')
    s = s:gsub('SC Dmg', 'Skillchain Dmg')
    s = s:gsub('M%.Def', 'Magic Def')
    s = s:gsub('MDEF', 'Magic Def')
    s = s:gsub('M%.Eva', 'Magic Eva')
    s = s:gsub('MEVA', 'Magic Eva')
    s = s:gsub('M%.Atk', 'Magic Atk')
    s = s:gsub('fTP ALL Hits', 'fTP All Hits')
    s = s:gsub('fTP ALL', 'fTP All Hits')
    s = s:gsub('(%d)h([,%s])', '%1 Hits%2')
    s = s:gsub('(%d)h$', '%1 Hits')
    s = s:gsub('STP', 'Store TP')
    s = s:gsub('Pet Heal', 'Pet/Eos Heal')
    return s
end

local function wrapLines(str, maxChars)
    local lines = {}
    local cur = ''
    for word in tostring(str or ''):gmatch('%S+') do
        if cur == '' then
            cur = word
        elseif #cur + 1 + #word <= maxChars then
            cur = cur .. ' ' .. word
        else
            table.insert(lines, cur)
            cur = word
        end
    end
    if cur ~= '' then
        table.insert(lines, cur)
    end
    return lines
end

local function drawBevelPanel(dl, x, y, w, h, fillCol, outerCol, innerCol, rounding)
    local r = rounding or 5.0
    dl:AddRectFilled({ x + 2, y + 3 }, { x + w + 2, y + h + 3 }, THEME.shadow, r)
    dl:AddRectFilled({ x, y }, { x + w, y + h }, fillCol, r)
    dl:AddRect({ x, y }, { x + w, y + h }, outerCol, r, 0, 1.5)
    dl:AddRect({ x + 1, y + 1 }, { x + w - 1, y + h - 1 }, innerCol or THEME.edge, math.max(1.0, r - 1.0), 0, 1.0)
end

local function getNodeRequirements(node, detail)
    local reqs = {}
    local lvl = node.reqLevel or 1
    local lvlOk = state.jobLevel >= lvl
    table.insert(reqs, {
        ok = lvlOk,
        text = string.format('Level %d+ %s (Current: %d)', lvl, state.jobKey, state.jobLevel),
        short = string.format('Lv.%d', lvl),
    })
    if (node.reqWsPoints or 0) > 0 then
        local ptsOk = detail.spent >= node.reqWsPoints
        table.insert(reqs, {
            ok = ptsOk,
            text = string.format('%d+ points in %s (Current: %d)', node.reqWsPoints, detail.name, detail.spent),
            short = string.format('%d WS pts', node.reqWsPoints),
        })
    end
    if node.reqKey ~= nil then
        local pNode = detail.byKey[node.reqKey]
        if pNode ~= nil then
            local pOk = pNode.rank >= (node.reqRank or 1)
            table.insert(reqs, {
                ok = pOk,
                text = string.format('%s Rank %d+ (Current: %d)', pNode.name, node.reqRank or 1, pNode.rank),
                short = string.format('%s R%d', pNode.name, node.reqRank or 1),
            })
        end
    end
    return reqs
end

local function drawNodeTooltip(node, detail, isMaxed, isScNode, titleCol)
    local readable = formatReadableDesc(node.desc)
    local reqs = getNodeRequirements(node, detail)
    local tierNames = { 'Tier 1 — Foundation', 'Tier 2 — Specialization', 'Tier 3 — Mastery', 'Tier 4 — Capstone' }

    imgui.BeginTooltip()
    local okTip, errTip = pcall(function()
        drawTextColored(titleCol, string.format('%s   [%d / %d]', node.name, node.rank, node.maxRank))
        drawTextDisabled(tierNames[node.tier] or ('Tier ' .. tostring(node.tier)))
        imgui.Separator()
        imgui.PushTextWrapPos(340)
        local okWrap, errWrap = pcall(function()
            if node.rank > 0 then
                drawTextColored({ 0.55, 0.95, 0.65, 1.0 }, 'Active Effect:')
            else
                drawTextColored({ 0.85, 0.78, 0.55, 1.0 }, 'Effect Preview:')
            end
            drawText(readable)
            imgui.Spacing()

            if isScNode then
                local scLabel = (node.scName ~= '' and node.scName) or 'None'
                drawTextColored({ 0.65, 0.85, 1.0, 1.0 }, 'Selected Skillchain: ' .. scLabel)
                drawTextDisabled('Use < / > on the card to cycle Skillchain properties.')
                imgui.Spacing()
            end

            if not isMaxed then
                imgui.Separator()
                drawTextColored({ 0.85, 0.78, 0.55, 1.0 }, string.format('Next Rank (%d/%d) Requirements:', node.rank + 1, node.maxRank))
                for _, req in ipairs(reqs) do
                    if req.ok then
                        drawTextColored({ 0.42, 0.88, 0.50, 1.0 }, '  [OK] ' .. req.text)
                    else
                        drawTextColored({ 1.00, 0.45, 0.45, 1.0 }, '  [X]  ' .. req.text)
                    end
                end
            else
                imgui.Separator()
                drawTextColored({ 1.00, 0.85, 0.35, 1.0 }, 'Maximum Rank Reached')
            end

            imgui.Spacing()
            drawTextDisabled('Left-Click: +1 Rank   |   Right-Click: -1 Rank')
        end)
        imgui.PopTextWrapPos()
        if not okWrap then
            error(errWrap)
        end
    end)
    imgui.EndTooltip()
    if not okTip then
        state.renderError = tostring(errTip)
    end
end

local function drawTreeCanvas()
    local detail = state.wsDetail
    if detail == nil then
        imgui.Spacing()
        drawTextColored({ 0.85, 0.78, 0.55, 1.0 }, '  No Weaponskill Selected')
        drawTextDisabled('  Choose a weaponskill from the list on the left to view and customize its talent tree.')
        if not state.synced then
            imgui.Spacing()
            imgui.SetCursorPosX(imgui.GetCursorPosX() + 10)
            if imgui.Button('Sync Catalog Now', { 170, 30 }) then
                requestFullSync()
            end
        end
        return
    end

    local unlocked = isWsUnlockedInDetail(detail)
    local dl = imgui.GetWindowDrawList()

    -- WS Header Banner
    drawTextColored({ 0.95, 0.84, 0.52, 1.0 }, detail.name)
    imgui.SameLine()
    drawTextDisabled(string.format('  •  %s  •  %s', detail.skillName, detail.wsType))
    imgui.SameLine()
    if unlocked then
        drawTextColored({ 0.45, 0.92, 0.55, 1.0 }, '   [UNLOCKED]')
    else
        drawTextColored({ 1.00, 0.52, 0.42, 1.0 }, '   [LOCKED — Invest 1 pt in Tier 1 to unlock]')
    end

    drawTextColored({ 0.72, 0.82, 0.94, 1.0 }, detail.orig)
    drawText(string.format('WS Points: %d / 56   |   Available %s (%s) Points: %d', detail.spent, state.jobKey, state.specName, state.avail))
    if detail.spent > 0 then
        imgui.SameLine()
        if imgui.SmallButton('Reset This WS') then
            sendTalentPacket(OP_RESET_WS, detail.id, 0, 0)
        end
    end
    imgui.Separator()

    -- Reserve bottom ~88px for the Pinned Node Inspector Panel
    local totalAvailW, totalAvailH = toXY(imgui.GetContentRegionAvail())
    local inspectorH = 88
    local treeRegionH = math.max(260, totalAvailH - inspectorH - 6)

    local hoveredNode = nil

    if imgui.BeginChild('ox_tree_scroll', { 0, treeRegionH }, CHILD_NONE) then
        local canvasPosX, canvasPosY = toXY(imgui.GetCursorScreenPos())
        local availW, availH = toXY(imgui.GetContentRegionAvail())
        local cardW = 194
        local cardH = 88
        local gapX  = 16
        local gapY  = 34
        local leftPad = 10

        local tierLabels =
        {
            [1] = 'TIER 1 • FOUNDATION (Lv 1+, 0+ WS pts — Unlocks WS)',
            [2] = 'TIER 2 • SPECIALIZATION (Lv 5+, 2+ WS pts)',
            [3] = 'TIER 3 • MASTERY (Lv 10+, 5+ WS pts)',
            [4] = 'TIER 4 • CAPSTONE (Lv 15+, 8+ WS pts)',
        }

        local coords = {}
        local maxCol = 1
        local maxTier = 1
        for _, node in ipairs(detail.nodes) do
            if node.col > maxCol then maxCol = node.col end
            if node.tier > maxTier then maxTier = node.tier end
            local x = canvasPosX + leftPad + (node.col - 1) * (cardW + gapX)
            local y = canvasPosY + 24 + (node.tier - 1) * (cardH + gapY)
            coords[node.key] = { x = x, y = y }
        end

        dl = imgui.GetWindowDrawList()

        -- Draw Tier Section Headers & subtle horizontal rule
        for t = 1, maxTier do
            local hy = canvasPosY + 4 + (t - 1) * (cardH + gapY)
            imgui.SetCursorScreenPos({ canvasPosX + leftPad, hy })
            local gateMet = (t == 1)
                or (t == 2 and detail.spent >= 2 and state.jobLevel >= 5)
                or (t == 3 and detail.spent >= 5 and state.jobLevel >= 10)
                or (t == 4 and detail.spent >= 8 and state.jobLevel >= 15)
            if gateMet then
                drawTextColored({ 0.85, 0.77, 0.55, 0.95 }, tierLabels[t] or ('TIER ' .. tostring(t)))
            else
                drawTextDisabled(tierLabels[t] or ('TIER ' .. tostring(t)))
            end
        end

        -- Draw Prerequisite Connector Lines with glow for active links
        for _, node in ipairs(detail.nodes) do
            if node.reqKey ~= nil and coords[node.reqKey] ~= nil and coords[node.key] ~= nil then
                local p = coords[node.reqKey]
                local c = coords[node.key]
                local parentNode = detail.byKey[node.reqKey]
                local activeLink = (parentNode ~= nil and parentNode.rank >= node.reqRank)
                    and (detail.spent >= node.reqWsPoints)
                    and (state.jobLevel >= (node.reqLevel or 1))
                local x1 = p.x + cardW * 0.5
                local y1 = p.y + cardH
                local x2 = c.x + cardW * 0.5
                local y2 = c.y
                local midY = (y1 + y2) * 0.5

                if activeLink then
                    dl:AddLine({ x1, y1 }, { x1, midY }, THEME.goldGlow, 6.0)
                    dl:AddLine({ x1, midY }, { x2, midY }, THEME.goldGlow, 6.0)
                    dl:AddLine({ x2, midY }, { x2, y2 }, THEME.goldGlow, 6.0)
                    dl:AddLine({ x1, y1 }, { x1, midY }, THEME.goldBright, 2.0)
                    dl:AddLine({ x1, midY }, { x2, midY }, THEME.goldBright, 2.0)
                    dl:AddLine({ x2, midY }, { x2, y2 }, THEME.goldBright, 2.0)
                    dl:AddRectFilled({ x2 - 3, y2 - 4 }, { x2 + 3, y2 + 1 }, THEME.goldBright, 1.0)
                else
                    dl:AddLine({ x1, y1 }, { x1, midY }, THEME.linkInactive, 1.5)
                    dl:AddLine({ x1, midY }, { x2, midY }, THEME.linkInactive, 1.5)
                    dl:AddLine({ x2, midY }, { x2, y2 }, THEME.linkInactive, 1.5)
                end
            end
        end

        -- Draw Modern Node Cards
        for _, node in ipairs(detail.nodes) do
            local pos = coords[node.key]
            local x, y = pos.x, pos.y

            local isMaxed = node.rank >= node.maxRank
            local isInspected = (state.inspectedNodeKey == node.key)
            local bgCol, outerCol, innerCol, accentCol, titleCol, pillCol
            if isMaxed then
                bgCol     = THEME.bgCardMax
                outerCol  = THEME.goldBright
                innerCol  = 0xFF705828
                accentCol = THEME.goldBright
                titleCol  = { 1.00, 0.88, 0.42, 1.00 }
                pillCol   = { 1.00, 0.88, 0.42, 1.00 }
            elseif node.rank > 0 then
                bgCol     = THEME.bgCardActive
                outerCol  = THEME.cyan
                innerCol  = 0xFF344B5E
                accentCol = THEME.cyan
                titleCol  = { 0.56, 0.88, 1.00, 1.00 }
                pillCol   = { 0.56, 0.88, 1.00, 1.00 }
            elseif node.canLearn then
                bgCol     = THEME.bgCardAvail
                outerCol  = THEME.green
                innerCol  = 0xFF284D35
                accentCol = THEME.green
                titleCol  = { 0.62, 0.96, 0.68, 1.00 }
                pillCol   = { 0.62, 0.96, 0.68, 1.00 }
            else
                bgCol     = THEME.bgCardLocked
                outerCol  = THEME.edge
                innerCol  = 0xFF2B201A
                accentCol = THEME.muted
                titleCol  = { 0.64, 0.60, 0.56, 1.00 }
                pillCol   = { 0.64, 0.60, 0.56, 1.00 }
            end

            local isScNode = (node.scTier or 0) > 0
            local btnH = isScNode and (cardH - 26) or cardH
            imgui.SetCursorScreenPos({ x, y })
            imgui.InvisibleButton('##node_' .. node.key, { cardW, btnH })
            local hovered = imgui.IsItemHovered()
            if hovered then
                hoveredNode = node
                state.inspectedNodeKey = node.key
            end

            if imgui.IsItemClicked(0) then
                state.inspectedNodeKey = node.key
                sendTalentPacket(OP_INVEST, detail.id, node.idx or 1, 0)
            elseif imgui.IsItemClicked(1) then
                state.inspectedNodeKey = node.key
                sendTalentPacket(OP_REFUND, detail.id, node.idx or 1, 0)
            end

            if hovered or isInspected then
                outerCol = THEME.silver
            end

            drawBevelPanel(dl, x, y, cardW, cardH, bgCol, outerCol, innerCol, 5.0)
            -- Top 3px state bar
            dl:AddRectFilled({ x + 4, y + 2 }, { x + cardW - 4, y + 4 }, accentCol, 1.0)

            -- Rank Pill Badge (top-right)
            local rankLabel = isMaxed and 'MAX' or string.format('%d/%d', node.rank, node.maxRank)
            local pillW = isMaxed and 36 or 32
            local pillX = x + cardW - pillW - 6
            local pillY = y + 7
            dl:AddRectFilled({ pillX, pillY }, { pillX + pillW, pillY + 16 }, THEME.barBg, 3.0)
            dl:AddRect({ pillX, pillY }, { pillX + pillW, pillY + 16 }, accentCol, 3.0, 0, 1.0)
            imgui.SetCursorScreenPos({ pillX + (isMaxed and 5 or 6), pillY + 1 })
            drawTextColored(pillCol, rankLabel)

            -- Title (left)
            local maxTitleChars = 19
            local titleStr = #node.name > maxTitleChars and (string.sub(node.name, 1, maxTitleChars - 2) .. '..') or node.name
            imgui.SetCursorScreenPos({ x + 8, y + 7 })
            drawTextColored(titleCol, titleStr)

            -- Body
            if isScNode then
                local scBonusPct = node.rank * (node.scTier == 4 and 15 or (node.scTier == 3 and 10 or (node.scTier == 2 and 8 or 5)))
                imgui.SetCursorScreenPos({ x + 8, y + 26 })
                drawTextColored({ 0.82, 0.80, 0.76, 1.0 }, string.format('+%d%% Skillchain Dmg', scBonusPct))

                imgui.SetCursorScreenPos({ x + 8, y + 46 })
                if imgui.SmallButton('<##sc_prev_' .. node.key) then
                    state.inspectedNodeKey = node.key
                    sendTalentPacket(OP_CYCLE_SC, detail.id, node.scTier, 255)
                end
                imgui.SameLine()
                local scDisp = (node.scName ~= '' and node.scName) or 'None'
                drawTextColored({ 0.86, 0.92, 1.0, 1.0 }, scDisp)
                imgui.SetCursorScreenPos({ x + cardW - 26, y + 46 })
                if imgui.SmallButton('>##sc_next_' .. node.key) then
                    state.inspectedNodeKey = node.key
                    sendTalentPacket(OP_CYCLE_SC, detail.id, node.scTier, 1)
                end
            else
                local readable = formatReadableDesc(node.desc)
                local wrapped = wrapLines(readable, 27)
                local line1 = wrapped[1] or ''
                local line2 = wrapped[2] or ''
                if #wrapped > 2 then
                    line2 = string.sub(line2, 1, 24) .. '...'
                end
                local descCol = (node.rank > 0 or node.canLearn) and { 0.85, 0.87, 0.90, 1.0 } or { 0.56, 0.52, 0.49, 1.0 }
                imgui.SetCursorScreenPos({ x + 8, y + 26 })
                drawTextColored(descCol, line1)
                if line2 ~= '' then
                    imgui.SetCursorScreenPos({ x + 8, y + 41 })
                    drawTextColored(descCol, line2)
                end
            end

            -- Footer Gate / Next Level Hint
            if not isMaxed then
                local reqLvl = node.reqLevel or 1
                imgui.SetCursorScreenPos({ x + 8, y + cardH - 21 })
                if state.jobLevel < reqLvl then
                    drawTextColored({ 1.00, 0.48, 0.45, 1.0 }, string.format('Req Lv.%d', reqLvl))
                elseif node.reqWsPoints > 0 and detail.spent < node.reqWsPoints then
                    drawTextColored({ 0.95, 0.68, 0.35, 1.0 }, string.format('Req %d WS pts', node.reqWsPoints))
                elseif node.canLearn then
                    drawTextColored({ 0.48, 0.90, 0.56, 1.0 }, string.format('Next: Lv.%d', reqLvl))
                else
                    drawTextDisabled(string.format('Locked (Lv.%d)', reqLvl))
                end
            else
                imgui.SetCursorScreenPos({ x + 8, y + cardH - 21 })
                drawTextColored({ 0.95, 0.84, 0.45, 1.0 }, 'Mastered')
            end

            -- Bottom Rank Progress Bar
            local barX1 = x + 6
            local barX2 = x + cardW - 6
            local barY1 = y + cardH - 6
            local barY2 = y + cardH - 3
            dl:AddRectFilled({ barX1, barY1 }, { barX2, barY2 }, THEME.barBg, 1.0)
            local pct = math.max(0, math.min(1, (node.rank or 0) / math.max(1, node.maxRank or 1)))
            if pct > 0 then
                dl:AddRectFilled({ barX1, barY1 }, { barX1 + (barX2 - barX1) * pct, barY2 }, accentCol, 1.0)
            end

            if hovered then
                drawNodeTooltip(node, detail, isMaxed, isScNode, titleCol)
            end
        end

        local contentW = 24 + maxCol * cardW + math.max(0, maxCol - 1) * gapX
        local contentH = 26 + maxTier * (cardH + gapY)
        imgui.SetCursorScreenPos({ canvasPosX, canvasPosY + math.max(availH - 10, contentH) })
        imgui.Dummy({ math.max(availW - 10, contentW), 4 })
    end
    imgui.EndChild()

    -- Pinned Node Inspector Panel at bottom of canvas
    local inspectNode = hoveredNode
    if inspectNode == nil and state.inspectedNodeKey ~= nil then
        inspectNode = detail.byKey[state.inspectedNodeKey]
    end
    if inspectNode == nil and detail.nodes and #detail.nodes > 0 then
        inspectNode = detail.nodes[1]
    end

    if imgui.BeginChild('ox_node_inspector', { 0, 0 }, CHILD_BORDERS) then
        if inspectNode ~= nil then
            local isMaxed = inspectNode.rank >= inspectNode.maxRank
            local titleCol = isMaxed and { 1.0, 0.88, 0.42, 1.0 }
                or (inspectNode.rank > 0 and { 0.56, 0.88, 1.0, 1.0 }
                or (inspectNode.canLearn and { 0.62, 0.96, 0.68, 1.0 } or { 0.72, 0.68, 0.64, 1.0 }))
            drawTextColored(titleCol, string.format('%s  (%d / %d)', inspectNode.name, inspectNode.rank, inspectNode.maxRank))
            imgui.SameLine()
            drawTextDisabled(string.format('  •  Tier %d  |  Left-Click: +1 Rank  |  Right-Click: -1 Rank', inspectNode.tier))

            imgui.PushTextWrapPos(math.max(300, totalAvailW - 24))
            pcall(function()
                drawText(formatReadableDesc(inspectNode.desc))
            end)
            imgui.PopTextWrapPos()

            if not isMaxed then
                local reqs = getNodeRequirements(inspectNode, detail)
                local first = true
                for _, req in ipairs(reqs) do
                    if not first then
                        imgui.SameLine()
                        drawTextDisabled('  |  ')
                        imgui.SameLine()
                    end
                    first = false
                    if req.ok then
                        drawTextColored({ 0.42, 0.88, 0.50, 1.0 }, '[OK] ' .. req.short)
                    else
                        drawTextColored({ 1.00, 0.45, 0.45, 1.0 }, '[X] ' .. req.text)
                    end
                end
            else
                drawTextColored({ 1.0, 0.85, 0.35, 1.0 }, '[MAX] Maximum rank reached.')
            end
        else
            drawTextDisabled('Hover or click any talent node to inspect its full details.')
        end
    end
    imgui.EndChild()
end

local function drawSidebar()
    local curSkillName = 'Equipped'
    for _, sk in ipairs(SKILL_LIST) do
        if sk.id == state.selectedSkill then
            curSkillName = sk.name
            break
        end
    end

    imgui.PushItemWidth(-1)
    local okFilter, errFilter = pcall(function()
        if imgui.BeginCombo('##skill_filter', curSkillName) then
            local okCombo, errCombo = pcall(function()
                for _, sk in ipairs(SKILL_LIST) do
                    local isSel = (sk.id == state.selectedSkill)
                    if imgui.Selectable(sk.name, isSel) then
                        state.selectedSkill = sk.id
                    end
                end
            end)
            imgui.EndCombo()
            if not okCombo then
                error(errCombo)
            end
        end
        imgui.InputText('##ws_search', state.searchBuf, 64)
    end)
    imgui.PopItemWidth()
    if not okFilter then
        error(errFilter)
    end

    imgui.Checkbox('Invested Only', state.investedOnly)
    imgui.Separator()

    local filtered = getFilteredCatalog()
    if imgui.BeginChild('ox_ws_list', { 0, 0 }, CHILD_NONE) then
        local okList, errList = pcall(function()
            local dl = imgui.GetWindowDrawList()
            for _, ws in ipairs(filtered) do
                local pts = state.spentByWs[ws.id] or 0
                local unl = state.unlockedByWs[ws.id] == true
                local isEquipped = (ws.skill == state.mainSkill or (state.rangedSkill ~= 0 and ws.skill == state.rangedSkill))
                local prefix = isEquipped and '[EQ] ' or ''
                local statusTag = unl and string.format(' [%d]', pts) or (pts > 0 and string.format(' [%d L]', pts) or '')
                local label = string.format('%s%s%s##ws_%u', prefix, ws.name, statusTag, ws.id)
                local isSelected = (state.selectedWsId == ws.id)

                if not unl and not isSelected then
                    imgui.PushStyleColor(COL_TEXT, { 0.62, 0.58, 0.54, 1.0 })
                elseif unl and not isSelected then
                    imgui.PushStyleColor(COL_TEXT, { 0.88, 0.92, 0.94, 1.0 })
                end
                local clicked = imgui.Selectable(label, isSelected)
                if not isSelected then
                    imgui.PopStyleColor()
                end
                if isSelected and dl then
                    local rx, ry = toXY(imgui.GetItemRectMin())
                    local _, rmaxY = toXY(imgui.GetItemRectMax())
                    dl:AddRectFilled({ rx - 2, ry + 2 }, { rx + 1, rmaxY - 2 }, THEME.goldBright, 1.0)
                end
                if clicked then
                    state.inspectedNodeKey = nil
                    requestWS(ws.id)
                end
            end
        end)
        if not okList then
            state.renderError = tostring(errList)
        end
    end
    imgui.EndChild()
end

local function drawMainContents()
    -- Top Header Bar
    drawTextColored({ 0.95, 0.84, 0.52, 1.0 }, string.format('%s (%s) Lv.%d', state.jobKey, state.specName, state.jobLevel))
    imgui.SameLine()
    drawTextDisabled('   |   ')
    imgui.SameLine()
    drawTextColored({ 0.45, 0.92, 0.55, 1.0 }, string.format('Available: %d pts', state.avail))
    imgui.SameLine()
    drawText(string.format('   (Spent: %d / Earned: %d)', state.spent, state.earned))
    imgui.SameLine()
    if imgui.Button('Sync') then
        requestFullSync()
    end
    imgui.SameLine()
    if not state.confirmResetAll then
        if imgui.Button('Reset Spec') then
            state.confirmResetAll = true
            state.confirmResetAt = os.clock()
        end
    else
        if os.clock() - state.confirmResetAt > 5.0 then
            state.confirmResetAll = false
        else
            if imgui.Button('Confirm Reset Spec!') then
                state.confirmResetAll = false
                sendTalentPacket(OP_RESET_ALL, 0, 0, 0)
                if state.selectedWsId ~= nil then
                    requestWS(state.selectedWsId)
                end
                setStatus(string.format('Reset all weaponskill talents for %s (%s).', state.jobKey, state.specName))
            end
            imgui.SameLine()
            if imgui.Button('Cancel') then
                state.confirmResetAll = false
            end
        end
    end

    if state.statusText ~= nil then
        if os.clock() - state.statusTime > 4.0 then
            state.statusText = nil
        else
            imgui.SameLine()
            drawTextColored({ 1.0, 0.65, 0.35, 1.0 }, '  ' .. state.statusText)
        end
    end

    if state.renderError ~= nil then
        drawTextColored({ 1.0, 0.35, 0.35, 1.0 }, 'UI Error: ' .. state.renderError)
    end

    imgui.Separator()

    -- Left Sidebar: Weapon Type + WS List
    if imgui.BeginChild('ox_ws_sidebar', { 265, 0 }, CHILD_BORDERS) then
        local okSide, errSide = xpcall(drawSidebar, debug.traceback)
        if not okSide then
            state.renderError = tostring(errSide)
        end
    end
    imgui.EndChild()

    imgui.SameLine()

    -- Right Canvas: Selected WS Talent Tree
    if imgui.BeginChild('ox_ws_canvas', { 0, 0 }, CHILD_BORDERS) then
        local okCanvas, errCanvas = xpcall(drawTreeCanvas, debug.traceback)
        if not okCanvas then
            state.renderError = tostring(errCanvas)
        end
    end
    imgui.EndChild()
end

local function pushThemeStyles()
    local pushed = 0
    if not (imgui.PushStyleColor and imgui.PopStyleColor) then
        return 0
    end
    local function pushCol(colId, rgba)
        if colId ~= nil then
            imgui.PushStyleColor(colId, rgba)
            pushed = pushed + 1
        end
    end
    pushCol(ImGuiCol_WindowBg,       { 0.08, 0.05, 0.04, 0.96 })
    pushCol(ImGuiCol_ChildBg,        { 0.11, 0.07, 0.05, 0.92 })
    pushCol(ImGuiCol_PopupBg,        { 0.10, 0.06, 0.05, 0.96 })
    pushCol(ImGuiCol_Border,         { 0.35, 0.25, 0.18, 0.90 })
    pushCol(ImGuiCol_TitleBg,        { 0.12, 0.08, 0.06, 1.00 })
    pushCol(ImGuiCol_TitleBgActive,  { 0.20, 0.13, 0.09, 1.00 })
    pushCol(ImGuiCol_FrameBg,        { 0.16, 0.10, 0.07, 1.00 })
    pushCol(ImGuiCol_FrameBgHovered, { 0.24, 0.15, 0.10, 1.00 })
    pushCol(ImGuiCol_Button,         { 0.26, 0.17, 0.11, 1.00 })
    pushCol(ImGuiCol_ButtonHovered,  { 0.38, 0.25, 0.16, 1.00 })
    pushCol(ImGuiCol_ButtonActive,   { 0.46, 0.31, 0.19, 1.00 })
    pushCol(ImGuiCol_Header,         { 0.32, 0.21, 0.13, 0.90 })
    pushCol(ImGuiCol_HeaderHovered,  { 0.40, 0.27, 0.17, 0.95 })
    pushCol(ImGuiCol_HeaderActive,   { 0.48, 0.33, 0.20, 1.00 })
    pushCol(ImGuiCol_Separator,      { 0.35, 0.25, 0.18, 0.85 })
    return pushed
end

ashita.events.register('d3d_present', 'ox_talents_present', function()
    -- Auto-detect job or level changes
    local now = os.clock()
    if now - state.lastAutoCheck >= 1.0 then
        state.lastAutoCheck = now
        local player = AshitaCore:GetMemoryManager():GetPlayer()
        if player ~= nil and player:GetMainJob() > 0 then
            local getLvl = player.GetMainJobLevel or player.GetMainLevel
            local j = player:GetMainJob()
            local l = getLvl and getLvl(player) or 1
            if state.lastKnownJob ~= nil and (j ~= state.lastKnownJob or l ~= state.lastKnownLvl) then
                if state.open[1] then
                    sendTalentPacket(OP_STATE, 0, 0, 0)
                end
            end
            state.lastKnownJob = j
            state.lastKnownLvl = l
        end
    end

    if not state.open[1] then
        return
    end

    local pushedCols = pushThemeStyles()
    imgui.SetNextWindowSize({ 1160, 680 }, ImGuiCond_FirstUseEver or 4)
    if imgui.Begin('OverlordsXI - Weaponskill Talents###OXTalentsWin', state.open) then
        local okWin, errWin = xpcall(drawMainContents, debug.traceback)
        if not okWin then
            state.renderError = tostring(errWin)
            drawTextColored({ 1.0, 0.35, 0.35, 1.0 }, 'UI Error: ' .. state.renderError)
        end
    end
    imgui.End()
    if pushedCols > 0 then
        imgui.PopStyleColor(pushedCols)
    end
end)
