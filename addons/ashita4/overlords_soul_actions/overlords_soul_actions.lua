-- OverlordsXI Soul Actions: native Soul action synchronization, macro resolution,
-- local combat-log presentation, and optional ImGui inspector for Ashita v4.
addon.name = 'overlords_soul_actions'
addon.author = 'OverlordsXI'
addon.version = '0.4.1'
addon.desc = 'Soul-specific spell, ability, and weapon skill native presentation.'
addon.link = 'https://github.com/Infomatictek/overlordsxi-launcher'
require('common')
local imgui = require('imgui')
local catalog = require('catalog')
local builtinProfiles = require('builtin_profiles')
local profiles = require('profiles')
local presentation = require('presentation')
local soulBridge = require('soul_bridge')
local soulPacket = require('soul_packet')
local resourceAudit = require('resource_audit')
local nativeActions = require('native_actions')
local macroResolver = require('macro_resolver')
local combatLog = require('combat_log')

local state = {
    soul = nil,
    visible = false,
    lastJob = 0,
    lastCharacter = 0,
    lastPlayerName = nil,
    lastPoll = -100,
    selected = nil,
    preview = false,
    source = 'none',
    packetSoul = nil,
    packetJob = 0,
    lastDllStatus = nil,
    lastActionStatus = nil,
    catalogSynced = false,
    lastSyncedSoul = nil,
    textSeen = 0,
    textRewritten = 0,
    castNameMisses = 0,
}

local vanillaCache = { spell = {}, ability = {}, weaponskill = {} }

local function log(message) print('[Soul Actions] ' .. tostring(message)) end

local function readVanillaName(kind, id)
    local bucket = vanillaCache[kind]
    if bucket and bucket[id] ~= nil then
        return bucket[id] or nil
    end
    local ok, name = pcall(function()
        local rm = AshitaCore:GetResourceManager()
        if not rm then return nil end
        local rec = (kind == 'spell') and rm:GetSpellById(id) or rm:GetAbilityById(id)
        if not rec or not rec.Name then return nil end
        for _, idx in ipairs({ 3, 1, 2 }) do
            local v = rec.Name[idx]
            if type(v) == 'string' and v ~= '' then return v end
        end
        return nil
    end)
    local resolved = (ok and type(name) == 'string' and name ~= '') and name or false
    if bucket then bucket[id] = resolved end
    return resolved or nil
end

local function syncNativeCatalog()
    local ok, countOrErr = nativeActions.syncCatalog(catalog)
    state.catalogSynced = ok == true
    return ok, countOrErr
end

local function loadExternalDefaults()
    local count, why, path = builtinProfiles.install(catalog, addon.path)
    if why then
        log('External definitions warning (' .. tostring(path) .. '): ' .. tostring(why))
    end
    syncNativeCatalog()
    return count, why, path
end

local function inGame()
    local ok, job, character, name = pcall(function()
        local m = AshitaCore:GetMemoryManager()
        if not m then return 0, 0, nil end
        local p, party = m:GetPlayer(), m:GetParty()
        if not p or not party or not party:GetMemberName(0) or party:GetMemberTargetIndex(0) == 0 then
            return 0, 0, nil
        end
        return p:GetMainJob() or 0, party:GetMemberServerId(0) or 0, party:GetMemberName(0)
    end)
    return ok and tonumber(job) or 0, ok and tonumber(character) or 0, ok and name or nil
end

local function reset()
    state.soul = nil
    state.selected = nil
    state.preview = false
    state.source = 'none'
    state.packetSoul, state.packetJob = nil, 0
    state.lastDllStatus = nil
    state.lastSyncedSoul = nil
    nativeActions.clearActiveSoul()
end

-- Initial external data load + native catalog sync.
loadExternalDefaults()

