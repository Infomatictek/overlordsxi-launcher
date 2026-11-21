-- SoulspireXI WS Talent State Machine & Protocol Parser (Pure Lua, Headless-Testable)
--
-- Responsibilities:
--   - Authoritative server protocol parsing (META, SPENT, CAT, WS, NODE, WS_END, ERR)
--   - Active-Soul weapon family grouping (Primary vs Signature Secondary; zero ineligible weapons)
--   - Anti-double-click pending-action guard (never fabricates permanent state)
--   - Soul-switch invalidation & clean resync detection
--   - Prerequisite connection graph & mutually exclusive peer resolution
--   - Player-facing tooltip model (strips internal IDs; shows current + next rank)
local meta = require('ws_client_meta')

local S = {}

S.OP_SYNC      = 1
S.OP_STATE     = 2
S.OP_WS        = 3
S.OP_INVEST    = 4
S.OP_REFUND    = 5
S.OP_CYCLE_SC  = 6
S.OP_RESET_WS  = 7
S.OP_RESET_ALL = 8

S.MAX_WS_POINTS = 56
S.MAX_MASTERED_WS = 4
S.PENDING_TIMEOUT_SEC = 1.5

local function splitPipe(str)
    local out = {}
    local start = 1
    while true do
        local pos = string.find(str, '|', start, true)
        if not pos then
            out[#out + 1] = string.sub(str, start)
            break
        end
        out[#out + 1] = string.sub(str, start, pos - 1)
        start = pos + 1
    end
    return out
end

-- Sanitize any internal tokens from player-facing text
function S.cleanPlayerText(text)
    local s = tostring(text or '')
    s = s:gsub('OX_[%w_]+', '')
    s = s:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return s
end

function S.newState()
    return {
        open             = { false },
        synced           = false,
        syncRequestedAt  = 0,
        jobKey           = '---',
        jobLevel         = 1,
        specName         = 'Base',
        soulKey          = nil,
        soulMeta         = nil,
        role             = 'Damage',
        avail            = 0,
        spent            = 0,
        earned           = 3,
        mainSkill        = 0,
        rangedSkill      = 0,
        catalog          = {},
        catalogById      = {},
        weaponGroups     = {},
        tempCatalog      = nil,
        spentByWs        = {},
        unlockedByWs     = {},
        tempSpent        = nil,
        tempUnlocked     = nil,
        selectedWsId     = nil,
        wsDetail         = nil,
        tempWs           = nil,
        searchBuf        = { '' },
        investedOnly     = { false },
        confirmResetWs   = false,
        confirmResetWsAt = 0,
        confirmResetAll  = false,
        confirmResetAt   = 0,
        statusText       = nil,
        statusKind       = 'info', -- 'info' | 'ok' | 'err' | 'pending'
        statusTime       = 0,
        pendingOp        = nil,    -- { op, wsId, slot, at }
        lastKnownJob     = nil,
        lastKnownLvl     = nil,
        lastAutoCheck    = 0,
        needsFullResync  = false,
        needsWsRequest   = nil,
        uiFont           = nil,
        renderError      = nil,
    }
end

function S.setStatus(st, msg, kind, nowFn)
    st.statusText = S.cleanPlayerText(msg)
    st.statusKind = kind or 'info'
    st.statusTime = (nowFn and nowFn()) or os.clock()
end

function S.isPending(st, nowFn)
    if st.pendingOp == nil then return false end
    local now = (nowFn and nowFn()) or os.clock()
    if (now - (st.pendingOp.at or 0)) >= S.PENDING_TIMEOUT_SEC then
        st.pendingOp = nil
        return false
    end
    return true
end

function S.markPending(st, op, wsId, slot, nowFn)
    st.pendingOp = {
        op   = op,
        wsId = wsId,
        slot = slot,
        at   = (nowFn and nowFn()) or os.clock(),
    }
end

function S.clearPending(st)
    st.pendingOp = nil
end

function S.countInvestedWs(st)
    local n = 0
    for _, pts in pairs(st.spentByWs or {}) do
        if (pts or 0) > 0 then n = n + 1 end
    end
    return n
end

-- Build grouped eligible weapon families strictly for the active Soul
function S.rebuildWeaponGroups(st)
    local groups = {}
    local bySkill = {}
    local sm = st.soulMeta

    local primarySet = {}
    local secondarySet = {}
    local orderedSkills = {}

    if sm then
        for _, sid in ipairs(sm.primary or {}) do
            if not primarySet[sid] then
                primarySet[sid] = true
                orderedSkills[#orderedSkills + 1] = { id = sid, tier = 'Primary' }
            end
        end
        for _, sid in ipairs(sm.secondary or {}) do
            if not primarySet[sid] and not secondarySet[sid] then
                secondarySet[sid] = true
                orderedSkills[#orderedSkills + 1] = { id = sid, tier = 'Signature' }
            end
        end
    end

    -- Filter catalog strictly to approved skills when Soul metadata is known
    for _, ws in ipairs(st.catalog or {}) do
        local allowed = (sm == nil) or primarySet[ws.skill] or secondarySet[ws.skill]
        if allowed then
            local bucket = bySkill[ws.skill]
            if bucket == nil then
                bucket = {}
                bySkill[ws.skill] = bucket
                if sm == nil then
                    orderedSkills[#orderedSkills + 1] = { id = ws.skill, tier = 'Eligible' }
                end
            end
            bucket[#bucket + 1] = ws
        end
    end

    for _, sk in ipairs(orderedSkills) do
        local list = bySkill[sk.id]
        if list and #list > 0 then
            groups[#groups + 1] = {
                skillId   = sk.id,
                skillName = meta.SKILL_NAMES[sk.id] or ('Weapon ' .. tostring(sk.id)),
                tierLabel = sk.tier,
                weapons   = list,
            }
        end
    end

    st.weaponGroups = groups
    return groups
end

function S.pickDefaultWsId(st)
    -- 1. Keep current selection if still eligible in current catalog
    if st.selectedWsId ~= nil then
        for _, grp in ipairs(st.weaponGroups or {}) do
            for _, ws in ipairs(grp.weapons) do
                if ws.id == st.selectedWsId then return ws.id end
            end
        end
    end
    -- 2. Prefer equipped main or ranged weapon skill
    for _, grp in ipairs(st.weaponGroups or {}) do
        if grp.skillId == st.mainSkill or grp.skillId == st.rangedSkill then
            if grp.weapons[1] then return grp.weapons[1].id end
        end
    end
    -- 3. Fallback to first Primary eligible WS
    if st.weaponGroups[1] and st.weaponGroups[1].weapons[1] then
        return st.weaponGroups[1].weapons[1].id
    end
    return nil
end

function S.isEvolutionTree(detail)
    if not detail or not detail.nodes then return false end
    for _, n in ipairs(detail.nodes) do
        if n.branch == 'evolution' or (detail.id == 1 and tostring(n.key):match('^e_co_')) or (detail.id == 47 and tostring(n.key):match('^e_sg_')) then
            return true
        end
    end
    return false
end

function S.isExcludedByPeer(detail, node)
    if not detail or not node or not node.exclusiveGroup or node.exclusiveGroup == '' then
        return false, nil
    end
    for _, other in ipairs(detail.nodes or {}) do
        if other.key ~= node.key and other.exclusiveGroup == node.exclusiveGroup and (other.rank or 0) > 0 then
            return true, other
        end
    end
    return false, nil
end

-- Build ONLY genuine progression connections (explicit reqKey or vertical tier link in same branch)
function S.buildConnections(detail)
    local edges = {}
    if not detail or not detail.nodes then return edges end
    local byKey = detail.byKey or {}
    local byBranchTier = {}
    for _, n in ipairs(detail.nodes) do
        if (n.scTier or 0) == 0 then
            local br = n.branch or 'damage'
            byBranchTier[br] = byBranchTier[br] or {}
            byBranchTier[br][n.tier or 1] = n
        end
    end

    for _, n in ipairs(detail.nodes) do
        if (n.scTier or 0) == 0 then
            if n.reqKey and byKey[n.reqKey] then
                edges[#edges + 1] = { from = byKey[n.reqKey], to = n, kind = 'prereq' }
            elseif not S.isEvolutionTree(detail) and (n.tier or 1) > 1 then
                local prev = byBranchTier[n.branch or 'damage'] and byBranchTier[n.branch or 'damage'][(n.tier or 1) - 1]
                if prev then
                    edges[#edges + 1] = { from = prev, to = n, kind = 'tier' }
                end
            end
        end
    end
    return edges
end

-- Player-facing tooltip data derived strictly from server NODE metadata & Soul metadata
function S.buildTooltipModel(st, node)
    local detail = st.wsDetail
    local excluded, exclPeer = S.isExcludedByPeer(detail, node)
    local branch = node.branch or 'damage'
    local branchLabel = (branch == 'damage' and 'Damage Branch')
        or (branch == 'utility' and 'Utility Branch')
        or (branch == 'soul' and ('Soul Branch · ' .. (st.soulMeta and st.soulMeta.name or st.specName)))
        or (branch == 'evolution' and ('Evolution Stage ' .. tostring(node.tier or 1)))
        or 'Skillchain Augment'

    local prereqs = {}
    if (node.reqLevel or 1) > 1 then
        prereqs[#prereqs + 1] = {
            text = string.format('Requires Level %d %s', node.reqLevel, st.jobKey),
            met  = (st.jobLevel or 1) >= node.reqLevel,
        }
    end
    if (node.reqWsPoints or 0) > 0 then
        local spent = (detail and detail.spent) or 0
        prereqs[#prereqs + 1] = {
            text = string.format('Requires %d pts in %s (%d/%d)', node.reqWsPoints, detail and detail.name or 'WS', spent, node.reqWsPoints),
            met  = spent >= node.reqWsPoints,
        }
    end
    if node.reqKey and detail and detail.byKey and detail.byKey[node.reqKey] then
        local pn = detail.byKey[node.reqKey]
        local reqR = math.max(1, node.reqRank or 1)
        prereqs[#prereqs + 1] = {
            text = string.format('Requires %s (Rank %d/%d)', pn.name, pn.rank or 0, reqR),
            met  = (pn.rank or 0) >= reqR,
        }
    end

    local statusLabel = 'Locked'
    if (node.rank or 0) >= (node.maxRank or 1) and (node.maxRank or 1) > 0 then
        statusLabel = 'Mastered'
    elseif (node.rank or 0) > 0 then
        statusLabel = 'Learned'
    elseif excluded then
        statusLabel = 'Mutually Exclusive'
    elseif node.canLearn then
        statusLabel = 'Available'
    end

    return {
        name          = S.cleanPlayerText(node.name),
        branch        = branch,
        branchLabel   = branchLabel,
        tier          = node.tier or 1,
        rank          = node.rank or 0,
        maxRank       = node.maxRank or 1,
        statusLabel   = statusLabel,
        currentEffect = S.cleanPlayerText(node.desc),
        nextEffect    = S.cleanPlayerText(node.nextDesc or ''),
        prereqs       = prereqs,
        excluded      = excluded,
        excludedBy    = exclPeer and exclPeer.name or nil,
        canLearn      = node.canLearn and not excluded,
        canRefund     = (node.rank or 0) > 0,
        soulMechanic  = (branch == 'soul' and st.soulMeta) and st.soulMeta.mechanic or nil,
    }
end

-- Parse a single [OXTAL]| protocol line from the server
function S.handleProtoLine(st, payload, nowFn)
    local parts = splitPipe(payload)
    local kind = parts[1]

    if kind == 'META' then
        local prevJob  = st.jobKey
        local prevSpec = st.specName
        local prevSoul = st.soulKey

        st.jobKey      = parts[2] or '---'
        st.jobLevel    = tonumber(parts[3]) or 1
        st.avail       = tonumber(parts[4]) or 0
        st.spent       = tonumber(parts[5]) or 0
        st.earned      = tonumber(parts[6]) or 3
        st.mainSkill   = tonumber(parts[7]) or 0
        st.rangedSkill = tonumber(parts[8]) or 0
        st.specName    = (parts[9] and parts[9] ~= '') and parts[9] or 'Base'
        local sk, sm = meta.resolveSoul(parts[10], st.specName)
        st.soulKey     = sk
        st.soulMeta    = sm
        st.role        = (parts[11] and parts[11] ~= '') and parts[11] or (sm and sm.role) or 'Damage'

        -- Soul or Job switched: invalidate stale WS tree & request authoritative catalog resync
        if prevJob ~= '---' and (prevJob ~= st.jobKey or prevSpec ~= st.specName or prevSoul ~= st.soulKey) then
            st.wsDetail = nil
            st.selectedWsId = nil
            st.needsFullResync = true
            S.clearPending(st)
        end

    elseif kind == 'SPENT_BEGIN' then
        st.tempSpent    = {}
        st.tempUnlocked = {}

    elseif kind == 'SPENT' then
        st.tempSpent    = st.tempSpent or {}
        st.tempUnlocked = st.tempUnlocked or {}
        if parts[2] and parts[2] ~= '' then
            for entry in string.gmatch(parts[2], '([^,]+)') do
                local wsId, pts, unl = string.match(entry, '^(%d+):(%d+):(%d+)$')
                if not wsId then
                    wsId, pts = string.match(entry, '^(%d+):(%d+)$')
                    unl = (tonumber(pts) or 0) > 0 and '1' or '0'
                end
                if wsId and pts then
                    local idNum = tonumber(wsId)
                    st.tempSpent[idNum]    = tonumber(pts)
                    st.tempUnlocked[idNum] = (tonumber(unl) or 0) == 1
                end
            end
        end

    elseif kind == 'SPENT_END' then
        if st.tempSpent ~= nil then
            st.spentByWs    = st.tempSpent
            st.unlockedByWs = st.tempUnlocked or {}
            st.tempSpent    = nil
            st.tempUnlocked = nil
        end

    elseif kind == 'CAT_BEGIN' then
        st.tempCatalog = {}

    elseif kind == 'CAT' then
        st.tempCatalog = st.tempCatalog or {}
        if parts[2] and parts[2] ~= '' then
            for entry in string.gmatch(parts[2], '([^,]+)') do
                local wsId, skillId, name, wsType = string.match(entry, '^(%d+):(%d+):(.+):([^:]+)$')
                if wsId then
                    st.tempCatalog[#st.tempCatalog + 1] = {
                        id     = tonumber(wsId),
                        skill  = tonumber(skillId),
                        name   = name,
                        wsType = wsType,
                    }
                end
            end
        end

    elseif kind == 'CAT_END' then
        if st.tempCatalog ~= nil then
            st.catalog = st.tempCatalog
            st.catalogById = {}
            for _, ws in ipairs(st.catalog) do
                st.catalogById[ws.id] = ws
            end
            st.tempCatalog = nil
            st.synced = true
            st.needsFullResync = false
            S.rebuildWeaponGroups(st)
            local pick = S.pickDefaultWsId(st)
            if pick ~= nil and (st.wsDetail == nil or st.wsDetail.id ~= pick) then
                st.selectedWsId = pick
                st.needsWsRequest = pick
            end
        end

    elseif kind == 'WS' then
        st.tempWs = {
            id        = tonumber(parts[2]),
            name      = parts[3] or 'Unknown',
            skillName = parts[4] or '',
            wsType    = parts[5] or 'physical',
            spent     = tonumber(parts[6]) or 0,
            summary   = parts[7] or '',
            nodes     = {},
            byKey     = {},
        }

    elseif kind == 'NODES' then
        local body = string.sub(payload, 7)
        local startPos = 1
        while startPos <= #body do
            local sepStart, sepEnd = string.find(body, ';;', startPos, true)
            local entry
            if sepStart then
                entry = string.sub(body, startPos, sepStart - 1)
                startPos = sepEnd + 1
            else
                entry = string.sub(body, startPos)
                startPos = #body + 1
            end
            if entry ~= '' then
                S.handleProtoLine(st, 'NODE|' .. entry, nowFn)
            end
        end

    elseif kind == 'NODE' then
        if st.tempWs ~= nil and tonumber(parts[2]) == st.tempWs.id then
            local nodeIdx = #st.tempWs.nodes + 1
            local col = tonumber(parts[5]) or 1
            local scTier = tonumber(parts[15]) or 0
            local slot = tonumber(parts[18]) or nodeIdx
            local branch = (parts[19] and parts[19] ~= '') and parts[19]
                or (scTier > 0 and 'skillchain')
                or (col == 2 and 'utility' or (col == 3 and 'soul' or 'damage'))
            local exclGroup = (parts[20] and parts[20] ~= '') and parts[20] or nil
            -- Backwards compatibility: infer exclusive group on evolution nodes for older servers
            if exclGroup == nil and ((st.tempWs.id == 1 and tostring(parts[3]):match('^e_co_')) or (st.tempWs.id == 47 and tostring(parts[3]):match('^e_sg_'))) then
                branch = 'evolution'
                exclGroup = 'evo_stage_' .. tostring(tonumber(parts[4]) or 1)
            end
            local nextDesc = (parts[21] and parts[21] ~= '') and parts[21] or ''

            local node = {
                idx            = nodeIdx,
                slot           = slot,
                key            = parts[3],
                tier           = tonumber(parts[4]) or 1,
                col            = col,
                rank           = tonumber(parts[6]) or 0,
                maxRank        = tonumber(parts[7]) or 1,
                canLearn       = (tonumber(parts[8]) or 0) == 1,
                reqWsPoints    = tonumber(parts[9]) or 0,
                reqKey         = (parts[10] and parts[10] ~= '') and parts[10] or nil,
                reqRank        = tonumber(parts[11]) or 0,
                name           = parts[12] or parts[3],
                desc           = parts[13] or '',
                reqLevel       = tonumber(parts[14]) or 1,
                scTier         = scTier,
                scId           = tonumber(parts[16]) or 0,
                scName         = parts[17] or '',
                branch         = branch,
                exclusiveGroup = exclGroup,
                nextDesc       = nextDesc,
            }
            st.tempWs.nodes[nodeIdx] = node
            st.tempWs.byKey[node.key] = node
        end

    elseif kind == 'WS_END' then
        if st.tempWs ~= nil and tonumber(parts[2]) == st.tempWs.id then
            st.avail = tonumber(parts[3]) or st.avail
            st.spentByWs[st.tempWs.id] = st.tempWs.spent or 0
            if parts[4] ~= nil then
                st.unlockedByWs[st.tempWs.id] = (tonumber(parts[4]) or 0) == 1
            else
                st.unlockedByWs[st.tempWs.id] = (st.tempWs.spent or 0) > 0
            end
            st.wsDetail = st.tempWs
            st.tempWs = nil
            if st.pendingOp ~= nil then
                local pop = st.pendingOp.op
                S.clearPending(st)
                if pop == S.OP_INVEST then
                    S.setStatus(st, 'Talent point invested.', 'ok', nowFn)
                elseif pop == S.OP_REFUND then
                    S.setStatus(st, 'Talent point refunded.', 'ok', nowFn)
                elseif pop == S.OP_RESET_WS then
                    S.setStatus(st, 'Weapon skill talents reset.', 'ok', nowFn)
                elseif pop == S.OP_RESET_ALL then
                    S.setStatus(st, 'All Soul talents reset.', 'ok', nowFn)
                end
            end
        end

    elseif kind == 'ERR' then
        S.clearPending(st)
        S.setStatus(st, parts[2] or 'Action rejected by server.', 'err', nowFn)
    end
end

return S
