-- Loads default Soul action definitions from editable external data (data/soul_actions.tsv).
-- No Soul-specific spell or ability names are hardcoded in this module or in native C++.
local profiles = require('profiles')
local M = {}

local function scriptDir()
    if type(debug) == 'table' and type(debug.getinfo) == 'function' then
        local info = debug.getinfo(1, 'S')
        if info and type(info.source) == 'string' then
            local src = info.source:gsub('^@', '')
            local dir = src:match('^(.*)[/\\][^/\\]+$')
            if dir and dir ~= '' then return dir end
        end
    end
    return '.'
end

function M.defaultPath(basePath)
    local root = (type(basePath) == 'string' and basePath ~= '') and basePath or scriptDir()
    return root:gsub('[/\\]+$', '') .. '/data/soul_actions.tsv'
end

function M.install(catalog, basePath)
    local path = M.defaultPath(basePath)
    local count, why = profiles.load(path, catalog)
    if not count then
        return 0, why
    end
    return count, nil, path
end

return M
