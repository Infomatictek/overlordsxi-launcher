-- Pure client-side eligibility presentation policy. Never grants an action.
-- Intentionally returns 'unmanaged' for unspecified actions: a partial
-- catalog must not implicitly hide a valid main/subjob spell.
local M = {}
local VALID_KIND = { spell=true, ability=true, weaponskill=true }
local LIMIT = { spell=1023, ability=2047, weaponskill=511 }
local function validKey(v)
    return type(v) == 'string' and #v >= 2 and #v <= 64
        and v:match('^[a-z0-9_%-]+$') ~= nil
end
function M.parse(contents)
    if type(contents) ~= 'string' or #contents > 256*1024 then
        return nil, 'invalid_policy_size'
    end
    local policy = {}
    local count = 0
    for line in (contents .. '\n'):gmatch('(.-)\n') do
        line = line:gsub('\r$', '')
        if line ~= '' and not line:match('^%s*#') then
            local soul,kind,id,level,rule = line:match('^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$')
            local n, minLevel = tonumber(id), tonumber(level)
            if not validKey(soul) or not VALID_KIND[kind] or not n or n % 1 ~= 0
                or n < 0 or n > LIMIT[kind] or not minLevel or minLevel % 1 ~= 0
                or minLevel < 1 or minLevel > 75
                or (rule ~= 'unlock' and rule ~= 'hidden') then
                return nil, 'invalid_policy_row'
            end
            local bySoul = policy[soul] or {}
            policy[soul] = bySoul
            local byKind = bySoul[kind] or {}
            bySoul[kind] = byKind
            if byKind[n] then return nil, 'duplicate_policy_key' end
            byKind[n] = { minLevel=minLevel, rule=rule }
            count = count + 1
            if count > 4096 then return nil, 'policy_too_large' end
        end
    end
    return { souls=policy, count=count }
end

function M.load(path)
    if type(path) ~= 'string' or path == '' then return nil, 'missing_path' end
    local f = io.open(path, 'rb')
    if not f then return nil, 'cannot_open_policy' end
    local content = f:read(256*1024 + 1)
    f:close()
    return M.parse(content)
end

-- Return 'show', 'hide' or 'unmanaged'. The caller must never interpret
-- 'show' as cast permission; only the server can authorize a cast.
function M.decide(policy, soul, kind, id, effectiveLevel)
    if type(policy) ~= 'table' or type(policy.souls) ~= 'table'
        or not validKey(soul) or not VALID_KIND[kind]
        or type(id) ~= 'number' or id % 1 ~= 0
        or type(effectiveLevel) ~= 'number' or effectiveLevel % 1 ~= 0
        or effectiveLevel < 1 or effectiveLevel > 75 then
        return 'unmanaged'
    end
    local group = policy.souls[soul]
    local entry = group and group[kind] and group[kind][id]
    if not entry then return 'unmanaged' end
    if entry.rule == 'hidden' or effectiveLevel < entry.minLevel then return 'hide' end
    return 'show'
end
return M
