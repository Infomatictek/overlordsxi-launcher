--[[
* OverlordsXI - Chi Weaver Boost Stack HUD Addon for Ashita v4
*
* Compact Crystal-styled HUD widget displaying active Chi Weaver Boost stacks
* (0..100), remaining Boost duration, Cure/Magic bonuses, and Cleanse tiers.
* Receives silent [OXBST]|... tagged 0x017 sync packets from the server.
*
* Commands:
*   /boost              - Toggle HUD visibility (Auto <-> Hide)
*   /boost show         - Always show the widget (for positioning/preview)
*   /boost hide         - Hide the widget
*   /boost auto         - Auto-show only when Chi Weaver is active (default)
*   /boost lock         - Lock widget position
*   /boost unlock       - Unlock widget position for dragging
*   /boost scale <num>  - Set widget scale (0.75 - 2.00)
*   /boost sync         - Request fresh Boost stack state from server
*   /boost status       - Print current Boost HUD state and diagnostics
*   /boost reset        - Reset position and scale to defaults
*   /boost help         - Print command usage
--]]

addon.name    = 'overlords_boost'
addon.author  = 'OverlordsXI'
addon.version = '1.0.1'
addon.desc    = 'Compact Crystal-styled Boost stack counter HUD for OverlordsXI Chi Weaver.'
addon.link    = 'https://github.com/Infomatictek/overlordsxi-launcher'

pcall(require, 'common')
local okBit, bit     = pcall(require, 'bit')
local okChat, chat   = pcall(require, 'chat')
local okD3d, d3d8    = pcall(require, 'd3d8')
local okFfi, ffi     = pcall(require, 'ffi')
local okImgui, imgui = pcall(require, 'imgui')

local PROTO_TAG = '[OXBST]|'

local function bitBor(...)
    if okBit and bit and bit.bor then
        return bit.bor(...)
    end
    local acc = 0
    for i = 1, select('#', ...) do
        local v = tonumber(select(i, ...)) or 0
        local p = 1
        local out = 0
        local a, b = acc, v
        while a > 0 or b > 0 do
            local ra = a % 2
            local rb = b % 2
            if ra == 1 or rb == 1 then
                out = out + p
            end
            a = (a - ra) / 2
            b = (b - rb) / 2
            p = p * 2
        end
        acc = out
    end
    return acc
end

-- Optional crystaljobs.dll poll to detect Chi Weaver branch (MNK branch 3) immediately on login/load.
local crystal_status_t = nil
if okFfi and ffi then
    pcall(ffi.cdef, 'void* __stdcall GetModuleHandleA(const char* name);')
    pcall(ffi.cdef, 'void* __stdcall GetProcAddress(void* module, const char* name);')
    local okType, stType = pcall(ffi.typeof, [=[struct {
        uint32_t size, version, enabled, hooks, character_id, job, known, branch;
        uint32_t search_rows, decoded_rows, item_labels, search_labels, full_labels;
        uint32_t queries_sent, replies_accepted, replies_rejected, last_error;
    }[1]]=])
    if okType then
        crystal_status_t = stType
    end
end

local default_settings = {
    x      = 320,
    y      = 140,
    scale  = 1.0,
    mode   = 'auto', -- 'auto' | 'show' | 'hide'
    locked = false,
}

local cfg = {
    x      = default_settings.x,
    y      = default_settings.y,
    scale  = default_settings.scale,
    mode   = default_settings.mode,
    locked = default_settings.locked,
}

