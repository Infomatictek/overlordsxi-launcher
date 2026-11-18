local Registry = {}
Registry.__index = Registry

local VALID = {
    stack = true, gauge = true, charges = true, cooldown = true,
    timer = true, toggle = true, combo = true, counter = true, status = true,
}

function Registry.new()
    return setmetatable({ souls = {} }, Registry)
end

function Registry:registerSoul(key, definition)
    assert(type(key) == 'string' and key ~= '', 'Soul key required')
    assert(type(definition) == 'table', 'Soul definition required')
    local elements, seen = {}, {}
    for _, item in ipairs(definition.elements or {}) do
        assert(type(item.id) == 'string' and item.id ~= '', 'Element id required')
        assert(not seen[item.id], 'Duplicate element: ' .. item.id)
        assert(VALID[item.type], 'Unsupported type: ' .. tostring(item.type))
        seen[item.id] = true
        local copy = {}
        for k, v in pairs(item) do copy[k] = v end
        elements[#elements + 1] = copy
    end
    self.souls[key] = { key = key, title = definition.title or key, elements = elements }
end

function Registry:getSoul(key)
    return self.souls[key]
end

function Registry:normalize(key, state)
    local soul = self.souls[key]
    if not soul then return nil end
    local result = {}
    for _, def in ipairs(soul.elements) do
        local value = state[def.field or def.id]
        if value ~= nil then
            if def.type == 'toggle' then
                value = tonumber(value) == 1 or value == true
            elseif def.type == 'status' or def.type == 'combo' then
                value = tostring(value)
            else
                value = tonumber(value)
                if value ~= nil then
                    if def.min ~= nil then value = math.max(def.min, value) end
                    if def.max ~= nil then value = math.min(def.max, value) end
                end
            end
            if value ~= nil then result[#result + 1] = { def = def, value = value } end
        end
    end
    return result
end

return Registry
