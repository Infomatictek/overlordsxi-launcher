-- Read-only, opt-in Ashita v4 resource inventory for native Soul-action research.
-- No DAT writes, packet modification, command injections or memory patches.
-- Processes a bounded batch each frame to avoid client hitching.
local M = {}
local LIMITS = {spell = 1023, ability = 2047}
local KINDS = {'spell','ability'}
local active = nil
local function clean(s)
    if type(s) ~= 'string' then return '' end
    return (s:gsub('[\r\n\t]', ' '):gsub('[%z\1-\8\11\12\14-\31]', '')):sub(1, 180)
end
local function value(resource, field)
    local ok, result = pcall(function() return resource[field] end)
    return ok and result or nil
end
local function lang(resource, field)
    local tableValue = value(resource, field)
    if tableValue == nil then return '' end
    -- Ashita Lua resource names use 1-based arrays: English is generally [3],
    -- default [1]; use Japanese [2] only as a last resort.
    for _, index in ipairs({3, 1, 2}) do
        local ok, result = pcall(function() return tableValue[index] end)
        if ok and type(result) == 'string' and result ~= '' then return clean(result) end
    end
    return ''
end
function M.start(manager, rootPath)
    if active ~= nil then return nil, 'Resource audit already running.' end
    if type(manager) ~= 'table' and type(manager) ~= 'userdata' and type(manager) ~= 'cdata' then
        -- Ashita resource interfaces may be userdata; reject absent managers.
        return nil, 'Resource manager unavailable.'
    end
    if type(rootPath) ~= 'string' or rootPath == '' then
        return nil, 'Addon path unavailable.'
    end
    local path = rootPath:gsub('[/\\]+$', '') .. '/native-actions-audit.tsv'
    local file, err = io.open(path, 'wb')
    if file == nil then return nil, err or 'Cannot open audit output.' end
    file:write('kind\tid\tvanilla_name\tvanilla_description\tmp_cost\tcast_time\trecast_delay\n')
    active = { manager = manager, file = file, path = path, kindIndex = 1, id = 0, count = 0 }
    return true
end
function M.cancel()
    if active then active.file:close(); active = nil end
end
function M.step(batch)
    if not active then return nil end
    batch = math.max(1, math.min(40, math.floor(tonumber(batch) or 20)))
    local job = active
    for _ = 1, batch do
        local kind = KINDS[job.kindIndex]
        if not kind then
            local path, count = job.path, job.count
            job.file:close()
            active = nil
            return {complete = true, path = path, count = count}
        end
        local ok, record = pcall(function()
            return kind == 'spell' and job.manager:GetSpellById(job.id)
                or job.manager:GetAbilityById(job.id)
        end)
        if ok and record ~= nil then
            local name = lang(record, 'Name')
            if name ~= '' then
                local description = lang(record, 'Description')
                job.file:write(kind, '\t', job.id, '\t', name, '\t', description, '\t',
                    tostring(value(record, 'ManaCost') or ''), '\t',
                    tostring(value(record, 'CastTime') or ''), '\t',
                    tostring(value(record, 'RecastDelay') or ''), '\n')
                job.count = job.count + 1
            end
        end
        job.id = job.id + 1
        if job.id > LIMITS[kind] then
            job.kindIndex = job.kindIndex + 1
            job.id = 0
        end
    end
    return {complete = false, kind = KIN[job.kindIndex], id = job.id, count = job.count}
end
function M.running() return active ~= nil end
return M
