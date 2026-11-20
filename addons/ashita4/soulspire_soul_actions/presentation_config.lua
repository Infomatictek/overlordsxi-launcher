-- Whitelisted, line-based native action presentation settings.
local M = {}
function M.load(base)
    if type(base) ~= 'string' or base == '' then return nil, 'addon path unavailable' end
    local path = base:gsub('[/\\]+$', '') .. '/data/presentation.cfg'
    local f = io.open(path, 'rb')
    if not f then return nil, 'cannot read ' .. path end
    local content = f:read(4097)
    f:close()
    if type(content) ~= 'string' or #content > 4096 then return nil, 'invalid presentation.cfg size' end
    local value
    for line in (content .. '\n'):gmatch('(.-)\n') do
        line = line:gsub('\r$', '')
        if line ~= '' and not line:match('^%s*#') then
            local key, number = line:match('^%s*([%w_]+)%s*=%s*(%d+)%s*$')
            if key ~= 'action_row_max_chars' or value ~= nil then
                return nil, 'unknown or duplicate presentation setting'
            end
            value = tonumber(number)
        end
    end
    if not value or value < 8 or value > 48 then
        return nil, 'action_row_max_chars must be 8..48'
    end
    return value, nil
end
return M