-- Slash commands and active-Soul macro translation.
ashita.events.register('command', 'osa_command', function(e)
    local raw = tostring(e.command or '')
    -- Translate active Soul action names in /ma, /nin, /ja, /ws commands and macros.
    if not state.preview and state.soul then
        local rewritten = macroResolver.translate(raw, catalog, state.soul, readVanillaName)
        if rewritten then
            e.command = rewritten
            return
        end
    end

    local args = {}
    for word in raw:gmatch('%S+') do args[#args + 1] = word end
    if not args[1] or args[1]:lower() ~= '/soulactions' then return end
    e.blocked = true
    local op = (args[2] or 'help'):lower()
    if op == 'show' then state.visible = true
    elseif op == 'hide' then state.visible = false
    elseif op == 'toggle' then state.visible = not state.visible
    elseif op == 'clear' then
        reset()
        catalog.clear()
        loadExternalDefaults()
        log('Cleared preview and reloaded external Soul action definitions.')
    elseif op == 'reload' or op == 'reset' then
        local count, why, path = loadExternalDefaults()
        if why then log('Reload failed: ' .. tostring(why))
        else log(('Reloaded %d external Soul action definitions from %s (native sync=%s).'):format(
            count, tostring(path), tostring(state.catalogSynced))) end
    elseif op == 'status' then
        local d = state.lastDllStatus
        local a = nativeActions.readStatus()
        state.lastActionStatus = a
        log('Soul=' .. tostring(state.soul or 'unknown') .. ', source=' .. state.source ..
            ', DLL=' .. (d and ('enabled=' .. tostring(d.enabled) .. ', known=' .. tostring(d.known) ..
            ', job=' .. tostring(d.job) .. ', branch=' .. tostring(d.branch) ..
            ', character=' .. tostring(d.character_id)) or 'unavailable') ..
            ', NativeActions=' .. (a and ('hooks=' .. tostring(a.total_hooks) .. '/' .. tostring(a.expected_hooks) ..
            ', catalog=' .. tostring(a.catalog_count) .. ', gen=' .. tostring(a.catalog_generation) ..
            ', caps=0x' .. string.format('%x', a.capabilities)) or 'unavailable'))
    elseif op == 'logstatus' then
        log(('Combat log: seen=%d rewritten=%d candidate_misses=%d soul=%s player=%s'):format(
            state.textSeen, state.textRewritten, state.castNameMisses,
            tostring(state.soul), tostring(state.lastPlayerName)))
    elseif op == 'capabilities' then
        local a = nativeActions.readStatus()
        state.lastActionStatus = a
        if not a then
            log('Native Action API unavailable (crystaljobs.dll not loaded or unsupported build).')
            return
        end
        log(('Native hooks: %d/%d, catalog=%d (gen=%d), hits: mag=%d/%d/%d abi=%d/%d/%d'):format(
            a.total_hooks, a.expected_hooks, a.catalog_count, a.catalog_generation,
            a.magic_name_hits, a.magic_desc_hits, a.magic_icon_hits,
            a.ability_name_hits, a.ability_desc_hits, a.ability_icon_hits))
        for _, cap in ipairs(nativeActions.CAPABILITIES) do
            local active = math.floor(a.capabilities / cap.bit) % 2 == 1
            log(('  [%s] %s'):format(active and 'OK' or '--', cap.name))
        end
    elseif op == 'preview' and args[3] and args[3]:match('^[%w_%-]+$') then
        state.soul = soulPacket.canonicalKey(args[3])
        state.preview = true
        state.source = 'manual preview'
        state.visible = true
        log('Preview mode; Soul identity has NOT been verified by the server.')
    elseif op == 'load' then
        local path = type(addon.path) == 'string' and (addon.path .. '/actions.tsv') or nil
        if not path then log('Addon path unavailable.'); return end
        local count, why = profiles.load(path, catalog)
        if count then
            state.selected = nil
            syncNativeCatalog()
            log('Loaded ' .. tostring(count) .. ' local action identities and synced to native DLL.')
        else log('Profile rejected: ' .. tostring(why)) end
    elseif op == 'inspect' then
        local kind, id = args[3], tonumber(args[4])
        local entry = presentation.resolve(catalog, state.soul, kind, id)
        if entry then log(entry.name .. ': ' .. entry.description)
        else log('No client identity for the current Soul and action.') end
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
        log('Commands: /soulactions show|hide|toggle|status|logstatus|capabilities|reload|clear|reset|load|inspect <kind> <id>|preview <soul>')
    end
end)

-- Local-player-only in-place combat-log action-name presentation (zero duplicate lines).
ashita.events.register('text_in', 'osa_text_in', function(e)
    if e.blocked or state.preview or not state.soul or not state.lastPlayerName then return end
    -- In Ashita an empty message_modified is truthy in Lua. Prefer its content
    -- only when populated, otherwise inspect the original message.
    local current = type(e.message_modified) == 'string' and e.message_modified ~= ''
        and e.message_modified or e.message
    if type(current) ~= 'string' or current == '' then return end
    state.textSeen = state.textSeen + 1
    local rewritten = combatLog.rewriteLine(current,
        state.lastPlayerName, catalog, state.soul, readVanillaName)
    if rewritten then
        state.textRewritten = state.textRewritten + 1
        e.message_modified = rewritten
    elseif current:find('Utsusemi', 1, true) then
        -- Diagnostics only; do not rewrite unverified actor messages.
        state.castNameMisses = state.castNameMisses + 1
    end
end)

ashita.events.register('load', 'osa_load', function()
    syncNativeCatalog()
    log('Native Soul Actions loaded. Use /soulactions capabilities to inspect active hooks.')
end)

ashita.events.register('unload', 'osa_unload', function()
    resourceAudit.cancel()
    reset()
end)

ashita.events.register('packet_in', 'osa_zone', function(e)
    -- 0x00A / 0x00B zone transitions: never retain stale identities.
    if e.id == 0x00B or e.id == 0x00A then reset(); return end
    if e.id == 0x1FC then
        local job, character = inGame()
        local payload = soulPacket.decode(e.data, job)
        if payload then
            state.packetSoul, state.packetJob = payload.soul, payload.job
            if not state.preview then
                state.soul = payload.soul
                state.source = payload.soul and 'Soul HUD packet' or 'no active Soul'
                state.selected = nil
                if state.soul then nativeActions.setActiveSoul(state.soul, character)
                else nativeActions.clearActiveSoul() end
                state.lastSyncedSoul = state.soul
            end
        end
    end
end)

ashita.events.register('d3d_present', 'osa_render', function()
    local job, character, playerName = inGame()
    if job == 0 or character == 0 then
        if state.lastJob ~= 0 then reset() end
        state.lastJob, state.lastCharacter, state.lastPlayerName = 0, 0, nil
        return
    end
    if (state.lastJob ~= 0 and job ~= state.lastJob)
        or (state.lastCharacter ~= 0 and character ~= state.lastCharacter) then
        reset()
    end
    state.lastJob, state.lastCharacter, state.lastPlayerName = job, character, playerName
    local now = os.clock()
    if not state.preview and now - state.lastPoll >= 1 then
        state.lastPoll = now
        if not state.catalogSynced then syncNativeCatalog() end
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
        if state.soul ~= state.lastSyncedSoul then
            state.lastSyncedSoul = state.soul
            if state.soul then nativeActions.setActiveSoul(state.soul, character)
            else nativeActions.clearActiveSoul() end
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
        local ast = nativeActions.readStatus()
        state.lastActionStatus = ast
        if ast then
            imgui.TextDisabled(('Native Hooks: %d/%d | Catalog: %d (gen %d)'):format(
                ast.total_hooks, ast.expected_hooks, ast.catalog_count, ast.catalog_generation))
        else
            imgui.TextDisabled('Native Action API: unavailable')
        end
        if imgui.Button('Reload external definitions') then
            loadExternalDefaults()
        end
        imgui.SameLine()
        if resourceAudit.running() then
            imgui.TextDisabled('Exporting...')
        elseif imgui.Button('Export native spell/ability IDs') then
            local ok, manager = pcall(function() return AshitaCore:GetResourceManager() end)
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
            for id in pairs(entries) do ids[#ids + 1] = id end
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
    end
    imgui.End()
    if not open[1] then state.visible = false end
end)
