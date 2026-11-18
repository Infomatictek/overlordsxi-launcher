--[[
* OverlordsXI Soul HUD - bespoke mechanics per Soul.
*
* build(soulKey, kv, def, rt, role) -> { pips = {...}|nil, bar = {...}|nil }
*   pips = { label, cur, max, gem = 'gold|crimson|azure|emerald|violet', glow = bool }
*   bar  = { key, label, cur, max|nil(peak-tracked), countdown = bool, fmt = 'sec|num|frac|pct',
*            notches = n, warn = bool, idle = 'text' }
* `kv` is the parsed server 0x1FC key/value map (strings); `def`/`rt` are the optional registry
* definition + runtime state used for the generic fallback of Souls without a bespoke layout.
--]]

local M = {}

local ROLE_GEM = { tank = 'azure', healer = 'emerald', support = 'violet', damage = 'crimson' }

local function num(kv, key)
    return tonumber(kv and kv[key]) or 0
end

local function first(kv, ...)
    for i = 1, select('#', ...) do
        local v = tonumber(kv and kv[select(i, ...)])
        if v ~= nil then return v end
    end
    return 0
end

local function pips(label, cur, max, gem, glow)
    return { label = label, cur = math.max(0, math.min(max, math.floor(cur + 0.5))), max = max, gem = gem, glow = glow == true }
end

local function timerBar(key, label, remaining, idle)
    return { key = key, label = label, cur = remaining, countdown = true, fmt = 'sec', idle = idle or 'Idle' }
end

local BESPOKE = {
    spartan = function(kv)
        return {
            pips = pips('Grit', num(kv, 'grit'), 5, 'gold'),
            bar  = timerBar('ward', 'Phalanx Ward', num(kv, 'ward_rem')),
        }
    end,

    miragesentinel = function(kv)
        return {
            pips = pips('Finishing Moves', num(kv, 'fm'), 5, 'gold'),
            bar  = { key = 'aegis', label = 'Aegis Waltz', cur = num(kv, 'aegis_hp'), fmt = 'num', idle = 'No Shield' },
        }
    end,

    kagemusha = function(kv)
        return {
            pips = pips('Ash', num(kv, 'ash'), 4, 'violet'),
            bar  = timerBar('ash', 'Ash Fade', num(kv, 'ash_rem')),
        }
    end,

    animist = function(kv)
        return { pips = pips('Soulspark', first(kv, 'soulspark', 'cells'), 3, 'emerald') }
    end,

    gambler = function(kv)
        local debt = num(kv, 'debt_rem')
        local bar
        if debt > 0 then
            bar = { key = 'debt', label = 'HOUSE DEBT', cur = debt, max = 12, countdown = true, fmt = 'sec', warn = true }
        else
            local tot = num(kv, 'roll_tot')
            bar = {
                key = 'du', label = tot > 0 and ('Double-Up  ' .. math.floor(tot)) or 'Double-Up',
                cur = num(kv, 'du_rem'), max = 45, countdown = true, fmt = 'sec', idle = 'Idle',
                warn = num(kv, 'roll_lock') > 0,
            }
        end
        return { pips = pips('Rolls', num(kv, 'rolls'), 3, 'gold', num(kv, 'overdrive') > 0), bar = bar }
    end,

    spellblade = function(kv)
        return { pips = pips('Prep', first(kv, 'prep_stacks', 'prep'), 3, 'crimson') }
    end,

    chiweaver = function(kv)
        return { bar = { key = 'chi', label = 'Chi', cur = first(kv, 'chi_stacks', 'chi'), max = 100, fmt = 'frac', idle = '0/100' } }
    end,

    ronin = function(kv)
        local ticks = num(kv, 'stagger_ticks')
        return {
            pips = pips("Mind's Eye", num(kv, 'minds_eye'), 3, 'azure'),
            bar  = {
                key = 'stagger', label = ticks > 0 and ('Stagger  x' .. math.floor(ticks)) or 'Stagger',
                cur = num(kv, 'stagger_pool'), fmt = 'num', idle = 'Steady',
                notches = ticks > 1 and math.min(10, math.floor(ticks)) or 0,
            },
        }
    end,

    dreadnought = function(kv)
        local reap = num(kv, 'reap_rem')
        return {
            bar = {
                key = 'tithe', label = reap > 0 and ('Blood Tithe  Reap ' .. math.floor(reap) .. 's') or 'Blood Tithe',
                cur = num(kv, 'tithe'), max = 3, fmt = 'frac', notches = 3, idle = '0/3',
            },
        }
    end,

    wyvernheart = function(kv)
        local rem = num(kv, 'wyrmscale_rem')
        return {
            bar = {
                key = 'wyrm', label = rem > 0 and ('Wyrmscale  ' .. math.floor(rem) .. 's') or 'Wyrmscale',
                cur = num(kv, 'wyrmscale'), max = 3, fmt = 'frac', notches = 3, idle = '0/3',
            },
        }
    end,

    buccaneer = function(kv)
        return {
            pips = pips('Grapeshot', num(kv, 'grapeshot'), 3, 'crimson'),
            bar  = { key = 'salt', label = 'Salt Spray', cur = num(kv, 'saltspray'), fmt = 'num', idle = 'No Shield' },
        }
    end,

    magus = function(kv)
        return {
            pips = pips('Catalyst', first(kv, 'catalyst', 'catalyst_stacks'), 5, 'azure'),
            bar  = timerBar('conduit', 'Osmotic Conduit', num(kv, 'conduit_rem')),
        }
    end,

    azurebastion = function(kv)
        return {
            pips = pips('Carapace', first(kv, 'carapace', 'chitin_stacks'), 5, 'azure'),
            bar  = timerBar('shell', 'Diamond Shell', num(kv, 'shell_rem')),
        }
    end,
}

