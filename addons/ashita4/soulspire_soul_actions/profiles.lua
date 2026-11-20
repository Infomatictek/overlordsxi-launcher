-- Local client profile parser. No Lua execution, packet rewriting, or server dependency.
-- TSV columns: soul<TAB>kind<TAB>id<TAB>name<TAB>description[<TAB>icon_id<TAB>icon_id_v2]
local M = {}
local validKinds = { spell = true, ability = true, weaponskill = true }
local function safe(s, max)
    return type(s) == 'string' and #s > 0 and #s <= max
        and not s:find('[%c]') and not s:find('|', 1, true)
end
local function validIcon(col)
    if col == nil or col == '' then return 65535 end
    local v = tonumber(col)
    if not v or v < 0 or v > 65535 or v % 1 ~= 0 then return nil end
    return v
end
function M.parse(input)
    if type(input) ~= 'string' or #input > 262144 then return nil, 'Invalid profile size' end
    local rows, errors, count = {}, {}, 0
    for line in (input .. '\n'):gmatch('(.-)\n') do
        line = line:gsub('\r$', '')
        if line ~= '' and not line:match('^#') then
            local cols = {}
            for field in (line .. '\t'):gmatch('(.-)\t') do cols[#cols + 1] = field end
            local id = tonumber(cols[3])
            local iconId = (#cols >= 6) and validIcon(cols[6]) or 65535
            local iconIdV2 = (#cols >= 7) and validIcon(cols[7]) or 65535
            if (#cols ~= 5 and #cols ~= 7) or not safe(cols[1], 64) or not cols[1]:match('^[%w_%-]+$')
                or not validKinds[cols[2]] or not id or id < 0 or id > 65535 or id % 1 ~= 0
                or not safe(cols[4], 79) or not safe(cols[5], 180)
                or iconId == nil or iconIdV2 == nil then
                errors[#errors + 1] = 'Invalid action profile row ' .. tostring(count + 1)
            else
                rows[#rows + 1] = { soul = cols[1]:lower(), kind = cols[2], id = id,
                    name = cols[4], description = cols[5],
                    iconId = iconId, iconIdV2 = iconIdV2 }
            end
            count = count + 1
            if count > 4096 then return nil, 'Profile exceeds 4096 entries' end
        end
    end
    if #errors > 0 then return nil, table.concat(errors, '; ') end
    return rows
end
function M.load(path, catalog)
    local file, err = io.open(path, 'rb')
    if not file then return nil, err or 'Cannot open profile' end
    local input = file:read(262145)
    file:close()
    local rows, why = M.parse(input)
    if not rows then return nil, why end
    -- Validate all rows before replacing current catalog.
    local seen = {}
    for _, row in ipairs(rows) do
        local key = row.soul .. ':' .. row.kind .. ':' .. row.id
        if seen[key] then return nil, 'Duplicate profile entry: ' .. key end
        seen[key] = true
    end
    catalog.clear()
    for _, row in ipairs(rows) do
        assert(catalog.register(row.soul, row.kind, row.id, row))
    end
    return #rows
end
return M
