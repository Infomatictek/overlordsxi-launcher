-- Pure-Lua parser and reversible updater for Ashita v4 XIPivot soulspirexi.ini.
-- Never touches live FFXI DATs in memory; changes apply cleanly on the next client launch.

local M = {}

M.FLINTLOCK_OVERLAY = 'flintlock-akimbo-compact'
M.BASE_OVERLAY = 'soulspirexi'

local function trim(s)
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- Parse [overlays] entries from soulspirexi.ini text into an ordered list of overlay names.
function M.parse_overlays(ini_text)
    if type(ini_text) ~= 'string' then
        return {}
    end
    local in_overlays = false
    local indexed = {}
    for raw_line in (ini_text .. '\n'):gmatch('(.-)\r?\n') do
        local line = trim(raw_line)
        local section = line:match('^%[(.-)%]$')
        if section then
            in_overlays = (section:lower() == 'overlays')
        elseif in_overlays and line ~= '' and line:sub(1, 1) ~= ';' and line:sub(1, 1) ~= '#' then
            local k, v = line:match('^([^=]+)=(.*)$')
            if k and v then
                local idx = tonumber(trim(k))
                local val = trim(v)
                if idx ~= nil and val ~= '' then
                    indexed[#indexed + 1] = { idx = idx, name = val }
                end
            end
        end
    end
    table.sort(indexed, function(a, b) return a.idx < b.idx end)
    local out = {}
    for _, item in ipairs(indexed) do
        out[#out + 1] = item.name
    end
    return out
end

function M.is_flintlock_enabled(ini_text)
    local overlays = M.parse_overlays(ini_text)
    for _, name in ipairs(overlays) do
        if name:lower() == M.FLINTLOCK_OVERLAY then
            return true
        end
    end
    return false
end

-- Return updated soulspirexi.ini text with flintlock-akimbo-compact enabled (priority 0) or removed,
-- preserving [settings], [cache], and all other user overlays.
function M.set_flintlock_enabled(ini_text, enabled)
    if type(ini_text) ~= 'string' or ini_text == '' then
        return nil, 'Empty pivot INI content.'
    end

    local current = M.parse_overlays(ini_text)
    local filtered = {}
    for _, name in ipairs(current) do
        if name:lower() ~= M.FLINTLOCK_OVERLAY then
            filtered[#filtered + 1] = name
        end
    end
    if #filtered == 0 then
        filtered[1] = M.BASE_OVERLAY
    end

    local next_overlays = {}
    if enabled then
        next_overlays[1] = M.FLINTLOCK_OVERLAY
        for _, name in ipairs(filtered) do
            next_overlays[#next_overlays + 1] = name
        end
    else
        next_overlays = filtered
    end

    local out_lines = {}
    local in_overlays = false
    local wrote_overlays = false

    local function emit_overlays()
        for i, name in ipairs(next_overlays) do
            out_lines[#out_lines + 1] = tostring(i - 1) .. '=' .. name
        end
        wrote_overlays = true
    end

    for raw_line in (ini_text .. '\n'):gmatch('(.-)\r?\n') do
        local line = trim(raw_line)
        local section = line:match('^%[(.-)%]$')
        if section then
            if in_overlays and not wrote_overlays then
                emit_overlays()
            end
            in_overlays = (section:lower() == 'overlays')
            out_lines[#out_lines + 1] = raw_line
            if in_overlays then
                emit_overlays()
            end
        elseif not in_overlays then
            out_lines[#out_lines + 1] = raw_line
        end
    end

    if not wrote_overlays then
        if #out_lines > 0 and trim(out_lines[#out_lines]) ~= '' then
            out_lines[#out_lines + 1] = ''
        end
        out_lines[#out_lines + 1] = '[overlays]'
        emit_overlays()
    end

    -- Trim trailing duplicate blank lines, keep single LF newline.
    while #out_lines > 0 and trim(out_lines[#out_lines]) == '' do
        table.remove(out_lines)
    end
    return table.concat(out_lines, '\n') .. '\n', nil
end

return M
