-- Pure client-side Soul presentation resolver.
-- No server dependency, packet mutation or global resource rewriting.
local M = {}
local valid = { spell = true, ability = true, weaponskill = true }
function M.resolve(catalog, soul, kind, id)
    if not valid[kind] or type(id) ~= 'number' or id < 0 or id % 1 ~= 0 then return nil end
    if type(soul) ~= 'string' or soul == '' then return nil end
    return catalog.get(soul, kind, id)
end
function M.label(catalog, soul, kind, id)
    local action = M.resolve(catalog, soul, kind, id)
    return action and action.name or nil
end
function M.description(catalog, soul, kind, id)
    local action = M.resolve(catalog, soul, kind, id)
    return action and action.description or nil
end
function M.formatCast(catalog, soul, kind, id, actorName)
    local action = M.resolve(catalog, soul, kind, id)
    if not action then return nil end
    local actor = type(actorName) == 'string' and actorName or 'Unknown'
    if kind == 'spell' then return actor .. ' begins casting ' .. action.name .. '.' end
    return actor .. ' uses ' .. action.name .. '.'
end
-- Explicit Soul resolution is required: identical underlying action IDs can
-- have different presentations for different Souls and other players.
return M
