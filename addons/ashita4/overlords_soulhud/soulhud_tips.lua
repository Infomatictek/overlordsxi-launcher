--[[
* OverlordsXI Soul HUD - player-facing tooltip text.
*
* Plain-English mechanic explanations (no raw formulas). Every tooltip is structured as
*   Core Loop (Build -> Spend)  /  How It Scales  /  Right Now (live, resolved here from the 0x1FC kv map)
*   / Next Threshold.
* The server never sends computed text: the resolved numbers below are derived from `kv` quietly in Lua and
* only the clean outcome is shown.
*
* Public API
*   tips.soul(entry, ctx)               -> { weapon = '...', lines = { ... } }   Soul header / medallion / pill
*   tips.element(soulKey, which, ctx)   -> lines | nil     which = 'pips' | 'bar'  (12 wired Souls)
*   tips.buff(b, now, fmtTime)          -> title, lines                              ox_buffs status icons
* A `line` is { head = 'Title', text = '...', color = {r,g,b}|nil } or { sep = true }.
* ctx = { kv = {}, lvl = number, boost = { stacks, remSec, at } | nil }
--]]

local M = {}

local GOLD  = { 232, 200, 110 }
local GREEN = { 120, 220, 150 }
local DIM   = { 184, 168, 156 }
local WARN  = { 238, 85, 68 }

-- ---------------------------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------------------------
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

-- Level breakpoints used across the Soul kits: Lv10 / 30 / 50 / 70+.
local function tier(lvl, a, b, c, d)
    lvl = tonumber(lvl) or 0
    if lvl >= 70 then return d end
    if lvl >= 50 then return c end
    if lvl >= 30 then return b end
    return a
end

local function secs(n)
    n = math.max(0, math.ceil(tonumber(n) or 0))
    if n >= 60 then return ('%d:%02d'):format(math.floor(n / 60), n % 60) end
    return ('%ds'):format(n)
end

local function plural(n, one, many)
    return (n == 1) and one or many
end

local function L(head, text, color) return { head = head, text = text, color = color } end
local SEP = { sep = true }

-- ---------------------------------------------------------------------------------------------
-- role identity
-- ---------------------------------------------------------------------------------------------
local ROLE_NAME = { tank = 'Tank', healer = 'Healer', support = 'Support', damage = 'Damage' }

local ROLE_PLAY = {
    tank    = 'Stands in front, holds enemy attention and soaks hits so the party does not have to.',
    healer  = 'Keeps the party alive while still fighting, instead of standing back and only casting.',
    support = 'Strengthens the party and weakens enemies, so everyone else hits harder and lasts longer.',
    damage  = 'Turns every action into offense. No self-healing, all of the power goes into killing things.',
}

local ROLE_SCALE = {
    tank    = 'Barriers and mends scale off your Max HP and VIT, and you hold threat through Enmity rather than raw weapon damage.',
    healer  = 'Healing scales off your healing potency and Max HP, and melee or weaponskill tempo is converted into party healing.',
    support = 'Power scales with your level and support stats (potency and duration). You boost the party rather than deal damage.',
    damage  = 'All of it channels into offense with zero self-healing, so power scales with your damage stats and weaponskills.',
}

