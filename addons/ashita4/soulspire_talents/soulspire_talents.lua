--[[
* SoulspireXI — Weapon Skill Talent Tree Addon for Ashita v4 (v3.0.0)
*
* Classic dark-fantasy RPG three-branch talent interface aligned with
* SoulspireXI's website branding (site/styles.css) and Foundation 2.1.
*
* Commands:
*   /talents         - Toggle the talent tree window
*   /tal             - Alias for /talents
*   /talents sync    - Force resync eligible catalog & points from server
--]]

addon.name    = 'soulspire_talents'
addon.author  = 'SoulspireXI'
addon.version = '3.0.0'
addon.desc    = 'Classic RPG three-branch weapon skill talent UI for SoulspireXI.'

require('common')
local bit   = require('bit')
local imgui = require('imgui')
local T     = require('talent_theme')
local S     = require('talent_state')
local UI    = require('talent_tree_ui')

local PROTO_TAG     = '[OXTAL]|'
local PACKET_C2S_ID = 0x11F
local PACKET_S2C_ID = 0x1FD
local PACKET_ZONE   = 0x00A

local state = S.newState()

local function sendTalentPacket(op, wsId, arg1, arg2)
    local w  = tonumber(wsId) or 0
    local a1 = (tonumber(arg1) or 0) % 256
    local a2 = (tonumber(arg2) or 0) % 256
    local pkt = string.char(0x1F, 0x09, 0x00, 0x00)
        .. 'OXTL'
        .. string.char(1, op % 256, w % 256, math.floor(w / 256) % 256, a1, a2, 0, 0)
    local bytes = { pkt:byte(1, #pkt) }
    AshitaCore:GetPacketManager():AddOutgoingPacket(PACKET_C2S_ID, bytes)
end

local function requestFullSync()
    state.syncRequestedAt = os.clock()
    state.needsFullResync = false
    sendTalentPacket(S.OP_SYNC, 0, 0, 0)
end

local function requestWS(wsId)
    if wsId == nil then return end
    state.selectedWsId = wsId
    state.needsWsRequest = nil
    sendTalentPacket(S.OP_WS, wsId, 0, 0)
end

local actions =
{
    sync = function()
        S.setStatus(state, 'Syncing with server...', 'pending')
        requestFullSync()
    end,
    selectWs = function(wsId)
        requestWS(wsId)
    end,
    invest = function(wsId, slot)
        if S.isPending(state) then return end
        S.markPending(state, S.OP_INVEST, wsId, slot)
        S.setStatus(state, 'Investing point...', 'pending')
        sendTalentPacket(S.OP_INVEST, wsId, slot, 0)
    end,
    refund = function(wsId, slot)
        if S.isPending(state) then return end
        S.markPending(state, S.OP_REFUND, wsId, slot)
        S.setStatus(state, 'Refunding point...', 'pending')
        sendTalentPacket(S.OP_REFUND, wsId, slot, 0)
    end,
    cycleSc = function(wsId, scTier, dir)
        if S.isPending(state) then return end
        sendTalentPacket(S.OP_CYCLE_SC, wsId, scTier, dir == -1 and 2 or 1)
    end,
    resetWs = function(wsId)
        if S.isPending(state) then return end
        S.markPending(state, S.OP_RESET_WS, wsId, 0)
        S.setStatus(state, 'Resetting weapon skill...', 'pending')
        sendTalentPacket(S.OP_RESET_WS, wsId, 0, 0)
    end,
    resetAll = function()
        if S.isPending(state) then return end
        S.markPending(state, S.OP_RESET_ALL, 0, 0)
        S.setStatus(state, 'Resetting all Soul talents...', 'pending')
        sendTalentPacket(S.OP_RESET_ALL, 0, 0, 0)
    end,
}

local function processProtoLine(payload)
    S.handleProtoLine(state, payload)
    if state.needsFullResync then
        requestFullSync()
    elseif state.needsWsRequest ~= nil then
        requestWS(state.needsWsRequest)
    end
end

-- Push SoulspireXI dark-fantasy ImGui theme tokens
local function pushWindowTheme()
    if not (imgui.PushStyleColor and imgui.PopStyleColor) then return 0 end
    local pairsList = {
        { ImGuiCol_WindowBg,       T.COLORS.abyss },
        { ImGuiCol_ChildBg,        T.COLORS.surface },
        { ImGuiCol_PopupBg,        T.COLORS.abyss },
        { ImGuiCol_Border,         T.COLORS.borderGold },
        { ImGuiCol_TitleBg,        T.COLORS.stoneDark },
        { ImGuiCol_TitleBgActive,  T.COLORS.surface },
        { ImGuiCol_FrameBg,        T.COLORS.card },
        { ImGuiCol_FrameBgHovered, T.COLORS.cardHover },
        { ImGuiCol_Button,         T.COLORS.elevated },
        { ImGuiCol_ButtonHovered,  T.COLORS.cardHover },
        { ImGuiCol_ButtonActive,   T.COLORS.goldDeep },
        { ImGuiCol_Header,         T.COLORS.elevated },
        { ImGuiCol_HeaderHovered,  T.COLORS.cardHover },
        { ImGuiCol_HeaderActive,   T.COLORS.goldDeep },
        { ImGuiCol_Separator,      T.COLORS.borderSubtle },
        { ImGuiCol_Text,           T.COLORS.textPrimary },
    }
    local pushed = 0
    for _, p in ipairs(pairsList) do
        if p[1] ~= nil and p[2] ~= nil then
            imgui.PushStyleColor(p[1], p[2])
            pushed = pushed + 1
        end
    end
    return pushed
end

-----------------------------------
-- Ashita v4 Events
-----------------------------------
ashita.events.register('load', 'ox_talents_load', function()
    if imgui.AddFontFromFileTTF then
        local fontPaths = {
            'C:\\Windows\\Fonts\\segoeui.ttf',
            'C:\\Windows\\Fonts\\arial.ttf',
        }
        for _, fontPath in ipairs(fontPaths) do
            local ok, font = pcall(imgui.AddFontFromFileTTF, fontPath, 16)
            if ok and font ~= nil then
                state.uiFont = font
                break
            end
        end
    end

    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if player ~= nil and player:GetMainJob() > 0 then
        local getLvl = player.GetMainJobLevel or player.GetMainLevel
        state.lastKnownJob = player:GetMainJob()
        state.lastKnownLvl = getLvl and getLvl(player) or 1
        requestFullSync()
    end
end)

ashita.events.register('command', 'ox_talents_cmd', function(e)
    local args = e.command:args()
    if #args == 0 then return end

    local cmd = string.lower(args[1])
    if cmd ~= '/talents' and cmd ~= '/tal' then return end
    e.blocked = true

    local sub = args[2] and string.lower(args[2]) or nil
    if sub == 'sync' then
        actions.sync()
        return
    elseif sub == 'close' or sub == 'hide' then
        state.open[1] = false
        return
    end

    state.open[1] = not state.open[1]
    if state.open[1] then
        if not state.synced then
            requestFullSync()
        else
            sendTalentPacket(S.OP_STATE, 0, 0, 0)
            if state.selectedWsId ~= nil then
                requestWS(state.selectedWsId)
            end
        end
    end
end)

ashita.events.register('packet_in', 'ox_talents_packet_in', function(e)
    -- Re-sync cleanly on zone-in / reconnect
    if e.id == PACKET_ZONE then
        state.synced = false
        state.wsDetail = nil
        S.clearPending(state)
        requestFullSync()
        return
    end

    -- Binary SoulspireXI S2C Talent Packet (0x1FD, magic 'OXTL')
    if e.id == PACKET_S2C_ID and e.data ~= nil and #e.data >= 12 then
        if string.sub(e.data, 5, 8) == 'OXTL' then
            local len = bit.bor(string.byte(e.data, 10), bit.lshift(string.byte(e.data, 11), 8))
            local payload = string.sub(e.data, 13, 12 + len)
            if payload ~= '' then
                processProtoLine(payload)
            end
            e.blocked = true
        end
        return
    end

    -- Legacy 0x017 chat-framed fallback (blocked from chat log)
    if e.id == 0x017 and e.data ~= nil then
        local raw = string.sub(e.data, 25)
        local nul = string.find(raw, '\0', 1, true)
        if nul then raw = string.sub(raw, 1, nul - 1) end
        local idx = string.find(raw, PROTO_TAG, 1, true)
        if idx ~= nil then
            e.blocked = true
            processProtoLine(string.sub(raw, idx + #PROTO_TAG))
        end
    end
end)

ashita.events.register('text_in', 'ox_talents_text_in', function(e)
    if e.message ~= nil and string.find(e.message, PROTO_TAG, 1, true) ~= nil then
        e.blocked = true
    end
end)

ashita.events.register('d3d_present', 'ox_talents_present', function()
    local now = os.clock()
    -- Lightweight 1 Hz job/level change check (zero per-frame overhead)
    if now - state.lastAutoCheck >= 1.0 then
        state.lastAutoCheck = now
        local player = AshitaCore:GetMemoryManager():GetPlayer()
        if player ~= nil and player:GetMainJob() > 0 then
            local getLvl = player.GetMainJobLevel or player.GetMainLevel
            local j = player:GetMainJob()
            local l = getLvl and getLvl(player) or 1
            if state.lastKnownJob ~= nil and (j ~= state.lastKnownJob or l ~= state.lastKnownLvl) then
                state.synced = false
                if state.open[1] then
                    requestFullSync()
                end
            end
            state.lastKnownJob = j
            state.lastKnownLvl = l
        end
    end

    if not state.open[1] then return end

    if not state.synced and (now - (state.syncRequestedAt or 0)) >= 3.5 then
        local player = AshitaCore:GetMemoryManager():GetPlayer()
        if player ~= nil and player:GetMainJob() > 0 then
            requestFullSync()
        end
    end

    local pushedCols = pushWindowTheme()
    imgui.SetNextWindowSize({ 1060, 680 }, ImGuiCond_FirstUseEver or 4)
    if imgui.SetNextWindowSizeConstraints then
        imgui.SetNextWindowSizeConstraints({ 820, 560 }, { 1600, 1080 })
    end

    if imgui.Begin('SoulspireXI — Weapon Skill Talents###OXTalentsWin', state.open, ImGuiWindowFlags_NoScrollbar or 8) then
        local fontPushed = false
        if state.uiFont ~= nil and imgui.PushFont then
            fontPushed = pcall(imgui.PushFont, state.uiFont, 16)
        end
        local okWin, errWin = xpcall(function()
            UI.render(state, actions)
        end, debug.traceback)
        if fontPushed and imgui.PopFont then
            imgui.PopFont()
        end
        if not okWin then
            state.renderError = tostring(errWin)
            imgui.TextColored(T.COLORS.rose, 'UI Error: ' .. state.renderError)
        end
    end
    imgui.End()

    if pushedCols > 0 then
        imgui.PopStyleColor(pushedCols)
    end
end)

ashita.events.register('unload', 'ox_talents_unload', function()
    UI.unload()
end)
