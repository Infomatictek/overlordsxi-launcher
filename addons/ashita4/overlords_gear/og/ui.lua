--[[
* OverlordsXI Gear Manager (overlords_gear) - ImGui User Interface
* Dark gold & slate OverlordsXI theme with Set Builder, Mode Toggles,
* Crystal Spec Selector, Weapon Advisor, and Storage Upgrade Scanner.
--]]

local bit     = require('bit')
local imgui   = require('imgui')
local db      = require('og.db')
local state   = require('og.state')
local swapper = require('og.swapper')
local ox_sync = require('og.ox_sync')

local ui = {
    Open        = { false },
    SelectedSet = 'Idle',
    NewSetName  = { '' },
    WeaponFilter= 'All',
}

local CHILD_BORDERS = ImGuiChildFlags_Borders or ImGuiChildFlags_Border or 1
local COL_TEXT      = ImGuiCol_Text or 0
local COL_GOLD      = { 0.95, 0.78, 0.32, 1.00 }
local COL_CYAN      = { 0.38, 0.86, 0.96, 1.00 }
local COL_GREEN     = { 0.42, 0.90, 0.52, 1.00 }
local COL_ORANGE    = { 0.96, 0.62, 0.25, 1.00 }
local COL_RED       = { 0.95, 0.38, 0.38, 1.00 }
local COL_MUTED     = { 0.62, 0.65, 0.72, 1.00 }
local COL_WHITE     = { 0.95, 0.96, 0.98, 1.00 }

local function drawText(str)
    local s = tostring(str or '')
    if imgui.TextUnformatted then
        imgui.TextUnformatted(s)
    else
        imgui.Text((s:gsub('%%', '%%%%')))
    end
end

local function drawTextColored(col, str)
    local s = tostring(str or '')
    if imgui.TextUnformatted and imgui.PushStyleColor and imgui.PopStyleColor then
        imgui.PushStyleColor(COL_TEXT, col)
        pcall(imgui.TextUnformatted, s)
        imgui.PopStyleColor()
    else
        imgui.TextColored(col, (s:gsub('%%', '%%%%')))
    end
end

local CATEGORY_ORDER = {
    'Standing & Defense',
    'Engaged / Melee',
    'Weaponskills',
    'Spells & Casting',
    'Ranged & Abilities',
    'Job Abilities & Pets',
    'Custom Sets',
}

local function renderHeaderBar()
    local who = state.Who
    if not who then
        drawTextColored(COL_MUTED, 'Waiting for character login...')
        return
    end

    local jobText = string.format('%s Lv.%d', who.JobAbbr, who.Level)
    if who.Sub and who.Sub > 0 then
        jobText = jobText .. string.format(' / %s', who.SubAbbr)
    end
    drawTextColored(COL_GOLD, jobText)
    imgui.SameLine()

    if who.SpecName then
        drawTextColored(COL_CYAN, string.format(' [Crystal: %s - %s]', who.SpecName, who.SpecRole or ''))
    else
        drawTextColored(COL_MUTED, ' [Crystal: Vanilla / None]')
    end

    imgui.SameLine()
    if swapper.IsZoneHolding(state.Prefs.ZoneWait) then
        drawTextColored(COL_ORANGE, string.format('  (Zone Hold: %.1fs)', swapper.ZoneHoldRemaining(state.Prefs.ZoneWait)))
    elseif state.Toggles.Dress then
        drawTextColored(COL_ORANGE, '  (Dressing Mode: Swaps Paused)')
    elseif state.ConflictAddon then
        drawTextColored(COL_RED, string.format('  (Conflict: unload %s!)', state.ConflictAddon))
    else
        drawTextColored(COL_GREEN, string.format('  [Active: %s]', swapper.LastEquippedSetName or 'Idle'))
    end

    -- Quick Mode Bar
    if imgui.Button('Rebuild Sets') then
        state.StartRebuild(true)
    end
    imgui.SameLine()
    if imgui.Button('DT: ' .. state.Toggles.DT) then
        local order = { Off = 'All', All = 'PDT', PDT = 'MDT', MDT = 'Off' }
        state.Toggles.DT = order[state.Toggles.DT] or 'Off'
    end
    imgui.SameLine()
    if imgui.Button('TP: ' .. state.Toggles.TP) then
        local order = { Default = 'Hybrid', Hybrid = 'Acc', Acc = 'Tank', Tank = 'Default' }
        state.Toggles.TP = order[state.Toggles.TP] or 'Default'
    end
    imgui.SameLine()
    if imgui.Button('Idle: ' .. state.Toggles.Idle) then
        local order = { Auto = 'Normal', Normal = 'DT', DT = 'Regen', Regen = 'Refresh', Refresh = 'Auto' }
        state.Toggles.Idle = order[state.Toggles.Idle] or 'Auto'
    end
    imgui.SameLine()
    if imgui.Button('Burst: ' .. (state.Toggles.Burst and 'ON' or 'OFF')) then
        state.Toggles.Burst = not state.Toggles.Burst
    end
    imgui.SameLine()
    if imgui.Button('Kite: ' .. (state.Toggles.Kite and 'ON' or 'OFF')) then
        state.Toggles.Kite = not state.Toggles.Kite
    end
    imgui.SameLine()
    if imgui.Button('TH: ' .. (state.Toggles.TH and 'ON' or 'OFF')) then
        state.Toggles.TH = not state.Toggles.TH
    end