-- ---------------------------------------------------------------------------------------------
-- Soul header data (signature weapon + how it plays). Souls not listed fall back to their role text.
-- ---------------------------------------------------------------------------------------------
local SOULS = {
    commander      = { w = 'Any weapon', p = 'Battlefield tactician. Weaves short-cooldown party and mark abilities that grow stronger as you level, at the cost of some swing uptime.' },
    berserker      = { w = 'Any weapon', p = 'Unrelenting fury. Berserk, Blood Rage and Warcry are pushed into heavy Attack, Double Attack and weaponskill damage.' },
    spartan        = { w = 'Polearm + Buckler', p = 'Frontline wall. Damage you take and block turns into Grit, which Polearm weaponskills cash in for big barriers and heavy threat.' },
    sensei         = { w = 'Staff', p = 'Agile staff master. Dodges and parries incoming blows, ripostes misses, and anchors threat through Counterstance.' },
    chiweaver      = { w = 'Bare fists only', p = 'Empty-handed healer. Landing melee Chi bolts and ranged hand-to-hand weaponskills builds Chi Flow, which powers party-wide Chi Blast heals. Runs on zero MP.', scale = 'Runs purely on melee Chi Flow with zero MP. More Chi means stronger healing and more debuffs cleansed.' },
    blackbelt      = { w = 'Hand-to-Hand', p = 'Pure hand-to-hand striker. Gives up weapon variety for relentless kicks, Double Attack, crits and constant weaponskill flow.' },
    bishop         = { w = 'Club', p = 'Proactive white mage. Cure healing and overhealing become Stoneskin barriers, and Club weaponskills fire free area Cures.' },
    necromancer    = { w = 'Scythe', p = 'Commands undead thralls to tank and cast, drains life through weaponskills, and detonates thralls for burst damage.' },
    crimsonduelist = { w = '1H Sword, empty off-hand', p = 'Frontline duelist. Parries and ripostes, and gets tougher for every enfeeble on the enemy, backed by instant barriers.' },
    templar        = { w = 'Club + Shield', p = 'Holy frontliner healer. Single-target Cures splash to the whole party as heal-over-time, and melee hits pulse extra healing.' },
    aegistemplar   = { w = 'Club + Shield', p = 'Silver Aegis guardian. Intercepts damage for nearby allies and builds Zeal from blocks to power holy auras.' },
    dreadnought    = { w = 'Scythe', p = 'Abyssal blood-knight. Drains turn into an HP pool and Blood Tithe, which become Dread Spikes shields; Scythe weaponskills heal you back.' },
    adventurer     = { w = 'Dual Dagger / Sword', p = 'Wandering troubadour. Dual-wield melee that builds Cadence, follows weaponskills with Sonic strikes and hastes the party with Encore.' },
    musician       = { w = 'Instrument + songs', p = 'Lyrical mage. Turns Threnodies, Requiems and Elegies into fast elemental nukes that can Magic Burst.' },
    minstrel       = { w = 'Instrument + songs', p = 'Song tank. Lullaby, Elegy and Requiem draw heavy threat while Minne, Paeon and Scherzo keep you alive.' },
    alphawarden    = { w = '1H Axe', p = 'Tank bonded to a guardian beast. Splits damage with your pet, mirrors heals to it, and uses reworked Ready skills for threat.' },
    huntsman       = { w = 'Ranged weapon + pet', p = 'Pack ranger. Bond with a Glacial Tusker to hold bosses, or a Volcanic Saurian to boost the party\'s offense.' },
    flintlock      = { w = 'Gun', p = 'Pure damage Corsair. Chambers a shot, detonates Powder Marks with Quick Draw, never runs out of bullets and never heals.' },
    gambler        = { w = 'Gun', p = 'Pure support Corsair. Rolls are made safer, Lucky and XI rolls overdrive, and Quick Draw tightens party ability cooldowns.' },
    buccaneer      = { w = '1H Sword + Gun', p = 'Pure tank Corsair. Single-target pistol shots hold threat and charge Grapeshot, which Quick Draw turns into a Stoneskin barrier.' },
    vampire        = { w = 'Dagger / Throwing', p = 'Blood-dancer healer. Turns the damage you deal into party lifesteal and barriers, and detonates Finishing Moves on weaponskills. Zero MP.' },
    bladewheel     = { w = 'Chakram (throwing)', p = 'Ranged dancer. Throws your chakram from out of melee range and lets Steps, Flourishes and Sambas work at range.' },
    miragesentinel = { w = 'Dual Daggers', p = 'Acrobatic frontline dancer. Steps and Dagger weaponskills build Finishing Moves that Flourishes turn into barriers, with Fan Dance cutting damage.' },
    wyvernheart    = { w = 'Polearm', p = 'Dragoon healer. Polearm weaponskills, Jumps and Spirit Link build Wyrmscale that fuels party heals, while your wyvern patches up whoever is lowest.' },
    verdant        = { w = 'Club / Staff', p = 'Nature healer. Your Luopan pulses heals, MP and Barkskin every few seconds, and weaponskills trigger an extra surge.' },
    magus          = { w = 'Dual-wield (Sword / Club)', p = 'Blue-magic healer. Healing spells splash to the party, dual-wield hits build Azure Catalyst, and linked blades siphon HP and MP to allies.' },
    azurebastion   = { w = 'Dual-wield (Sword / Club)', p = 'Monster-forged frontliner. Physical Blue Magic builds Chitin Carapace for mitigation while holding threat and weaving barriers.' },
    kagemusha      = { w = 'Dual Katanas', p = 'Shadow tank. Broken Utsusemi shadows turn into Kawarimi Ash, which Katana weaponskills spend to restore shadows and HP.' },
    ronin          = { w = 'Great Katana', p = 'Masterless tank. Mind\'s Eye counters incoming swings, and Mushin defers part of each hit into a Stagger pool you purify with Tachi skills.' },
    imperialarcher = { w = 'Bow + Great Katana', p = 'Skirmisher. Shoots from range when out of melee and chains Tachi and Archery weaponskills together.' },
    warlord        = { w = 'Great Katana', p = 'Battlefield supporter. Channels Ashura stacks and Onimaru skillchains into party-wide TP, HP and MP surges while sundering enemy armor.' },
    celestial      = { w = 'Avatar conduit', p = 'Summoner healer. Your avatar projects a healing sanctuary, resets your wards faster and pulses Starlight Mend.' },
    animist        = { w = 'Hand-to-Hand', p = 'Martial automaton healer. Light, Water and Earth Maneuvers power a built-in white-magic automaton.' },
    vanguard       = { w = 'Hand-to-Hand', p = 'Automaton tank. Your Valoredge puppet draws threat on single targets and shares damage with you through Clockwork Bulwark.' },
    pugilist       = { w = 'Hand-to-Hand', p = 'Tandem striker. Hand-to-hand weaponskills open a window where you and your automaton hit together.' },
    inquisitor     = { w = 'Rune sword', p = 'Ward tank. Carries three runes that are never lost to your abilities, ripostes when you parry and switches between physical and elemental stances.' },
    spellblade     = { w = 'Great Sword', p = 'Elemental spellweaver. Rune Edge strikes build Conduction and MP, which prime Runic Bolt and Runic Sever for faster, cheaper, harder spells. Damage only.' },
    lifebinder     = { w = 'Rune sword', p = 'Rune healer. Vivacious Pulse becomes a short-cooldown party heal, with runes driving Regen, Refresh, Stoneskin and cleanses.' },
    medic          = { w = 'Staff / Light Arts', p = 'Light Arts scholar. Calls the Eos faerie, sublimates safely, and auto-applies Accession to Cure and Regen spells.' },
    sage           = { w = 'Staff / Dark Arts', p = 'Dark Arts scholar. Calls the Titania faerie, keeps Ebullience up and hits harder with Helix and elemental magic.' },
}

