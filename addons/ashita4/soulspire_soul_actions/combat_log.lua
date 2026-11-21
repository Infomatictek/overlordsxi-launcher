-- Local-player-only combat log presentation. Never infer other actors' Souls.
local M = {}

-- Permit only decoration before the actor, never another readable name.
-- Ashita may prepend extended FFXI color/format tokens containing digits and
-- punctuation. Matching the entire actor+verb after this boundary ensures
-- "Other Rin", "OtherRin", and targets mentioning Rin are never relabeled.
local function formattingPrefix(prefix)
    if #prefix > 64 then return false end
    if prefix == '' then return true end
    -- Exact live Ashita cast timestamp prefix, including embedded 'Q'.
    -- 1E 51 5B HH:MM:SS 5D 1E 01 20; no other text may precede the actor.
    local timestampEnvelope = '^' .. string.char(0x1E)
        .. 'Q%[%d%d:%d%d:%d%d%]' .. string.char(0x1E, 0x01) .. ' ' .. string.char(36)
    if prefix:match(timestampEnvelope) then return true end
    -- Explicit actor name must be the first readable word. Allow control
    -- bytes and nonalphabetic formatting parameters, but no letter-bearing
    -- characters or extra player names.
    if prefix:find('[%a]') then return false end
    -- Reject ordinary spaces unless accompanied by an FFXI control marker
    -- or a timestamp in brackets.
    if not prefix:find('[%c]') and not prefix:match('^%[%d%d:%d%d:%d%d%]%s*' .. string.char(36))
        and not prefix:match('^%[%d%d:%d%d:%d%d:%d%d%]%s*' .. string.char(36)) then
        return false
    end
    return true
end

local function actorStart(message, player)
    -- Search for the exact actor token before a known action verb. Other
    -- names appearing as targets or in chat are never sufficient.
    for _, verb in ipairs({ ' starts casting ', ' casts ', ' uses ', ' readies ' }) do
        local marker = player .. verb
        local from = 1
        while true do
            local first = message:find(marker, from, true)
            if not first then break end
            if formattingPrefix(message:sub(1, first - 1)) then return first + #marker end
            from = first + #player
        end
    end
    return nil
end

local function actionNameStart(message, start)
    -- Native color controls may decorate the action token. Do not scan past
    -- readable text: that could be a target or an unrelated action name.
    local pos = start
    for _ = 1, 4 do
        local marker = message:byte(pos)
        if marker ~= 0x1E and marker ~= 0x1F then break end
        if not message:byte(pos + 1) then return nil end
        pos = pos + 2
    end
    return pos
end

local function tryReplace(message, start, vanilla, custom)
    if type(vanilla) ~= 'string' or vanilla == '' or vanilla == custom then return nil end
    local first = actionNameStart(message, start)
    if not first or message:sub(first, first + #vanilla - 1) ~= vanilla then return nil end
    local last = first + #vanilla - 1
    local after = message:sub(last + 1, last + 1)
    local afterCtrl = after ~= '' and after:byte(1) < 32
    if after == '' or after == ' ' or after == '.' or after == '!' or after == "'"
        or after == '"' or afterCtrl then
        return message:sub(1, first - 1) .. custom .. message:sub(last + 1)
    end
    return nil
end

-- The vanilla lookup may return a string or a list of localization aliases.
-- Returns updated line or nil; a second diagnostic value explains a miss.
function M.rewriteLine(message, localPlayerName, catalog, activeSoul, vanillaNameFn)
    if type(message) ~= 'string' or message == '' then return nil, 'empty' end
    if type(localPlayerName) ~= 'string' or localPlayerName == '' then return nil, 'player_unknown' end
    if type(activeSoul) ~= 'string' or activeSoul == '' then return nil, 'soul_unknown' end
    if type(catalog) ~= 'table' or type(catalog.souls) ~= 'table'
        or type(vanillaNameFn) ~= 'function' then return nil, 'unavailable' end
    local actionStart = actorStart(message, localPlayerName)
    if not actionStart then return nil, 'actor_mismatch' end
    local soulData = catalog.souls[activeSoul]
    if not soulData then return nil, 'catalog_missing' end

    local knownAction = false
    local anyVanilla = false
    local replacement = nil
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
                                local rewritten = tryReplace(message, actionStart, vanilla, info.name)
                                if rewritten then
                                    if replacement and replacement ~= rewritten then
                                        return nil, 'ambiguous_action'
                                    end
                                    replacement = rewritten
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if replacement then return replacement, 'rewritten' end
    if not knownAction then return nil, 'catalog_empty' end
    return nil, anyVanilla and 'name_mismatch' or 'vanilla_unavailable'
end

return M
