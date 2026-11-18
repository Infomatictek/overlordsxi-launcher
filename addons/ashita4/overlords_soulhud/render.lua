local imgui = require('imgui')
local Render = {}

local function valueText(item)
    local def, value = item.def, item.value
    if def.type == 'toggle' then
        return value and 'ACTIVE' or 'INACTIVE'
    end
    if def.type == 'status' or def.type == 'combo' then
        return tostring(value)
    end
    local n = tonumber(value) or 0
    if def.type == 'timer' or def.type == 'cooldown' then
        return n <= 0 and 'READY' or (tostring(math.ceil(n)) .. 's')
    end
    return tostring(n) .. (def.unit and (' ' .. def.unit) or '')
end

local function drawElement(item, compact)
    local def, value = item.def, item.value
    imgui.PushID(def.id)
    imgui.Columns(2, 'soulhud_' .. def.id, false)
    imgui.Text(def.label)
    imgui.NextColumn()
    imgui.Text(valueText(item))
    imgui.NextColumn()
    imgui.Columns(1)
    if not compact and def.max and def.max > 0 and
        (def.type == 'stack' or def.type == 'gauge' or def.type == 'charges') then
        local fraction = math.max(0, math.min(1, (tonumber(value) or 0) / def.max))
        imgui.ProgressBar(fraction, { -1, 5 }, '')
    end
    imgui.PopID()
end

function Render.draw(title, items, config)
    if not config.visible or not title or not items then return end
    imgui.SetNextWindowPos({ config.x, config.y }, ImGuiCond_FirstUseEver)
    imgui.SetNextWindowBgAlpha(config.opacity)
    imgui.SetNextWindowSize({ config.width, 0 }, ImGuiCond_FirstUseEver)
    local flags = bit.bor(ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoCollapse)
    if imgui.Begin('OverlordsXI Soul HUD', nil, flags) then
        imgui.TextColored({ 0.82, 0.65, 0.32, 1.0 }, title)
        imgui.Separator()
        for _, item in ipairs(items) do drawElement(item, config.compact) end
    end
    imgui.End()
end

return Render