local function resolveSoul(entry)
    local d = SOULS[entry.key]
    local role = entry.role
    local p = d and d.p or ROLE_PLAY[role]
    local scale = d and d.scale or ROLE_SCALE[role]
    return d and d.w or nil, p, scale
end

function M.soul(entry, ctx)
    local weapon, play, scale = resolveSoul(entry)
    local lines = {
        L('How It Plays', play),
        L('How It Scales', scale),
    }
    local lvl = tonumber(ctx and ctx.lvl) or 0
    if lvl > 0 and lvl < 10 then
        lines[#lines + 1] = L('Locked', 'Soul abilities unlock at level 10.', WARN)
    end
    return { weapon = weapon, lines = lines, role = ROLE_NAME[entry.role] }
end

-- ---------------------------------------------------------------------------------------------
-- Gauge / pip tooltips for the 12 wired Souls
-- ---------------------------------------------------------------------------------------------
local E = {}

E.spartan = {
    pips = {
        core  = 'Build: taking hits and blocking grants Grit. Spend: any Polearm weaponskill burns all your Grit into a protective barrier and heavy Enmity.',
        scale = 'The barrier is a share of your Max HP (and VIT makes you tougher), not weapon damage. Enmity keeps enemies pointed at you.',
        live  = function(c)
            local g = math.floor(num(c.kv, 'grit'))
            if g <= 0 then return 'No Grit yet. Take a hit or block to start building.' end
            local per = tier(c.lvl, 4, 5, 6, 7)
            return ('%d Grit: a Polearm weaponskill now would raise a barrier of about %d%% of your Max HP.'):format(g, math.min(g * per, 40))
        end,
        nxt   = function(c)
            local g = math.floor(num(c.kv, 'grit'))
            if g >= 5 then return 'Grit is full. Use a Polearm weaponskill to cash it in.' end
            return ('Each Grit adds about %d%% more barrier. At 5 Grit the barrier is as big as it gets.'):format(tier(c.lvl, 4, 5, 6, 7))
        end,
    },
    bar = {
        core  = 'Spend 2 Grit on Phalanx Ward for a short window of heavy blocking and reduced damage while you hold the enemy\'s attention.',
        scale = 'Block chance, damage reduction and threat all grow with your level and Max HP/VIT.',
        live  = function(c)
            local r = num(c.kv, 'ward_rem')
            if r > 0 then return ('Phalanx Ward is up for %s: you block more, take less damage and cannot be knocked back.'):format(secs(r)) end
            return 'Phalanx Ward is not active.'
        end,
        nxt   = function(c)
            if num(c.kv, 'ward_rem') > 0 then return 'Keep taking hits. Landing blocks while it is up refills Grit.' end
            if num(c.kv, 'grit') >= 2 then return 'You have the 2 Grit needed. Phalanx Ward is ready when its cooldown allows.' end
            return 'Reach 2 Grit to use Phalanx Ward.'
        end,
    },
}

E.dreadnought = {
    bar = {
        core  = 'Build: Absorb spells and Abyssal Cleave add Blood Tithe. Spend: Dread Spikes turns Tithe into a bigger HP shield, and Scythe weaponskills trigger Blood Reap healing.',
        scale = 'Shields and healing scale off your Max HP and VIT. Enmity from Dread Spikes and Cleave keeps threat on you.',
        live  = function(c)
            local t = math.floor(num(c.kv, 'tithe'))
            local reap = num(c.kv, 'reap_rem')
            local s = ('%d Tithe: Dread Spikes would shield about %d%% of your Max HP.'):format(t, 25 + 5 * t)
            if reap > 0 then s = s .. (' Blood Reap is active for %s, so Scythe weaponskills heal you extra.'):format(secs(reap)) end
            return s
        end,
        nxt   = function(c)
            local t = math.floor(num(c.kv, 'tithe'))
            if t >= 3 then return 'Tithe is full. Dread Spikes is at its strongest (40% Max HP shield).' end
            return 'One more Tithe adds +5% to the Dread Spikes shield. At 3 it peaks at 40%.'
        end,
    },
}

E.wyvernheart = {
    bar = {
        core  = 'Build: Polearm weaponskills, Jumps and Spirit Link add Wyrmscale. Spend: Restoring Breath spends your stacks to heal the party.',
        scale = 'Healing is a share of your Max HP, boosted by VIT/MND, not weapon damage. Your wyvern separately tops up the lowest-HP ally.',
        live  = function(c)
            local n = math.floor(num(c.kv, 'wyrmscale'))
            local rem = num(c.kv, 'wyrmscale_rem')
            local s = ('%d Wyrmscale: Restoring Breath would heal the party for about %d%% of your Max HP'):format(n, tier(c.lvl, 14, 20, 26, 32))
            s = s .. (n >= 3 and ' and wrap them in a Stoneskin.' or '.')
            if rem > 0 then s = s .. (' Stacks fade in %s.'):format(secs(rem)) end
            return s
        end,
        nxt   = function(c)
            local n = math.floor(num(c.kv, 'wyrmscale'))
            if n >= 3 then return 'Wyrmscale is full. Spend it with Restoring Breath for the Stoneskin bonus.' end
            return ('Reach 3 Wyrmscale (%d more) so Restoring Breath also shields the party.'):format(3 - n)
        end,
    },
}

E.buccaneer = {
    pips = {
        core  = 'Build: Point-Blank Pistol weaponskills and Grapeshot Broadside add Grapeshot. Spend: Quick Draw consumes it into a Salt Spray Stoneskin barrier.',
        scale = 'The barrier is a share of your Max HP. Single-target pistol shots generate threat through Enmity, not raw damage.',
        live  = function(c)
            local g = math.floor(num(c.kv, 'grapeshot'))
            if g <= 0 then return 'No Grapeshot loaded. Land a Point-Blank Pistol weaponskill to build it.' end
            return ('%d Grapeshot: Quick Draw would raise a barrier of about %d%% of your Max HP.'):format(g, g * 6)
        end,
        nxt   = function(c)
            local g = math.floor(num(c.kv, 'grapeshot'))
            if g >= 3 then return 'Grapeshot is full (18% Max HP barrier). Use Quick Draw.' end
            return ('Each Grapeshot adds 6%% more barrier. %d more fills it.'):format(3 - g)
        end,
    },
    bar = {
        core  = 'Salt Spray is the Stoneskin barrier your Quick Draw raised from Grapeshot.',
        scale = 'Its size comes from your Max HP and how much Grapeshot you spent.',
        live  = function(c)
            local ss = num(c.kv, 'saltspray')
            if ss > 0 then return ('Salt Spray will absorb the next %d damage you take.'):format(math.floor(ss)) end
            return 'No barrier up.'
        end,
        nxt   = function() return 'Build Grapeshot, then Quick Draw to raise a new barrier.' end,
    },
}

E.magus = {
    pips = {
        core  = 'Build: dual-wield hits add Azure Catalyst. Spend: at 5 stacks, or on a Sword/Club weaponskill, an Azure Mending Wave heals the whole party.',
        scale = 'You heal through melee tempo: the wave scales with your Max HP and healing potency, and you draw little threat.',
        live  = function(c)
            local n = math.floor(first(c.kv, 'catalyst', 'catalyst_stacks'))
            local pct = tier(c.lvl, 12, 16, 20, 24)
            local s = ('%d/5 Catalyst: the next Mending Wave heals the party for about %d%% of your Max HP and restores some MP.'):format(n, pct)
            if n >= 5 then s = s .. ' It fires on your next hit.' end
            return s
        end,
        nxt   = function(c)
            local n = math.floor(first(c.kv, 'catalyst', 'catalyst_stacks'))
            if n >= 5 then return 'Catalyst is full. Keep swinging to release the wave.' end
            return ('%d more dual-wield %s will release a Mending Wave.'):format(5 - n, plural(5 - n, 'hit', 'hits'))
        end,
    },
    bar = {
        core  = 'Osmotic Conduit links your blades to the party so your swings feed them HP and MP.',
        scale = 'The siphon is a share of your Max HP and MP per swing, so more swings means more healing.',
        live  = function(c)
            local r = num(c.kv, 'conduit_rem')
            if r > 0 then return ('Conduit is up for %s: each swing siphons HP and MP to the party and you take less magic damage.'):format(secs(r)) end
            return 'Conduit is not active.'
        end,
        nxt   = function(c)
            if num(c.kv, 'conduit_rem') > 0 then return 'Keep attacking while it lasts.' end
            return 'Use Osmotic Conduit when the party needs sustain.'
        end,
    },
}

E.azurebastion = {
    pips = {
        core  = 'Build: physical Blue Magic such as Head Butt and Sudden Lunge grants Chitin Carapace. Spend: the stacks harden you passively, and at 3 or more your defensive spells get stronger.',
        scale = 'Protection scales off Max HP and VIT, and the physical spells you build with also generate heavy threat.',
        live  = function(c)
            local n = math.floor(first(c.kv, 'carapace', 'chitin_stacks'))
            if n <= 0 then return 'No Carapace. Cast a physical Blue Magic spell to start.' end
            local s = ('%d Carapace: about %d%% more defense and %d%% less damage taken.'):format(n, 4 * n, 3 * n)
            if n >= 3 then s = s .. ' Your defensive spells are also stronger.' end
            return s
        end,
        nxt   = function(c)
            local n = math.floor(first(c.kv, 'carapace', 'chitin_stacks'))
            if n >= 5 then return 'Carapace is full. Keep casting to hold it before it fades.' end
            if n < 3 then return ('Reach 3 Carapace (%d more) to power up your defensive spells.'):format(3 - n) end
            return 'Each extra stack adds more defense and damage reduction, up to 5.'
        end,
    },
    bar = {
        core  = 'Diamond Shell is a protective ward you keep up while tanking.',
        scale = 'It leans on your Max HP and defense to keep damage off you.',
        live  = function(c)
            local r = num(c.kv, 'shell_rem')
            if r > 0 then return ('Diamond Shell is protecting you for %s.'):format(secs(r)) end
            return 'Diamond Shell is not active.'
        end,
        nxt   = function(c)
            if num(c.kv, 'shell_rem') > 0 then return 'Refresh it before it ends if the fight continues.' end
            return 'Recast it before a big hit comes.'
        end,
    },
}

E.gambler = {
    pips = {
        core  = 'Build: each Phantom Roll you land fills a roll slot (up to 3 at once). Spend: rolls run until they expire, and Lucky or XI rolls trigger Overdrive.',
        scale = 'Roll strength scales with your level, CHR and AGI. It is pure support, so you boost the party instead of dealing damage.',
        live  = function(c)
            local r = math.floor(num(c.kv, 'rolls'))
            local s = ('%d/3 rolls active.'):format(r)
            if num(c.kv, 'overdrive') > 0 then
                s = s .. ' Overdrive is on, so your rolls are working at 150% strength.'
            end
            return s
        end,
        nxt   = function(c)
            local r = math.floor(num(c.kv, 'rolls'))
            if r >= 3 then return 'All three roll slots are in use. Keep them refreshed.' end
            return ('Roll again to fill another slot (%d open).'):format(3 - r)
        end,
    },
    bar = {
        core  = 'Double-Up lets you push a roll for a better result. Pushing too far can bust it, which costs House Debt.',
        scale = 'The roll total decides how strong the buff is. Safe Standing keeps rolls of 8 and 9 from being wasted.',
        live  = function(c)
            local debt = num(c.kv, 'debt_rem')
            if debt > 0 then return ('House Debt for %s: the house is collecting for your last gamble.'):format(secs(debt)) end
            local du = num(c.kv, 'du_rem')
            local tot = math.floor(num(c.kv, 'roll_tot'))
            if du > 0 then return ('Double-Up window open for %s (roll total %d).'):format(secs(du), tot) end
            return 'No Double-Up window open.'
        end,
        nxt   = function(c)
            if num(c.kv, 'debt_rem') > 0 then return 'Wait it out before gambling again.' end
            if num(c.kv, 'du_rem') > 0 then return 'Double-Up now, or hold if your total is already good.' end
            return 'Roll to open a Double-Up window.'
        end,
    },
}

E.miragesentinel = {
    pips = {
        core  = 'Build: Steps and Dagger weaponskills add Finishing Moves. Spend: Flourishes turn them into a Stoneskin barrier and a cleanse.',
        scale = 'Barriers are a share of your Max HP per Finishing Move. Steps draw threat, and VIT/DEX keep you standing.',
        live  = function(c)
            local fm = math.floor(num(c.kv, 'fm'))
            if fm <= 0 then return 'No Finishing Moves. Land a Step or a Dagger weaponskill.' end
            return ('%d Finishing %s: a Flourish now would shield about %d%% of your Max HP.'):format(fm, plural(fm, 'Move', 'Moves'), 3 * fm)
        end,
        nxt   = function(c)
            local fm = math.floor(num(c.kv, 'fm'))
            if fm >= 5 then return 'Finishing Moves are full. Spend them with a Flourish.' end
            return ('Each Finishing Move adds 3%% more barrier. %d more fills the gauge.'):format(5 - fm)
        end,
    },
    bar = {
        core  = 'Aegis Waltz is the Stoneskin barrier your Flourishes raised.',
        scale = 'Its size comes from your Max HP and how many Finishing Moves you spent.',
        live  = function(c)
            local hp = num(c.kv, 'aegis_hp')
            if hp > 0 then return ('Aegis Waltz will absorb the next %d damage.'):format(math.floor(hp)) end
            return 'No barrier up.'
        end,
        nxt   = function() return 'Build Finishing Moves, then Flourish to raise a new barrier.' end,
    },
}

E.kagemusha = {
    pips = {
        core  = 'Build: whenever an Utsusemi shadow breaks you gain Kawarimi Ash. Spend: Katana weaponskills spend 3 Ash to restore a shadow and heal you.',
        scale = 'Healing is a share of your Max HP, and your protection comes from keeping shadows up. Zero ninja tools needed.',
        live  = function(c)
            local a = math.floor(num(c.kv, 'ash'))
            if a >= 3 then
                return ('%d Ash: a Katana weaponskill now restores a shadow and heals about %d%% of your Max HP.'):format(a, tier(c.lvl, 8, 10, 12, 14))
            end
            return ('%d Ash: not enough to spend yet.'):format(a)
        end,
        nxt   = function(c)
            local a = math.floor(num(c.kv, 'ash'))
            if a >= 3 then return 'Spend 3 Ash on your next Katana weaponskill.' end
            return ('%d more Ash unlocks the shadow-and-heal on your weaponskill.'):format(3 - a)
        end,
    },
    bar = {
        core  = 'Ash fades with time, so it is meant to be spent, not hoarded.',
        scale = 'The more shadows that break, the more Ash you can bank.',
        live  = function(c)
            local r = num(c.kv, 'ash_rem')
            if r > 0 then return ('Your Ash fades in %s.'):format(secs(r)) end
            return 'No Ash banked.'
        end,
        nxt   = function(c)
            if num(c.kv, 'ash_rem') > 0 then return 'Use a Katana weaponskill before it fades.' end
            return 'Let shadows absorb hits to earn Ash.'
        end,
    },
}

E.ronin = {
    pips = {
        core  = 'Build: Third Eye and Meditate charge Mind\'s Eye. Spend: each charge counters one melee swing or single-target enemy skill, gaining TP and heavy Enmity.',
        scale = 'You hold threat through counters and Enmity, not weapon damage. Needs a Great Katana equipped.',
        live  = function(c)
            local m = math.floor(num(c.kv, 'minds_eye'))
            if m <= 0 then return 'No Mind\'s Eye charges. Use Third Eye.' end
            return ('%d %s ready: the next %d %s will be countered.'):format(m, plural(m, 'charge', 'charges'), m, plural(m, 'attack', 'attacks'))
        end,
        nxt   = function(c)
            local m = math.floor(num(c.kv, 'minds_eye'))
            if m >= 3 then return 'Mind\'s Eye is full.' end
            return ('Third Eye or Meditate can add %d more %s.'):format(3 - m, plural(3 - m, 'charge', 'charges'))
        end,
    },
    bar = {
        core  = 'Mushin defers part of every hit you take into a Stagger pool that bleeds over time. Tachi weaponskills, Blade Bash and Meditate purify it.',
        scale = 'The pool is a share of the damage you are hit for, so tougher hits defer more. Purifying removes it before it lands.',
        live  = function(c)
            local pool = math.floor(num(c.kv, 'stagger_pool'))
            local ticks = math.floor(num(c.kv, 'stagger_ticks'))
            if pool <= 0 then return 'Steady: no damage is being deferred.' end
            return ('%d damage is deferred and will land over %d %s.'):format(pool, ticks, plural(ticks, 'tick', 'ticks'))
        end,
        nxt   = function(c)
            if num(c.kv, 'stagger_pool') > 0 then return 'Use a Tachi weaponskill, Blade Bash or Meditate to purify it.' end
            return 'Nothing to purify.'
        end,
    },
}

E.spellblade = {
    pips = {
        core  = 'Build: Rune Edge strikes on your Great Sword build Prepared charges and MP. Spend: Runic Bolt and Runic Sever use the charges to cast faster, cheaper and harder.',
        scale = 'Damage only: your power scales with INT, STR, Great Sword skill, Elemental skill and how many runes you carry. There is no self-healing.',
        live  = function(c)
            local p = math.floor(first(c.kv, 'prep_stacks', 'prep'))
            if p <= 0 then return 'No Prepared charges. Land Rune Edge hits to build them.' end
            return ('%d Prepared: Runic Bolt hits about %d%% harder, casts %.1fs faster and costs %d%% less MP.'):format(p, 10 * p, 0.5 * p, 15 * p)
        end,
        nxt   = function(c)
            local p = math.floor(first(c.kv, 'prep_stacks', 'prep'))
            if p >= 3 then return 'Prepared is full. Fire Runic Bolt or Runic Sever.' end
            return ('%d more Prepared makes your next spell stronger still.'):format(3 - p)
        end,
    },
}

E.chiweaver = {
    bar = {
        core  = 'Build: every landed Chi bolt adds a stack, ranged hand-to-hand weaponskills add several, and the Boost ability adds more. Spend: Chi Blast heals the whole party and cleanses debuffs.',
        scale = 'Runs purely on melee Chi Flow with zero MP. More Chi means stronger healing power and more debuffs cleansed, and Chi fades when Boost runs out.',
        live  = function(c)
            local s = math.floor(math.max(first(c.kv, 'chi_stacks', 'chi'), (c.boost and c.boost.stacks) or 0))
            local pot = math.floor(s / 5)
            local cl = (s >= 80 and 3) or (s >= 50 and 2) or (s >= 25 and 1) or 0
            local mult = 0.50 + (s * 0.045) + ((s * s) / 10000.0) * 1.55
            local out = ('%d Chi: +%d%% Healing Power, +%d Magic Accuracy and Attack. Chi Blast heals about %.1fx its base amount'):format(s, pot, pot, mult)
            if cl > 0 then
                out = out .. (' and cleanses %d %s.'):format(cl, plural(cl, 'debuff', 'debuffs'))
            else
                out = out .. ' but cleanses nothing yet.'
            end
            local rem = c.boost and c.boost.remSec or 0
            if rem > 0 and c.boost.at then
                rem = math.max(0, rem - (os.clock() - c.boost.at))
                if rem > 0 then out = out .. (' Boost lasts %s.'):format(secs(rem)) end
            end
            return out
        end,
        nxt   = function(c)
            local s = math.floor(math.max(first(c.kv, 'chi_stacks', 'chi'), (c.boost and c.boost.stacks) or 0))
            if s >= 100 then return 'Chi is maxed out. Spend it with Chi Blast.' end
            for _, step in ipairs({ { 25, 'cleanse 1 debuff' }, { 50, 'cleanse 2 debuffs' }, { 80, 'cleanse 3 debuffs' }, { 100, 'reach maximum power' } }) do
                if s < step[1] then
                    return ('Reach %d Chi (%d more) to %s.'):format(step[1], step[1] - s, step[2])
                end
            end
            return ''
        end,
    },
}

local KEY_GEM = { pips = true, bar = true }

local function build(def, which, ctx)
    local d = def[which]
    if not d then return nil end
    local lines = {
        L('Core Loop', d.core),
        L('How It Scales', d.scale),
        SEP,
    }
    local okL, live = pcall(d.live, ctx)
    local okN, nxt = pcall(d.nxt, ctx)
    if okL and live then lines[#lines + 1] = L('Right Now', live, GOLD) end
    if okN and nxt and nxt ~= '' then lines[#lines + 1] = L('Next Threshold', nxt, GREEN) end
    return lines
end

function M.element(soulKey, which, ctx)
    local def = E[soulKey]
    if not def or not KEY_GEM[which] then return nil end
    -- A single-element Soul reports its only element for either hover target.
    if not def[which] then which = def.pips and 'pips' or 'bar' end
    ctx = ctx or {}
    ctx.kv = ctx.kv or {}
    return build(def, which, ctx)
end

function M.isWired(soulKey)
    return E[soulKey] ~= nil
end

-- ---------------------------------------------------------------------------------------------
-- ox_buffs status icons
-- ---------------------------------------------------------------------------------------------
function M.buff(b, now, fmtTime)
    local e = b.entry
    local title = e and e.name or ('Effect #' .. tostring(b.iconId))
    local lines = {}
    local rem = b.expiresAt and math.max(0, b.expiresAt - now) or nil
    lines[#lines + 1] = { text = rem and ('Remaining: ' .. fmtTime(rem)) or 'Lasts until removed', color = DIM }
    if e and e.tooltip and e.tooltip ~= '' then
        lines[#lines + 1] = { text = e.tooltip }
    else
        lines[#lines + 1] = { text = 'A custom OverlordsXI effect is active.' }
    end
    if e then
        local who
        if e.isDebuff then who = 'Harmful effect.' elseif e.isShared then who = 'Shared with your party.' else who = 'Affects you.' end
        lines[#lines + 1] = { text = who, color = e.isDebuff and WARN or DIM }
    end
    return title, lines
end

return M
