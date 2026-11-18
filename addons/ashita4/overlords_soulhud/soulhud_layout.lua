--[[
* OverlordsXI Soul HUD - bespoke mechanics per Soul (~40 implemented Souls).
*
* build(soulKey, kv, def, rt, role) -> { pips = {...}|nil, bar = {...}|nil }
*   pips = { label, cur, max, gem = 'gold|crimson|azure|emerald|violet', glow = bool,
*            right = 'custom right text'|nil, badge = bool (stance/mode pill) }
*   bar  = { key, label, cur, max|nil(peak-tracked), countdown = bool, fmt = 'sec|num|frac|pct',
*            notches = n, warn = bool, idle = 'text', right = 'custom value text'|nil }
* Souls without a BESPOKE entry (~26 unbuilt Souls) return `{}` so they render only the
* Soul Crystal medallion + compact Soul header pill.
--]]

local M = {}

local ROLE_GEM = { tank = 'azure', healer = 'emerald', support = 'violet', damage = 'crimson' }

local function num(kv, key)
    return tonumber(kv and kv[key]) or 0
end

local function str(kv, key)
    return tostring((kv and kv[key]) or '')
end

local function first(kv, ...)
    for i = 1, select('#', ...) do
        local v = tonumber(kv and kv[select(i, ...)])
        if v ~= nil then return v end
    end
    return 0
end

local function pips(label, cur, max, gem, glow, right)
    return {
        label = label,
        cur   = math.max(0, math.min(max, math.floor((tonumber(cur) or 0) + 0.5))),
        max   = max,
        gem   = gem,
        glow  = glow == true,
        right = right,
    }
end

local function badge(label, right, glow)
    return {
        badge = true,
        label = label,
        right = right or '',
        cur   = glow and 1 or 0,
        max   = 1,
        glow  = glow == true,
    }
end

local function timerBar(key, label, remaining, idle, maxDur)
    return {
        key       = key,
        label     = label,
        cur       = remaining,
        max       = maxDur,
        countdown = true,
        fmt       = 'sec',
        idle      = idle or 'Idle',
    }
end

local WAR_STANCE_NAMES = {
    [0] = 'NO STANCE',
    [1] = 'BERSERK',
    [2] = 'DEFENDER',
    [3] = 'AGGRESSOR',
    [4] = 'RETALIATION',
    [5] = 'RESTRAINT',
}

local BST_BEAST_NAMES = {
    [1] = 'CARRIE (CRAB)',
    [2] = 'GALAHAD (BEETLE)',
    [3] = 'RAPHIE (TORTOISE)',
    [4] = 'SIRAVARDE (TIGER)',
}

local PUP_HEAD_NAMES = {
    [1] = 'HARLEQUIN',
    [2] = 'VALOREDGE',
    [3] = 'SHARPSHOT',
    [4] = 'STORMWAKER',
    [5] = 'SOULSOOTHER',
    [6] = 'SPIRITREAVER',
}

local BESPOKE = {}

-- =============================================================================
-- 1. WAR: commander, berserker, spartan (gladiator)
-- =============================================================================
BESPOKE.commander = function(kv)
    local stCode  = math.floor(num(kv, 'stance'))
    local stName  = WAR_STANCE_NAMES[stCode] or 'NO STANCE'
    local breach  = num(kv, 'breach_rem')
    local warcry  = num(kv, 'warcry_rem')
    local banner  = math.max(warcry, num(kv, 'bulwark_rem'), num(kv, 'cadence_rem'), num(kv, 'regroup_rem'))
    local orders  = first(kv, 'orders')
    if orders == 0 then
        orders = (stCode > 0 and 1 or 0) + (warcry > 0 and 1 or 0) + (banner > 0 and 1 or 0) + (breach > 0 and 1 or 0)
    end
    local bar
    if breach > 0 then
        bar = timerBar('breach', 'Tactical Breach', breach, 'No Mark', 10)
    elseif banner > 0 then
        bar = timerBar('banner', warcry > 0 and 'Warcry Banner' or 'Formation Order', banner, 'Idle', 45)
    else
        bar = timerBar('stance', 'Active Command', num(kv, 'stance_rem'), 'Ready', 180)
    end
    return {
        pips = pips('Orders', orders, 4, 'violet', breach > 0 or warcry > 0, stName),
        bar  = bar,
    }
end

BESPOKE.berserker = function(kv)
    local bRem  = num(kv, 'berserk_rem')
    local aRem  = num(kv, 'aggressor_rem')
    local sRem  = num(kv, 'surge_rem')
    local brRem = math.max(num(kv, 'bloodrage_rem'), num(kv, 'warcry_rem'), num(kv, 'retal_rem'))
    local fury  = first(kv, 'fury')
    if fury == 0 then
        fury = (bRem > 0 and 1 or 0) + (aRem > 0 and 1 or 0) + (sRem > 0 and 1 or 0) + (brRem > 0 and 1 or 0)
    end
    local bar
    if sRem > 0 then
        bar = timerBar('surge', 'Bloodlust Surge', sRem, 'Idle', 10)
    elseif brRem > 0 then
        bar = timerBar('rage', 'Blood Rage / Warcry', brRem, 'Idle', 45)
    else
        bar = timerBar('berserk', 'Berserk Fury', bRem, 'Unleashed Ready', 240)
    end
    return {
        pips = pips('Fury', fury, 4, 'crimson', sRem > 0),
        bar  = bar,
    }
