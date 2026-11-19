-- OverlordsXI Soul Actions: safe identity viewer for Ashita v4.
-- This module intentionally does NOT rewrite native packets or client resources.
addon.name = 'overlords_soul_actions'
addon.author = 'OverlordsXI'
addon.version = '0.1.0'
addon.desc = 'Soul-specific spell, ability and weapon skill identities.'
addon.link = 'https://github.com/Infomatictek/overlordsxi-launcher'
require('common')
local imgui = require('imgui')
local catalog = require('catalog')
local profiles = require('profiles')
local presentation = require('presentation')
local state = { soul = nil, visible = false, transitioning = false, lastJob = 0, selected = nil }
local function log(message) print('[Soul Actions] ' .. tostring(message)) end
local function inGame()
    local ok, job = pcall(function()
        local m = AshitaCore:GetMemoryManager()
        if not m then return 0 end
        local p, party = m:GetPlayer(), m:GetParty()
        if not p or not party or not party:GetMemberName(0) or party:GetMemberTargetIndex(0) == 0 then return 0 end
        return p:GetMainJob() or 0
    end)
    return ok and tonumber(job) or 0
end
local function reset()
    state.soul = nil
    state.selected = nil
    catalog.clear()
end
-- Manual local preview is deliberately separate from verified server sync.
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
    elseif op == 'clear' then reset(); log('Cleared identity data.')
    elseif op == 'status' then log('Soul=' .. tostring(state.soul or 'unknown') .. ', entries=' .. tostring(catalog.souls[state.soul] and 'loaded' or 'none'))
    elseif op == 'preview' and args[3] and args[3]:match('^[%w_%-]+$') then
        state.soul = args[3]:lower()
        state.visible = true
        log('Preview mode; Soul identity has NOT been verified by the server.')
    elseif op == 'load' then
        local path = type(addon.path) == 'string' and
            (addon.path:gsub('[/\\]+
        reset()
        catalog.register('astromancer', 'spell', 1, {
            name = 'Tsunami', description = 'Demonstration only: a deliberate water incantation.',
            castTime = 12, mpCost = 100, effectProfile = 'tsunami' })
        state.soul = 'astromancer'
        state.visible = true
        log('Loaded demonstration data only; spell ID and values are not verified.')
    else
        log('Commands: /soulactions show|hide|toggle|status|clear|demo|load|inspect <kind> <id>|preview <soul>')
    end
end)
ashita.events.register('load', 'osa_load', function() log('Identity viewer loaded. Use /soulactions demo to inspect a sample.') end)
ashita.events.register('unload', 'osa_unload', function() reset() end)
ashita.events.register('packet_in', 'osa_zone', function(e)
    -- 0x00A zone transition; do not retain stale identities.
    if e.id == 0x00A then reset() end
end)
ashita.events.register('d3d_present', 'osa_render', function()
    local job = inGame()
    if job == 0 then
        if state.lastJob ~= 0 then reset() end
        state.lastJob = 0
        return
    end
    if state.lastJob ~= 0 and job ~= state.lastJob then reset() end
    state.lastJob = job
    if not state.visible then return end
    local open = { true }
    if imgui.Begin('OverlordsXI Soul Actions', open) then
        imgui.Text('Soul: ' .. (state.soul or 'Not synchronized'))
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
        if count == 0 then imgui.TextWrapped('No server-verified Soul action definitions loaded.') end
        imgui.TextDisabled('Viewer only: native menus, logs, cast bars and VFX unchanged.')
    end
    imgui.End()
    if not open[1] then state.visible = false end
end)
, '') .. '/actions.tsv') or nil
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
        catalog.register('astromancer', 'spell', 1, {
            name = 'Tsunami', description = 'Demonstration only: a deliberate water incantation.',
            castTime = 12, mpCost = 100, effectProfile = 'tsunami' })
        state.soul = 'astromancer'
        state.visible = true
        log('Loaded demonstration data only; spell ID and values are not verified.')
    else
        log('Commands: /soulactions show|hide|toggle|status|clear|demo|preview <soul>')
    end
end)
ashita.events.register('load', 'osa_load', function() log('Identity viewer loaded. Use /soulactions demo to inspect a sample.') end)
ashita.events.register('unload', 'osa_unload', function() reset() end)
ashita.events.register('packet_in', 'osa_zone', function(e)
    -- 0x00A zone transition; do not retain stale identities.
    if e.id == 0x00A then reset() end
end)
ashita.events.register('d3d_present', 'osa_render', function()
    local job = inGame()
    if job == 0 then
        if state.lastJob ~= 0 then reset() end
        state.lastJob = 0
        return
    end
    if state.lastJob ~= 0 and job ~= state.lastJob then reset() end
    state.lastJob = job
    if not state.visible then return end
    local open = { true }
    if imgui.Begin('OverlordsXI Soul Actions', open) then
        imgui.Text('Soul: ' .. (state.soul or 'Not synchronized'))
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
        if count == 0 then imgui.TextWrapped('No server-verified Soul action definitions loaded.') end
        imgui.TextDisabled('Viewer only: native menus, logs, cast bars and VFX unchanged.')
    end
    imgui.End()
    if not open[1] then state.visible = false end
end)
