local bit = require('bit')
local protocol = require('protocol')
local Buckler = require('buckler')
local UI = {}
UI.__index = UI

-- ImGui draw colors are packed ABGR.
local colors = {
    navy      = 0xFF361B10,
    selection = 0xFF583922,
    silver    = 0xFFAD9789,
    edge      = 0xFF523929,
    text      = 0xFFE2E8E9,
    secondary = 0xFFB8A89C,
    dark      = 0xFF261108,
    muted     = 0xFF7B6557,
    shadow    = 0x55000000,
    accent    = 0xFFD9C38C,
}

local fallback_tints = {
    blue_crystal    = 0xFFCC9944,
    spartan         = 0xFF3355CC,
    crimson_shard   = 0xFF4444CC,
    amber_crescent  = 0xFF4499DD,
    jade_orb        = 0xFF66BB55,
    blackbelt       = 0xFF3344DD,
    chiweaver       = 0xFFDDAA55,
    white_prism     = 0xFFE6E6D8,
    onyx_tome       = 0xFFAA6688,
    chakram_crystal = 0xFF8844BB,
    ronin           = 0xFFCC9955,
    imperialarcher  = 0xFF66AA55,
    warlord         = 0xFF3333CC,
    inquisitor      = 0xFFD89848,
    spellblade      = 0xFF5566EE,
    lifebinder      = 0xFF66CC77,
    aegistemplar    = 0xFFD8D0A8,
    alphawarden     = 0xFF55AA66,
    kagemusha       = 0xFFAA55CC,
    azurebastion    = 0xFF3377EE,
    crimsonduelist  = 0xFFCC3344,
    miragesentinel  = 0xFFE070C0,
    dreadnought     = 0xFFAA2233,
    vanguard        = 0xFFD88838,
    pugilist        = 0xFF3366DD,
    bishop          = 0xFFF0E6CC,
    templar         = 0xFFD8D088,
    magus           = 0xFFCC9933,
    vampire         = 0xFF3333CC,
    celestial       = 0xFFDD88CC,
    animist         = 0xFF55BB88,
    verdant         = 0xFF44BB55,
    wyvernheart     = 0xFF5566DD,
    flintlock       = 0xFFD74830,
    gambler         = 0xFFD9C38C,
    buccaneer       = 0xFF269BAF,
}

function UI.new(imgui, state, send, scaling, icon_loader)
    return setmetatable({
        imgui        = imgui,
        state        = state,
        send         = send,
        icon_loader  = icon_loader,
        icons        = {},
        sx           = scaling.scale_w(1),
        sy           = scaling.scale_h(1),
        selected     = 1,
        focused      = false,
        focus_window = nil,
        focus_cursor = nil,
        lastslot     = { visible = false, clicks = 0 },
    }, UI)
end

function UI:has_socket(snapshot)
    snapshot = snapshot or self.state:snapshot()
    if snapshot.open or snapshot.status == 'error' then return true end
    local entries = snapshot.catalog and snapshot.catalog.entries
    return snapshot.loaded and type(entries) == 'table' and #entries > 0
end

function UI:close()
    self.state:cancel()
end

function UI:close_buckler()
    if self.buckler and not self.focused then self.focus_window, self.focus_cursor = nil, nil end
    self.buckler = nil
end

function UI:blur()
    self:close()
    self.buckler = nil
    self.focused, self.focus_window, self.focus_cursor = false, nil, nil
end

function UI:show(now, window, cursor)
    local snapshot = self.state:snapshot()
    local entries = (snapshot.catalog and snapshot.catalog.entries) or {}
    self.focused = true
    self.focus_window = window or self.focus_window
    self.focus_cursor = cursor or self.focus_cursor
    self.feedback = nil
    local sel = 1
    if snapshot.active and snapshot.active > 0 then
        for idx, e in ipairs(entries) do
            if e.id == snapshot.active then sel = idx; break end
        end
    end
    self.selected = sel
    return self.state:show(now, self.send)
end

function UI:entry_count()
    local snapshot = self.state:snapshot()
    local entries = snapshot.catalog and snapshot.catalog.entries or {}
    return #entries
end

