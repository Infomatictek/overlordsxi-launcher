-- Local-player-only combat log presentation. Never infer other actors' Souls.
local M = {}

local function actorStart(message, player)
    -- Leading FFXI chat color/control markers may precede the actor name.
    local prefix = message:match('^[%c]*') or ''
    local start = #prefix + 1
    if message:sub(start, start + #player - 1) ~= player then return false end
    local nextChar = message:sub(start + #player, start + #player)
    return nextChar == ' ' or nextChar == "'"
end

local function tryReplace(message, vanilla, custom)
    if type(vanilla) ~= 'string' or vanilla == '' or vanilla == custom then return nil end
    -- Match the *entire* action name as a substring, not a Lua pattern.
    -- Avoid renaming "Utsusemi: Ichi" inside longer unrelated action names.
    local offset = 1
    while true do
        local first, last = message:find(vanilla, offset, true)
        if not first then return nil end
        local before = first > 1 and message:sub(first - 1, first - 1) or ''
        local after = message:sub(last + 1, last + 1)
        if (before == ' ' or before == "'" or before == '"')
            and (after == '' or after == ' ' or after == '.' or after == '!' or after == "'" or after == '"') then
            return message:sub(1, first - 1) .. custom .. message:sub(last + 1)
        end
        offset = last + 1
    end
end

-- The vanilla lookup may return a string or a list of localization aliases.
-- Returns updated line or nil; a second diagnostic value explains a miss.
function M.rewriteLine(message, localPlayerName, catalog, activeSoul, vanillaNameFn)
    if type(message) ~= 'string' or message == '' then return nil, 'empty' end
    if type(localPlayerName) ~= 'string' or localPlayerName == '' then return nil, 'player_unknown' end
    if type(activeSoul) ~= 'string' or activeSoul == '' then return nil, 'soul_unknown' end
    if type(catalog) ~= 'table' or type(catalog.souls) ~= 'table'
        or type(vanillaNameFn) ~= 'function' then return nil, 'unavailable' end
    if not actorStart(message, localPlayerName) then return nil, 'actor_mismatch' end
    local soulData = catalog.souls[activeSoul]
    if not soulData then return nil, 'catalog_missing' end

    local knownAction = false
    local anyVanilla = false
    for _, kind in ipairs({ 'spell', 'ability', 'weaponskill' }) do
        local entries = soulData[kind]
        if type(entries) == 'table' then
            for id, info in pairs(entries) do
                if type(info) == 'table' and type(info.name) == 'string' and info.name ~= '' then
                    knownAction = true
                    local aliases = vanillaNameFn(kind, id)
                    if type(aliases) == 'string' then aliases = { aliases } end
                    if type(aliases) == 'table' then
                        for _, vanilla in ipairs(aliases) do
                            if type(vanilla) == 'string' and vanilla ~= '' then
                                anyVanilla = true
                                local rewritten = tryReplace(message, vanilla, info.name)
                                if rewritten then return rewritten, 'rewritten' end
                            end
                        end
                    end
                end
            end
        end
    end
    if not knownAction then return nil, 'catalog_empty' end
    return nil, anyVanilla and 'name_mismatch' or 'vanilla_unavailable'
end

return M
