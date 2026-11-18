--[[
* OverlordsXI Soul HUD - live preview ("demo") mode.
*
*   /soulhud demo <soulKey>   animate one Soul's medallion, pips, gauge bar and status icons
*   /soulhud demo cycle       step through every Soul (every CYCLE_SEC seconds)
*   /soulhud demo off
*
* Produces synthetic server kv maps + an `ox_buffs` string so the real renderer is exercised
* without any server data or combat.
--]]

local okCat, catalog = pcall(require, 'status_catalog')
if not okCat or type(catalog) ~= 'table' then catalog = { list = {}, byIconId = {}, byEffectId = {} } end

local M = {}

local CYCLE_SEC = 7

local state = { key = nil, cycle = false, cycleIdx = 0, cycleAt = 0, buffsKey = nil, buffsAt = 0 }

local function step(t, rate, count)
    return math.floor(t * rate) % count
end

local function wave(t, speed)
    return 0.5 + 0.5 * math.sin(t * speed)
end

local KV = {
    spartan        = function(t) return { grit = step(t, 0.7, 6), ward_rem = 18 - (t % 18) } end,
    miragesentinel = function(t) return { fm = step(t, 0.7, 6), aegis_hp = 900 * wave(t, 0.8) } end,
    kagemusha      = function(t) return { ash = step(t, 0.7, 5), ash_rem = 30 - (t % 30) } end,
    animist        = function(t) return { soulspark = step(t, 0.7, 4) } end,
    gambler        = function(t)
        local c = t % 24
        return {
            rolls = step(t, 0.5, 4), overdrive = (step(t, 0.25, 2) == 0) and 1 or 0,
            du_rem = 45 - (t * 3) % 45, roll_tot = 7 + step(t, 0.3, 5),
            debt_rem = c > 19 and (24 - c) or 0,
        }
    end,
    spellblade     = function(t) return { prep_stacks = step(t, 0.6, 4) } end,
    chiweaver      = function(t) return { chi_stacks = (t * 12) % 101 } end,
    ronin          = function(t) return { stagger_pool = 4200 * wave(t, 0.7), stagger_ticks = 1 + step(t, 1, 6), minds_eye = step(t, 0.5, 4) } end,
    dreadnought    = function(t) return { tithe = step(t, 0.6, 4), reap_rem = 12 - (t % 12) } end,
    wyvernheart    = function(t) return { wyrmscale = step(t, 0.6, 4), wyrmscale_rem = 30 - (t % 30) } end,
    buccaneer      = function(t) return { grapeshot = step(t, 0.7, 4), saltspray = 650 * wave(t, 0.9) } end,
    magus          = function(t) return { catalyst = step(t, 0.7, 6), conduit_rem = 20 - (t % 20) } end,
    azurebastion   = function(t) return { carapace = step(t, 0.7, 6), shell_rem = 15 - (t % 15) } end,
}

function M.active()
    return state.key ~= nil or state.cycle
end

function M.key()
    return state.key
end

-- arg: soulKey | 'cycle' | 'off' ; returns ok, message
function M.set(arg, roster)
    arg = string.lower(tostring(arg or ''))
    if arg == '' or arg == 'off' then
        state.key, state.cycle, state.buffsKey = nil, false, nil
        return true, 'Demo mode off.'
    elseif arg == 'cycle' then
        state.cycle, state.cycleIdx, state.cycleAt, state.buffsKey = true, 0, 0, nil
        state.key = nil
        return true, ('Demo cycling through %d Souls (%ds each). /soulhud demo off to stop.'):format(#roster.list, CYCLE_SEC)
    elseif roster.known(arg) then
        state.key, state.cycle, state.buffsKey = arg, false, nil
        return true, 'Demo soul: ' .. arg .. '. Drag to position, /soulhud scale <0.75-2.0>, /soulhud demo off to stop.'
    end
    return false, 'Unknown soul key: ' .. arg
end

-- Returns the soul key being demoed (advancing the cycle) or nil.
function M.tick(now, roster)
    if state.cycle then
        if state.cycleAt == 0 or (now - state.cycleAt) >= CYCLE_SEC then
            state.cycleIdx = state.cycleIdx % #roster.list + 1
            state.cycleAt = now
            state.buffsKey = nil
        end
        return roster.list[state.cycleIdx].key
    end
    return state.key
end

function M.kv(key, now)
    local fn = KV[key]
    if fn then
        local kv = {}
        for k, v in pairs(fn(now)) do kv[k] = tostring(v) end
        return kv
    end
    return { demo_pips = tostring(step(now, 0.7, 4)), demo_bar = tostring((now * 0.12) % 1) }
end

-- Synthesizes registry runtime values (stack/gauge/timer) for registered Souls without a bespoke layout.
function M.fillRuntime(def, rt, now)
    if not def or not rt or not rt.values then return end
    for i, res in ipairs(def.resources or {}) do
        local st = rt.values[res.id]
        if st then
            local mx = math.max(1, res.max or res.maxCharges or 1)
            if res.type == 'stack' or res.type == 'charges' or res.type == 'counter' then
                st.current = step(now + i, 0.7, mx + 1)
                st.charges = st.current
                st.active = st.current > 0
            elseif res.type == 'gauge' then
                st.current = (res.min or 0) + wave(now + i, 0.9) * mx
            elseif res.type == 'timer' or res.type == 'cooldown' then
                local dur = math.max(5, math.min(30, res.duration or 20))
                st.duration = dur
                st.remaining = dur - ((now + i * 3) % dur)
                st.active = true
            end
        end
    end
end

-- Returns an `ox_buffs` string when the demo buffs need (re)seeding, else nil.
function M.buffs(key, now)
    if state.buffsKey == key and (now - state.buffsAt) < 18 then return nil end
    state.buffsKey, state.buffsAt = key, now

    local picked, seen = {}, {}
    for _, e in ipairs(catalog.list or {}) do
        if e.soulKey == key and not seen[e.iconId] then
            picked[#picked + 1], seen[e.iconId] = e, true
        end
    end
    for _, e in ipairs(catalog.list or {}) do
        if #picked >= 4 then break end
        if not seen[e.iconId] and not e.isDebuff then
            picked[#picked + 1], seen[e.iconId] = e, true
        end
    end

    local parts = {}
    for i, e in ipairs(picked) do
        if i > 8 then break end
        local power = (i % 3 == 0) and 3 or ((i % 2 == 0) and 15 or 0)
        parts[#parts + 1] = ('%d:%d:%d'):format(e.iconId, power, 14 + i * 6)
    end
    return table.concat(parts, ',')
end

return M