-- Generic fallback driven by the registry runtime (flintlock, future Souls) or demo synth values.
local function generic(kv, def, rt, role)
    local gem = ROLE_GEM[role] or 'gold'
    local out = {}

    if kv and kv.demo_pips ~= nil then
        out.pips = pips('Charge', num(kv, 'demo_pips'), 3, gem)
        out.bar = { key = 'demo', label = 'Resonance', cur = num(kv, 'demo_bar'), max = 1, fmt = 'pct', idle = '0%' }
        return out
    end

    if def and rt and rt.values then
        for _, res in ipairs(def.resources or {}) do
            local st = rt.values[res.id]
            if st then
                if out.pips == nil and (res.type == 'stack' or res.type == 'charges') and (res.max or 0) > 0 and (res.max or 0) <= 6 then
                    local cur = res.type == 'charges' and (st.charges or st.current or 0) or (st.current or 0)
                    out.pips = pips(res.shortLabel or res.label, cur, math.floor(res.max), gem)
                elseif out.bar == nil and res.type == 'gauge' then
                    out.bar = { key = res.id, label = res.label, cur = st.current or 0, max = math.max(1, res.max or 1), fmt = 'frac', idle = '0' }
                elseif out.bar == nil and (res.type == 'timer') then
                    out.bar = {
                        key = res.id, label = res.label, cur = st.remaining or 0, max = math.max(1, st.duration or res.duration or 1),
                        fmt = 'sec', idle = 'Idle',
                    }
                end
            end
        end
    end
    return out
end

function M.build(soulKey, kv, def, rt, role)
    kv = kv or {}
    local fn = BESPOKE[soulKey]
    if fn then
        local ok, res = pcall(fn, kv)
        if ok and type(res) == 'table' then return res end
    end
    return generic(kv, def, rt, role)
end

function M.hasBespoke(soulKey)
    return BESPOKE[soulKey] ~= nil
end

M.ROLE_GEM = ROLE_GEM

return M