end

BESPOKE.spartan = function(kv)
    local brace = math.floor(num(kv, 'brace'))
    local right = brace >= 2 and 'HEAVY BRACE' or (brace == 1 and 'LIGHT BRACE' or nil)
    return {
        pips = pips('Grit', num(kv, 'grit'), 5, 'gold', brace > 0, right),
        bar  = timerBar('ward', 'Phalanx Ward', num(kv, 'ward_rem'), 'Idle', 12),
    }
end
BESPOKE.gladiator = BESPOKE.spartan

-- =============================================================================
-- 2. MNK: sensei, blackbelt, chiweaver
-- =============================================================================
BESPOKE.sensei = function(kv)
    local staff    = num(kv, 'staff') > 0
    local csRem    = num(kv, 'counter_rem')
    local dodgeRem = num(kv, 'dodge_rem')
    local focusRem = num(kv, 'focus_rem')
    local pcRem    = math.max(num(kv, 'pcounter_rem'), num(kv, 'inner_rem'))
    local stances  = first(kv, 'stances')
    if stances == 0 then
        stances = (csRem > 0 and 1 or 0) + (dodgeRem > 0 and 1 or 0) + (focusRem > 0 and 1 or 0) + (pcRem > 0 and 1 or 0)
    end
    local bar
    if pcRem > 0 then
        bar = timerBar('pc', num(kv, 'inner_rem') > 0 and 'Inner Strength' or 'Perfect Counter', pcRem, 'Idle', 30)
    elseif dodgeRem > 0 or focusRem > 0 then
        bar = timerBar('df', dodgeRem >= focusRem and 'Dodge Riposte' or 'Focus Guard', math.max(dodgeRem, focusRem), 'Idle', 60)
    else
        bar = timerBar('cs', 'Counterstance', csRem, 'Stance Open', 300)
    end
    return {
        pips = pips('Kata', stances, 4, 'azure', pcRem > 0, staff and 'STAFF RIPOSTE' or 'NO STAFF'),
        bar  = bar,
    }
end

BESPOKE.blackbelt = function(kv)
    local focusRem = num(kv, 'focus_rem')
    local footRem  = num(kv, 'footwork_rem')
    local boostRem = num(kv, 'boost_rem')
    local hfRem    = num(kv, 'hf_rem')
    local dodgeRem = num(kv, 'dodge_rem')
    local stances  = first(kv, 'stances')
    if stances == 0 then
        stances = (focusRem > 0 and 1 or 0) + (footRem > 0 and 1 or 0) + (boostRem > 0 and 1 or 0) + (math.max(dodgeRem, hfRem) > 0 and 1 or 0)
    end
    local bar
    if hfRem > 0 then
        bar = timerBar('hf', 'Hundred Fists', hfRem, 'Idle', 45)
    elseif footRem > 0 then
        bar = timerBar('fw', 'Footwork Stance', footRem, 'Idle', 60)
    else
        bar = timerBar('focus', 'Focus / Boost', math.max(focusRem, boostRem, dodgeRem), 'Ready', 60)
    end
    return {
        pips = pips('Forms', stances, 4, 'crimson', hfRem > 0 or boostRem > 0),
        bar  = bar,
    }
end

BESPOKE.chiweaver = function(kv)
    local chi      = first(kv, 'chi_stacks', 'chi')
    local tierPips = (chi >= 100 and 4) or (chi >= 80 and 3) or (chi >= 50 and 2) or (chi >= 25 and 1) or 0
    local hRem     = num(kv, 'harmony_rem')
    local lRem     = num(kv, 'lotus_rem')
    local right    = hRem > 0 and ('HARMONY ' .. math.ceil(hRem) .. 's')
        or (lRem > 0 and ('LOTUS ' .. math.ceil(lRem) .. 's') or ('CLEANSE x' .. math.min(3, tierPips)))
    return {
        pips = pips('Cleanse', tierPips, 4, 'emerald', chi >= 80, right),
        bar  = { key = 'chi', label = 'Chi Flow', cur = chi, max = 100, fmt = 'frac', idle = '0/100', notches = 4 },
    }
end

-- =============================================================================
-- 3. WHM: bishop
-- =============================================================================
BESPOKE.bishop = function(kv)
    local grace   = num(kv, 'grace')
    local solace  = math.floor(num(kv, 'solace'))
    local vRem    = num(kv, 'veil_rem')
    local wRem    = num(kv, 'ward_rem')
    local gRem    = num(kv, 'grace_rem')
    local right   = solace == 1 and 'SOLACE 100% SIRD' or (solace == 2 and 'MISERY 100% SIRD' or string.format('GRACE %d/3', grace))
    local bar
    if vRem > 0 then
        bar = timerBar('veil', 'Divine Veil', vRem, 'Idle', 15)
    elseif wRem > 0 then
        bar = timerBar('ward', 'Solace Ward', wRem, 'Idle', 8)
    else
        bar = timerBar('grace', 'Sacred Grace', gRem, 'Cast Banish / Holy / WS', 30)
    end
    return {
        pips = pips('Sacred Grace', grace, 3, 'emerald', grace >= 3, right),
        bar  = bar,
    }
