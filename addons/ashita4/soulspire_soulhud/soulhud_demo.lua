--[[
* SoulspireXI Soul HUD - live preview ("demo") mode.
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
    -- 1. WAR: commander, berserker, spartan (gladiator)
    commander      = function(t)
        return {
            stance      = 1 + step(t, 0.25, 5),
            stance_rem  = 180 - ((t * 4) % 180),
            warcry_rem  = 30 - (t % 30),
            bulwark_rem = 15 - (t % 15),
            cadence_rem = 12 - (t % 12),
            regroup_rem = 0,
            breach_rem  = (step(t, 0.3, 2) == 0) and (10 - (t % 10)) or 0,
            orders      = 1 + step(t, 0.6, 4),
        }
    end,
    berserker      = function(t)
        return {
            berserk_rem   = 120 - ((t * 3) % 120),
            aggressor_rem = 90 - ((t * 2) % 90),
            surge_rem     = (step(t, 0.35, 2) == 0) and (10 - (t % 10)) or 0,
            bloodrage_rem = 30 - (t % 30),
            warcry_rem    = 25 - (t % 25),
            retal_rem     = 60 - (t % 60),
            fury          = 1 + step(t, 0.6, 4),
        }
    end,
    spartan        = function(t)
        return {
            grit     = step(t, 0.7, 6),
            brace    = step(t, 0.3, 3),
            ward_rem = 12 - (t % 12),
        }
    end,

    -- 2. MNK: sensei, blackbelt, chiweaver
    sensei         = function(t)
        return {
            staff        = 1,
            counter_rem  = 180 - ((t * 3) % 180),
            dodge_rem    = 30 - (t % 30),
            focus_rem    = 30 - ((t * 1.2) % 30),
            pcounter_rem = (step(t, 0.3, 2) == 0) and (15 - (t % 15)) or 0,
            inner_rem    = 0,
            stances      = 1 + step(t, 0.5, 4),
        }
    end,
    blackbelt      = function(t)
        return {
            focus_rem    = 30 - (t % 30),
            footwork_rem = 60 - ((t * 2) % 60),
            boost_rem    = 15 - (t % 15),
            dodge_rem    = 25 - (t % 25),
            hf_rem       = (step(t, 0.25, 2) == 0) and (45 - ((t * 2) % 45)) or 0,
            stances      = 1 + step(t, 0.6, 4),
        }
    end,
    chiweaver      = function(t)
        return {
            chi_stacks  = math.floor((t * 12) % 101),
            harmony_rem = (step(t, 0.3, 2) == 0) and (15 - (t % 15)) or 0,
            lotus_rem   = 12 - (t % 12),
        }
    end,

    -- 3. WHM: bishop
    bishop         = function(t)
        return {
            grace     = step(t, 0.6, 4),
            grace_rem = 30 - (t % 30),
            solace    = 1,
            veil_rem  = (step(t, 0.3, 2) == 0) and (15 - (t % 15)) or 0,
            ward_rem  = 8 - (t % 8),
        }
    end,

    -- 4. BLM: necromancer
    necromancer    = function(t)
        local isTank = (step(t, 0.2, 2) == 0)
        return {
            thrall_mode = isTank and 'dullahan' or 'corse',
            thrall_role = isTank and 'tank' or 'caster',
            thrall_hpp  = math.floor(35 + 65 * wave(t, 0.7)),
            dark_pact   = step(t, 0.4, 2),
        }
    end,

    -- 5. RDM: crimsonduelist
    crimsonduelist = function(t)
        return {
            hexes      = step(t, 0.7, 6),
            fencer     = 1,
            flow_rem   = (step(t, 0.35, 2) == 0) and (6 - (t % 6)) or 0,
            fleche_rem = 6 - (t % 6),
            stoneskin  = math.floor(450 * wave(t, 0.8)),
        }
    end,

    -- 6. PLD: aegistemplar (defender), templar
    aegistemplar   = function(t)
        return {
            zeal       = step(t, 0.7, 6),
            zeal_rem   = 30 - (t % 30),
            consec_rem = (step(t, 0.3, 2) == 0) and (15 - (t % 15)) or 0,
            retrib_rem = 8 - (t % 8),
        }
    end,
    templar        = function(t)
        return {
            majesty   = 1,
            shield    = 1,
            aegis_rem = (step(t, 0.3, 2) == 0) and (15 - (t % 15)) or 0,
            grace_rem = 10 - (t % 10),
            dseal_rem = 30 - (t % 30),
        }
    end,

    -- 7. DRK: dreadnought
    dreadnought    = function(t)
        return {
            tithe        = step(t, 0.6, 4),
            tithe_rem    = 30 - (t % 30),
            reap_rem     = 12 - (t % 12),
            bastion_rem  = (step(t, 0.25, 2) == 0) and (15 - (t % 15)) or 0,
            carapace_rem = 0,
            spikes_hp    = 0,
        }
    end,

    -- 8. BST: alphawarden
    alphawarden    = function(t)
        local hpp = math.floor(25 + 75 * wave(t, 0.65))
        return {
            beast_idx = 1 + step(t, 0.2, 4),
            pet_alive = 1,
            pet_hpp   = hpp,
            soullink  = (hpp >= 15) and 1 or 0,
            bond_rem  = 30 - (t % 30),
        }
    end,

    -- 9. BRD: adventurer, musician, minstrel
    adventurer     = function(t)
        return {
            cadence     = step(t, 0.7, 6),
            cadence_rem = 20 - (t % 20),
            encore_rem  = (step(t, 0.3, 2) == 0) and (12 - (t % 12)) or 0,
            songs       = 2 + step(t, 0.4, 3),
        }
    end,
    musician       = function(t)
        return {
            resonance     = step(t, 0.6, 4),
            resonance_rem = 30 - (t % 30),
            overdrive_rem = (step(t, 0.3, 2) == 0) and (15 - (t % 15)) or 0,
            songs         = 3 + step(t, 0.3, 2),
        }
    end,
    minstrel       = function(t)
        return {
            minne         = 1,
            paeon         = 1,
            scherzo       = step(t, 0.35, 2),
            iron_aria_rem = 15 - (t % 15),
        }
    end,

    -- 10. RNG: huntsman
    huntsman       = function(t)
        return {
            pet_id        = 1 + step(t, 0.2, 4),
            pet_hpp       = math.floor(40 + 60 * wave(t, 0.65)),
            sharpshot_rem = 30 - (t % 30),
            barrage_rem   = 15 - (t % 15),
            unlimited     = 1,
        }
    end,

    -- 11. SAM: ronin, imperialarcher, warlord
    ronin          = function(t)
        return {
            stagger_pool  = math.floor(4200 * wave(t, 0.7)),
            stagger_ticks = 1 + step(t, 1, 6),
            minds_eye     = step(t, 0.5, 4),
            seigan        = 1,
        }
    end,
    imperialarcher = function(t)
        return {
            oisoya_rem = 15 - (t % 15),
            cosmic_rem = (step(t, 0.35, 2) == 0) and (15 - ((t * 1.2) % 15)) or 0,
            hasso_rem  = 180 - ((t * 3) % 180),
        }
    end,
    warlord        = function(t)
        return {
            ashura     = step(t, 0.6, 4),
            ashura_rem = 20 - (t % 20),
            noto_rem   = (step(t, 0.35, 2) == 0) and (15 - (t % 15)) or 0,
        }
    end,

    -- 12. NIN: kurogane (Shinobi), kagemusha
    kurogane       = function(t)
        local c = math.max(1, step(t, 0.4, 5))
        local ph = step(t, 0.35, 4) -- 0=Build, 1=Feint, 2=Switch, 3=Cascade
        local pRem = (ph == 0 and step(t, 0.5, 2) == 0) and (8 - (t % 8)) or 0
        local lastCmds = { [0] = '', [1] = '', [2] = 'FA', [3] = 'MS' }
        return {
            clones      = c,
            engaged     = c,
            clone_exp   = 30 - (t % 30),
            phase       = ph,
            phase_rem   = ph > 0 and (20 - (t % 20)) or 0,
            feint_hits  = ph == 0 and step(t, 0.9, 2) or 0,
            opening_rem = (ph == 2) and (12 - (t % 12)) or 0,
            last_cmd    = lastCmds[ph] or '',
            legion_cd   = (step(t, 0.2, 2) == 0) and 0 or (90 - (t % 90)),
            phantom_cd  = pRem > 0 and (30 - (8 - pRem)) or ((step(t, 0.25, 2) == 0) and 0 or (30 - (t % 30))),
            phantom_rem = pRem,
        }
    end,
    kagemusha      = function(t)
        return {
            ash          = step(t, 0.7, 5),
            ash_rem      = 30 - (t % 30),
            shadows      = 1 + step(t, 0.6, 5),
            migawari_rem = (step(t, 0.3, 2) == 0) and (12 - (t % 12)) or 0,
        }
    end,

    -- 13. DRG: wyvernheart
    wyvernheart    = function(t)
        return {
            wyrmscale     = step(t, 0.6, 4),
            wyrmscale_rem = 30 - (t % 30),
            sanct_rem     = (step(t, 0.3, 2) == 0) and (12 - (t % 12)) or 0,
            wyvern_hpp    = math.floor(55 + 45 * wave(t, 0.7)),
        }
    end,

    -- 14. SMN: celestial
    celestial      = function(t)
        return {
            avatar     = 1,
            avatar_hpp = math.floor(50 + 50 * wave(t, 0.7)),
            conv_rem   = (step(t, 0.3, 2) == 0) and (12 - (t % 12)) or 0,
            astral_rem = 0,
        }
    end,

    -- 15. BLU: magus, azurebastion
    magus          = function(t) return { catalyst = step(t, 0.7, 6), conduit_rem = 20 - (t % 20) } end,
    azurebastion   = function(t) return { carapace = step(t, 0.7, 6), shell_rem = 15 - (t % 15) } end,

    -- 16. COR: flintlock, gambler, buccaneer
    flintlock      = function(t)
        return {
            chamber_rem = 30 - (t % 30),
            chamber_wsd = 25,
            hair_rem    = (step(t, 0.35, 2) == 0) and (10 - (t % 10)) or 0,
            mark_rem    = 10 - (t % 10),
        }
    end,
    gambler        = function(t)
        local c = t % 24
        return {
            rolls     = step(t, 0.5, 4),
            overdrive = (step(t, 0.25, 2) == 0) and 1 or 0,
            du_rem    = 45 - (t * 3) % 45,
            roll_tot  = 7 + step(t, 0.3, 5),
            debt_rem  = c > 19 and (24 - c) or 0,
        }
    end,
    buccaneer      = function(t) return { grapeshot = step(t, 0.7, 4), saltspray = math.floor(650 * wave(t, 0.9)) } end,

    -- 17. PUP: vanguard, pugilist, animist
    vanguard       = function(t)
        return {
            pet_alive     = 1,
            pet_hpp       = math.floor(45 + 55 * wave(t, 0.7)),
            maneuvers     = 2 + step(t, 0.4, 2),
            bulwark_rem   = (step(t, 0.3, 2) == 0) and (12 - (t % 12)) or 0,
            overdrive_rem = 0,
        }
    end,
    pugilist       = function(t)
        return {
            pet_alive   = 1,
            pet_hpp     = math.floor(55 + 45 * wave(t, 0.75)),
            maneuvers   = 2 + step(t, 0.5, 2),
            head        = 2 + step(t, 0.2, 2),
            opening_rem = (step(t, 0.4, 2) == 0) and (8 - (t % 8)) or 0,
            limiter_rem = 12 - (t % 12),
        }
    end,
    animist        = function(t)
        return {
            soulspark     = step(t, 0.7, 4),
            soulspark_rem = 30 - (t % 30),
            pet_alive     = 1,
            pet_hpp       = math.floor(60 + 40 * wave(t, 0.65)),
            pet_mpp       = math.floor(35 + 65 * wave(t, 0.55)),
            head          = 4 + step(t, 0.2, 2),
            maneuvers     = 3,
            aegis_rem     = (step(t, 0.3, 2) == 0) and (12 - (t % 12)) or 0,
        }
    end,

    -- 18. DNC: bladewheel, vampire, miragesentinel
    bladewheel     = function(t)
        return {
            throw_stance = 1,
            fm           = step(t, 0.7, 6),
            am_rem       = 60 - ((t * 2) % 60),
        }
    end,
    vampire        = function(t)
        return {
            fm           = step(t, 0.7, 6),
            trance_rem   = (step(t, 0.25, 2) == 0) and (30 - (t % 30)) or 0,
            contra_rem   = 15 - (t % 15),
            veil_rem     = 10 - (t % 10),
            sanguine_rem = (step(t, 0.35, 2) == 0) and (15 - (t % 15)) or 0,
        }
    end,
    miragesentinel = function(t) return { fm = step(t, 0.7, 6), aegis_hp = math.floor(900 * wave(t, 0.8)) } end,

    -- 19. SCH: medic, sage
    medic          = function(t)
        return {
            eos        = 1,
            eos_hpp    = math.floor(55 + 45 * wave(t, 0.6)),
            arts       = 1 + step(t, 0.3, 2),
            subl_state = 1 + step(t, 0.25, 2),
            subl_mp    = math.floor(150 + 300 * wave(t, 0.5)),
        }
    end,
    sage           = function(t)
        return {
            titania     = 1,
            titania_hpp = math.floor(50 + 50 * wave(t, 0.7)),
            arts        = 1 + step(t, 0.3, 2),
            ebullience  = 1,
        }
    end,

    -- 20. GEO: verdant
    verdant        = function(t)
        return {
            luopan      = 1,
            luopan_hpp  = math.floor(45 + 55 * wave(t, 0.65)),
            bolster_rem = 30 - (t % 30),
            canopy_rem  = (step(t, 0.3, 2) == 0) and (12 - (t % 12)) or 0,
        }
    end,

    -- 21. RUN: inquisitor, spellblade, lifebinder
    inquisitor     = function(t)
        return {
            runes        = 1 + step(t, 0.6, 3),
            stance       = 1 + step(t, 0.25, 3),
            converge_rem = (step(t, 0.3, 2) == 0) and (10 - (t % 10)) or 0,
            battuta_rem  = 60 - ((t * 2) % 60),
            aegis_rem    = 45 - ((t * 1.5) % 45),
        }
    end,
    spellblade     = function(t)
        return {
            prep_stacks    = step(t, 0.6, 4),
            runes          = 2 + step(t, 0.4, 2),
            edgeflare_rem  = 12 - (t % 12),
            overcharge_rem = (step(t, 0.3, 2) == 0) and (12 - (t % 12)) or 0,
            ascend_rem     = 0,
        }
    end,
    lifebinder     = function(t)
        return {
            runes        = 1 + step(t, 0.6, 3),
            sanct_rem    = (step(t, 0.3, 2) == 0) and (15 - (t % 15)) or 0,
            font_rem     = 12 - (t % 12),
            valiance_rem = 60 - ((t * 2) % 60),
        }
    end,
}

-- Legacy aliases
KV.defender  = KV.aegistemplar
KV.gladiator = KV.spartan

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
    -- Unbuilt Souls return empty KV so they display only the Soul Crystal medallion + header pill
    return {}
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

    -- Unbuilt Souls have no custom server buff strip in demo mode
    if not KV[key] then return '' end

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
