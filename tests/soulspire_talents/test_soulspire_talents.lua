-- Headless LuaJIT Test Suite for SoulspireXI Weapon Skill Talent Addon (v3.0)
-- Validates against the exact SoulspireXI server wire protocol (soulspire_ws_talents.lua):
--   1. Module loading (ws_client_meta, talent_theme, talent_state, talent_tree_ui)
--   2. Real wire protocol parsing (META, SPENT_BEGIN/SPENT/SPENT_END, CAT_BEGIN/CAT/CAT_END,
--      WS, NODES/NODE, WS_END, ERR) — both legacy and enriched v2.1 fields
--   3. Strict Soul weapon eligibility grouping (Primary vs Signature, zero ineligible)
--   4. Soul switching state invalidation & full resync trigger
--   5. Anti-double-click pending lock, clear on WS_END/ERR, and timeout recovery
--   6. Genuine progression connection graph & exclusive group lock detection
--   7. Tooltip model completeness & zero internal identifier (OX_*) leakage
--   8. Headless ImGui render pass across standard, Evolution, and compact resolutions

local addonDir = arg and arg[1] or '.'
package.path = addonDir .. '/?.lua;' .. addonDir .. '/?/init.lua;' .. package.path

local passed, failed = 0, 0

local function assertTrue(cond, msg)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        io.stderr:write('[FAIL] ' .. tostring(msg) .. '\n')
    end
end

local function assertEq(actual, expected, msg)
    if actual == expected then
        passed = passed + 1
    else
        failed = failed + 1
        io.stderr:write(string.format('[FAIL] %s: expected=%s actual=%s\n',
            tostring(msg), tostring(expected), tostring(actual)))
    end
end

-- ============================================================================
-- 1. Load pure-Lua modules
-- ============================================================================
local Meta  = require('ws_client_meta')
local Theme = require('talent_theme')
local State = require('talent_state')

assertTrue(type(Meta) == 'table' and type(Meta.SOULS) == 'table', 'ws_client_meta loaded')
assertTrue(type(Theme) == 'table' and type(Theme.BRANCHES) == 'table', 'talent_theme loaded')
assertTrue(type(State) == 'table' and type(State.newState) == 'function', 'talent_state loaded')

-- Verify all 66 canonical Souls exist in ws_client_meta
local soulCount = 0
for k, info in pairs(Meta.SOULS) do
    soulCount = soulCount + 1
    assertTrue(type(info.primary) == 'table' and #info.primary >= 1,
        'Soul ' .. k .. ' has at least 1 primary weapon')
    assertTrue(type(info.name) == 'string' and #info.name > 0,
        'Soul ' .. k .. ' has player-facing name')
    assertTrue(type(info.mechanic) == 'string' and #info.mechanic > 0,
        'Soul ' .. k .. ' has player-facing mechanic label')
end
assertEq(soulCount, 66, 'ws_client_meta contains all 66 canonical Souls')

-- Verify branch themes match verified official website palette
assertEq(Theme.BRANCHES.damage.title, 'DAMAGE', 'Damage branch title')
assertEq(Theme.BRANCHES.soul.title, 'SOUL', 'Soul branch title')
assertEq(Theme.BRANCHES.soul.centerpiece, true, 'Soul branch is visual centerpiece')
assertEq(Theme.BRANCHES.utility.title, 'UTILITY', 'Utility branch title')

-- ============================================================================
-- 2. Real Wire Protocol Parsing & Strict Weapon Eligibility Grouping
-- ============================================================================
local fakeNow = 100.0
local function nowFn() return fakeNow end

local st = State.newState()
State.handleProtoLine(st, 'META|WAR|75|12|3|15|6|0|Berserker|berserker|Damage', nowFn)
assertEq(st.jobKey, 'WAR', 'META jobKey')
assertEq(st.jobLevel, 75, 'META jobLevel')
assertEq(st.avail, 12, 'META avail')
assertEq(st.spent, 3, 'META spent')
assertEq(st.earned, 15, 'META earned')
assertEq(st.mainSkill, 6, 'META mainSkill')
assertEq(st.specName, 'Berserker', 'META specName')
assertEq(st.soulKey, 'berserker', 'META soulKey')
assertEq(st.role, 'Damage', 'META role')

