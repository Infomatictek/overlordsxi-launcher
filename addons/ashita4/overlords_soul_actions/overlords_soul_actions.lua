-- OverlordsXI Soul Actions: safe identity viewer for Ashita v4.
-- This module intentionally does NOT rewrite native packets or client resources.
addon.name = 'overlords_soul_actions'
addon.author = 'OverlordsXI'
addon.version = '0.3.1'
addon.desc = 'Soul-specific spell, ability and weapon skill identities.'
addon.link = 'https://github.com/Infomatictek/overlordsxi-launcher'
require('common')
local imgui = require('imgui')
local catalog = require('catalog')
local builtinProfiles = require('builtin_profiles')
builtinProfiles.install(catalog)
local profiles = require('profiles')
local presentation = require('presentation')
local soulBridge = require('soul_bridge')
local soulPacket = require('soul_packet')
local resourceAudit = require('resource_audit')
local state = { soul = nil, visible = false, lastJob = 0, lastCharacter = 0,
    lastPoll = -100, selected = nil, preview = false, source = 'none',
    packetSoul = nil, packetJob = 0, lastDllStatus = nil }
local function log(message) print('[Soul Actions] ' .. tostring(message)) end
local function inGame()
    local ok, job, character = pcall(function()
        local m = AshitaCore:GetMemoryManager()
        if not m then return 0 end
        local p, party = m:GetPlayer(), m:GetParty()
        if not p or not party or not party:GetMemberName(0) or party:GetMemberTargetIndex(0) == 0 then return 0, 0 end
        return p:GetMainJob() or 0, party:GetMemberServerId(0) or 0
    end)
    return ok and tonumber(job) or 0, ok and tonumber(character) or 0
end
local function reset()
    state.soul = nil
    state.selected = nil
    state.preview = false
    state.source = 'none'
    state.packetSoul, state.packetJob = nil, 0
    state.lastDllStatus = nil
    -- Catalog is local data and survives zoning or job changes.
    -- /soulactions clear explicitly unloads it.