end

-- =============================================================================
-- 4. BLM: necromancer
-- =============================================================================
BESPOKE.necromancer = function(kv)
    local mode = str(kv, 'thrall_mode')
    local role = str(kv, 'thrall_role')
    local hpp  = num(kv, 'thrall_hpp')
    local pact = num(kv, 'dark_pact') > 0
    local title, rText
    if mode == 'dullahan' then
        title, rText = 'DULLAHAN [TANK]', pact and 'DARK PACT' or 'TANK'
    elseif mode == 'warrior' then
        title, rText = 'WARRIOR [TANK]', pact and 'DARK PACT' or 'TANK'
    elseif mode == 'corse' then
        title, rText = 'CORSE [CASTER]', pact and 'DARK PACT' or 'CASTER'
    elseif mode == 'mage' then
        title, rText = 'MAGE [CASTER]', pact and 'DARK PACT' or 'CASTER'
    else
        title, rText = 'NO THRALL', 'SUMMON THRALL'
    end
    return {
        pips = badge(title, rText, role == 'tank' or pact),
        bar  = {
            key   = 'thrall',
            label = role == 'tank' and 'Tank Thrall HP' or (role == 'caster' and 'Caster Thrall HP' or 'Undead Thrall'),
            cur   = hpp,
            max   = 100,
            fmt   = 'pct',
            idle  = 'Unsummoned',
            warn  = hpp > 0 and hpp < 25,
        },
    }
end

-- =============================================================================
-- 5. RDM: crimsonduelist
-- =============================================================================
BESPOKE.crimsonduelist = function(kv)
    local hexes     = num(kv, 'hexes')
    local fencer    = num(kv, 'fencer') > 0
    local flowRem   = num(kv, 'flow_rem')
    local flecheRem = num(kv, 'fleche_rem')
    local right     = flowRem > 0 and 'CRIMSON FLOW!' or (fencer and ('HEX -' .. (hexes * 5) .. '% DMG') or 'NEED 1H SWORD')
    local bar
    if flowRem > 0 then
        bar = timerBar('flow', 'Crimson Flow (Instant)', flowRem, 'Idle', 6)
    elseif flecheRem > 0 then
        bar = timerBar('fleche', 'Crimson Fleche (+35% Parry)', flecheRem, 'Idle', 6)
    else
        bar = { key = 'skin', label = 'Stoneskin Barrier', cur = num(kv, 'stoneskin'), fmt = 'num', idle = 'No Barrier' }
    end
    return {
        pips = pips('Hexes', hexes, 5, 'crimson', flowRem > 0 or hexes >= 5, right),
        bar  = bar,
    }
end

-- =============================================================================
-- 6. PLD: aegistemplar (defender), templar
-- =============================================================================
BESPOKE.aegistemplar = function(kv)
    local zeal  = num(kv, 'zeal')
    local cRem  = num(kv, 'consec_rem')
    local rRem  = num(kv, 'retrib_rem')
    local zRem  = num(kv, 'zeal_rem')
    local bar
    if cRem > 0 then
        bar = timerBar('consec', 'Aegis Consecration', cRem, 'Idle', 15)
    elseif rRem > 0 then
        bar = timerBar('retrib', 'Holy Retribution (-10% DT)', rRem, 'Idle', 8)
    else
        bar = timerBar('zeal', 'Aegis Zeal Window', zRem, 'Block / Flash to build', 30)
    end
    return {
        pips = pips('Zeal', zeal, 5, 'gold', zeal >= 5),
        bar  = bar,
    }
end
BESPOKE.defender = BESPOKE.aegistemplar

BESPOKE.templar = function(kv)
    local aRem   = num(kv, 'aegis_rem')
    local gRem   = num(kv, 'grace_rem')
    local dRem   = num(kv, 'dseal_rem')
    local shield = num(kv, 'shield') > 0
    local right  = aRem > 0 and '2x BEACON PULSE' or (shield and 'MAJESTY 100% SIRD' or 'MAJESTY ON')
    local bar
    if aRem > 0 then
        bar = timerBar('aegis', "Crusader's Aegis", aRem, 'Idle', 15)
    elseif gRem > 0 then
        bar = timerBar('grace', "Light's Grace HoT", gRem, 'Idle', 10)
    else
        bar = timerBar('dseal', 'Divine Seal', dRem, 'Perpetual Majesty Ready', 60)
    end
    return {
        pips = badge('PERPETUAL MAJESTY', right, aRem > 0 or gRem > 0),
        bar  = bar,
    }
end

