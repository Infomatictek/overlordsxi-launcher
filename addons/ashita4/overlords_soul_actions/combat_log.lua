-- Local-player-only combat log presentation helper.
-- Safety rules:
--   1. Only rewrites lines beginning with the verified local player's exact name.
--   2. Rewrites in-place (zero duplicate combat log messages).
--   3. Never infers another player's Soul from an action ID or spell name alone.
local M = {}

local function escapePattern(s)
    return (s:gsub('([%(%)%.%%%+%-%*%?%[%]%^%$])', '%%%1'))
end

-- Rewrite a single incoming chat/combat-log line for the verified local player.
-- Returns the rewritten string, or nil if the line must remain unmodified.
function M.rewriteLine(message, localPlayerName, catalog, activeSoul, vanillaNameFn)
    if type(message) ~= 'string' or message == '' then return nil end
    if type(localPlayerName) ~= 'string' or localPlayerName == '' then return nil end
    if type(activeSoul) ~= 'string' or activeSoul == '' then return nil end
    if type(catalog) ~= 'table' or type(catalog.souls) ~= 'table' then return nil end
    if type(vanillaNameFn) ~= 'function' then return nil end

    -- Strip leading FFXI color/control bytes only for the actor-prefix check.
    local cleanStart = message:gsub('^[\x01-\x1f\x7f]+', '')
    local prefixLen = #localPlayerName
    if cleanStart:sub(1, prefixLen) ~= localPlayerName then return nil end
    local nextChar = cleanStart:sub(prefixLen + 1, prefixLen + 1)
    if nextChar ~= ' ' and nextChar ~= "'" then return nil end

    local soulData = catalog.souls[activeSoul]
    if not soulData then return nil end

    for _, kind in ipairs({ 'spell', 'ability', 'weaponskill' }) do
        local entries = soulData[kind]
        if type(entries) == 'table' then
            for id, info in pairs(entries) do
                if type(info) == 'table' and type(info.name) == 'string' and info.name ~= '' then
                    local vanilla = vanillaNameFn(kind, id)
                    if type(vanilla) == 'string' and vanilla ~= '' and vanilla ~= info.name then
                        local pat = escapePattern(vanilla)
                        if message:find(pat) then
                            local replaced, count = message:gsub(pat, (info.name:gsub('%%', '%%%%')), 1)
                            if count > 0 then return replaced end
                        end
                    end
                end
            end
        end
    end
    return nil
end

return M