-- Crystal UI palette (ImGui draw list colors are packed ABGR).
local colors = {
    navy      = 0xFF361B10,
    dark      = 0xFF261108,
    silver    = 0xFFAD9789,
    edge      = 0xFF523929,
    text      = 0xFFE2E8E9,
    secondary = 0xFFB8A89C,
    muted     = 0xFF7B6557,
    shadow    = 0x55000000,
    accent    = 0xFFD9C38C,
    track     = 0xFF1A0C06,
    tick      = 0x88AD9789,
    tier0     = 0xFFB8A89C, -- 0 stacks (warm silver)
    tier1     = 0xFFD9C38C, -- 1-24 (pale cyan/ice)
    tier25    = 0xFFDDAA55, -- 25-49 (chiweaver azure)
    tier50    = 0xFF66CC77, -- 50-79 (jade/emerald)
    tier80    = 0xFF44BBEE, -- 80-99 (radiant gold)
    tier100   = 0xFF22D4FF, -- 100 MAX (bright amber-gold)
}

local state = {
    synced          = false,
    chiWeaverActive = false,
    stacks          = 0,
    maxStacks       = 100,
    remSec          = 0,
    timerUpdatedAt  = 0,
    transitioning   = false,
    lastSyncReqAt   = 0,
    lastDllPollAt   = 0,
    dllChiWeaver    = false,
    iconTex         = nil,
    iconLoadFailed  = false,
    uiFont          = nil,
    resetPosPending = false,
    dirtySettings   = false,
    lastSaveAt      = 0,
    lastJobId       = nil,
    reportedErrors  = {},
}

local function clamp(val, lo, hi)
    if val < lo then return lo end
    if val > hi then return hi end
    return val
end

local function logMessage(text)
    local msg = tostring(text or '')
    if okChat and chat and chat.header and chat.message then
        local ok, formatted = pcall(function()
            return chat.header('overlords_boost') .. chat.message(msg)
        end)
        if ok and formatted then
            print(formatted)
            return
        end
    end
    print('[overlords_boost] ' .. msg)
end

local function logError(part, err)
    local full = tostring(err or 'unknown error')
    local firstLine = full:match('^[^\n]*') or full
    if not state.reportedErrors[firstLine] then
        state.reportedErrors[firstLine] = true
        if okChat and chat and chat.header and chat.error then
            local ok, formatted = pcall(function()
                return chat.header('overlords_boost') .. chat.error(part .. ': ' .. firstLine)
            end)
            if ok and formatted then
                print(formatted)
                return
            end
        end
        print('[overlords_boost] ' .. part .. ': ' .. firstLine)
    end
end

local function guard(part, fn, ...)
    local ok, res = xpcall(fn, debug.traceback, ...)
    if not ok then
        logError(part, res)
        return false, nil
    end
    return true, res
end

