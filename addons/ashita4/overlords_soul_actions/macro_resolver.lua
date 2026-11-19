-- Translates active Soul action names in slash commands and FFXI macros
-- (e.g. /ma "Shadow Squadron: Ichi" <me>) back to canonical vanilla FFXI action names
-- before FFXI executes them. Never alters underlying action IDs or target syntax.
local M = {}

local CMD_KIND = {
    ['/ma']          = 'spell',
    ['/magic']       = 'spell',
    ['/nin']         = 'spell',
    ['/ninjutsu']    = 'spell',
    ['/song']        = 'spell',
    ['/so']          = 'spell',
    ['/ja']          = 'ability',
    ['/jobability']  = 'ability',
    ['/pet']         = 'ability',
    ['/ws']          = 'weaponskill',
    ['/weaponskill'] = 'weaponskill',
}

local function trim(s)
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- Parse "/prefix \"Action Name\" <target>" or "/prefix ActionName <target>"
local function parseCommand(cmd)
    if type(cmd) ~= 'string' then return nil end
    local prefix, rest = cmd:match('^%s*(/%a+)%s+(.+)$')
    if not prefix then return nil end
    local kind = CMD_KIND[prefix:lower()]
    if not kind then return nil end

    local actionName, tail = rest:match('^"([^"]+)"(.*)$')
    if actionName then
        return prefix, kind, trim(actionName), tail or ''
    end
    local single, singleTail = rest:match('^(%S+)(.*)$')
    if single then
        return prefix, kind, single, singleTail or ''
    end
    return nil
end

-- Resolve a Soul action command into a vanilla FFXI command string, or nil if no rewrite applies.
-- vanillaNameFn(kind, id) -> string|nil
function M.translate(command, catalog, activeSoul, vanillaNameFn)
    if type(activeSoul) ~= 'string' or activeSoul == '' then return nil end
    if type(catalog) ~= 'table' or type(catalog.souls) ~= 'table' then return nil end
    if type(vanillaNameFn) ~= 'function' then return nil end

    local prefix, kind, actionName, tail = parseCommand(command)
    if not prefix then return nil end

    local soulEntries = catalog.souls[activeSoul]
    local kindEntries = soulEntries and soulEntries[kind]
    if not kindEntries then return nil end

    local needle = actionName:lower()
    for id, info in pairs(kindEntries) do
        if type(info) == 'table' and type(info.name) == 'string' and info.name:lower() == needle then
            local vanilla = vanillaNameFn(kind, id)
            if type(vanilla) == 'string' and vanilla ~= '' and vanilla:lower() ~= needle then
                return string.format('%s "%s"%s', prefix, vanilla, tail)
            end
            return nil
        end
    end
    return nil
end

return M
