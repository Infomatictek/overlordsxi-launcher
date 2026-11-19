-- Local-player-only combat log presentation. Never infer other actors' Souls.
local M = {}

local function formattingPrefix(prefix)
    -- Strictly permit a short run of FFXI control codes, each optionally
    -- followed by up to two printable parameter bytes. Never skip ordinary
    -- readable text such as another player's name or a chat prefix.
    if #prefix > 32 then return false end
    local parameterBytes = 0
    local hasControl = false
    for i = 1, #prefix do
        local b = prefix:byte(i)
        if b < 32 or b == 127 then
            hasControl = true
            parameterBytes = 0
        elseif hasControl and parameterBytes < 2 then
            parameterBytes = parameterBytes + 1
        else
            return false
        end
    end
    return true
end

local function actorStart(message, player)
    -- FFXI text may prepend color/control sequences containing *printable*
    -- parameter bytes. A pure ^[%c]* trim therefore rejects real chat.
    -- Only accept the exact actor name near the beginning, preceded by at
    -- most 32 formatting bytes and no readable alphanumeric actor prefix.
    local from = 1
    while true do
        local start = message:find(player, from, true)
        if not start or start > 33 then return false end
        local prefix = message:sub(1, start - 1)
        local nextChar = message:sub(start + #player, start + #player)
        if formattingPrefix(prefix) and (nextChar == ' ' or nextChar == "'") then
            return true
        end
        from = start + #player
    end
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
        local beforeCtrl = before ~= '' and before:byte(1) < 32
        local afterCtrl = after ~= '' and after:byte(1) < 32
        if (before == ' ' or before == "'" or before == '"' or beforeCtrl)
            and (after == '' or after == ' ' or after == '.' or after == '!' or after == "'" or after == '"' or afterCtrl) then
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