-- Feed SPENT for 2 WSs (out of 4 mastery cap)
State.handleProtoLine(st, 'SPENT_BEGIN', nowFn)
State.handleProtoLine(st, 'SPENT|80:2:1,81:1:1', nowFn)
State.handleProtoLine(st, 'SPENT_END', nowFn)
assertEq(st.spentByWs[80], 2, 'SPENT ws 80 = 2')
assertEq(st.spentByWs[81], 1, 'SPENT ws 81 = 1')
assertEq(State.countInvestedWs(st), 2, 'Invested WS count = 2')

-- Feed CAT with Great Axe (skill 6, primary), Axe (skill 5, signature),
-- AND an incidental Sword WS (skill 3) to verify strict client filtering
State.handleProtoLine(st, 'CAT_BEGIN', nowFn)
State.handleProtoLine(st, 'CAT|80:6:Iron Tempest:physical,81:6:Sturmwind:physical,84:6:Raging Rush:physical,64:5:Raging Axe:physical,68:5:Mistral Axe:physical,32:3:Fast Blade:physical', nowFn)
State.handleProtoLine(st, 'CAT_END', nowFn)
assertEq(#st.catalog, 6, 'Raw catalog has 6 entries')
assertEq(st.synced, true, 'CAT_END sets synced=true')

local groups = st.weaponGroups
assertEq(#groups, 2, 'Berserker has exactly 2 eligible weapon groups (Great Axe + Axe)')
assertEq(groups[1].skillId, 6, 'Primary group is Great Axe (6)')
assertEq(groups[1].tierLabel, 'Primary', 'Great Axe is Primary')
assertEq(#groups[1].weapons, 3, 'Great Axe has 3 WSs')
assertEq(groups[2].skillId, 5, 'Signature group is Axe (5)')
assertEq(groups[2].tierLabel, 'Signature', 'Axe is Signature')
assertEq(#groups[2].weapons, 2, 'Axe has 2 WSs')

-- Confirm incidental Sword WS (32) was strictly excluded
for _, g in ipairs(groups) do
    assertTrue(g.skillId ~= 3, 'Incidental Sword (skill 3) excluded for Berserker')
end

-- Default WS picks invested eligible WS (80)
assertEq(st.selectedWsId, 80, 'Default WS picks invested eligible WS (80)')

-- Test single-primary Soul (Spartan = Polearm only)
local stSpartan = State.newState()
State.handleProtoLine(stSpartan, 'META|DRG|75|10|0|10|8|0|Spartan|spartan|Tank', nowFn)
State.handleProtoLine(stSpartan, 'CAT_BEGIN', nowFn)
State.handleProtoLine(stSpartan, 'CAT|112:8:Double Thrust:physical,118:8:Wheeling Thrust:physical,32:3:Fast Blade:physical,16:2:Wasp Sting:physical', nowFn)
State.handleProtoLine(stSpartan, 'CAT_END', nowFn)
assertEq(#stSpartan.weaponGroups, 1, 'Spartan has exactly 1 eligible weapon group (Polearm)')
assertEq(stSpartan.weaponGroups[1].skillId, 8, 'Spartan primary is Polearm (8)')
assertEq(#stSpartan.weaponGroups[1].weapons, 2, 'Spartan Polearm has 2 WSs')

-- Test Pet Soul (Wyvernheart = Polearm)
local stWyv = State.newState()
State.handleProtoLine(stWyv, 'META|DRG|75|10|0|10|8|0|Wyvernheart|wyvernheart|Pet', nowFn)
State.handleProtoLine(stWyv, 'CAT_BEGIN', nowFn)
State.handleProtoLine(stWyv, 'CAT|112:8:Double Thrust:physical,119:8:Impulse Drive:physical', nowFn)
State.handleProtoLine(stWyv, 'CAT_END', nowFn)
assertEq(#stWyv.weaponGroups, 1, 'Wyvernheart has Polearm primary')
assertEq(stWyv.weaponGroups[1].skillId, 8, 'Wyvernheart skillId = 8')

-- Test Dual-Weapon Throwing Soul (Bladewheel = Throwing + Dagger)
local stBw = State.newState()
State.handleProtoLine(stBw, 'META|NIN|75|10|0|10|2|27|Bladewheel|bladewheel|Damage', nowFn)
State.handleProtoLine(stBw, 'CAT_BEGIN', nowFn)
State.handleProtoLine(stBw, 'CAT|224:27:Pinwheel Toss:ranged,16:2:Wasp Sting:physical,128:9:Blade: Rin:physical', nowFn)
State.handleProtoLine(stBw, 'CAT_END', nowFn)
assertEq(#stBw.weaponGroups, 2, 'Bladewheel has Throwing (Primary) + Dagger (Signature)')
assertEq(stBw.weaponGroups[1].skillId, 27, 'Bladewheel primary is Throwing (27)')
assertEq(stBw.weaponGroups[2].skillId, 2, 'Bladewheel signature is Dagger (2)')

-- ============================================================================
-- 3. Tree Detail Parsing, Progression Graph & Tooltips
-- ============================================================================
local function feedSampleStandardTree(targetState, wsId)
    State.handleProtoLine(targetState, string.format('WS|%d|Raging Rush|Great Axe|physical|4|Physical 3-hit crit WS', wsId), nowFn)
    -- Damage branch (col 1, slots 1..4)
    State.handleProtoLine(targetState, string.format('NODE|%d|dmg_t1|1|1|2|3|1|0||0|Savage Edge|Increases weapon skill damage by 10%%.|1|0|0||1|damage||Next rank: +15%% weapon skill damage.', wsId), nowFn)
    State.handleProtoLine(targetState, string.format('NODE|%d|dmg_t2|2|1|1|2|1|2|dmg_t1|1|Brutal Crit|Increases critical hit rate by 8%%.|20|0|0||2|damage||Next rank: +16%% critical hit rate.', wsId), nowFn)
    State.handleProtoLine(targetState, string.format('NODE|%d|dmg_t3|3|1|0|2|0|4|dmg_t2|2|Cleaving Blow|Ignores 15%% of target physical defense.|40|0|0||3|damage||Next rank: Ignores 30%% defense.', wsId), nowFn)
    State.handleProtoLine(targetState, string.format('NODE|%d|dmg_t4|4|1|0|1|0|6|dmg_t3|1|Executioner Apex|Deals +35%% bonus damage against targets below 40%% HP.|60|0|0||4|damage||', wsId), nowFn)
    -- Utility branch (col 2, slots 5..8)
    State.handleProtoLine(targetState, string.format('NODE|%d|util_t1|1|2|0|3|1|0||0|Steady Grip|Grants +15 Accuracy during weapon skill execution.|1|0|0||5|utility||Next rank: +30 Accuracy.', wsId), nowFn)
    State.handleProtoLine(targetState, string.format('NODE|%d|util_t2|2|2|0|2|0|2|util_t1|1|Momentum Return|Refunds 120 TP when landing a hit.|20|0|0||6|utility||Next rank: Refunds 240 TP.', wsId), nowFn)
    State.handleProtoLine(targetState, string.format('NODE|%d|util_t3|3|2|0|2|0|4|util_t2|1|Shattering Stagger|Applies Defense Down (-10%%) for 15 seconds.|40|0|0||7|utility||Next rank: -20%% Defense Down.', wsId), nowFn)
    State.handleProtoLine(targetState, string.format('NODE|%d|util_t4|4|2|0|1|0|6|util_t3|1|Tactical Mastery|Reduces next Soul Action cooldown by 10s.|60|0|0||8|utility||', wsId), nowFn)
    -- Soul branch (col 3, slots 9..12)
    State.handleProtoLine(targetState, string.format('NODE|%d|soul_t1|1|3|1|3|1|0||0|Fury Conduit|Generates +12 Rage on weapon skill hit.|1|0|0||9|soul||Next rank: Generates +24 Rage.', wsId), nowFn)
    State.handleProtoLine(targetState, string.format('NODE|%d|soul_t2|2|3|0|2|1|2|soul_t1|1|Bloodlust Surge|Extends active Berserk duration by 4 seconds.|20|0|0||10|soul||Next rank: Extends duration by 8 seconds.', wsId), nowFn)
    State.handleProtoLine(targetState, string.format('NODE|%d|soul_t3|3|3|0|2|0|4|soul_t2|1|Rampage Echo|Consuming 50+ Rage grants a 25%% follow-up strike.|40|0|0||11|soul||Next rank: 50%% follow-up strike.', wsId), nowFn)
    State.handleProtoLine(targetState, string.format('NODE|%d|soul_t4|4|3|0|1|0|6|soul_t3|1|Unstoppable Avatar|Weapon skill triggers Peak Fury for 12s.|60|0|0||12|soul||', wsId), nowFn)
    -- Skillchain bonus node (scTier = 1)
    State.handleProtoLine(targetState, string.format('NODE|%d|sc_1|5|1|0|1|1|3||0|Fragmentation Link|Adds Fragmentation skillchain property.|30|1|11|Fragmentation|13|skillchain||', wsId), nowFn)
    State.handleProtoLine(targetState, string.format('WS_END|%d|12|1', wsId), nowFn)
end

feedSampleStandardTree(st, 84)
local tree = st.wsDetail
assertTrue(tree ~= nil, 'Standard WS 84 tree loaded')
assertEq(tree.name, 'Raging Rush', 'Tree name')
assertEq(#tree.nodes, 13, 'Tree has 13 nodes (12 branch + 1 SC)')

-- Verify genuine connection graph: only explicit reqKey dependencies (9 total)
local edges = State.buildConnections(tree)
assertEq(#edges, 9, 'Standard 3x4 tree has exactly 9 genuine reqKey edges')
local prereqCount = 0
for _, e in ipairs(edges) do
    assertEq(e.from.branch, e.to.branch, 'Edge connects within same branch only')
    assertEq(e.to.reqKey, e.from.key, 'Edge strictly matches reqKey')
    if e.kind == 'prereq' then prereqCount = prereqCount + 1 end
end
assertEq(prereqCount, 9, 'All 9 edges are explicit prereq links')

-- Verify tooltip model & zero internal ID leakage
for _, node in ipairs(tree.nodes) do
    local tip = State.buildTooltipModel(st, node)
    assertEq(tip.name, node.name, 'Tooltip name matches node name')
    assertTrue(type(tip.currentEffect) == 'string' and #tip.currentEffect > 0, 'Tooltip has currentEffect')
    local prereqParts = {}
    for _, pr in ipairs(tip.prereqs or {}) do
        prereqParts[#prereqParts + 1] = tostring(pr.text or pr)
    end
    local allText = table.concat({
        tip.name or '', tip.branchLabel or '', tip.statusLabel or '', tip.currentEffect or '',
        tip.nextEffect or '', tip.excludedBy or '', tip.soulMechanic or '',
        table.concat(prereqParts, ' ')
    }, ' ')
    assertTrue(not allText:find('OX_'), 'Tooltip has zero OX_ internal strings: ' .. node.name)
    assertTrue(not allText:find('ox_'), 'Tooltip has zero ox_ internal strings: ' .. node.name)
    assertTrue(not allText:find('slot_id'), 'Tooltip has zero slot_id leaks: ' .. node.name)
end

-- Check nextEffect on non-maxed node & prereqs on locked tier 3 node
local tipDmg1 = State.buildTooltipModel(st, tree.nodes[1])
assertEq(tipDmg1.nextEffect, 'Next rank: +15% weapon skill damage.', 'Tooltip includes next-rank preview')
local tipDmg3 = State.buildTooltipModel(st, tree.nodes[3])
assertTrue(#(tipDmg3.prereqs or {}) >= 1, 'Locked tier 3 node shows prerequisite requirement')

-- ============================================================================
-- 4. Mutually Exclusive Talents (Evolution Tree #1 Combo)
-- ============================================================================
local stEvo = State.newState()
State.handleProtoLine(stEvo, 'META|MNK|75|8|2|10|1|0|Blackbelt|blackbelt|Damage', nowFn)
State.handleProtoLine(stEvo, 'CAT_BEGIN', nowFn)
State.handleProtoLine(stEvo, 'CAT|1:1:Combo:physical,2:1:Shoulder Tackle:physical', nowFn)
State.handleProtoLine(stEvo, 'CAT_END', nowFn)
State.handleProtoLine(stEvo, 'WS|1|Combo|Hand-to-Hand|physical|2|3-hit Evolution WS', nowFn)
State.handleProtoLine(stEvo, 'NODE|1|e_co_force|1|1|1|1|0|0||0|Crushing Force|Boosts Combo base fTP by +0.35.|1|0|0||1|evolution|evo_stage_1|', nowFn)
State.handleProtoLine(stEvo, 'NODE|1|e_co_tempo|1|2|0|1|0|0||0|Fluid Tempo|Refunds 150 TP after Combo.|1|0|0||2|evolution|evo_stage_1|', nowFn)
State.handleProtoLine(stEvo, 'NODE|1|e_co_hits|2|1|0|1|0|1||0|Twin Impact|Adds a 4th strike at 50% potency.|15|0|0||3|evolution|evo_stage_2|', nowFn)
State.handleProtoLine(stEvo, 'NODE|1|e_co_focus|2|2|1|1|0|1||0|Chi Focus|Generates +25 Chi on hit.|15|0|0||4|evolution|evo_stage_2|', nowFn)
State.handleProtoLine(stEvo, 'NODE|1|e_co_open|3|1|0|1|1|2||0|Shatter Guard|Applies Defense Down on hit.|30|0|0||5|evolution|evo_stage_3|', nowFn)
State.handleProtoLine(stEvo, 'NODE|1|e_co_edge|3|2|0|1|1|2||0|Keen Edge|Increases crit damage by +20%.|30|0|0||6|evolution|evo_stage_3|', nowFn)
State.handleProtoLine(stEvo, 'NODE|1|e_co_break|4|1|0|1|0|3||0|Guard Break|Ignores 30% physical defense.|50|0|0||7|evolution|evo_stage_4|', nowFn)
State.handleProtoLine(stEvo, 'NODE|1|e_co_flow|4|2|0|1|0|3||0|Inner Flow|Reduces Chakra cooldown by 10s.|50|0|0||8|evolution|evo_stage_4|', nowFn)
State.handleProtoLine(stEvo, 'NODE|1|e_co_storm|5|1|0|1|0|4||0|Tempest Barrage|Capstone: Unleashes rapid flurry.|70|0|0||9|evolution|evo_stage_5|', nowFn)
State.handleProtoLine(stEvo, 'NODE|1|e_co_window|5|2|0|1|0|4||0|Transcendent Window|Capstone: Doubles Chi gain for 15s.|70|0|0||10|evolution|evo_stage_5|', nowFn)
State.handleProtoLine(stEvo, 'WS_END|1|8|1', nowFn)

local evoTree = stEvo.wsDetail
assertTrue(State.isEvolutionTree(evoTree), 'Combo tree detected as Evolution')
local excl, peer = State.isExcludedByPeer(evoTree, evoTree.nodes[2])
assertEq(excl, true, 'Stage 1 right peer is excluded by learned peer')
assertTrue(peer ~= nil and peer.key == 'e_co_force', 'Exclusive peer correctly identified')
local tipExcl = State.buildTooltipModel(stEvo, evoTree.nodes[2])
assertEq(tipExcl.excluded, true, 'Exclusive tooltip sets excluded=true')
assertEq(tipExcl.excludedBy, 'Crushing Force', 'Exclusive tooltip identifies peer Crushing Force')

-- ============================================================================
-- 5. Anti-Double-Click Pending Guard & Recovery
-- ============================================================================
fakeNow = 100.0
assertEq(State.isPending(st, nowFn), false, 'Initially not pending')
State.markPending(st, State.OP_INVEST, 84, 1, nowFn)
assertEq(State.isPending(st, nowFn), true, 'State is now pending')

-- WS_END clears pending
State.handleProtoLine(st, 'WS|84|Raging Rush|Great Axe|physical|4|Physical WS', nowFn)
State.handleProtoLine(st, 'WS_END|84|11|1', nowFn)
assertEq(State.isPending(st, nowFn), false, 'WS_END clears pending')
assertEq(st.statusKind, 'ok', 'WS_END after OP_INVEST sets ok status')

-- ERR clears pending & sets error toast
State.markPending(st, State.OP_INVEST, 84, 4, nowFn)
State.handleProtoLine(st, 'ERR|Not enough points in branch', nowFn)
assertEq(State.isPending(st, nowFn), false, 'ERR clears pending')
assertEq(st.statusKind, 'err', 'ERR sets err status')

-- Timeout auto-clears stuck pending op after 3.5s
fakeNow = 300.0
State.markPending(st, State.OP_INVEST, 84, 1, nowFn)
fakeNow = 301.0
assertEq(State.isPending(st, nowFn), true, 'Pending still active at 1s')
fakeNow = 304.0
assertEq(State.isPending(st, nowFn), false, 'Pending auto-clears after timeout')

-- ============================================================================
-- 6. Soul Switching State Invalidation
-- ============================================================================
assertEq(st.needsFullResync, false, 'No full resync needed before Soul switch')
State.handleProtoLine(st, 'META|DRG|75|15|0|15|8|0|Wyvernheart|wyvernheart|Pet', nowFn)
assertEq(st.needsFullResync, true, 'Switching Soul sets needsFullResync=true')
assertEq(st.selectedWsId, nil, 'Switching Soul clears stale selectedWsId')
assertEq(st.wsDetail, nil, 'Switching Soul clears stale wsDetail')

-- ============================================================================
-- 7. Headless ImGui Render Verification (Standard, Evolution, Compact 860x580)
-- ============================================================================
local drawCmdCount = 0
local mockDl = {
    AddRectFilled = function() drawCmdCount = drawCmdCount + 1 end,
    AddRectFilledMultiColor = function() drawCmdCount = drawCmdCount + 1 end,
    AddRect = function() drawCmdCount = drawCmdCount + 1 end,
    AddLine = function() drawCmdCount = drawCmdCount + 1 end,
    AddCircle = function() drawCmdCount = drawCmdCount + 1 end,
    AddCircleFilled = function() drawCmdCount = drawCmdCount + 1 end,
    AddQuad = function() drawCmdCount = drawCmdCount + 1 end,
    AddQuadFilled = function() drawCmdCount = drawCmdCount + 1 end,
    AddTriangle = function() drawCmdCount = drawCmdCount + 1 end,
    AddTriangleFilled = function() drawCmdCount = drawCmdCount + 1 end,
    AddText = function() drawCmdCount = drawCmdCount + 1 end,
    AddImage = function() drawCmdCount = drawCmdCount + 1 end,
}

local curX, curY = 20, 20
local availW, availH = 1060, 680
package.loaded['imgui'] = {
    SetNextWindowSizeConstraints = function() end,
    SetNextWindowSize = function() end,
    PushStyleVar = function() end,
    PopStyleVar = function() end,
    PushStyleColor = function() end,
    PopStyleColor = function() end,
    Begin = function() return true end,
    End = function() end,
    BeginChild = function(_, size)
        if type(size) == 'table' then
            availW = (size[1] and size[1] > 0) and size[1] or availW
            availH = (size[2] and size[2] > 0) and size[2] or availH
        end
        return true
    end,
    EndChild = function() end,
    GetWindowDrawList = function() return mockDl end,
    GetCursorScreenPos = function() return { curX, curY } end,
    SetCursorScreenPos = function(p) curX, curY = p[1], p[2] end,
    GetContentRegionAvail = function() return { availW, availH } end,
    InvisibleButton = function() return false end,
    IsItemHovered = function() return false end,
    IsItemClicked = function() return false end,
    IsMouseClicked = function() return false end,
    Button = function() return false end,
    SameLine = function() end,
    Dummy = function() end,
    TextUnformatted = function() drawCmdCount = drawCmdCount + 1 end,
    TextWrapped = function() drawCmdCount = drawCmdCount + 1 end,
    CalcTextSize = function(s) return { #(tostring(s or '')) * 7, 14 } end,
    BeginTooltip = function() end,
    EndTooltip = function() end,
    SetNextWindowBgAlpha = function() end,
    PushTextWrapPos = function() end,
    PopTextWrapPos = function() end,
    PushItemWidth = function() end,
    PopItemWidth = function() end,
    InputTextWithHint = function() return false end,
    InputText = function() return false end,
    Checkbox = function() return false end,
    PushID = function() end,
    PopID = function() end,
    Spacing = function() end,
    Separator = function() end,
    BeginGroup = function() end,
    EndGroup = function() end,
    GetWindowPos = function() return { 20, 20 } end,
    GetWindowSize = function() return { availW, availH } end,
    GetMousePos = function() return { 0, 0 } end,
    PushFont = function() end,
    PopFont = function() end,
}

local UI = require('talent_tree_ui')

-- Render standard tree (Berserker Raging Rush)
local stRender = State.newState()
stRender.open[1] = true
State.handleProtoLine(stRender, 'META|WAR|75|12|3|15|6|0|Berserker|berserker|Damage', nowFn)
State.handleProtoLine(stRender, 'SPENT_BEGIN', nowFn)
State.handleProtoLine(stRender, 'SPENT|84:4:1', nowFn)
State.handleProtoLine(stRender, 'SPENT_END', nowFn)
State.handleProtoLine(stRender, 'CAT_BEGIN', nowFn)
State.handleProtoLine(stRender, 'CAT|80:6:Iron Tempest:physical,84:6:Raging Rush:physical,64:5:Raging Axe:physical', nowFn)
State.handleProtoLine(stRender, 'CAT_END', nowFn)
feedSampleStandardTree(stRender, 84)
stRender.selectedWsId = 84

local actions = {
    requestSync = function() end,
    selectWs = function() end,
    invest = function() end,
    refund = function() end,
    resetWs = function() end,
    resetAll = function() end,
}

drawCmdCount = 0
local okStd, errStd = pcall(UI.render, stRender, actions)
assertTrue(okStd, 'UI.render succeeds on standard 3-branch tree: ' .. tostring(errStd))
assertTrue(drawCmdCount > 100, 'UI.render emits rich RPG draw commands (' .. tostring(drawCmdCount) .. ')')

-- Render Evolution tree
stEvo.open[1] = true
drawCmdCount = 0
availW, availH = 1060, 680
local okEvo, errEvo = pcall(UI.render, stEvo, actions)
assertTrue(okEvo, 'UI.render succeeds on Evolution tree: ' .. tostring(errEvo))
assertTrue(drawCmdCount > 80, 'UI.render emits Evolution draw commands (' .. tostring(drawCmdCount) .. ')')

-- Render Compact resolution (860x580)
drawCmdCount = 0
availW, availH = 860, 580
local okCmp, errCmp = pcall(UI.render, stRender, actions)
assertTrue(okCmp, 'UI.render succeeds on compact 860x580 resolution: ' .. tostring(errCmp))
assertTrue(drawCmdCount > 100, 'UI.render emits draw commands at 860x580 (' .. tostring(drawCmdCount) .. ')')

-- Summary
print(string.format('[WS_TALENT_ADDON_TESTS] passed=%d failed=%d', passed, failed))
if failed > 0 then
    os.exit(1)
end
