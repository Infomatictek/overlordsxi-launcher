addon.name = 'crystalsocket'
addon.author = 'OverlordsXI / Crystal Socket'
addon.version = '0.3.0'
addon.desc = 'OverlordsXI Soul Job crystal socket integrated with the Equipment menu.'

require('common')
local ffi = require('ffi')
local d3d8 = require('d3d8')
local imgui = require('imgui')
local protocol = require('protocol')
local state = require('state').new()
local UI = require('ui')
local Menu = require('menu')

local ui, menu
local textures, asset_status = {}, {}
local preload_names = { 'commander', 'berserker', 'gladiator', 'sensei', 'medic', 'sage' }
local epoch, transitioning = 0, false
local captured = {}
local last_mouse
local was_anchored, last_anchor_refresh = false, 0
local transport = { queued = 0, outgoing = 0, incoming = 0 }
local keys = { [1] = 'back', [200] = 'up', [208] = 'down', [28] = 'enter', [156] = 'enter' }

local function now()
    return ashita.time.get_tick64() / 1000
end

local function reset(reason)
    epoch = epoch + 1
    state:reset(reason, false)
    if ui then ui:close() end
end

local function load_icon_texture(name)
    if type(name) ~= 'string' or name == '' then return nil end
    if textures[name] ~= nil then return tonumber(ffi.cast('uint32_t', textures[name])) end

    local ok, result, tex = pcall(function()
        if type(addon.path) ~= 'string' then return 'addon path unavailable', nil end
        local safe = name:gsub('[^%w_%-]', '')
        if safe == '' then return 'invalid asset name', nil end
        local file = io.open(addon.path:gsub('[/\\]+$', '') .. '/assets/' .. safe .. '.png', 'rb')
        if not file then return 'file unavailable', nil end
        local data = file:read('*a')
        file:close()
        if not data or #data == 0 then return 'file unreadable', nil end
        local out = ffi.new('IDirect3DTexture8*[1]')
        local hr = ffi.C.D3DXCreateTextureFromFileInMemoryEx(d3d8.get_device(), data,
            #data, 0xFFFFFFFF, 0xFFFFFFFF, 1, 0, ffi.C.D3DFMT_A8R8G8B8,
            ffi.C.D3DPOOL_MANAGED, ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT, 0, nil, nil, out)
        if hr ~= ffi.C.S_OK or out[0] == nil then
            if out[0] ~= nil then out[0]:Release() end
            return 'texture failed (' .. tostring(hr) .. ')', nil
        end
        return 'ready', out[0]
    end)

    if ok and tex then
        textures[name] = tex
        asset_status[name] = 'ready'
        return tonumber(ffi.cast('uint32_t', tex))
    end

    asset_status[name] = ok and result or 'texture API unavailable'
    return nil
end

local function context()
    local memory = AshitaCore:GetMemoryManager()
    local party = memory:GetParty()
    local player = memory:GetPlayer()
    local id, name = party:GetMemberServerId(0), party:GetMemberName(0)
    if transitioning or id == 0 or name == nil or name == '' or party:GetMemberTargetIndex(0) == 0 then
        state:set_context(nil, nil, nil, nil)
        return
    end
    local lvl = player.GetMainJobLevel and player:GetMainJobLevel() or nil
    local changed = state:set_context(tostring(id) .. ':' .. name .. ':' .. epoch,
        player:GetMainJob(), party:GetMemberZone(0), lvl)
    if changed and ui then ui.feedback = nil end
end