end

-- ========================= Tab 1: Sets & Builder =========================

local function renderSetsTab()
    if not state.Sets[ui.SelectedSet] and #state.SetOrder > 0 then
        ui.SelectedSet = state.SetOrder[1]
    end

    -- Left Sidebar: Categorized Set List
    imgui.BeginChild('##og_sets_sidebar', { 235, -4 }, CHILD_BORDERS)
    drawTextColored(COL_GOLD, string.format('Gear Sets (%d)', #state.SetOrder))
    imgui.Separator()

    local byCat = {}
    for _, sName in ipairs(state.SetOrder) do
        local s = state.Sets[sName]
        if s then
            local cat = s.Category or 'General'
            byCat[cat] = byCat[cat] or {}
            table.insert(byCat[cat], s)
        end
    end

    for _, catName in ipairs(CATEGORY_ORDER) do
        local list = byCat[catName]
        if list and #list > 0 then
            drawTextColored(COL_CYAN, catName)
            for _, s in ipairs(list) do
                local hasOverrides = state.UserOverrides[s.Name] and next(state.UserOverrides[s.Name]) ~= nil
                local prefix = (state.Toggles.WearSet == s.Name) and '[HOLD] ' or (hasOverrides and '* ' or '  ')
                local lbl = prefix .. (s.Label or s.Name) .. '##' .. s.Name
                if imgui.Selectable(lbl, ui.SelectedSet == s.Name) then
                    ui.SelectedSet = s.Name
                end
            end
            imgui.Separator()
        end
    end

    drawTextColored(COL_GOLD, 'Save Worn Gear As Set:')
    imgui.PushItemWidth(145)
    imgui.InputText('##og_new_set', ui.NewSetName, 32)
    imgui.PopItemWidth()
    imgui.SameLine()
    if imgui.Button('Save##og_save_new') then
        local name = db.CleanSetKey(ui.NewSetName[1] or '')
        if name ~= '' then
            state.SaveCurrentEquipmentToSet(name)
            ui.SelectedSet = name
            ui.NewSetName[1] = ''
        end
    end
    imgui.EndChild()

    imgui.SameLine()

    -- Right Pane: Selected Set Details & 16-Slot Editor
    imgui.BeginChild('##og_sets_detail', { 0, -4 }, CHILD_BORDERS)
    local curSet = state.Sets[ui.SelectedSet]
    if not curSet then
        drawTextColored(COL_MUTED, 'Select a set on the left to inspect or customize its 16 slots.')
        imgui.EndChild()
        return
    end

    drawTextColored(COL_GOLD, string.format('%s  (%s)', curSet.Label or curSet.Name, curSet.Name))
    imgui.SameLine()
    drawTextColored(COL_MUTED, string.format('  [Set Score: %.1f]', curSet.SetScore or 0))

    -- Action buttons for the selected set
    if imgui.Button('Equip Now') then
        swapper.EquipSlots(curSet.Slots, state.Prefs.LockedSlots, curSet.Label or curSet.Name)
    end
    imgui.SameLine()
    local isHeld = (state.Toggles.WearSet == curSet.Name)
    if imgui.Button(isHeld and 'Release Hold (/og wear off)' or 'Hold Set (/og wear)') then
        state.Toggles.WearSet = isHeld and nil or curSet.Name
        if not isHeld then
            swapper.EquipSlots(curSet.Slots, state.Prefs.LockedSlots, 'Wear: ' .. (curSet.Label or curSet.Name))
        end
    end
    imgui.SameLine()
    if imgui.Button('Save Current Gear Here') then
        state.SaveCurrentEquipmentToSet(curSet.Name)
    end
    imgui.SameLine()
    local jobAbbr = (state.Who and state.Who.JobAbbr) or 'WAR'
    local isLockedLook = (state.Prefs.LockstyleByJob[jobAbbr] == curSet.Name)
    if imgui.Button(isLockedLook and 'Unlock Appearance' or 'Lockstyle This Set') then
        if isLockedLook then
            state.Prefs.LockstyleByJob[jobAbbr] = nil
            state.SavePrefs()
            AshitaCore:GetChatManager():QueueCommand(1, '/lockstyle off')
        else
            state.Prefs.LockstyleByJob[jobAbbr] = curSet.Name
            state.SavePrefs()
            swapper.LockStyleSet(curSet.Slots)
        end
    end
    imgui.SameLine()
    if state.UserOverrides[curSet.Name] and next(state.UserOverrides[curSet.Name]) ~= nil then
        if imgui.Button('Clear Manual Picks') then
            state.UserOverrides[curSet.Name] = nil
            state.SaveJobProfile()
            state.RebuildSingleSet(curSet.Name)
            curSet = state.Sets[ui.SelectedSet]
        end
    end

    -- Totals Bar
    local tot = curSet.Totals or {}
    imgui.Separator()
    drawTextColored(COL_CYAN, string.format(
        'Totals:  Gear Haste %+.1f%% (cap 25%%)  |  PDT %+.1f%%  |  MDT %+.1f%%  |  Fast Cast %+d%%  |  DEF %+d  |  HP %+d  |  MP %+d',
        tot.Haste or 0, tot.PDT or 0, tot.MDT or 0, tot.FastCast or 0, tot.DEF or 0, tot.HP or 0, tot.MP or 0
    ))
    drawTextColored(COL_MUTED, string.format(
        'Combat:  ACC %+d  |  ATT %+d  |  Store TP %+d  |  DA %+d%%  |  TA %+d%%  |  MACC %+d  |  MAB %+d  |  Refresh %+d  |  Regen %+d',
        tot.ACC or 0, tot.ATT or 0, tot.StoreTP or 0, tot.DA or 0, tot.TA or 0, tot.MACC or 0, tot.MATT or 0, tot.Refresh or 0, tot.Regen or 0
    ))
    imgui.Separator()

    -- 16-Slot Editor List
    for sIdx = 1, 16 do
        local sDef = db.SLOT_BY_INDEX[sIdx]
        local piece = curSet.Slots[sIdx]
        local exp   = curSet.Explain and curSet.Explain[sIdx]
        local ovMap = state.UserOverrides[curSet.Name]
        local hasOv = ovMap and ovMap[sIdx] ~= nil
        local isGlobalLock = state.Prefs.LockedSlots[sIdx] == true

        -- Slot Label
        local slotLabel = string.format('%-6s', sDef.key)
        if isGlobalLock then
            drawTextColored(COL_ORANGE, slotLabel .. ' [L]')
        elseif hasOv then
            drawTextColored(COL_GOLD, slotLabel .. ' [*]')
        else
            drawTextColored(COL_MUTED, slotLabel .. '    ')
        end
        imgui.SameLine(85)

        -- Combo dropdown to pick any wearable item for this slot
        local preview = piece and string.format('%s (%s)', piece.Name, piece.BagName) or (sIdx <= 4 and '(Weapon Untouched)' or '(Empty)')
        imgui.PushItemWidth(265)
        if imgui.BeginCombo('##slot_combo_' .. tostring(sIdx), preview) then
            if imgui.Selectable('Auto (Let Builder Choose)##auto_' .. tostring(sIdx), not hasOv) then
                if state.UserOverrides[curSet.Name] then
                    state.UserOverrides[curSet.Name][sIdx] = nil
                    state.SaveJobProfile()
                    state.RebuildSingleSet(curSet.Name)
                end
            end
            if imgui.Selectable('Leave Slot Untouched##none_' .. tostring(sIdx), hasOv and ovMap[sIdx] == 'none') then
                state.UserOverrides[curSet.Name] = state.UserOverrides[curSet.Name] or {}
                state.UserOverrides[curSet.Name][sIdx] = 'none'
                state.SaveJobProfile()
                state.RebuildSingleSet(curSet.Name)
            end
            imgui.Separator()
            for _, cand in ipairs(state.WearablePieces) do
                if bit.band(cand.SlotMask or 0, sDef.mask) ~= 0 then
                    local cLabel = string.format('%s  [Lv.%d, %s]##%s', cand.Name, cand.Level or 1, cand.BagName, cand.UniqueKey)
                    local isSelected = (piece and piece.UniqueKey == cand.UniqueKey)
                    if imgui.Selectable(cLabel, isSelected) then
                        state.UserOverrides[curSet.Name] = state.UserOverrides[curSet.Name] or {}
                        state.UserOverrides[curSet.Name][sIdx] = { Id = cand.Id, Name = cand.Name }
                        state.SaveJobProfile()
                        state.RebuildSingleSet(curSet.Name)
                    end
                end
            end
            imgui.EndCombo()
        end
        imgui.PopItemWidth()

        imgui.SameLine(360)
        if exp then
            drawTextColored(COL_GREEN, string.format('%+6.1f', exp.Score or 0))
            imgui.SameLine(420)
            drawTextColored(COL_WHITE, exp.Summary or '')
        else
            drawTextColored(COL_MUTED, '   ---')
        end
    end

    imgui.EndChild()
end

-- ========================= Tab 2: Modes & Crystal Spec =========================

local function renderModesTab()
    imgui.BeginChild('##og_modes_pane', { 0, -4 }, CHILD_BORDERS)
    local who = state.Who

    drawTextColored(COL_GOLD, '1. OverlordsXI Soul Crystal Specialization Profile')
    drawTextColored(COL_MUTED, 'Adjusts stat weights, tank/melee/pet sets, and weapon eligibility for your active OverlordsXI Soul Crystal.')
    if who then
        local specs = ox_sync.GetSpecsForJob(who.Job)
        local curOverride = ox_sync.State.OverrideSpec[who.Job] or 'auto'
        if imgui.Button((curOverride == 'auto' and '[*] ' or '    ') .. 'Auto (Follow Equipped Crystal)') then
            ox_sync.State.OverrideSpec[who.Job] = 'auto'
            state.SaveJobProfile()
            state.StartRebuild(true)
        end
        imgui.SameLine()
        if imgui.Button((curOverride == 'none' and '[*] ' or '    ') .. 'Vanilla (No Crystal)') then
            ox_sync.State.OverrideSpec[who.Job] = 'none'
            state.SaveJobProfile()
            state.StartRebuild(true)
        end
        for _, sp in ipairs(specs) do
            imgui.SameLine()
            local isSel = (curOverride == sp.key)
            if imgui.Button(string.format('%s%s (%s)', isSel and '[*] ' or '    ', sp.name, sp.role)) then
                ox_sync.State.OverrideSpec[who.Job] = sp.key
                state.SaveJobProfile()
                state.StartRebuild(true)
            end
        end
    end

    imgui.Separator()
    drawTextColored(COL_GOLD, '2. Combat, Casting & Standing Mode Toggles')

    drawTextColored(COL_CYAN, 'Damage Taken Override (/og dt):')
    for _, m in ipairs({ 'Off', 'All', 'PDT', 'MDT' }) do
        imgui.SameLine()
        if imgui.Button((state.Toggles.DT == m and '[*] ' or '    ') .. m .. '##dt_' .. m) then
            state.Toggles.DT = m
        end
    end

    drawTextColored(COL_CYAN, 'Engaged TP Mode (/og tp):      ')
    for _, m in ipairs({ 'Default', 'Hybrid', 'Acc', 'Tank' }) do
        imgui.SameLine()
        if imgui.Button((state.Toggles.TP == m and '[*] ' or '    ') .. m .. '##tp_' .. m) then
            state.Toggles.TP = m
        end
    end

    drawTextColored(COL_CYAN, 'Idle Mode (/og idle):          ')
    for _, m in ipairs({ 'Auto', 'Normal', 'DT', 'Regen', 'Refresh' }) do
        imgui.SameLine()
        if imgui.Button((state.Toggles.Idle == m and '[*] ' or '    ') .. m .. '##idle_' .. m) then
            state.Toggles.Idle = m
        end
    end

    drawTextColored(COL_CYAN, 'Elemental Nuke Mode (/og nuke):')
    for _, m in ipairs({ 'Power', 'Acc' }) do
        imgui.SameLine()
        if imgui.Button((state.Toggles.Nuke == m and '[*] ' or '    ') .. m .. '##nuke_' .. m) then
            state.Toggles.Nuke = m
        end
    end

    imgui.Separator()
    drawTextColored(COL_GOLD, '3. Action Overlays & Movement')
    if imgui.Button((state.Toggles.Burst and '[ON] ' or '[OFF] ') .. 'Magic Burst Overlay (/og burst)') then
        state.Toggles.Burst = not state.Toggles.Burst
    end
    imgui.SameLine()
    if imgui.Button((state.Toggles.Kite and '[ON] ' or '[OFF] ') .. 'Kite / Movement Speed Lock (/og kite)') then
        state.Toggles.Kite = not state.Toggles.Kite
    end
    imgui.SameLine()
    if imgui.Button((state.Toggles.TH and '[ON] ' or '[OFF] ') .. 'Treasure Hunter Overlay (/og th)') then
        state.Toggles.TH = not state.Toggles.TH
    end

    if imgui.Button((state.Prefs.AutoMoveGear and '[ON] ' or '[OFF] ') .. 'Auto-Equip Movement Speed Gear When Running (Idle)') then
        state.Prefs.AutoMoveGear = not state.Prefs.AutoMoveGear
        state.SavePrefs()
    end
    imgui.SameLine()
    if imgui.Button((state.Toggles.Dress and '[PAUSED] ' or '[ACTIVE] ') .. 'Dressing Mode (/og dress)') then
        state.Toggles.Dress = not state.Toggles.Dress
    end

    imgui.Separator()
    drawTextColored(COL_GOLD, '4. Global Slot Locks (Prevent Auto-Swapping Specific Slots)')
    for sIdx = 1, 16 do
        local sDef = db.SLOT_BY_INDEX[sIdx]
        local locked = state.Prefs.LockedSlots[sIdx] == true
        if (sIdx - 1) % 8 ~= 0 then imgui.SameLine() end
        if imgui.Button(string.format('%s%s##lock_%d', locked and '[LOCK] ' or '', sDef.key, sIdx)) then
            state.Prefs.LockedSlots[sIdx] = not locked and true or nil
            state.SavePrefs()
            state.StartRebuild(false)
        end
    end

    imgui.Separator()
    drawTextColored(COL_GOLD, '5. Post-Zone Safety Delay')
    drawTextColored(COL_MUTED, string.format('Current Zone Wait: %d seconds after first movement in a new zone.', state.Prefs.ZoneWait or 6))
    for _, sec in ipairs({ 2, 4, 6, 8, 10 }) do
        imgui.SameLine()
        if imgui.Button(string.format('%s%ds##zw_%d', (state.Prefs.ZoneWait == sec) and '[*] ' or '', sec, sec)) then
            state.Prefs.ZoneWait = sec
            state.SavePrefs()
        end
    end

    imgui.EndChild()
end

-- ========================= Tab 3: Weapon Advisor =========================

local function renderWeaponsTab()
    imgui.BeginChild('##og_weapons_pane', { 0, -4 }, CHILD_BORDERS)
    drawTextColored(COL_GOLD, 'Weapon, Shield, Ranged & Ammo Advisor')
    drawTextColored(COL_MUTED, 'Generated sets never overwrite your Main/Sub/Range/Ammo slots automatically. Use this advisor to compare and equip weapons from your bags.')

    for _, filt in ipairs({ 'All', 'Main', 'Sub', 'Range', 'Ammo' }) do
        if filt ~= 'All' then imgui.SameLine() end
        if imgui.Button((ui.WeaponFilter == filt and '[*] ' or '    ') .. filt .. '##wf_' .. filt) then
            ui.WeaponFilter = filt
        end
    end
    imgui.Separator()

    for idx, w in ipairs(state.WeaponRanks or {}) do
        if ui.WeaponFilter == 'All' or ui.WeaponFilter == w.SlotType then
            local p = w.Piece
            local slotIdx = (w.SlotType == 'Main' and 1) or (w.SlotType == 'Sub' and 2) or (w.SlotType == 'Range' and 3) or 4
            if p.Equippable then
                if imgui.Button(string.format('Equip %s##eqw_%d', w.SlotType, idx)) then
                    swapper.EquipSinglePiece(p, slotIdx)
                end
            else
                drawTextColored(COL_MUTED, '[In Storage]')
            end
            imgui.SameLine(110)
            drawTextColored(COL_WHITE, string.format('%-26s', p.Name))
            imgui.SameLine(320)
            drawTextColored(COL_CYAN, string.format('Lv.%-2d %-14s', p.Level or 1, w.Skill or ''))
            imgui.SameLine(465)
            if w.DPS > 0 then
                drawTextColored(COL_GREEN, string.format('DMG:%d Delay:%d (%.1f DPS)', p.Dmg or 0, p.Delay or 0, w.DPS))
            else
                drawTextColored(COL_MUTED, 'Stat / Shield / Grip')
            end
            imgui.SameLine(650)
            if w.SpecNote then
                drawTextColored(COL_GOLD, '[' .. w.SpecNote .. '] ')
            end
            drawTextColored(COL_MUTED, '(' .. p.BagName .. ')')
        end
    end

    imgui.EndChild()
end

-- ========================= Tab 4: Storage Upgrades =========================

local function renderUpgradesTab()
    imgui.BeginChild('##og_upgrades_pane', { 0, -4 }, CHILD_BORDERS)
    drawTextColored(COL_GOLD, string.format('Storage Bag Upgrade Finder (%d found)', #(state.Upgrades or {})))
    drawTextColored(COL_MUTED, 'Items sitting in Mog Safe, Safe 2, Storage, Mog Locker, Satchel, Sack, or Case that score higher than your current equippable bags:')
    imgui.Separator()

    if #(state.Upgrades or {}) == 0 then
        drawTextColored(COL_GREEN, 'All of your best gear for this job & level is already in your Inventory or Wardrobes!')
    else
        for i, u in ipairs(state.Upgrades) do
            if i > 60 then break end
            drawTextColored(COL_ORANGE, string.format('[%s]', u.BagName))
            imgui.SameLine(120)
            drawTextColored(COL_WHITE, string.format('%-26s', u.Piece.Name))
            imgui.SameLine(330)
            drawTextColored(COL_CYAN, string.format('%s -> %s', u.SetName, u.SlotKey))
            imgui.SameLine(540)
            drawTextColored(COL_GREEN, string.format('+%.1f pts over %s', u.ScoreGain, u.Current))
        end
    end

    imgui.EndChild()
end

-- ========================= Tab 5: Commands & Help =========================

local function renderHelpTab()
    imgui.BeginChild('##og_help_pane', { 0, -4 }, CHILD_BORDERS)
    drawTextColored(COL_GOLD, 'OverlordsXI Gear Manager (/og, /ogear) - Command Reference')
    imgui.Separator()

    local cmds = {
        { '/og  (or /ogear)',              'Toggle this OverlordsXI Gear Manager window.' },
        { '/og build',                     'Force an immediate rebuild of all sets for your job, level, and Crystal Spec.' },
        { '/og dt [off|all|pdt|mdt]',      'Cycle or set Damage Taken override mode.' },
        { '/og tp [default|hybrid|acc|tank]', 'Cycle or set Engaged melee set mode.' },
        { '/og idle [auto|normal|dt|regen|refresh]', 'Cycle or set Idle standing set mode.' },
        { '/og nuke [power|acc]',          'Toggle Elemental magic between max damage and magic accuracy.' },
        { '/og burst [on|off]',            'Toggle Magic Burst midcast set overlay.' },
        { '/og kite [on|off]',             'Toggle Movement Speed / Kite overlay.' },
        { '/og th [on|off]',               'Toggle Treasure Hunter overlay on Engaged & Midcast actions.' },
        { '/og spec [auto|none|<spec>]',   'Follow your equipped OverlordsXI Soul Crystal or force a specific Spec profile.' },
        { '/og wear <SetName> | off',      'Equip and hold a specific set continuously until "/og wear off".' },
        { '/og equip <SetName>',           'Equip a set once immediately.' },
        { '/og dress',                     'Pause automatic swapping so you can manually equip gear from the menu.' },
        { '/og save <SetName>',            'Save your currently worn equipment into <SetName> and resume swapping.' },
        { '/og look <SetName> | off',      'Lock your visual character appearance (Lockstyle) to <SetName>.' },
        { '/og upgrades',                  'Check Mog Safe, Storage, Locker, Satchel, Sack & Case for gear upgrades.' },
    }

    for _, c in ipairs(cmds) do
        drawTextColored(COL_CYAN, string.format('%-36s', c[1]))
        imgui.SameLine(300)
        drawTextColored(COL_WHITE, c[2])
    end

    imgui.EndChild()
end

-- Main ImGui Render Entrypoint
function ui.Render()
    if not ui.Open[1] then return end

    imgui.SetNextWindowSize({ 880, 600 }, ImGuiCond_FirstUseEver or 4)
    if imgui.Begin('OverlordsXI Gear Manager (/og)##overlords_gear_main', ui.Open) then
        renderHeaderBar()
        imgui.Separator()

        if imgui.BeginTabBar('##og_main_tabs') then
            if imgui.BeginTabItem('Sets & Loadouts') then
                renderSetsTab()
                imgui.EndTabItem()
            end
            if imgui.BeginTabItem('Modes & Crystal Spec') then
                renderModesTab()
                imgui.EndTabItem()
            end
            if imgui.BeginTabItem('Weapon Advisor') then
                renderWeaponsTab()
                imgui.EndTabItem()
            end
            if imgui.BeginTabItem('Storage Upgrades') then
                renderUpgradesTab()
                imgui.EndTabItem()
            end
            if imgui.BeginTabItem('Commands & Help') then
                renderHelpTab()
                imgui.EndTabItem()
            end
            imgui.EndTabBar()
        end
    end
    imgui.End()
end

return ui
