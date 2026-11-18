--[[
* OverlordsXI Soul HUD - settings window (opened from the gauge's quick options or /soulhud config).
* The HUD itself is drawn by soulhud_gauge.lua (Crystal Job Gauge); this file only hosts the
* optional per-element configuration panel, styled with the same navy/gold palette.
--]]

local M = {}

function M.renderConfig(imgui, soulDef, cfg, settingsMod, callbacks)
    if not imgui or not callbacks.isConfigOpen() then
        return
    end

    local pushed = 0
    local function pc(idx, v)
        if idx ~= nil then imgui.PushStyleColor(idx, v); pushed = pushed + 1 end
    end
    pc(ImGuiCol_WindowBg, { 0.07, 0.085, 0.15, 0.96 })
    pc(ImGuiCol_Border, { 0.85, 0.68, 0.31, 1.0 })
    pc(ImGuiCol_TitleBg, { 0.09, 0.12, 0.22, 1.0 })
    pc(ImGuiCol_TitleBgActive, { 0.15, 0.2, 0.36, 1.0 })

    imgui.SetNextWindowSize({ 320, 360 }, ImGuiCond_FirstUseEver or 4)
    local open = { true }
    if imgui.Begin('Overlords Soul HUD Config', open, 0) then
        if imgui.Checkbox('Lock Position', { cfg.locked }) then
            cfg.locked = not cfg.locked
            settingsMod.save(cfg)
        end

        if imgui.Checkbox('Show Shared Party Buffs', { cfg.showShared ~= false }) then
            cfg.showShared = not (cfg.showShared ~= false)
            settingsMod.save(cfg)
        end

        local modes = { 'auto', 'show', 'hide' }
        if imgui.BeginCombo('Visibility Mode', cfg.mode) then
            for _, m in ipairs(modes) do
                if imgui.Selectable(m, cfg.mode == m) then
                    cfg.mode = m
                    settingsMod.save(cfg)
                end
            end
            imgui.EndCombo()
        end

        local scaleArr = { cfg.scale }
        if imgui.SliderFloat('Scale', scaleArr, 0.75, 2.0, '%.2f') then
            cfg.scale = scaleArr[1]
            settingsMod.save(cfg)
        end

        local opArr = { cfg.opacity }
        if imgui.SliderFloat('Opacity', opArr, 0.25, 1.0, '%.2f') then
            cfg.opacity = opArr[1]
            settingsMod.save(cfg)
        end

        imgui.Separator()
        imgui.Text('Preview without combat:')
        imgui.Text('/soulhud demo <soulKey|cycle|off>')

        if soulDef and #(soulDef.resources or {}) > 0 then
            imgui.Separator()
            imgui.Text(('Elements (%s):'):format(soulDef.name))
            for _, res in ipairs(soulDef.resources or {}) do
                local vis = settingsMod.isElementVisible(cfg, soulDef.key, res.id)
                if imgui.Checkbox(res.label .. '##' .. res.id, { vis }) then
                    settingsMod.setElementVisible(cfg, soulDef.key, res.id, not vis)
                    settingsMod.save(cfg)
                end
            end
        end
    end
    imgui.End()
    if pushed > 0 then imgui.PopStyleColor(pushed) end
    if not open[1] then
        callbacks.setConfigOpen(false)
    end
end

return M