local function send(packet)
    if type(packet) ~= 'string' or #packet ~= 16 then return nil, 'Invalid crystal packet.' end
    local bytes = { packet:byte(1, #packet) }
    AshitaCore:GetPacketManager():AddOutgoingPacket(protocol.REQUEST_ID, bytes)
    transport.queued = transport.queued + 1
    transport.request_id = bytes[11] + bytes[12] * 256
    return true
end

local function hex16(packet)
    if type(packet) ~= 'string' then return '?' end
    return (packet:sub(1, 16):gsub('.', function(byte) return ('%02X'):format(byte:byte()) end))
end

local function event_packet(e)
    local buffer, size = e.data_modified or e.data, e.size
    if type(buffer) ~= 'string' or type(size) ~= 'number' or size % 1 ~= 0
        or size < 0 or size > 512 or size > #buffer then
        return nil, 'Invalid custom packet event size.'
    end
    return buffer:sub(1, size)
end

local function can_capture_keys()
    return state:snapshot().open and AshitaCore:GetChatManager():IsInputOpen() == 0
end

ashita.events.register('command', 'crystalsocket_command', function(e)
    local cmd = e.command:lower()
    if cmd:match('^/crystalsocket%s+sync%s*$') then
        e.blocked = true
        context()
        local ok, why = state:sync_current(now(), send, true)
        if not ok then
            print('[crystalsocket] Sync failed: ' .. tostring(why))
        else
            print('[crystalsocket] Syncing soul crystals for current job...')
        end
        return
    end
    if not cmd:match('^/crystalsocket%s+status%s*$') then return end
    e.blocked = true
    local lines = {}
    local function report(line)
        lines[#lines + 1] = line
        print(line)
    end
    local snapshot = state:snapshot()
    local loaded_assets = {}
    for k, st in pairs(asset_status) do
        loaded_assets[#loaded_assets + 1] = k .. ':' .. st
    end
    table.sort(loaded_assets)
    report(('[crystalsocket] version=%s assets=[%s]'):format(addon.version, table.concat(loaded_assets, ', ')))
    report(('[crystalsocket] model=%s session=%s job=%s lvl=%s loaded=%s pending=%s open=%s active=%s owned=%s'):format(
        tostring(snapshot.status), tostring(snapshot.session_key), tostring(snapshot.current_job),
        tostring(snapshot.current_lvl), tostring(snapshot.loaded), tostring(snapshot.pending),
        tostring(snapshot.open), tostring(snapshot.active), tostring(snapshot.owned_mask)))
    report(('[crystalsocket] catalog_entries=%d'):format(snapshot.catalog and #(snapshot.catalog.entries or {}) or -1))
    report('[crystalsocket] ' .. tostring(snapshot.message))
    report(('[crystalsocket] tx queued=%d request=%s observed=%d size=%s buffer=%s injected=%s blocked=%s'):format(
        transport.queued, tostring(transport.request_id), transport.outgoing, tostring(transport.out_size),
        tostring(transport.out_buffer), tostring(transport.out_injected), tostring(transport.out_blocked)))
    report('[crystalsocket] tx16=' .. tostring(transport.out_hex))
    report(('[crystalsocket] rx=%d size=%s buffer=%s request=%s expected=%s matched=%s result=%s error=%s'):format(
        transport.incoming, tostring(transport.in_size), tostring(transport.in_buffer), tostring(transport.in_request),
        tostring(transport.in_expected), tostring(transport.in_matched), tostring(transport.in_result),
        tostring(transport.in_error)))
    if ui then
        local slot = ui.lastslot
        local function n(value) return value and ('%.1f'):format(value) or '?' end
        report(('[crystalsocket] slot=%s hover=%s clicks=%d scale=%s,%s anchor=%s,%s'):format(
            tostring(slot.visible), tostring(slot.hovered), slot.clicks, n(ui.sx), n(ui.sy),
            n(slot.anchor_x), n(slot.anchor_y)))
    end
    if last_mouse then
        report(('[crystalsocket] mouse event=%s xy=%s,%s blocked=%s'):format(
            tostring(last_mouse.message), tostring(last_mouse.x), tostring(last_mouse.y), tostring(last_mouse.blocked)))
    end
    if type(addon.path) == 'string' then
        local file = io.open(addon.path:gsub('[/\\]+$', '') .. '/crystalsocket-status.log', 'w')
        if file then file:write(table.concat(lines, '\n'), '\n'); file:close() end
    end
end)

ashita.events.register('mouse', 'crystalsocket_mouse_diagnostic', function(e)
    last_mouse = last_mouse or {}
    last_mouse.message, last_mouse.x, last_mouse.y, last_mouse.blocked = e.message, e.x, e.y, e.blocked
end)

ashita.events.register('load', 'crystalsocket_load', function()
    local ok, scaling = pcall(require, 'scaling')
    if not ok or scaling.scaled.w <= 0 or scaling.scaled.h <= 0 then
        print('[crystalsocket] Menu scaling is unavailable; socket hidden.')
        return
    end
    menu = Menu.new(ashita.memory, scaling, AshitaCore:GetPointerManager():Get('menu'))
    ui = UI.new(imgui, state, send, scaling, load_icon_texture)
    local font_ok, font = pcall(imgui.AddFontFromFileTTF, 'C:\\Windows\\Fonts\\arial.ttf', 14)
    if font_ok then ui.font = font end
    for _, name in ipairs(preload_names) do
        local tex = load_icon_texture(name)
        if tex then ui.icons[name] = tex end
    end
    if not menu.manager then print('[crystalsocket] Menu layout unavailable; socket hidden.') end
end)

ashita.events.register('packet_in', 'crystalsocket_packet_in', function(e)
    if e.id == protocol.RESPONSE_ID then
        -- Reserved replies must never reach the stock packet dispatcher, including malformed replies.
        e.blocked = true
        context()
        local packet, boundary_error = event_packet(e)
        local decoded = packet and protocol.decode_packet(packet) or nil
        transport.incoming = transport.incoming + 1
        local buffer = e.data_modified or e.data
        transport.in_size, transport.in_buffer = e.size, type(buffer) == 'string' and #buffer or nil
        transport.in_request = decoded and decoded.request_id
        transport.in_result = decoded and decoded.result
        transport.in_expected = state:snapshot().pending_request
        transport.in_matched = decoded ~= nil and transport.in_expected == decoded.request_id
        if packet then
            local _, why = state:receive(packet, now())
            transport.in_error = why
        else
            transport.in_error = boundary_error
        end
        return
    end
    if e.id == 0x00A then
        transitioning = false
        reset('Zone changed; syncing soul crystals...')
    elseif e.id == 0x00B then
        transitioning = true
        reset('Changing zones...')
        state:set_context(nil, nil, nil, nil)
    end
end)

ashita.events.register('packet_out', 'crystalsocket_packet_out', function(e)
    if e.id == protocol.REQUEST_ID then
        local packet = event_packet(e)
        transport.outgoing = transport.outgoing + 1
        local buffer = e.data_modified or e.data
        transport.out_size, transport.out_buffer = e.size, type(buffer) == 'string' and #buffer or nil
        transport.out_hex = hex16(packet)
        transport.out_injected, transport.out_blocked = e.injected, e.blocked
        return
    end
    if e.id == 0x00D then
        transitioning = true
        reset('Leaving this session...')
        state:set_context(nil, nil, nil, nil)
    end
end)

ashita.events.register('key_data', 'crystalsocket_key_data', function(e)
    local key = keys[e.key]
    if not ui or not key then return end
    if captured[e.key] then e.blocked = true end
    if e.down and can_capture_keys() then
        if not captured[e.key] then ui:key(key, now()) end
        captured[e.key] = true
        e.blocked = true
    end
end)

ashita.events.register('key_state', 'crystalsocket_key_state', function(e)
    if not ui or not e.data_raw or e.size < 209 then return end
    local data = ffi.cast('uint8_t*', e.data_raw)
    for scan, key in pairs(keys) do
        if data[scan] == 0 then
            captured[scan] = nil
        elseif captured[scan] or can_capture_keys() then
            if not captured[scan] then ui:key(key, now()) end
            captured[scan] = true
            data[scan] = 0
        end
    end
end)

ashita.events.register('d3d_present', 'crystalsocket_present', function()
    context()
    local ts = now()
    state:tick(ts)
    state:ensure_loaded(ts, send)
    local snap = state:snapshot()
    local anchor = snap.session_key and menu and menu:anchor() or nil
    if anchor and not was_anchored and snap.loaded and not snap.pending and (ts - last_anchor_refresh) >= 2 then
        last_anchor_refresh = ts
        state:sync_current(ts, send, false)
    end
    was_anchored = anchor ~= nil
    if ui then
        ui:draw(anchor, ts)
    end
end)

ashita.events.register('unload', 'crystalsocket_unload', function()
    state:set_context(nil, nil, nil, nil)
    if ui then ui:close(); ui.icons = {} end
    ui, menu = nil, nil
    for name, texture in pairs(textures) do
        texture:Release()
        textures[name] = nil
    end
    asset_status = {}
end)