-- =============================================================================
-- 7. DRK: dreadnought
-- =============================================================================
BESPOKE.dreadnought = function(kv)
    local tithe  = num(kv, 'tithe')
    local reap   = num(kv, 'reap_rem')
    local bRem   = num(kv, 'bastion_rem')
    local cRem   = num(kv, 'carapace_rem')
    local spikes = num(kv, 'spikes_hp')
    local right  = reap > 0 and ('BLOOD REAP ' .. math.ceil(reap) .. 's') or nil
    local bar
    if spikes > 0 then
        bar = { key = 'spikes', label = 'Dread Spikes Shield', cur = spikes, fmt = 'num', idle = 'No Spikes' }
    elseif bRem > 0 or cRem > 0 then
        bar = timerBar('ward', bRem >= cRem and 'Dread Bastion' or 'Blood Carapace', math.max(bRem, cRem), 'Idle', 15)
    else
        bar = timerBar('tithe', reap > 0 and ('Blood Reap (' .. math.ceil(reap) .. 's)') or 'Blood Tithe Fade',
            math.max(reap, num(kv, 'tithe_rem')), 'Cast Absorb / Cleave', 30)
    end
    return {
        pips = pips('Blood Tithe', tithe, 3, 'crimson', tithe >= 3 or reap > 0, right),
        bar  = bar,
    }
end

-- =============================================================================
-- 8. BST: alphawarden
-- =============================================================================
BESPOKE.alphawarden = function(kv)
    local idx   = math.max(1, math.min(4, math.floor(first(kv, 'beast_idx') > 0 and first(kv, 'beast_idx') or 1)))
    local alive = num(kv, 'pet_alive') > 0
    local hpp   = num(kv, 'pet_hpp')
    local link  = num(kv, 'soullink') > 0 or (alive and hpp >= 15)
    local right = link and 'SOUL-LINK 50%' or (alive and 'LOW HP (<15%)' or (BST_BEAST_NAMES[idx] or 'BEAST #1'))
    return {
        pips = pips('Guardian', idx, 4, 'azure', link, right),
        bar  = {
            key   = 'pet_hp',
            label = BST_BEAST_NAMES[idx] or 'Guardian Beast',
            cur   = alive and hpp or 0,
            max   = 100,
            fmt   = 'pct',
            idle  = 'Call Beast Ready',
            warn  = alive and hpp < 25,
        },
    }
end

-- =============================================================================
-- 9. BRD: adventurer, musician, minstrel
-- =============================================================================
BESPOKE.adventurer = function(kv)
    local cad   = num(kv, 'cadence')
    local cRem  = num(kv, 'cadence_rem')
    local eRem  = num(kv, 'encore_rem')
    local songs = num(kv, 'songs')
    local right = ('CADENCE %d/5  SONGS %d'):format(cad, songs)
    local bar   = eRem > 0
        and timerBar('encore', "Troubadour's Encore (+15% Haste)", eRem, 'Idle', 12)
        or timerBar('cadence', 'Cadence Window', cRem, 'Swing to build Cadence', 20)
    return {
        pips = pips('Cadence', cad, 5, 'crimson', eRem > 0 or cad >= 5, right),
        bar  = bar,
    }
end

BESPOKE.musician = function(kv)
    local res   = num(kv, 'resonance')
    local rRem  = num(kv, 'resonance_rem')
    local oRem  = num(kv, 'overdrive_rem')
    local right = oRem > 0 and 'OVERDRIVE +30%!' or ('RESONANCE %d/3'):format(res)
    local bar   = oRem > 0
        and timerBar('overdrive', 'Lyrical Overdrive', oRem, 'Idle', 15)
        or timerBar('res', 'Resonance (+MAB)', rRem, 'Cast Threnody / Requiem', 30)
    return {
        pips = pips('Resonance', res, 3, 'violet', oRem > 0 or res >= 3, right),
        bar  = bar,
    }
end

