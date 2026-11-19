-- OverlordsXI client-side Soul action catalog.
-- Identity data only: the server is authoritative for gameplay.
local M = { version = 1, souls = {} }
local kinds = { spell = true, ability = true, weaponskill = true }
local function validText(s) return type(s) == 'string' and #s > 0 and #s <= 180 and not s:find('[\r\n|]') end
function M.register(soul, kind, id, info)
    if not validText(soul) or not kinds[kind] or type(id) ~= 'number' or id < 0 or id % 1 ~= 0 then return false end
    if type(info) ~= 'table' or not validText(info.name) or not validText(info.description) then return false end
    local entries = M.souls[soul] or {}
    entries[kind] = entries[kind] or {}
    entries[kind][id] = { name = info.name, description = info.description,
        effectProfile = info.effectProfile, castTime = info.castTime,
        recastTime = info.recastTime, mpCost = info.mpCost, tpCost = info.tpCost,
        iconId = info.iconId, iconIdV2 = info.iconIdV2 }
    M.souls[soul] = entries
    return true
end
function M.get(soul, kind, id)
    local data = M.souls[soul]
    return data and data[kind] and data[kind][id] or nil
end
function M.clear() M.souls = {} end
return M