function UI:activate(branch, now)
    local snapshot = self.state:snapshot()
    if snapshot.pending or (branch == 0 and snapshot.active == 0) then return end
    local ok, why = self.state:request(protocol.OP_SELECT, branch, now, self.send, snapshot.current_job)
    self.feedback = ok and nil or why
end

function UI:key(key, now, navigation)
    local snapshot = self.state:snapshot()

    -- Polearm + Buckler picker (opened from the native Equipment menu's locked Sub slot).
    if self.buckler then
        local list = self.buckler.list
        if key == 'back' then
            self:close_buckler()
        elseif key == 'up' then
            self.buckler.sel = ((self.buckler.sel - 2) % #list) + 1
        elseif key == 'down' then
            self.buckler.sel = (self.buckler.sel % #list) + 1
        elseif key == 'enter' then
            Buckler.equip(list[self.buckler.sel].entry)
            self:close_buckler()
        elseif key ~= 'left' and key ~= 'right' then
            return false
        end
        return true
    end
    local entries = (snapshot.catalog and snapshot.catalog.entries) or {}
    local total_rows = #entries + 1
    if total_rows < 1 then total_rows = 1 end

    if snapshot.open then
        if key == 'back' then
            self:close()
        elseif key == 'up' then
            self.selected = ((self.selected - 2) % total_rows) + 1
        elseif key == 'down' then
            self.selected = (self.selected % total_rows) + 1
        elseif key == 'enter' then
            if self.selected <= #entries and entries[self.selected] then
                self:activate(entries[self.selected].id, now)
            elseif self.selected == total_rows then
                self:activate(0, now)
            end
        elseif key ~= 'left' and key ~= 'right' then
            return false
        end
        return true
    end

    if self.focused then
        if key == 'up' or key == 'back' then
            self:blur()
        elseif key == 'enter' then
            self:show(now)
        elseif key ~= 'down' and key ~= 'left' and key ~= 'right' then
            return false
        end
        return true
    end

    -- Sub slot (row 1, col 2) is locked by the stock client under a 2H weapon; open our picker instead.
    if key == 'enter' and navigation and navigation.selected == Buckler.SUB_NATIVE_SLOT
        and Buckler.active(snapshot) then
        self:open_buckler(snapshot, navigation)
        return true
    end

    -- FFXI's 4x4 Equipment grid indexes slots column-major (col 1: 1..4, col 2: 5..8, col 3: 9..12, col 4: 13..16),
    -- so the bottom row (Legs, Feet, Back, Waist) is slots 4, 8, 12, and 16.
    if key == 'down' and self:has_socket(snapshot) and navigation
        and navigation.selected and navigation.selected >= 1 and navigation.selected <= 16
        and navigation.selected % 4 == 0 then
        self.focused = true
        self.focus_window = navigation.window
        self.focus_cursor = navigation.cursor or navigation.selected
        return true
    end
    return false
end

function UI:open_buckler(snapshot, navigation)
    local list = { { label = '[Unequip]', entry = nil } }
    for _, item in ipairs(Buckler.list(snapshot)) do
        list[#list + 1] = { label = item.name, entry = item }
    end
    self.buckler = { list = list, sel = 1 }
    if not self.focused then
        self.focus_window = navigation and navigation.window
        self.focus_cursor = navigation and (navigation.cursor or navigation.selected)
    end
end

function UI:resolve_icon(entry)
    if not entry then return nil end
    local candidates = { entry.key, entry.icon }
    for _, name in ipairs(candidates) do
        if type(name) == 'string' and name ~= '' then
            if self.icons[name] ~= nil then
                if self.icons[name] ~= false then
                    return self.icons[name]
                end
            elseif self.icon_loader then
                local tex = self.icon_loader(name)
                self.icons[name] = tex or false
                if tex then return tex end
            end
        end
    end
    return nil
end

function UI:draw_fallback_crystal(draw, entry, x, y, w, h)
    local tint = (entry and fallback_tints[entry.icon]) or colors.accent
    local cx, cy = x + w * 0.5, y + h * 0.5
    local rx, ry = w * 0.34, h * 0.42
    draw:AddQuadFilled(
        { cx, cy - ry },
        { cx + rx, cy },
        { cx, cy + ry },
        { cx - rx, cy },
        tint
    )
    draw:AddQuad(
        { cx, cy - ry },
        { cx + rx, cy },
        { cx, cy + ry },
        { cx - rx, cy },
        colors.text,
        1.0
    )
end

local function tooltip_text(imgui, str)
    local s = tostring(str or '')
    if imgui.TextUnformatted then
        imgui.TextUnformatted(s)
    else
        imgui.Text((s:gsub('%%', '%%%%')))
    end
end

function UI:draw_crystal_tooltip(entry, owned, is_active)
    local imgui = self.imgui
    imgui.BeginTooltip()
    pcall(function()
        tooltip_text(imgui, ('%s (%s)'):format(entry.name, entry.role))
        local req = entry.req_level or 10
        if is_active then
            tooltip_text(imgui, owned and ('Status: Socketed (Lv.%d+)'):format(req)
                or ('Status: Socketed - Inactive (< Lv.%d)'):format(req))
        elseif owned then
            tooltip_text(imgui, ('Unlocked (Requires Lv.%d+)'):format(req))
        else
            tooltip_text(imgui, ('Locked - Requires Lv.%d+'):format(req))
        end
        if imgui.PushTextWrapPos then imgui.PushTextWrapPos(340 * self.sx) end
        pcall(function()
            if entry.description and entry.description ~= '' then
                if imgui.Separator then imgui.Separator() end
                tooltip_text(imgui, entry.description)
            end
            if entry.highlights and #entry.highlights > 0 then
                if imgui.Separator then imgui.Separator() end
                for _, line in ipairs(entry.highlights) do
                    tooltip_text(imgui, '- ' .. line)
                end
            end
        end)
        if imgui.PopTextWrapPos then imgui.PopTextWrapPos() end
    end)
    imgui.EndTooltip()
end

function UI:draw(anchor, now, window, cursor)
    local imgui, sx, sy = self.imgui, self.sx, self.sy
    local slot = self.lastslot
    slot.visible, slot.hovered = false, false
    if not anchor then self:blur(); return end
    slot.anchor_x, slot.anchor_y = anchor.x, anchor.y

    local snapshot = self.state:snapshot()
    local catalog = snapshot.catalog
    local entries = (catalog and catalog.entries) or {}

    -- Hide the socket cleanly for jobs that have no Soul Crystals configured.
    if not self:has_socket(snapshot) then
        self:blur()
        return
    end

    local entry_by_id = {}
    for _, e in ipairs(entries) do
        entry_by_id[e.id] = e
    end

    local flags = bit.bor(
        ImGuiWindowFlags_NoDecoration,
        ImGuiWindowFlags_NoBackground,
        ImGuiWindowFlags_NoSavedSettings,
        ImGuiWindowFlags_NoMove,
        ImGuiWindowFlags_NoScrollWithMouse
    )

    local function text(draw, x, y, value, color, size)
        if self.font then
            draw:AddText(self.font, (size or 14) * sy, { x, y }, color or colors.text, value)
        else
            draw:AddText({ x, y }, color or colors.text, value)
        end
    end

    local function panel(draw, x, y, width, height, recessed)
        draw:AddRectFilled({ x, y + 2 * sy }, { x + width + sx, y + height + 2 * sy }, colors.shadow, 3 * sy)
        draw:AddRectFilled({ x, y }, { x + width, y + height }, recessed and colors.dark or colors.navy, 3 * sy)
        draw:AddRect({ x, y }, { x + width, y + height }, colors.silver, 3 * sy)
        draw:AddRect({ x + sx, y + sy }, { x + width - sx, y + height - sy }, colors.edge, 2 * sy)
    end

    local function draw_entry_icon(draw, entry, x, y)
        local tex = self:resolve_icon(entry)
        if tex then
            draw:AddImage(tex, { x, y }, { x + 32 * sx, y + 32 * sy }, { 0, 0 }, { 1, 1 }, 0xFFFFFFFF)
            return true
        end
        return false
    end

    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 })
    imgui.SetNextWindowPos({ anchor.x, anchor.y }, ImGuiCond_Always)
    imgui.SetNextWindowSize({ 44 * sx, 44 * sy }, ImGuiCond_Always)
    if imgui.Begin('##crystal_socket', nil, flags) then
        slot.visible = true
        slot.window_x, slot.window_y = imgui.GetWindowPos()
        slot.window_w, slot.window_h = imgui.GetWindowSize()
        slot.mouse_x, slot.mouse_y = imgui.GetMousePos()
        local draw = imgui.GetWindowDrawList()
        panel(draw, anchor.x + 4 * sx, anchor.y + 4 * sy, 36 * sx, 36 * sy, true)

        local active_entry = snapshot.active and snapshot.active > 0 and entry_by_id[snapshot.active] or nil
        if active_entry then
            if not draw_entry_icon(draw, active_entry, anchor.x + 6 * sx, anchor.y + 6 * sy) then
                self:draw_fallback_crystal(draw, active_entry, anchor.x + 6 * sx, anchor.y + 6 * sy, 32 * sx, 32 * sy)
            end
        else
            draw:AddRect({ anchor.x + 14 * sx, anchor.y + 12 * sy },
                { anchor.x + 30 * sx, anchor.y + 31 * sy }, colors.muted, 8 * sy)
        end

        imgui.SetCursorPos({ 0, 0 })
        slot.button_x, slot.button_y = imgui.GetCursorScreenPos()
        local clicked = imgui.InvisibleButton('##socket', { 44 * sx, 44 * sy })
        slot.hovered = imgui.IsItemHovered()
        if slot.hovered or self.focused then
            draw:AddRect({ anchor.x + 4 * sx, anchor.y + 4 * sy },
                { anchor.x + 40 * sx, anchor.y + 40 * sy }, colors.text, 3 * sy)
        end

        if clicked then
            slot.clicks = slot.clicks + 1
            self.focused, self.focus_window, self.focus_cursor = true, window, cursor
            if snapshot.open then
                self:close()
            else
                self:show(now, window, cursor)
            end
        end

        if slot.hovered then
            if active_entry then
                local active_owned = protocol.owns(snapshot.owned_mask, active_entry.id)
                self:draw_crystal_tooltip(active_entry, active_owned, true)
            else
                local label = snapshot.loaded and 'empty (click to socket)' or 'syncing...'
                imgui.SetTooltip(('Soul crystal: ' .. label):gsub('%%', '%%%%'))
            end
        end
    end
    imgui.End()
    imgui.PopStyleVar()

    snapshot = self.state:snapshot()
    if self.buckler and not Buckler.active(snapshot) then self:close_buckler() end

    if self.buckler and not snapshot.open then
        local bk = self.buckler
        local rows, row_h = #bk.list, 28
        local bw, bh = 240 * sx, (36 + rows * row_h + 8) * sy
        local display = imgui.GetIO().DisplaySize
        local dw, dh = display.x or display[1], display.y or display[2]
        if dw > 0 and dh > 0 then
            local bx = anchor.x + 52 * sx
            if bx + bw > dw then bx = anchor.x - bw - 8 * sx end
            bx = math.max(0, math.min(bx, dw - bw))
            local by = math.max(0, math.min(anchor.y + 2 * sy, dh - bh))
            local mx, my = imgui.GetMousePos()
            local moved = mx ~= self.mouse_x or my ~= self.mouse_y
            self.mouse_x, self.mouse_y = mx, my
            imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 })
            imgui.SetNextWindowPos({ bx, by }, ImGuiCond_Always)
            imgui.SetNextWindowSize({ bw, bh }, ImGuiCond_Always)
            local chosen
            if imgui.Begin('##crystal_buckler', nil, flags) then
                local draw = imgui.GetWindowDrawList()
                panel(draw, bx, by, bw, bh)
                text(draw, bx + 12 * sx, by + 9 * sy, 'Sub: Buckler')
                draw:AddLine({ bx + 12 * sx, by + 32 * sy }, { bx + bw - 12 * sx, by + 32 * sy }, colors.edge)
                for i, row in ipairs(bk.list) do
                    local top = 36 + (i - 1) * row_h
                    imgui.SetCursorPos({ 5 * sx, top * sy })
                    local clicked = imgui.InvisibleButton('##buckler_' .. i, { bw - 10 * sx, row_h * sy })
                    if clicked then
                        bk.sel = i
                        chosen = i
                    elseif imgui.IsItemHovered() and moved then
                        bk.sel = i
                    end
                    if bk.sel == i then
                        draw:AddRectFilled({ bx + 5 * sx, by + top * sy },
                            { bx + bw - 5 * sx, by + (top + row_h) * sy }, colors.selection, 2 * sy)
                        draw:AddRectFilled({ bx + 5 * sx, by + (top + 6) * sy },
                            { bx + 7 * sx, by + (top + row_h - 6) * sy }, colors.silver)
                    end
                    text(draw, bx + 16 * sx, by + (top + 7) * sy, row.label,
                        row.entry and colors.text or colors.secondary)
                end
            end
            imgui.End()
            imgui.PopStyleVar()
            if chosen then
                Buckler.equip(bk.list[chosen].entry)
                self:close_buckler()
            end
        end
    end

    if not snapshot.open then return end
    catalog = snapshot.catalog
    entries = (catalog and catalog.entries) or {}
    local total_rows = #entries + 1
    if self.selected > total_rows then self.selected = 1 end

    local mouse_x, mouse_y = imgui.GetMousePos()
    local mouse_moved = mouse_x ~= self.mouse_x or mouse_y ~= self.mouse_y
    self.mouse_x, self.mouse_y = mouse_x, mouse_y

    local status = self.feedback or ((snapshot.status == 'error' or snapshot.status == 'unloaded') and snapshot.message)
    local lines = {}
    if status and not snapshot.pending then
        local line = ''
        for word in status:gmatch('%S+') do
            if #line + #word + 1 > 34 and line ~= '' then
                lines[#lines + 1], line = line, ''
            end
            line = line == '' and word or (line .. ' ' .. word)
        end
        if line ~= '' then lines[#lines + 1] = line end
    end

    local list_top = 36
    local row_h = 44
    local remove_top = list_top + math.max(1, #entries) * row_h
    local base_h = remove_top + 32
    local height = base_h + (#lines > 0 and (#lines * 16 + 30) or 0)

    local display = imgui.GetIO().DisplaySize
    local display_w, display_h = display.x or display[1], display.y or display[2]
    if display_w <= 0 or display_h <= 0 then return end
    local fit = math.min(1, display_w / (280 * sx), display_h / (height * sy))
    sx, sy = sx * fit, sy * fit
    local width = 280 * sx
    height = height * sy
    local x = anchor.x + 52 * self.sx
    if x + width > display_w then x = anchor.x - width - 8 * self.sx end
    x = math.max(0, math.min(x, display_w - width))
    local y = math.max(0, math.min(anchor.y + 2 * self.sy, display_h - height))

    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 })
    imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always)
    imgui.SetNextWindowSize({ width, height }, ImGuiCond_Always)
    if imgui.Begin('##crystal_collection', nil, flags) then
        local draw = imgui.GetWindowDrawList()
        panel(draw, x, y, width, height)

        local job_title = (catalog and catalog.job_name and catalog.job_name ~= '')
            and (catalog.job_name .. ' crystals')
            or 'Soul crystals'
        text(draw, x + 12 * sx, y + 9 * sy, job_title)

        imgui.SetCursorPos({ 226 * sx, 2 * sy })
        if imgui.InvisibleButton('##back', { 48 * sx, 28 * sy }) then self:close() end
        text(draw, x + 234 * sx, y + 9 * sy, 'Back', colors.secondary)
        draw:AddLine({ x + 12 * sx, y + 32 * sy }, { x + 268 * sx, y + 32 * sy }, colors.edge)

        local clicks, hovered_idx = {}, nil
        if #entries == 0 then
            local msg = snapshot.pending and 'Loading crystals...' or 'No soul crystals for this job.'
            text(draw, x + 14 * sx, y + (list_top + 12) * sy, msg, colors.secondary, 12)
        else
            for index = 1, #entries do
                local top = list_top + (index - 1) * row_h
                imgui.SetCursorPos({ 5 * sx, top * sy })
                clicks[index] = imgui.InvisibleButton('##crystal_' .. index, { 270 * sx, row_h * sy })
                if imgui.IsItemHovered() then
                    hovered_idx = index
                    if mouse_moved then self.selected = index end
                elseif clicks[index] then
                    self.selected = index
                end
            end
        end

        imgui.SetCursorPos({ 5 * sx, remove_top * sy })
        clicks[total_rows] = imgui.InvisibleButton('##crystal_remove', { 270 * sx, 32 * sy })
        if clicks[total_rows] or (imgui.IsItemHovered() and mouse_moved) then
            self.selected = total_rows
        end

        for index, entry in ipairs(entries) do
            local top = list_top + (index - 1) * row_h
            local owned = snapshot.loaded and protocol.owns(snapshot.owned_mask, entry.id)
            local is_active = snapshot.active == entry.id
            local enabled = snapshot.loaded and not snapshot.pending and owned

            if self.selected == index then
                draw:AddRectFilled({ x + 5 * sx, y + top * sy },
                    { x + 275 * sx, y + (top + row_h) * sy }, colors.selection, 2 * sy)
                draw:AddRectFilled({ x + 5 * sx, y + (top + 9) * sy },
                    { x + 7 * sx, y + (top + row_h - 9) * sy }, colors.silver)
            end

            if not draw_entry_icon(draw, entry, x + 14 * sx, y + (top + 6) * sy) then
                self:draw_fallback_crystal(draw, entry, x + 14 * sx, y + (top + 6) * sy, 32 * sx, 32 * sy)
            end

            local name_color = (snapshot.loaded and not owned) and colors.muted or colors.text
            text(draw, x + 58 * sx, y + (top + 14) * sy, entry.name, name_color)

            if is_active then
                local tag = owned and 'Socketed' or ('Lv.' .. (entry.req_level or 10) .. ' (Inactive)')
                local tag_x = owned and 212 or 168
                text(draw, x + tag_x * sx, y + (top + 15) * sy, tag, colors.secondary, 12)
            elseif snapshot.loaded and not owned then
                text(draw, x + 225 * sx, y + (top + 15) * sy, ('Lv.%d'):format(entry.req_level or 10), colors.muted, 12)
            end

            if hovered_idx == index then
                self:draw_crystal_tooltip(entry, owned, is_active)
            end

            if clicks[index] and enabled then
                self:activate(entry.id, now)
            end
        end

        draw:AddLine({ x + 12 * sx, y + remove_top * sy }, { x + 268 * sx, y + remove_top * sy }, colors.edge)
        local remove_enabled = snapshot.loaded and not snapshot.pending and snapshot.active ~= 0
        if self.selected == total_rows then
            draw:AddRectFilled({ x + 5 * sx, y + remove_top * sy },
                { x + 275 * sx, y + (remove_top + 32) * sy }, colors.selection, 2 * sy)
            draw:AddRectFilled({ x + 5 * sx, y + (remove_top + 9) * sy },
                { x + 7 * sx, y + (remove_top + 23) * sy }, colors.silver)
        end
        text(draw, x + 12 * sx, y + (remove_top + 9) * sy, 'Remove crystal',
            remove_enabled and colors.secondary or colors.muted, 12)
        if clicks[total_rows] and remove_enabled then
            self:activate(0, now)
        end

        if snapshot.pending then
            text(draw, x + 202 * sx, y + (remove_top + 9) * sy, 'Waiting...', colors.secondary, 12)
        end

        if #lines > 0 then
            for index, line in ipairs(lines) do
                text(draw, x + 12 * sx, y + (base_h + 4 + (index - 1) * 16) * sy, line, colors.secondary, 12)
            end
            local top = base_h + 4 + #lines * 16
            imgui.SetCursorPos({ 5 * sx, top * sy })
            if imgui.InvisibleButton('##refresh', { 270 * sx, 24 * sy }) then
                self.feedback = nil
                local ok, why = self.state:sync_current(now, self.send, true)
                if not ok then self.feedback = why end
            end
            text(draw, x + 12 * sx, y + (top + 4) * sy, 'Retry', colors.text, 12)
        end
    end
    imgui.End()
    imgui.PopStyleVar()
end

return UI