local function serializeValue(val, indent)
    indent = indent or ''
    if type(val) == 'table' then
        local lines = {}
        local keys = {}
        for k in pairs(val) do
            keys[#keys + 1] = k
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local keyStr = (type(k) == 'number')
                and ('[' .. k .. ']')
                or ('[' .. string.format('%q', tostring(k)) .. ']')
            lines[#lines + 1] = indent .. '    ' .. keyStr .. ' = ' .. serializeValue(val[k], indent .. '    ') .. ','
        end
        if #lines == 0 then
            return '{}'
        end
        return '{\n' .. table.concat(lines, '\n') .. '\n' .. indent .. '}'
    elseif type(val) == 'string' then
        return string.format('%q', val)
    elseif type(val) == 'number' or type(val) == 'boolean' then
        return tostring(val)
    end
    return 'nil'
end

local function getSettingsFolder()
    if AshitaCore == nil or not AshitaCore.GetInstallPath then
        return nil
    end
    local ok, installPath = pcall(function() return AshitaCore:GetInstallPath() end)
    if not ok or type(installPath) ~= 'string' or installPath == '' then
        return nil
    end
    return installPath:gsub('[/\\]+$', '') .. '\\config\\addons\\overlords_boost'
end

local function getSettingsPath()
    local folder = getSettingsFolder()
    if not folder then
        return nil
    end
    return folder .. '\\settings.lua'
end

local function applyLoadedSettings(tbl)
    if type(tbl) ~= 'table' then
        return
    end
    if type(tbl.x) == 'number' then cfg.x = math.floor(tbl.x + 0.5) end
    if type(tbl.y) == 'number' then cfg.y = math.floor(tbl.y + 0.5) end
    if type(tbl.scale) == 'number' then cfg.scale = clamp(tbl.scale, 0.75, 2.0) end
    if tbl.mode == 'auto' or tbl.mode == 'show' or tbl.mode == 'hide' then
        cfg.mode = tbl.mode
    end
    if type(tbl.locked) == 'boolean' then cfg.locked = tbl.locked end
end

local function saveSettings()
    pcall(function()
        local folder = getSettingsFolder()
        local path = getSettingsPath()
        if not folder or not path then
            return
        end
        if ashita and ashita.fs and ashita.fs.exists and ashita.fs.create_directory then
            if not ashita.fs.exists(folder) then
                ashita.fs.create_directory(folder)
            end
        end
        local f = io.open(path, 'w')
        if f then
            f:write('-- OverlordsXI Chi Weaver Boost HUD settings\nreturn ' .. serializeValue(cfg) .. '\n')
            f:close()
        end
    end)
end

local function loadSettings()
    pcall(function()
        local path = getSettingsPath()
        if not path then
            return
        end
        local f = io.open(path, 'r')
        if not f then
            saveSettings()
            return
        end
        f:close()

        local loader = loadfile(path)
        if not loader then
            return
        end
        if setfenv then
            setfenv(loader, {})
        end
        local ok, data = pcall(loader)
        if ok and type(data) == 'table' then
            applyLoadedSettings(data)
        end
    end)
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
            out[#out + 1] = string.sub(str, start)
            break
        end
        out[#out + 1] = string.sub(str, start, pos - 1)
        start = pos + 1
    end
    return out
end

local function parseCommandArgs(cmd)
    if type(cmd) ~= 'string' then
        return {}
    end
    if cmd.args then
        local ok, parsed = pcall(function() return cmd:args() end)
        if ok and type(parsed) == 'table' then
            return parsed
        end
    end
    local out = {}
    for token in string.gmatch(cmd, '%S+') do
        out[#out + 1] = token
    end
    return out
end

local function resolveAddonBasePath()
    if type(addon.path) == 'string' and addon.path ~= '' then
        return addon.path:gsub('[/\\]+$', '')
    end
    if AshitaCore ~= nil and AshitaCore.GetInstallPath then
        local ok, installPath = pcall(function() return AshitaCore:GetInstallPath() end)
        if ok and type(installPath) == 'string' and installPath ~= '' then
            return installPath:gsub('[/\\]+$', '') .. '\\addons\\overlords_boost'
        end
    end
    return nil
end

local function loadIconTexture()
    if state.iconTex ~= nil then
        return tonumber(ffi.cast('uint32_t', state.iconTex))
    end
    if state.iconLoadFailed or not (okFfi and ffi and okD3d and d3d8 and d3d8.get_device) then
        return nil
    end

    local ok, tex = pcall(function()
        local basePath = resolveAddonBasePath()
        if not basePath then
            return nil
        end
        local dev = d3d8.get_device()
        if dev == nil then
            return nil
        end

        local path = basePath .. '/assets/chiweaver.png'
        local f = io.open(path, 'rb')
        if not f then
            return nil
        end
        local data = f:read('*a')
        f:close()
        if not data or #data == 0 then
            return nil
        end

        local out = ffi.new('IDirect3DTexture8*[1]')
        local hr = ffi.C.D3DXCreateTextureFromFileInMemoryEx(
            dev,
            data,
            #data,
            0xFFFFFFFF,
            0xFFFFFFFF,
            1,
            0,
            ffi.C.D3DFMT_A8R8G8B8,
            ffi.C.D3DPOOL_MANAGED,
            ffi.C.D3DX_DEFAULT,
            ffi.C.D3DX_DEFAULT,
            0,
            nil,
            nil,
            out
        )
        if hr ~= ffi.C.S_OK or out[0] == nil then
            if out[0] ~= nil then
                out[0]:Release()
            end
            return nil
        end
        return out[0]
    end)

    if ok and tex ~= nil then
        state.iconTex = tex
        return tonumber(ffi.cast('uint32_t', tex))
    end
    if not ok then
        state.iconLoadFailed = true
    end
    return nil
end

local function pollCrystalDllChiWeaver()
    if not (okFfi and ffi and crystal_status_t) then
        return false
    end
    local now = os.clock()
    if (now - state.lastDllPollAt) < 1.0 then
        return state.dllChiWeaver
    end
    state.lastDllPollAt = now

    local active = false
    pcall(function()
        local mod = ffi.C.GetModuleHandleA('crystaljobs.dll')
        if mod == nil then
            return
        end
        local addr = ffi.C.GetProcAddress(mod, 'CrystalJobsGetStatus')
        if addr == nil then
            return
        end
        local fn = ffi.cast('uint32_t (__stdcall *)(void*, uint32_t)', addr)
        local st = ffi.new(crystal_status_t)
        if fn(st, ffi.sizeof(st)) == 0 and st[0].size == 68 and st[0].known == 1 then
            active = (tonumber(st[0].job) == 2 and tonumber(st[0].branch) == 3)
        end
    end)

    state.dllChiWeaver = active
    return active
end

local function isPlayerInGame()
    if AshitaCore == nil or not AshitaCore.GetMemoryManager then
        return false, 0
    end
    local ok, inGame, jobId = pcall(function()
        local memory = AshitaCore:GetMemoryManager()
        if memory == nil then
            return false, 0
        end
        local party  = memory:GetParty()
        local player = memory:GetPlayer()
        if party == nil or player == nil then
            return false, 0
        end
        local sid  = party:GetMemberServerId(0) or 0
        local tidx = party:GetMemberTargetIndex(0) or 0
        local name = party:GetMemberName(0)
        local job  = player:GetMainJob() or 0
        if state.transitioning or sid < 1 or tidx == 0 or name == nil or name == '' or job < 1 then
            return false, 0
        end
        return true, job
    end)
    if not ok then
        return false, 0
    end
    return inGame == true, jobId or 0
end

local function requestBoostSync(force)
    local inGame = isPlayerInGame()
    if not inGame then
        return
    end
    local now = os.clock()
    if not force and (now - state.lastSyncReqAt) < 3.0 then
        return
    end
    if AshitaCore == nil or not AshitaCore.GetChatManager then
        return
    end
    state.lastSyncReqAt = now
    pcall(function()
        local chatMgr = AshitaCore:GetChatManager()
        if chatMgr ~= nil then
            chatMgr:QueueCommand(1, '/say !spec boost')
        end
    end)
end

local function getTierColor(stacks, maxStacks)
    if stacks >= maxStacks and maxStacks > 0 then
        return colors.tier100
    elseif stacks >= 80 then
        return colors.tier80
    elseif stacks >= 50 then
        return colors.tier50
    elseif stacks >= 25 then
        return colors.tier25
    elseif stacks > 0 then
        return colors.tier1
    end
    return colors.tier0
end

local function getCleanseTier(stacks)
    if stacks >= 80 then
        return 3
    elseif stacks >= 50 then
        return 2
    elseif stacks >= 25 then
        return 1
    end
    return 0
end

local function getChiBlastMultiplier(stacks)
    return 0.50 + (stacks * 0.045) + ((stacks * stacks) / 10000.0) * 1.55
end

local function getLiveRemainingSeconds()
    if state.stacks <= 0 or state.remSec <= 0 then
        return 0
    end
    local elapsed = math.max(0, os.clock() - state.timerUpdatedAt)
    return math.max(0, math.ceil(state.remSec - elapsed))
end

local function formatTimer(sec)
    if sec <= 0 then
        return ''
    end
    local m = math.floor(sec / 60)
    local s = sec % 60
    return string.format('%d:%02d', m, s)
end

local function drawPanel(draw, x, y, w, h, s, recessed)
    draw:AddRectFilled({ x, y + 2 * s }, { x + w + 1 * s, y + h + 2 * s }, colors.shadow, 3 * s)
    draw:AddRectFilled({ x, y }, { x + w, y + h }, recessed and colors.dark or colors.navy, 3 * s)
    draw:AddRect({ x, y }, { x + w, y + h }, colors.silver, 3 * s)
    draw:AddRect({ x + 1 * s, y + 1 * s }, { x + w - 1 * s, y + h - 1 * s }, colors.edge, 2 * s)
end

local function drawFallbackCrystal(draw, x, y, w, h, tint)
    local cx, cy = x + w * 0.5, y + h * 0.5
    local rx, ry = w * 0.34, h * 0.42
    draw:AddQuadFilled(
        { cx, cy - ry },
        { cx + rx, cy },
        { cx, cy + ry },
        { cx - rx, cy },
        tint or colors.tier25
    )
    draw:AddQuad(
        { cx, cy - ry },
        { cx + rx, cy },
        { cx, cy + ry },
        { cx - rx, cy },
        colors.text,
        1.0
    )
end

local function drawText(draw, x, y, str, color, sizePx)
    if state.uiFont ~= nil then
        local ok = pcall(function()
            draw:AddText(state.uiFont, sizePx, { x, y }, color, str)
        end)
        if ok then
            return
        end
        state.uiFont = nil
    end
    draw:AddText({ x, y }, color, str)
end

local function calcTextWidth(str, sizePx)
    if state.uiFont ~= nil then
        local ok, w = pcall(function()
            return toXY(state.uiFont:CalcTextSizeA(sizePx, 1000.0, 0.0, str))
        end)
        if ok and type(w) == 'number' and w > 0 then
            return w
        end
    end
    if imgui and imgui.CalcTextSize then
        local ok, baseW = pcall(function()
            return toXY(imgui.CalcTextSize(str))
        end)
        if ok and type(baseW) == 'number' and baseW > 0 then
            return baseW * (sizePx / 13.0)
        end
    end
    return #str * sizePx * 0.52
end

local function tooltipText(str)
    local s = tostring(str or '')
    if imgui.TextUnformatted then
        imgui.TextUnformatted(s)
    else
        imgui.Text((s:gsub('%%', '%%%%')))
    end
end

local function drawBoostTooltip(stacks, maxStacks, liveRem)
    imgui.BeginTooltip()
    pcall(function()
        local header = (stacks >= maxStacks)
            and string.format('Chi Weaver - Boost: %d / %d (MAX)', stacks, maxStacks)
            or string.format('Chi Weaver - Boost: %d / %d', stacks, maxStacks)
        if liveRem > 0 then
            header = header .. string.format(' (%s)', formatTimer(liveRem))
        end
        tooltipText(header)
        if imgui.Separator then imgui.Separator() end

        local perFive = math.floor(stacks / 5)
        tooltipText(string.format('Active Buff: +%d%% Cure Potency, +%d MACC, +%d MAB', perFive, perFive, perFive))

        local mult = getChiBlastMultiplier(stacks)
        local cln  = getCleanseTier(stacks)
        tooltipText(string.format('Chi Blast (5s CD, 20y AoE): %.2fx Heal | %d Cleanse(s)', mult, cln))
        tooltipText('Stacking: +1/hit | +3..5/WS | +5 Boost JA (180s dur)')

        if imgui.Separator then imgui.Separator() end
        tooltipText(cfg.locked
            and 'Position locked (/boost unlock to move, /boost help)'
            or 'Drag to move (/boost lock | /boost hide | /boost help)')
    end)
    imgui.EndTooltip()
end

local function renderHudWindow()
    if not (okImgui and imgui) then
        return
    end

    local inGame, jobId = isPlayerInGame()
    if not inGame then
        return
    end

    if state.lastJobId ~= nil and state.lastJobId ~= jobId then
        state.synced = false
        if jobId ~= 2 then
            state.chiWeaverActive = false
            state.stacks = 0
            state.remSec = 0
        end
    end
    state.lastJobId = jobId

    if jobId == 2 and pollCrystalDllChiWeaver() and not state.synced then
        state.chiWeaverActive = true
        requestBoostSync(false)
    elseif not state.synced and jobId == 2 then
        requestBoostSync(false)
    end

    if cfg.mode == 'hide' then
        return
    end

    if cfg.mode ~= 'show' and not state.chiWeaverActive then
        return
    end

    local s = clamp(tonumber(cfg.scale) or 1.0, 0.75, 2.0)
    local w = math.floor(216 * s)
    local h = math.floor(60 * s)

    local flags = bitBor(
        ImGuiWindowFlags_NoDecoration or 43,
        ImGuiWindowFlags_NoBackground or 128,
        ImGuiWindowFlags_NoSavedSettings or 256,
        ImGuiWindowFlags_NoResize or 2,
        ImGuiWindowFlags_NoScrollWithMouse or 16
    )
    if cfg.locked then
        flags = bitBor(flags, ImGuiWindowFlags_NoMove or 4)
    end

    local condAlways = ImGuiCond_Always or 1
    local condFirst  = ImGuiCond_FirstUseEver or 4
    local posCond    = state.resetPosPending and condAlways or condFirst
    state.resetPosPending = false

    local pushedPad = false
    if ImGuiStyleVar_WindowPadding ~= nil and imgui.PushStyleVar then
        imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 })
        pushedPad = true
    end

    imgui.SetNextWindowPos({ cfg.x or 320, cfg.y or 140 }, posCond)
    imgui.SetNextWindowSize({ w, h }, condAlways)

    if imgui.Begin('##ox_boost_stacks', nil, flags) then
        guard('render', function()
            local wx, wy = toXY(imgui.GetWindowPos())
            if math.abs(wx - (cfg.x or 0)) >= 1 or math.abs(wy - (cfg.y or 0)) >= 1 then
                cfg.x = math.floor(wx + 0.5)
                cfg.y = math.floor(wy + 0.5)
                state.dirtySettings = true
            end

            if state.dirtySettings and (os.clock() - state.lastSaveAt) > 2.0 then
                state.dirtySettings = false
                state.lastSaveAt = os.clock()
                saveSettings()
            end

            local draw = imgui.GetWindowDrawList()
            local stacks = state.stacks
            local maxStacks = state.maxStacks
            local tierCol = getTierColor(stacks, maxStacks)
            local liveRem = getLiveRemainingSeconds()

            -- Outer Crystal panel
            drawPanel(draw, wx, wy, w, h, s, false)

            -- Left 36x36 recessed Crystal socket
            local sx = wx + 10 * s
            local sy = wy + 12 * s
            local sw = 36 * s
            drawPanel(draw, sx, sy, sw, sw, s, true)

            local tex = loadIconTexture()
            if tex ~= nil then
                draw:AddImage(tex, { sx + 2 * s, sy + 2 * s }, { sx + 34 * s, sy + 34 * s }, { 0, 0 }, { 1, 1 }, 0xFFFFFFFF)
            else
                drawFallbackCrystal(draw, sx + 2 * s, sy + 2 * s, 32 * s, 32 * s, tierCol)
            end

            if stacks >= 25 then
                draw:AddRect({ sx, sy }, { sx + sw, sy + sw }, tierCol, 3 * s, 0, (stacks >= maxStacks) and 2.0 or 1.25)
            end

            -- Right content metrics
            local cx = wx + 54 * s
            local rightEdge = wx + w - 11 * s

            -- Row 1: Title + Timer
            drawText(draw, cx, wy + 8 * s, 'Boost Stacks', colors.secondary, 12 * s)

            local rightLabel = ''
            local rightColor = colors.secondary
            if stacks >= maxStacks and liveRem > 0 then
                rightLabel = 'MAX ' .. formatTimer(liveRem)
                rightColor = colors.tier100
            elseif liveRem > 0 then
                rightLabel = formatTimer(liveRem)
                rightColor = (liveRem <= 15) and colors.tier80 or colors.secondary
            elseif not state.chiWeaverActive then
                rightLabel = 'Preview'
                rightColor = colors.muted
            else
                rightLabel = 'Idle'
                rightColor = colors.muted
            end

            local rlWidth = calcTextWidth(rightLabel, 12 * s)
            drawText(draw, rightEdge - rlWidth, wy + 8 * s, rightLabel, rightColor, 12 * s)

            -- Row 2: Stack Counter + Cleanse / Cure Potency Summary
            local countStr = string.format('%d / %d', stacks, maxStacks)
            drawText(draw, cx, wy + 22 * s, countStr, tierCol, 17 * s)

            local perFive = math.floor(stacks / 5)
            local cln = getCleanseTier(stacks)
            local bonusStr = (cln > 0)
                and string.format('+%d%% | %dCln', perFive, cln)
                or string.format('+%d%% Pot', perFive)
            local bonusWidth = calcTextWidth(bonusStr, 11 * s)
            drawText(draw, rightEdge - bonusWidth, wy + 26 * s, bonusStr, (cln > 0) and tierCol or colors.secondary, 11 * s)

            -- Row 3: Progress Gauge with 25 / 50 / 80 milestone ticks
            local bx = cx
            local by = wy + 45 * s
            local bw = rightEdge - cx
            local bh = 7 * s

            draw:AddRectFilled({ bx, by }, { bx + bw, by + bh }, colors.track, 2 * s)
            if stacks > 0 then
                local pct = clamp(stacks / maxStacks, 0.0, 1.0)
                local fw = math.max(3 * s, bw * pct)
                draw:AddRectFilled({ bx, by }, { bx + fw, by + bh }, tierCol, 2 * s)
            end
            draw:AddRect({ bx, by }, { bx + bw, by + bh }, colors.edge, 2 * s)

            for _, frac in ipairs({ 0.25, 0.50, 0.80 }) do
                local tx = bx + bw * frac
                draw:AddLine({ tx, by + 1 * s }, { tx, by + bh - 1 * s }, colors.tick, 1.0)
            end

            if imgui.IsWindowHovered and imgui.IsWindowHovered() then
                drawBoostTooltip(stacks, maxStacks, liveRem)
            end
        end)
    end
    imgui.End()
    if pushedPad and imgui.PopStyleVar then
        imgui.PopStyleVar()
    end
end

-----------------------------------
-- Ashita Events
-----------------------------------
ashita.events.register('load', 'ox_boost_load', function()
    guard('load', function()
        loadSettings()
        if okImgui and imgui and imgui.AddFontFromFileTTF then
            local ok, font = pcall(imgui.AddFontFromFileTTF, 'C:\\Windows\\Fonts\\arial.ttf', 15)
            if ok and font ~= nil then
                state.uiFont = font
            end
        end
        loadIconTexture()
        requestBoostSync(false)
    end)
end)

ashita.events.register('unload', 'ox_boost_unload', function()
    guard('unload', function()
        saveSettings()
        if state.iconTex ~= nil then
            pcall(function()
                state.iconTex:Release()
            end)
            state.iconTex = nil
        end
    end)
end)

ashita.events.register('packet_in', 'ox_boost_packet_in', function(e)
    guard('packet_in', function()
        if type(e) ~= 'table' then
            return
        end
        if e.id == 0x00B then
            state.transitioning = true
            return
        elseif e.id == 0x00A then
            state.transitioning = false
            state.synced = false
            return
        end

        local raw = e.data_modified or e.data
        if e.id ~= 0x017 or type(raw) ~= 'string' or #raw < 25 then
            return
        end

        local msg = string.sub(raw, 24):match('^([^%z]*)')
        if msg == nil or string.sub(msg, 1, #PROTO_TAG) ~= PROTO_TAG then
            return
        end

        e.blocked = true
        local parts = splitPipe(string.sub(msg, #PROTO_TAG + 1))
        local active    = tonumber(parts[1]) or 0
        local stacks    = tonumber(parts[2]) or 0
        local maxStacks = tonumber(parts[3]) or 100
        local remSec    = tonumber(parts[4]) or 0

        state.synced          = true
        state.chiWeaverActive = (active == 1)
        state.stacks          = clamp(math.floor(stacks), 0, math.max(1, math.floor(maxStacks)))
        state.maxStacks       = math.max(1, math.floor(maxStacks))
        state.remSec          = math.max(0, math.floor(remSec))
        state.timerUpdatedAt  = os.clock()
    end)
end)

ashita.events.register('command', 'ox_boost_command', function(e)
    guard('command', function()
        if type(e) ~= 'table' or type(e.command) ~= 'string' then
            return
        end
        local args = parseCommandArgs(e.command)
        if #args == 0 then
            return
        end

        local root = string.lower(args[1] or '')
        if root ~= '/boost' and root ~= '/oxboost' then
            return
        end

        e.blocked = true
        local sub = string.lower(args[2] or '')

        if sub == '' or sub == 'toggle' then
            if cfg.mode == 'hide' then
                cfg.mode = 'auto'
                logMessage('Mode: auto (visible on Chi Weaver).')
            else
                cfg.mode = 'hide'
                logMessage('Mode: hidden (/boost show or /boost auto to restore).')
            end
            saveSettings()
        elseif sub == 'show' then
            cfg.mode = 'show'
            saveSettings()
            logMessage('Mode: always show.')
        elseif sub == 'hide' then
            cfg.mode = 'hide'
            saveSettings()
            logMessage('Mode: hidden.')
        elseif sub == 'auto' then
            cfg.mode = 'auto'
            saveSettings()
            logMessage('Mode: auto (visible on Chi Weaver).')
        elseif sub == 'lock' then
            cfg.locked = true
            saveSettings()
            logMessage('Widget position locked.')
        elseif sub == 'unlock' then
            cfg.locked = false
            saveSettings()
            logMessage('Widget position unlocked (drag to move).')
        elseif sub == 'scale' then
            local n = tonumber(args[3])
            if n == nil then
                logMessage(('Current scale: %.2f (usage: /boost scale 0.75-2.0)'):format(cfg.scale or 1.0))
            else
                cfg.scale = clamp(n, 0.75, 2.0)
                saveSettings()
                logMessage(('Scale set to %.2f.'):format(cfg.scale))
            end
        elseif sub == 'reset' then
            cfg.x = default_settings.x
            cfg.y = default_settings.y
            cfg.scale = default_settings.scale
            cfg.locked = false
            state.resetPosPending = true
            saveSettings()
            logMessage('Reset position and scale to defaults.')
        elseif sub == 'sync' then
            requestBoostSync(true)
            logMessage('Requested Boost stack sync from server.')
        elseif sub == 'status' then
            logMessage(('mode=%s locked=%s scale=%.2f synced=%s chiweaver=%s stacks=%d/%d rem=%ds icon=%s'):format(
                tostring(cfg.mode), tostring(cfg.locked), tonumber(cfg.scale) or 1.0,
                tostring(state.synced), tostring(state.chiWeaverActive),
                state.stacks, state.maxStacks, getLiveRemainingSeconds(),
                tostring(state.iconTex ~= nil)
            ))
        else
            logMessage('Commands: /boost [toggle|show|hide|auto|lock|unlock|scale <n>|sync|status|reset]')
        end
    end)
end)

ashita.events.register('d3d_present', 'ox_boost_present', function()
    guard('d3d_present', renderHudWindow)
end)