BESPOKE.minstrel = function(kv)
    local minne   = num(kv, 'minne') > 0
    local paeon   = num(kv, 'paeon') > 0
    local scherzo = num(kv, 'scherzo') > 0
    local hymns   = (minne and 1 or 0) + (paeon and 1 or 0) + (scherzo and 1 or 0)
    local parts   = {}
    if minne then parts[#parts + 1] = 'MINNE' end
    if paeon then parts[#parts + 1] = 'PAEON' end
    if scherzo then parts[#parts + 1] = 'SCHERZO' end
    local right = #parts > 0 and table.concat(parts, '+') or 'SING HYMNS'
    return {
        pips = pips('Hymns', hymns, 3, 'azure', scherzo, right),
        bar  = timerBar('aria', 'Iron Aria Reflect', num(kv, 'iron_aria_rem'), 'Hymn Aura Active', 15),
    }
end

-- =============================================================================
-- 10. RNG: huntsman
-- =============================================================================
local HUNTSMAN_PETS = {
    [0] = { 'NO COMPANION', 'CALL BEAST' },
    [1] = { 'WILD RAAZ', 'TUSKER [TANK]' },
    [2] = { 'STALKER RAPTOR', 'SAURIAN [PACK]' },
    [3] = { 'CEHUETZI', 'APEX TUSKER [TANK]' },
    [4] = { 'GABBRATH', 'APEX SAURIAN [PACK]' },
}

BESPOKE.huntsman = function(kv)
    local pid  = math.floor(num(kv, 'pet_id'))
    local hpp  = num(kv, 'pet_hpp')
    local info = HUNTSMAN_PETS[pid] or HUNTSMAN_PETS[0]
    return {
        pips = badge(info[1], info[2], pid > 0),
        bar  = {
            key   = 'pet_hp',
            label = pid > 0 and (info[1] .. ' HP') or 'Pack Companion',
            cur   = pid > 0 and hpp or 0,
            max   = 100,
            fmt   = 'pct',
            idle  = 'Unsummoned',
            warn  = pid > 0 and hpp < 25,
        },
    }
end

-- =============================================================================
-- 11. SAM: ronin, imperialarcher, warlord
-- =============================================================================
BESPOKE.ronin = function(kv)
    local ticks = num(kv, 'stagger_ticks')
    return {
        pips = pips("Mind's Eye", num(kv, 'minds_eye'), 3, 'azure', num(kv, 'seigan') > 0),
        bar  = {
            key     = 'stagger',
            label   = ticks > 0 and ('Stagger  x' .. math.floor(ticks)) or 'Stagger',
            cur     = num(kv, 'stagger_pool'),
            fmt     = 'num',
            idle    = 'Steady',
            notches = ticks > 1 and math.min(10, math.floor(ticks)) or 0,
        },
    }
end

BESPOKE.imperialarcher = function(kv)
    local oRem   = num(kv, 'oisoya_rem')
    local cRem   = num(kv, 'cosmic_rem')
    local primes = (oRem > 0 and 1 or 0) + (cRem > 0 and 1 or 0)
    local right  = (oRem > 0 and cRem > 0 and 'BOW + BLADE PRIMED')
        or (oRem > 0 and 'DRAWN OISOYA (BOW)')
        or (cRem > 0 and 'COSMIC BRAND (TACHI)')
        or 'WEAVE TACHI <-> BOW'
    local bar
    if oRem >= cRem and oRem > 0 then
        bar = timerBar('oisoya', 'Drawn Oisoya (Next Bow WS)', oRem, 'Idle', 15)
    elseif cRem > 0 then
        bar = timerBar('cosmic', 'Cosmic Brand (Next Tachi)', cRem, 'Idle', 15)
    else
        bar = timerBar('hasso', 'Hasso Skirmish', num(kv, 'hasso_rem'), 'Ready', 300)
    end
    return {
        pips = pips('Primes', primes, 2, 'violet', primes > 0, right),
        bar  = bar,
    }
end

BESPOKE.warlord = function(kv)
    local ashura = num(kv, 'ashura')
    local aRem   = num(kv, 'ashura_rem')
    local nRem   = num(kv, 'noto_rem')
    local right  = nRem > 0 and ('NOTO IAIDO ' .. math.ceil(nRem) .. 's') or ('ASHURA %d/3'):format(ashura)
    local bar    = nRem > 0
        and timerBar('noto', 'Noto Sheathe (Iaijutsu Ready)', nRem, 'Idle', 15)
        or timerBar('ashura', "Ashura's Edge Party Aura", aRem, 'Use Tachi / Onimaru Tithe', 20)
    return {
        pips = pips("Ashura's Edge", ashura, 3, 'violet', ashura >= 3 or nRem > 0, right),
        bar  = bar,
    }
end

-- =============================================================================
-- 12. NIN: kagemusha
-- =============================================================================
BESPOKE.kagemusha = function(kv)
    local ash     = num(kv, 'ash')
    local shadows = num(kv, 'shadows')
    local migRem  = num(kv, 'migawari_rem')
    local right   = ('ASH %d/4  •  SHADOWS %d'):format(ash, shadows)
    local bar     = migRem > 0
        and timerBar('migawari', 'Migawari Intercept', migRem, 'Idle', 12)
        or timerBar('ash', 'Kawarimi Ash Fade', num(kv, 'ash_rem'), 'No Ash Banked', 30)
    return {
        pips = pips('Ash', ash, 4, 'violet', ash >= 3 or migRem > 0, right),
        bar  = bar,
    }
end

-- =============================================================================
-- 13. DRG: wyvernheart
-- =============================================================================
BESPOKE.wyvernheart = function(kv)
    local scale = num(kv, 'wyrmscale')
    local rem   = num(kv, 'wyrmscale_rem')
    local sRem  = num(kv, 'sanct_rem')
    local wHpp  = num(kv, 'wyvern_hpp')
    local right = wHpp > 0 and ('WYVERN ' .. math.floor(wHpp) .. '% HP') or ('WYRMSCALE %d/3'):format(scale)
    local bar   = sRem > 0
        and timerBar('sanct', 'Dragonscale Sanctuary', sRem, 'Idle', 12)
        or timerBar('wyrm', 'Wyrmscale Fade', rem, 'Jump / WS / Spirit Link', 30)
    return {
        pips = pips('Wyrmscale', scale, 3, 'emerald', scale >= 3, right),
        bar  = bar,
    }
end

-- =============================================================================
-- 14. SMN: celestial
-- =============================================================================
BESPOKE.celestial = function(kv)
    local alive = num(kv, 'avatar') > 0
    local hpp   = num(kv, 'avatar_hpp')
    local cRem  = num(kv, 'conv_rem')
    local aRem  = num(kv, 'astral_rem')
    local right = cRem > 0 and ('CONVERGENCE ' .. math.ceil(cRem) .. 's')
        or (aRem > 0 and 'ASTRAL FLOW (5s WARD)' or (alive and 'SANCTUARY 15Y' or 'SUMMON AVATAR'))
    local bar = cRem > 0
        and timerBar('conv', 'Celestial Convergence', cRem, 'Idle', 12)
        or {
            key   = 'avatar_hp',
            label = 'Avatar Conduit HP',
            cur   = alive and hpp or 0,
            max   = 100,
            fmt   = 'pct',
            idle  = 'No Avatar Summoned',
        }
    return {
        pips = badge(alive and 'AVATAR SANCTUARY' or 'NO AVATAR', right, alive),
        bar  = bar,
    }
end

-- =============================================================================
-- 15. BLU: magus, azurebastion
-- =============================================================================
BESPOKE.magus = function(kv)
    return {
        pips = pips('Catalyst', first(kv, 'catalyst', 'catalyst_stacks'), 5, 'azure'),
        bar  = timerBar('conduit', 'Osmotic Conduit', num(kv, 'conduit_rem')),
    }
end

BESPOKE.azurebastion = function(kv)
    return {
        pips = pips('Carapace', first(kv, 'carapace', 'chitin_stacks'), 5, 'azure'),
        bar  = timerBar('shell', 'Diamond Shell', num(kv, 'shell_rem')),
    }
end

-- =============================================================================
-- 16. COR: flintlock, gambler, buccaneer
-- =============================================================================
BESPOKE.flintlock = function(kv)
    local chRem   = num(kv, 'chamber_rem')
    local chWsd   = num(kv, 'chamber_wsd')
    local hairRem = num(kv, 'hair_rem')
    local markRem = num(kv, 'mark_rem')
    local primed  = (chRem > 0 and 1 or 0) + (hairRem > 0 and 1 or 0) + (markRem > 0 and 1 or 0)
    local right   = markRem > 0 and ('POWDER MARK ' .. math.ceil(markRem) .. 's')
        or (chWsd > 0 and ('DEADEYE +' .. math.floor(chWsd) .. '% WSD') or 'CHAMBER READY')
    local bar
    if markRem > 0 then
        bar = timerBar('mark', 'Target Powder Mark', markRem, 'No Mark', 10)
    elseif hairRem > 0 then
        bar = timerBar('hair', 'Hair Trigger (+25% WSD)', hairRem, 'Idle', 10)
    else
        bar = timerBar('chamber', 'Deadeye Chamber', chRem, 'Roll to Chamber', 30)
    end
    return {
        pips = pips('Primed', primed, 3, 'crimson', markRem > 0 or hairRem > 0, right),
        bar  = bar,
    }
end

BESPOKE.gambler = function(kv)
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
end

BESPOKE.buccaneer = function(kv)
    return {
        pips = pips('Grapeshot', num(kv, 'grapeshot'), 3, 'crimson'),
        bar  = { key = 'salt', label = 'Salt Spray', cur = num(kv, 'saltspray'), fmt = 'num', idle = 'No Shield' },
    }
end

-- =============================================================================
-- 17. PUP: vanguard, pugilist, animist
-- =============================================================================
BESPOKE.vanguard = function(kv)
    local alive   = num(kv, 'pet_alive') > 0
    local hpp     = num(kv, 'pet_hpp')
    local man     = num(kv, 'maneuvers')
    local bulRem  = num(kv, 'bulwark_rem')
    local odRem   = num(kv, 'overdrive_rem')
    local right   = bulRem > 0 and ('BULWARK ' .. math.ceil(bulRem) .. 's')
        or (odRem > 0 and 'OVERDRIVE!' or (alive and 'VALOREDGE TANK' or 'ACTIVATE PUPPET'))
    local bar = bulRem > 0
        and timerBar('bulwark', 'Clockwork Bulwark (50% Split)', bulRem, 'Idle', 12)
        or {
            key   = 'auto_hp',
            label = 'Valoredge Automaton HP',
            cur   = alive and hpp or 0,
            max   = 100,
            fmt   = 'pct',
            idle  = 'Offline',
            warn  = alive and hpp < 25,
        }
    return {
        pips = pips('Maneuvers', man, 3, 'azure', bulRem > 0 or odRem > 0, right),
        bar  = bar,
    }
end

BESPOKE.pugilist = function(kv)
    local alive   = num(kv, 'pet_alive') > 0
    local hpp     = num(kv, 'pet_hpp')
    local man     = num(kv, 'maneuvers')
    local openRem = num(kv, 'opening_rem')
    local limRem  = num(kv, 'limiter_rem')
    local head    = PUP_HEAD_NAMES[math.floor(num(kv, 'head'))] or 'AUTOMATON'
    local right   = openRem > 0 and ('TANDEM ' .. math.ceil(openRem) .. 's')
        or (limRem > 0 and ('LIMITER ' .. math.ceil(limRem) .. 's') or head)
    local bar
    if openRem > 0 then
        bar = timerBar('open', 'Tandem Opening (+25% Auto WS)', openRem, 'Idle', 8)
    elseif limRem > 0 then
        bar = timerBar('lim', 'Limiter Release (+22% ATK)', limRem, 'Idle', 12)
    else
        bar = {
            key   = 'auto_hp',
            label = 'Tandem Automaton HP',
            cur   = alive and hpp or 0,
            max   = 100,
            fmt   = 'pct',
            idle  = 'Offline',
        }
    end
    return {
        pips = pips('Maneuvers', man, 3, 'crimson', openRem > 0 or limRem > 0, right),
        bar  = bar,
    }
end

BESPOKE.animist = function(kv)
    local spark  = first(kv, 'soulspark', 'cells')
    local alive  = num(kv, 'pet_alive') > 0
    local hpp    = num(kv, 'pet_hpp')
    local mpp    = num(kv, 'pet_mpp')
    local aegis  = num(kv, 'aegis_rem')
    local head   = PUP_HEAD_NAMES[math.floor(num(kv, 'head'))] or 'SOULSOOTHER'
    local right  = alive and ('%s  MP %d%%'):format(head, math.floor(mpp)) or ('SOULSPARK %d/3'):format(spark)
    local bar    = aegis > 0
        and timerBar('aegis', 'Clockwork Aegis (-15% DT)', aegis, 'Idle', 12)
        or {
            key   = 'auto_mp',
            label = alive and ('Automaton HP ' .. math.floor(hpp) .. '%  /  MP') or 'Medical Automaton',
            cur   = alive and mpp or num(kv, 'soulspark_rem'),
            max   = alive and 100 or 30,
            fmt   = alive and 'pct' or 'sec',
            idle  = 'Activate Automaton',
        }
    return {
        pips = pips('Soulspark', spark, 3, 'emerald', spark >= 3, right),
        bar  = bar,
    }
end

-- =============================================================================
-- 18. DNC: bladewheel, vampire, miragesentinel
-- =============================================================================
BESPOKE.bladewheel = function(kv)
    local stance = num(kv, 'throw_stance') > 0
    local fm     = num(kv, 'fm')
    local amRem  = num(kv, 'am_rem')
    local right  = stance and 'THROW STANCE: ON' or 'THROW STANCE: AUTO'
    return {
        pips = pips('Finishing Moves', fm, 5, 'crimson', stance, right),
        bar  = timerBar('am', 'Chakram Aftermath', amRem, 'Chakram Ready', 60),
    }
end

BESPOKE.vampire = function(kv)
    local fm       = num(kv, 'fm')
    local tRem     = num(kv, 'trance_rem')
    local cRem     = num(kv, 'contra_rem')
    local vRem     = num(kv, 'veil_rem')
    local sRem     = num(kv, 'sanguine_rem')
    local right    = tRem > 0 and 'TRANCE (2x DRAIN)' or (cRem > 0 and 'CONTRADANCE' or ('FM %d/5'):format(fm))
    local bar
    if sRem > 0 then
        bar = timerBar('sang', 'Sanguine Waltz Regen', sRem, 'Idle', 15)
    elseif vRem > 0 then
        bar = timerBar('veil', 'Crimson Veil (-15% DT)', vRem, 'Idle', 10)
    else
        bar = timerBar('trance', tRem >= cRem and 'Trance' or 'Contradance', math.max(tRem, cRem), 'Crimson Drain Active', 30)
    end
    return {
        pips = pips('Finishing Moves', fm, 5, 'emerald', tRem > 0 or fm >= 5, right),
        bar  = bar,
    }
end

BESPOKE.miragesentinel = function(kv)
    return {
        pips = pips('Finishing Moves', num(kv, 'fm'), 5, 'gold'),
        bar  = { key = 'aegis', label = 'Aegis Waltz', cur = num(kv, 'aegis_hp'), fmt = 'num', idle = 'No Shield' },
    }
end

-- =============================================================================
-- 19. SCH: medic, sage
-- =============================================================================
BESPOKE.medic = function(kv)
    local eos   = num(kv, 'eos') > 0
    local hpp   = num(kv, 'eos_hpp')
    local arts  = math.floor(num(kv, 'arts'))
    local subl  = math.floor(num(kv, 'subl_state'))
    local subMp = math.floor(num(kv, 'subl_mp'))
    local lText = eos and 'EOS COMPANION' or 'CALL EOS READY'
    local rText = (arts == 2 and 'ADDENDUM: WHITE') or (arts == 1 and 'LIGHT ARTS') or 'NO ARTS'
    if subl == 2 then
        rText = ('SUBL READY (%d MP)'):format(subMp)
    elseif subl == 1 and subMp > 0 then
        rText = ('SUBL %d MP'):format(subMp)
    end
    return {
        pips = badge(lText, rText, eos or arts == 2),
        bar  = {
            key   = 'eos_hp',
            label = eos and 'Eos Faerie HP' or 'Sublimation Pool',
            cur   = eos and hpp or subMp,
            max   = eos and 100 or nil,
            fmt   = eos and 'pct' or 'num',
            idle  = 'Call Eos / Sublimation',
        },
    }
end

BESPOKE.sage = function(kv)
    local tit   = num(kv, 'titania') > 0
    local hpp   = num(kv, 'titania_hpp')
    local arts  = math.floor(num(kv, 'arts'))
    local ebul  = num(kv, 'ebullience') > 0
    local lText = tit and 'TITANIA COMPANION' or 'CALL TITANIA READY'
    local rText = (arts == 2 and 'ADDENDUM: BLACK') or (arts == 1 and 'DARK ARTS') or (ebul and 'EBULLIENCE' or 'NO ARTS')
    return {
        pips = badge(lText, rText, tit or ebul),
        bar  = {
            key   = 'tit_hp',
            label = 'Titania Faerie HP',
            cur   = tit and hpp or 0,
            max   = 100,
            fmt   = 'pct',
            idle  = 'Call Titania Ready',
        },
    }
end

-- =============================================================================
-- 20. GEO: verdant
-- =============================================================================
BESPOKE.verdant = function(kv)
    local luo   = num(kv, 'luopan') > 0
    local hpp   = num(kv, 'luopan_hpp')
    local bRem  = num(kv, 'bolster_rem')
    local cRem  = num(kv, 'canopy_rem')
    local lText = luo and 'LUOPAN SANCTUARY' or 'NO LUOPAN'
    local rText = cRem > 0 and ('CANOPY ' .. math.ceil(cRem) .. 's')
        or (bRem > 0 and 'BOLSTER (2x BLOOM)' or (luo and 'BLOOM 3s PULSE' or 'CAST GEO SPELL'))
    local bar = cRem > 0
        and timerBar('canopy', 'Canopy of the Ancients', cRem, 'Idle', 12)
        or {
            key   = 'luo_hp',
            label = 'Living Luopan HP',
            cur   = luo and hpp or 0,
            max   = 100,
            fmt   = 'pct',
            idle  = 'Place Luopan',
        }
    return {
        pips = badge(lText, rText, luo or cRem > 0),
        bar  = bar,
    }
end

-- =============================================================================
-- 21. RUN: inquisitor, spellblade, lifebinder
-- =============================================================================
local INQ_STANCES = {
    [0] = 'NO STANCE',
    [1] = 'IRON BATTUTA (PHYS)',
    [2] = 'RUNIC AEGIS (MAG)',
    [3] = 'CONVERGENCE (BOTH)',
}

BESPOKE.inquisitor = function(kv)
    local runes  = num(kv, 'runes')
    local stance = math.floor(num(kv, 'stance'))
    local cRem   = num(kv, 'converge_rem')
    local bRem   = num(kv, 'battuta_rem')
    local aRem   = num(kv, 'aegis_rem')
    local bar
    if cRem > 0 then
        bar = timerBar('conv', 'Runic Convergence', cRem, 'Idle', 10)
    elseif aRem >= bRem and aRem > 0 then
        bar = timerBar('aegis', 'Runic Aegis (Elem Ward)', aRem, 'Idle', 60)
    else
        bar = timerBar('bat', 'Iron Battuta (Parry Ward)', bRem, 'Choose Ward Stance', 60)
    end
    return {
        pips = pips('Runes', runes, 3, 'azure', stance == 3 or runes >= 3, INQ_STANCES[stance] or 'NO STANCE'),
        bar  = bar,
    }
end

BESPOKE.spellblade = function(kv)
    local prep  = first(kv, 'prep_stacks', 'prep')
    local runes = num(kv, 'runes')
    local eRem  = num(kv, 'edgeflare_rem')
    local oRem  = num(kv, 'overcharge_rem')
    local aRem  = num(kv, 'ascend_rem')
    local right = ('PREP %d/3  •  RUNES %d'):format(prep, runes)
    local bar
    if oRem > 0 or aRem > 0 then
        bar = timerBar('oc', aRem > oRem and 'Runic Ascendance' or 'Overcharge Runes (2x)', math.max(oRem, aRem), 'Idle', 12)
    else
        bar = timerBar('edge', 'Edgeflare (+25% Rune Edge)', eRem, 'Cast Bolt / Sever / Slash', 12)
    end
    return {
        pips = pips('Prep', prep, 3, 'crimson', prep >= 3 or oRem > 0, right),
        bar  = bar,
    }
end

BESPOKE.lifebinder = function(kv)
    local runes = num(kv, 'runes')
    local sRem  = num(kv, 'sanct_rem')
    local fRem  = num(kv, 'font_rem')
    local vRem  = num(kv, 'valiance_rem')
    local bar
    if sRem > 0 then
        bar = timerBar('sanct', 'Sanctified Ward (12y)', sRem, 'Idle', 15)
    elseif fRem > 0 then
        bar = timerBar('font', 'Font of Life', fRem, 'Idle', 12)
    else
        bar = timerBar('val', 'Valiance Ward', vRem, 'Vivacious Pulse Ready', 60)
    end
    return {
        pips = pips('Sacred Runes', runes, 3, 'emerald', runes >= 3),
        bar  = bar,
    }
end

function M.build(soulKey, kv, _def, _rt, _role)
    kv = kv or {}
    local fn = BESPOKE[soulKey]
    if fn then
        local ok, res = pcall(fn, kv)
        if ok and type(res) == 'table' then return res end
    end
    -- Unbuilt Souls (~26 Souls without custom server spec code) intentionally return `{}`
    -- so they render only the Soul Crystal medallion + compact Soul header pill.
    return {}
end

function M.hasBespoke(soulKey)
    return BESPOKE[soulKey] ~= nil
end

M.ROLE_GEM = ROLE_GEM

return M