end
-- Local preview is deliberately separate from client-verified DLL Soul state.
-- /soulactions preview <key> is for testing only, not proof of active Soul.
ashita.events.register('command', 'osa_command', function(e)
    local args = {}
    for word in tostring(e.command):gmatch('%S+') do args[#args+1] = word end
    if not args[1] or args[1]:lower() ~= '/soulactions' then return end
    e.blocked = true
    local op = (args[2] or 'help'):lower()
    if op == 'show' then state.visible = true
    elseif op == 'hide' then state.visible = false
    elseif op == 'toggle' then state.visible = not state.visible
    elseif op == 'clear' then reset(); catalog.clear(); builtinProfiles.install(catalog); log('Cleared preview and restored built-in Soul identities.')
    elseif op == 'status' then
        local d = state.lastDllStatus
        log('Soul=' .. tostring(state.soul or 'unknown') .. ', source=' .. state.source ..
            ', DLL=' .. (d and ('enabled=' .. tostring(d.enabled) .. ', known=' .. tostring(d.known) ..
            ', job=' .. tostring(d.job) .. ', branch=' .. tostring(d.branch) ..
            ', character=' .. tostring(d.character_id)) or 'unavailable'))
    elseif op == 'preview' and args[3] and args[3]:match('^[%w_%-]+$') then
        state.soul = soulPacket.canonicalKey(args[3])
        state.preview = true
        state.source = 'manual preview'
        state.visible = true
        log('Preview mode; Soul identity has NOT been verified by the server.')
    elseif op == 'reset' then
        reset(); catalog.clear(); builtinProfiles.install(catalog)
        log('Restored built-in Soul action identities.')
    elseif op == 'load' then
        local path = type(addon.path) == 'string' and (addon.path .. '/actions.tsv') or nil
        if not path then log('Addon path unavailable.'); return end
        local count, why = profiles.load(path, catalog)
        if count then
            state.selected = nil
            log('Loaded ' .. tostring(count) .. ' local action identities (client preview only).')
        else log('Profile rejected: ' .. tostring(why)) end
    elseif op == 'inspect' then
        local kind, id = args[3], tonumber(args[4])
        local entry = presentation.resolve(catalog, state.soul, kind, id)
        if entry then log(entry.name .. ': ' .. entry.description)
        else log('No client identity for the current preview Soul and action.') end
    elseif op == 'demo' then
        reset()
        catalog.clear()
        catalog.register('astromancer', 'spell', 1, {
            name = 'Tsunami', description = 'Demonstration only: a deliberate water incantation.',
            castTime = 12, mpCost = 100, effectProfile = 'tsunami' })
        state.soul = 'astromancer'
        state.preview = true
        state.source = 'demo'
        state.visible = true
        log('Loaded demonstration data only; spell ID and values are not verified.')
    else
        log('Commands: /soulactions show|hide|toggle|status|clear|reset|demo|load|inspect <kind> <id>|preview <soul>')
    end
end)
ashita.events.register('load', 'osa_load', function() log('Identity viewer loaded. Use /soulactions demo to inspect a sample.') end)
ashita.events.register('unload', 'osa_unload', function() resourceAudit.cancel(); reset() end)
ashita.events.register('packet_in', 'osa_zone', function(e)
    -- 0x00A zone transition; do not retain stale identities.
    if e.id == 0x00B or e.id == 0x00A then reset(); return end
    if e.id == 0x1FC then
        local job = inGame()
        local payload = soulPacket.decode(e.data, job)
        if payload then
            state.packetSoul, state.packetJob = payload.soul, payload.job
            if not state.preview then
                state.soul = payload.soul
                state.source = payload.soul and 'Soul HUD packet' or 'no active Soul'
                state.selected = nil
            end
        end
    end
end)
ashita.events.register('d3d_present', 'osa_render', function()
    local job, character = inGame()
    if job == 0 or character == 0 then
        if state.lastJob ~= 0 then reset() end
        state.lastJob, state.lastCharacter = 0, 0
        return
    end
    if (state.lastJob ~= 0 and job ~= state.lastJob)
        or (state.lastCharacter ~= 0 and character ~= state.lastCharacter) then reset() end
    state.lastJob, state.lastCharacter = job, character
    local now = os.clock()
    if not state.preview and now - state.lastPoll >= 1 then
        state.lastPoll = now
        local dllStatus = soulBridge.read()
        state.lastDllStatus = dllStatus
        local active = soulBridge.resolve(dllStatus, job, character)
        if active then
            if state.soul ~= active then state.selected = nil end
            state.soul = active
            state.source = 'Crystal Jobs client state'
        elseif state.packetJob == job and state.packetSoul then
            state.soul = state.packetSoul
            state.source = 'Soul HUD packet'
        else
            state.soul = nil
            state.source = dllStatus and 'DLL has no valid active Soul' or 'Crystal Jobs DLL unavailable'
        end
    end
    if resourceAudit.running() then
        local progress = resourceAudit.step(20)
        if progress and progress.complete then
            log(('Client resource inventory complete: %d records. File: %s'):format(
                progress.count, progress.path))
        end
    end
    if not state.visible then return end
    local open = { true }
    if imgui.Begin('OverlordsXI Soul Actions', open) then
        imgui.Text('Soul: ' .. (state.soul or 'Not synchronized'))
        imgui.TextDisabled('Identity: ' .. state.source)
        if resourceAudit.running() then
            imgui.TextDisabled('Exporting native action resources in small batches...')
        elseif imgui.Button('Export native spell and ability IDs') then
            local ok, manager = pcall(function()
                return AshitaCore:GetResourceManager()
            end)
            local started, why = resourceAudit.start(ok and manager or nil, addon.path)
            if started then log('Started read-only native resource export.')
            else log('Could not start export: ' .. tostring(why)) end
        end
        imgui.Separator()
        local soul = catalog.souls[state.soul] or {}
        local count = 0
        for _, kind in ipairs({ 'spell', 'ability', 'weaponskill' }) do
            local entries = soul[kind] or {}
            local ids = {}
            for id in pairs(entries) do ids[#ids+1] = id end
            table.sort(ids)
            if #ids > 0 then imgui.Text(kind:upper()) end
            for _, id in ipairs(ids) do
                local entry = entries[id]
                count = count + 1
                if imgui.Selectable(entry.name .. '##' .. kind .. id, state.selected == kind .. ':' .. id) then
                    state.selected = kind .. ':' .. id
                end
                if state.selected == kind .. ':' .. id then
                    imgui.TextWrapped(entry.description)
                    if entry.castTime then imgui.Text('Cast: ' .. tostring(entry.castTime) .. 's') end
                    if entry.recastTime then imgui.Text('Recast: ' .. tostring(entry.recastTime) .. 's') end
                    if entry.mpCost then imgui.Text('MP: ' .. tostring(entry.mpCost)) end
                    if entry.tpCost then imgui.Text('TP: ' .. tostring(entry.tpCost)) end
                end
            end
        end
        if count == 0 then imgui.TextWrapped('No custom client action definitions available for this Soul yet.') end
        imgui.TextDisabled('Viewer only: native menus, logs, cast bars and VFX unchanged.')
    end
    imgui.End()
    if not open[1] then state.visible = false end
end)
