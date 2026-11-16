--[[
* OverlordsXI Gear Manager (overlords_gear) - 22 Job & Crystal Spec Profiles
* Defines role flags, level-band weight tweaks, Job Ability sets, and
* OverlordsXI Soul Crystal specialization profiles for all 22 jobs.
--]]

local roles   = require('og.roles')
local db      = require('og.db')
local ox_sync = require('og.ox_sync')

local jobs = {}

local function deepCopy(t)
    if type(t) ~= 'table' then return t end
    local out = {}
    for k, v in pairs(t) do
        out[k] = deepCopy(v)
    end
    return out
end

local function mergeTweaks(baseMode, tweak)
    if not tweak then return baseMode end
    for _, field in ipairs({ 'Stats', 'Caps', 'Pet', 'PetCaps' }) do
        if tweak[field] then
            baseMode[field] = baseMode[field] or {}
            for k, v in pairs(tweak[field]) do
                if v == 0 then
                    baseMode[field][k] = nil
                else
                    baseMode[field][k] = v
                end
            end
        end
    end
    if tweak.Label then baseMode.Label = tweak.Label end
    return baseMode
end

-- Level-band general adjustments across melee/caster progression (1-30, 31-60, 61-75, 76-99)
local GLOBAL_BANDS = {
    {
        To = 30,
        Tweaks = {
            TP_Default = { Stats = { ACC = 1.0, ATT = 0.55, STR = 0.55, DEX = 0.45, DEF = 0.04 } },
            Idle       = { Stats = { DEF = 0.06, HP = 0.05, EVA = 0.06, REGEN = 3.0, REFRESH = 6.0 } },
        },
    },
    {
        To = 60,
        Tweaks = {
            TP_Default = { Stats = { ACC = 1.4, ATT = 0.55, STR = 0.50, DEX = 0.45, HASTE_GEAR = 2.8, DOUBLE_ATTACK = 2.2 } },
            Idle       = { Stats = { PDT = -2.5, MDT = -2.0, DEF = 0.04, REGEN = 3.0, REFRESH = 6.0 } },
        },
    },
    {
        To = 75,
        Tweaks = {
            TP_Default = { Stats = { HASTE_GEAR = 3.2, ACC = 1.0, ATT = 0.55, DOUBLE_ATTACK = 2.4, STORETP = 1.6, STR = 0.50, DEX = 0.40 } },
        },
    },
    {
        To = 99,
        Tweaks = {},
    },
}

-- All 22 Jobs + OverlordsXI Crystal Spec Definitions
jobs.Catalog = {
    WAR = {
        Fighter = true,
        Tweaks = {
            TP_Default = { Stats = { DOUBLE_ATTACK = 2.4, STORETP = 1.6, STR = 0.35 } },
            WS_Default = { Stats = { STR = 1.3, ALL_WSDMG_ALL_HITS = 3.5, ATT = 0.6 } },
        },
        Abilities = {
            ['Berserk']     = { Stats = { BERSERK_DURATION = 2, BERSERK_POTENCY = 2 } },
            ['Warcry']      = { Stats = { WARCRY_DURATION = 2, ENMITY = 1.5 } },
            ['Aggressor']   = { Stats = { AGGRESSOR_DURATION = 2 } },
            ['Provoke']     = { Base = 'Enmity' },
            ['Blood Rage']  = { Stats = { ENHANCES_BLOOD_RAGE = 2 } },
            ['Restraint']   = { Stats = { ENHANCES_RESTRAINT = 2 } },
            ['Mighty Strikes'] = { Stats = { MIGHTY_STRIKES_DURATION = 2 } },
        },
        Specs = {
            commander = {
                Tank = true,
                Tweaks = {
                    Idle       = { Stats = { PDT = -6.0, MDT = -5.0, HP = 0.05, REGEN = 3.0, MOVE_SPEED_GEAR_BONUS = 1.5 } },
                    TP_Default = {
                        Label = 'Engaged (Commander Tactical)',
                        Stats = { PDT = -4.5, MDT = -3.5, HASTE_GEAR = 3.0, STORETP = 1.8, DOUBLE_ATTACK = 2.0, ENMITY = 1.2, HP = 0.05, ACC = 0.8 },
                    },
                },
                Abilities = {
                    ['Tactical Breach']   = { Base = 'Enmity' },
                    ['Formation Bulwark'] = { Base = 'DT' },
                    ['Battle Cadence']    = { Base = 'Enmity' },
                    ['Rallying Horn']     = { Base = 'Enmity' },
                },
            },
            berserker = {
                Tweaks = {
                    TP_Default = {
                        Label = 'Engaged (Berserker Fury)',
                        Stats = { HASTE_GEAR = 3.4, DOUBLE_ATTACK = 2.8, TRIPLE_ATTACK = 3.6, CRITHITRATE = 1.8, CRIT_DMG_INCREASE = 1.2, STR = 0.55, ATT = 0.50, ACC = 0.70 },
                    },
                    WS_Default = {
                        Stats = { STR = 1.5, ALL_WSDMG_ALL_HITS = 4.0, CRIT_DMG_INCREASE = 1.2, ATT = 0.7 },
                    },
                },
            },
            gladiator = {
                Tank = true,
                Tweaks = {
                    Idle       = { Stats = { PDT = -7.0, MDT = -5.5, SHIELD = 0.8, DEF = 0.05, HP = 0.05 } },
                    TP_Default = {
                        Label = 'Engaged (Gladiator Shield & Club)',
                        Stats = { PDT = -5.5, MDT = -4.0, SHIELD = 1.0, HASTE_GEAR = 2.8, ENMITY = 1.5, STR = 0.45, MND = 0.35, ACC = 0.8, ATT = 0.4, DEF = 0.05 },
                    },
                },
            },
        },
    },

    MNK = {
        Fighter = true,
        Tweaks = {
            TP_Default = { Stats = { MARTIAL_ARTS = 2.5, KICK_ATTACK_RATE = 1.8, SUBTLE_BLOW = 0.5, HASTE_GEAR = 3.2, DOUBLE_ATTACK = 2.2, STR = 0.4, DEX = 0.4, VIT = 0.25 } },
            WS_Default = { Stats = { STR = 1.2, DEX = 0.8, VIT = 0.8, KICK_DMG = 0.8 } },
        },
        Abilities = {
            ['Chakra']        = { Stats = { CHAKRA_MULT = 3, VIT = 1.5, HP = 0.05 } },
            ['Focus']         = { Stats = { FOCUS_EFFECT = 2, ACC = 1.0 } },
            ['Dodge']         = { Stats = { DODGE_EFFECT = 2, EVA = 1.0 } },
            ['Footwork']      = { Stats = { KICK_DMG = 2, KICK_ATTACK_RATE = 2 } },
            ['Counterstance'] = { Stats = { COUNTER = 3, PDT = -3.0 } },
            ['Chi Blast']     = { Stats = { MND = 2.0 } },
        },
        Specs = {
            sensei = {
                Tank = true,
                Tweaks = {
                    Idle = {
                        Label = 'Idle (Sensei Staff Tank)',
                        Stats = { PDT = -7.0, MDT = -5.5, EVA = 0.4, EVASION = 0.5, PARRY = 0.6, COUNTER = 1.5, MEVA = 0.15, HP = 0.05 },
                    },
                    TP_Default = {
                        Label = 'Engaged (Sensei Staff Evasion/Counter)',
                        Stats = { COUNTER = 2.8, EVA = 0.6, EVASION = 0.7, PARRY = 1.0, PDT = -5.0, MDT = -4.0, HASTE_GEAR = 3.0, ACC = 0.9, AGI = 0.45, DEX = 0.45, VIT = 0.35, STORETP = 1.2 },
                    },
                },
            },
            blackbelt = {
                Tweaks = {
                    TP_Default = {
                        Label = 'Engaged (Black Belt H2H DPS)',
                        Stats = {
                            MARTIAL_ARTS = 2.8, KICK_ATTACK_RATE = 2.4, KICK_DMG = 1.4,
                            DOUBLE_ATTACK = 2.6, CRITHITRATE = 1.6, CRIT_DMG_INCREASE = 1.2,
                            STORETP = 1.8, SUBTLE_BLOW = 0.8, HASTE_GEAR = 3.4,
                            STR = 0.55, DEX = 0.45, ACC = 0.8, ATT = 0.55,
                        },
                    },
                    WS_Default = {
                        Stats = {
                            STR = 1.4, DEX = 1.0, VIT = 0.8, KICK_DMG = 1.0,
                            ALL_WSDMG_ALL_HITS = 4.0, ATT = 0.7, CRIT_DMG_INCREASE = 1.2,
                        },
                    },
                },
            },
            chiweaver = {
                Tweaks = {
                    Idle = {
                        Label = 'Idle (Chi Weaver Healer)',
                        Stats = { REGEN = 4.0, CURE_POTENCY = 2.0, MND = 0.65, HP = 0.04, PDT = -5.0, MDT = -4.0, ENMITY = -0.4, MEVA = 0.14 },
                    },
                    TP_Default = {
                        Label = 'Engaged (Chi Weaver Ranged Chi & Pulse)',
                        Stats = {
                            CURE_POTENCY = 3.2, MND = 0.95, MATT = 1.6, MACC = 1.2,
                            MARTIAL_ARTS = 2.2, HASTE_GEAR = 3.2, REGEN = 2.5,
                            STORETP = 1.6, ENMITY = -0.5, PDT = -2.0, MDT = -1.5,
                        },
                    },
                    WS_Default = {
                        Stats = { MND = 1.2, STR = 0.9, MATT = 1.2, MACC = 0.8, ALL_WSDMG_ALL_HITS = 3.5 },
                    },
                },
                Abilities = {
                    ['Resonant Chi']   = { Base = 'Cure' },
                    ['Tranquil Lotus'] = { Base = 'Cure' },
                    ['Inner Harmony']  = { Base = 'Cure' },
                },
            },
        },
    },

    WHM = {
        Caster = true,
        Meals  = { 'Precast', 'Cure_Precast', 'Cure', 'Cursna', 'Enhancing', 'Stoneskin', 'Regen', 'Enfeebling', 'Divine' },
        Tweaks = {
            Idle = { Stats = { REFRESH = 8.0, PDT = -4.0, MDT = -3.5, MEVA = 0.1 } },
        },
        Abilities = {
            ['Benediction']     = { Stats = { MND = 1.0, HP = 0.05 } },
            ['Afflatus Solace'] = { Base = 'Cure' },
            ['Devotion']        = { Stats = { HP = 0.15 } },
        },
    },

    BLM = {
        Caster = true,
        Meals  = { 'Precast', 'Nuke', 'Nuke_Acc', 'Burst', 'Dark', 'DrainAspir', 'Enfeebling', 'Enhancing', 'Stoneskin' },
        Tweaks = {
            Idle = { Stats = { REFRESH = 8.0, PDT = -4.0, MDT = -3.5, MP = 0.02 } },
        },
        Abilities = {
            ['Manafont']    = { Base = 'Nuke' },
            ['Elemental Seal'] = { Base = 'Enfeebling' },
            ['Mana Wall']   = { Stats = { MANA_WALL_DMG = -3, PDT = -5, MDT = -5 } },
        },
        Specs = {
            necromancer = {
                Fighter = true,
                Pet     = true,
                Meals   = { 'Precast', 'Nuke', 'Burst', 'Dark', 'DrainAspir', 'Enfeebling', 'Pet_Idle', 'Pet_TP', 'Pet_Magic' },
                Tweaks  = {
                    Idle = {
                        Label = 'Idle (Necromancer & Undead Pet)',
                        Stats = { REFRESH = 7.0, PDT = -4.5, MDT = -3.5, HP = 0.03 },
                        Pet   = { PDT = -4.0, MDT = -3.0, REGEN = 2.5 },
                    },
                    TP_Default = {
                        Label = 'Engaged (Necromancer Scythe)',
                        Stats = { HASTE_GEAR = 3.2, STORETP = 1.8, DOUBLE_ATTACK = 2.2, ACC = 0.9, ATT = 0.5, INT = 0.6, STR = 0.5, DARK = 0.5, PDT = -1.5 },
                        Pet   = { ACC = 0.5, ATT = 0.4, MATT = 0.8 },
                    },
                    WS_Default = {
                        Stats = { INT = 1.3, STR = 1.1, MATT = 1.2, ALL_WSDMG_ALL_HITS = 3.5, ATT = 0.6, ACC = 0.6 },
                    },
                },
            },
        },
    },

    RDM = {
        Fighter = true,
        Caster  = true,
        Meals   = { 'Precast', 'Cure', 'Enhancing', 'Stoneskin', 'Phalanx', 'Refresh', 'Regen', 'Enfeebling', 'Nuke', 'Burst', 'Dark' },
        Tweaks  = {
            Idle       = { Stats = { REFRESH = 8.0, PDT = -4.0, MDT = -3.5 } },
            TP_Default = { Stats = { HASTE_GEAR = 3.2, DOUBLE_ATTACK = 2.0, STORETP = 1.6, ENSPELL_DMG_BONUS = 2.0, ACC = 0.8, DEX = 0.4, INT = 0.2, MND = 0.2 } },
        },
        Abilities = {
            ['Chainspell'] = { Base = 'Enhancing' },
            ['Saboteur']   = { Stats = { ENHANCES_SABOTEUR = 3, MACC = 1.5, ENFEEBLE = 1.0 } },
            ['Convert']    = { Stats = { MP = 0.1, HP = 0.05 } },
        },
    },

    THF = {
        Fighter = true,
        Ranged  = true,
        Meals   = { 'TH', 'Preshot', 'Midshot' },
        Tweaks  = {
            TP_Default = { Stats = { TRIPLE_ATTACK = 3.5, DOUBLE_ATTACK = 2.2, HASTE_GEAR = 3.2, DUAL_WIELD = 2.0, DEX = 0.55, AGI = 0.35, CRITHITRATE = 1.4, CRIT_DMG_INCREASE = 1.0, ACC = 0.7 } },
            WS_Default = { Stats = { DEX = 1.4, AGI = 0.8, ALL_WSDMG_ALL_HITS = 3.5, CRIT_DMG_INCREASE = 1.0 } },
        },
        Abilities = {
            ['Sneak Attack'] = { Stats = { SNEAK_ATK_DEX = 3, DEX = 1.5, CRIT_DMG_INCREASE = 1.5 } },
            ['Trick Attack'] = { Stats = { TRICK_ATK_AGI = 3, AGI = 1.5, CRIT_DMG_INCREASE = 1.5 } },
            ['Steal']        = { Stats = { STEAL = 3 } },
            ['Despoil']      = { Stats = { DESPOIL = 3 } },
            ['Flee']         = { Stats = { FLEE_DURATION = 3 } },
            ['Accomplice']   = { Base = 'Enmity' },
            ['Collaborator'] = { Base = 'Enmity' },
        },
    },

    PLD = {
        Fighter = true,
        Tank    = true,
        Caster  = true,
        Meals   = { 'Tank_Engaged', 'Precast', 'Cure', 'Enhancing', 'Phalanx', 'Enmity', 'Divine', 'Midcast_Interrupt' },
        Tweaks  = {
            Idle       = { Stats = { PDT = -7.0, MDT = -5.5, SHIELD = 0.8, HP = 0.06, REFRESH = 4.0, REGEN = 3.0, DEF = 0.04 } },
            TP_Default = { Stats = { PDT = -5.5, MDT = -4.5, SHIELD = 0.8, HASTE_GEAR = 2.8, ENMITY = 1.2, HP = 0.05, ACC = 0.7, STORETP = 1.2, DOUBLE_ATTACK = 1.8 } },
        },
        Abilities = {
            ['Sentinel']     = { Stats = { SENTINEL_EFFECT = 2, ENMITY = 2.5 } },
            ['Rampart']      = { Stats = { RAMPART_DURATION = 2, HP = 0.06, ENMITY = 2.0 } },
            ['Shield Bash']  = { Stats = { SHIELD_BASH = 2, ENMITY = 2.0 } },
            ['Holy Circle']  = { Stats = { HOLY_CIRCLE_DURATION = 2, ENMITY = 1.5 } },
            ['Chivalry']     = { Stats = { MND = 1.5 } },
            ['Fealty']       = { Stats = { FEALTY_BONUS = 2, ENMITY = 2.0 } },
            ['Invincible']   = { Base = 'Enmity' },
        },
    },

    DRK = {
        Fighter = true,
        Caster  = true,
        Meals   = { 'Precast', 'Dark', 'DrainAspir', 'Enfeebling', 'Nuke' },
        Tweaks  = {
            TP_Default = { Stats = { HASTE_GEAR = 3.2, STORETP = 1.8, DOUBLE_ATTACK = 2.4, TRIPLE_ATTACK = 3.2, STR = 0.4, ACC = 0.75, ATT = 0.45 } },
            WS_Default = { Stats = { STR = 1.3, VIT = 0.7, INT = 0.5, ALL_WSDMG_ALL_HITS = 3.8, ATT = 0.65 } },
        },
        Abilities = {
            ['Souleater']   = { Stats = { SOULEATER_EFFECT = 3, HP = 0.05 } },
            ['Last Resort'] = { Stats = { DESPERATE_BLOWS = 3, HASTE_GEAR = 1.5 } },
            ['Weapon Bash'] = { Stats = { WEAPON_BASH = 2, ENMITY = 1.5 } },
            ['Arcane Circle'] = { Stats = { ARCANE_CIRCLE_DURATION = 2 } },
            ['Blood Weapon']  = { Stats = { ENHANCES_BLOOD_WEAPON = 2 } },
        },
    },

    BST = {
        Fighter = true,
        Pet     = true,
        Meals   = { 'Pet_Idle', 'Pet_TP', 'Pet_Magic' },
        Tweaks  = {
            Idle       = { Pet = { PDT = -4.0, MDT = -3.0, REGEN = 2.0 } },
            TP_Default = { Pet = { ACC = 0.5, ATT = 0.3, HASTE_GEAR = 1.5 } },
        },
        Abilities = {
            ['Call Beast']      = { Stats = { CALL_BEAST_DELAY = -2 } },
            ['Bestial Loyalty'] = { Stats = { CALL_BEAST_DELAY = -2 } },
            ['Reward']          = { Stats = { REWARD_HP_BONUS = 2, MND = 1.2 } },
            ['Charm']           = { Stats = { CHARM_CHANCE = 2, CHR = 1.5 } },
            ['Ready']           = { Base = 'Pet_TP' },
            ['Sic']             = { Base = 'Pet_TP' },
        },
    },

    BRD = {
        Caster = true,
        Meals  = { 'Precast', 'Song_Precast', 'Song', 'Song_Debuff', 'Cure', 'Enhancing', 'Stoneskin', 'Enfeebling' },
        Tweaks = {
            Idle       = { Stats = { REFRESH = 6.0, PDT = -4.5, MDT = -3.5, MOVE_SPEED_GEAR_BONUS = 2.0 } },
            TP_Default = { Stats = { HASTE_GEAR = 3.2, STORETP = 1.8, DOUBLE_ATTACK = 2.2, ACC = 0.85, DEX = 0.45, CHR = 0.3 } },
        },
        Abilities = {
            ['Nightingale'] = { Stats = { NIGHTINGALE = 2 } },
            ['Troubadour']  = { Stats = { TROUBADOUR = 2 } },
            ['Soul Voice']  = { Stats = { SOUL_VOICE = 2 } },
        },
    },

    RNG = {
        Fighter = true,
        Ranged  = true,
        Meals   = { 'Preshot', 'Midshot' },
        Tweaks  = {
            TP_Default = { Stats = { STORETP = 2.0, HASTE_GEAR = 3.0, RACC = 0.5, RATT = 0.4, AGI = 0.4, ACC = 0.7 } },
            WS_Default = { Stats = { AGI = 1.3, STR = 0.9, RATT = 0.8, RACC = 0.7, ALL_WSDMG_FIRST_HIT = 3.5 } },
        },
        Abilities = {
            ['Barrage']       = { Stats = { BARRAGE_ACC = 2, BARRAGE_COUNT = 10, RACC = 1.5, RATT = 1.0 } },
            ['Sharpshot']     = { Stats = { SHARPSHOT = 2, RACC = 1.5 } },
            ['Scavenge']      = { Stats = { SCAVENGE_EFFECT = 2 } },
            ['Camouflage']    = { Stats = { CAMOUFLAGE_DURATION = 2 } },
            ['Velocity Shot'] = { Stats = { VELOCITY_SHOT_RATT = 2, RATT = 1.0 } },
            ['Bounty Shot']   = { Base = 'TH' },
        },
    },

    SAM = {
        Fighter = true,
        Ranged  = true,
        Meals   = { 'Preshot', 'Midshot' },
        Tweaks  = {
            TP_Default = { Stats = { STORETP = 2.4, ZANSHIN = 1.4, HASTE_GEAR = 3.2, DOUBLE_ATTACK = 2.2, TRIPLE_ATTACK = 3.0, STR = 0.4, DEX = 0.35, ACC = 0.75 } },
            WS_Default = { Stats = { STR = 1.5, ALL_WSDMG_FIRST_HIT = 3.5, ALL_WSDMG_ALL_HITS = 3.5, ATT = 0.65, TP_BONUS = 0.012 } },
        },
        Abilities = {
            ['Meditate']       = { Stats = { MEDITATE_DURATION = 3 } },
            ['Warding Circle'] = { Stats = { WARDING_CIRCLE_DURATION = 2 } },
            ['Third Eye']      = { Stats = { THIRD_EYE_COUNTER_RATE = 2 } },
            ['Sengikori']      = { Stats = { SENGIKORI_BONUS = 2 } },
            ['Hasso']          = { Base = 'TP_Default' },
            ['Seigan']         = { Base = 'DT' },
        },
    },

    NIN = {
        Fighter = true,
        Tank    = true,
        Caster  = true,
        Meals   = { 'Precast', 'Ninjutsu_Buff', 'Ninjutsu_Nuke', 'Ninjutsu_Debuff', 'Enmity' },
        Tweaks  = {
            TP_Default = { Stats = { DUAL_WIELD = 2.2, HASTE_GEAR = 3.2, DOUBLE_ATTACK = 2.2, TRIPLE_ATTACK = 3.0, STORETP = 1.6, DEX = 0.45, AGI = 0.35, ACC = 0.8, EVA = 0.25 } },
            WS_Default = { Stats = { DEX = 1.2, STR = 1.0, AGI = 0.6, INT = 0.5, ALL_WSDMG_ALL_HITS = 3.5 } },
        },
        Abilities = {
            ['Yonin']  = { Base = 'Enmity' },
            ['Innin']  = { Base = 'Ninjutsu_Nuke' },
            ['Mijin Gakure'] = { Stats = { MATT = 2.0, INT = 1.0 } },
        },
    },

    DRG = {
        Fighter = true,
        Pet     = true,
        Meals   = { 'Jump', 'Pet_Idle', 'Pet_TP', 'Pet_Magic' },
        Tweaks  = {
            TP_Default = { Stats = { HASTE_GEAR = 3.2, DOUBLE_ATTACK = 2.4, TRIPLE_ATTACK = 3.2, STORETP = 1.8, STR = 0.45, DEX = 0.35, ACC = 0.75 }, Pet = { ACC = 0.4, REGEN = 1.0 } },
            WS_Default = { Stats = { STR = 1.4, VIT = 0.6, ALL_WSDMG_ALL_HITS = 3.8, CRIT_DMG_INCREASE = 1.0 } },
        },
        Abilities = {
            ['Jump']           = { Base = 'Jump' },
            ['High Jump']      = { Base = 'Jump' },
            ['Super Jump']     = { Base = 'Jump' },
            ['Spirit Jump']    = { Base = 'Jump' },
            ['Soul Jump']      = { Base = 'Jump' },
            ['Call Wyvern']    = { Stats = { WYVERN_LVL_BONUS = 5 } },
            ['Ancient Circle'] = { Stats = { ANCIENT_CIRCLE_DURATION = 2 } },
            ['Spirit Link']    = { Stats = { ENHANCES_SPIRIT_LINK = 2 } },
        },
    },

    SMN = {
        Caster = true,
        Pet    = true,
        Meals  = { 'Precast', 'Summoning_BP_Phys', 'Summoning_BP_Mag', 'Summoning_Ward', 'Pet_Idle', 'Pet_TP', 'Pet_Magic', 'Cure', 'Refresh' },
        Tweaks = {
            Idle = {
                Stats = { REFRESH = 8.0, AVATAR_PERPETUATION = -4.0, PDT = -3.0, MDT = -2.5 },
                Pet   = { PDT = -4.0, REGEN = 2.0 },
            },
        },
        Abilities = {
            ['Astral Flow'] = { Base = 'Summoning_BP_Mag' },
            ['Elemental Siphon'] = { Stats = { SUMMONING = 2.5 } },
            ['Mana Cede']   = { Stats = { ENHANCES_MANA_CEDE = 2 } },
        },
    },

    BLU = {
        Fighter = true,
        Caster  = true,
        Meals   = { 'Precast', 'Blue_Physical', 'Blue_Magical', 'Cure', 'Enhancing', 'Stoneskin' },
        Tweaks  = {
            Idle       = { Stats = { REFRESH = 6.0, PDT = -4.0, MDT = -3.0 } },
            TP_Default = { Stats = { DUAL_WIELD = 2.0, HASTE_GEAR = 3.2, DOUBLE_ATTACK = 2.2, TRIPLE_ATTACK = 3.0, STORETP = 1.7, DEX = 0.45, STR = 0.35, ACC = 0.8 } },
        },
        Abilities = {
            ['Chain Affinity'] = { Base = 'Blue_Physical' },
            ['Burst Affinity'] = { Base = 'Blue_Magical' },
            ['Diffusion']      = { Stats = { DIFFUSION = 2, BLUE = 1.0 } },
            ['Efflux']         = { Base = 'Blue_Physical' },
        },
    },

    COR = {
        Fighter = true,
        Ranged  = true,
        Meals   = { 'Preshot', 'Midshot', 'Nuke' },
        Tweaks  = {
            TP_Default = { Stats = { DUAL_WIELD = 1.8, HASTE_GEAR = 3.2, TRIPLE_ATTACK = 3.0, DOUBLE_ATTACK = 2.2, STORETP = 1.8, ACC = 0.8, RACC = 0.3 } },
            WS_Default = { Stats = { AGI = 1.3, STR = 1.0, MATT = 1.2, RATT = 0.7, ALL_WSDMG_FIRST_HIT = 3.5 } },
        },
        Abilities = {
            ['Phantom Roll'] = { Stats = { PHANTOM_ROLL = 5, PHANTOM_DURATION = 2, PDT = -2.0 } },
            ['Double-Up']    = { Stats = { PHANTOM_ROLL = 5, PHANTOM_DURATION = 2 } },
            ['Quick Draw']   = { Stats = { QUICK_DRAW_DMG = 2, MATT = 2.0, MACC = 1.5, AGI = 1.0 } },
            ['Random Deal']  = { Stats = { RANDOM_DEAL_BONUS = 2 } },
            ['Wild Card']    = { Stats = { WILD_CARD = 2 } },
            ['Triple Shot']  = { Stats = { TRIPLE_SHOT_RATE = 3 } },
        },
    },

    PUP = {
        Fighter = true,
        Pet     = true,
        Meals   = { 'Pet_Idle', 'Pet_TP', 'Pet_Magic' },
        Tweaks  = {
            TP_Default = {
                Stats = { MARTIAL_ARTS = 2.2, HASTE_GEAR = 3.2, DOUBLE_ATTACK = 2.2, STORETP = 1.5, DEX = 0.4, STR = 0.4, ACC = 0.75 },
                Pet   = { HASTE_GEAR = 2.2, ACC = 0.6, ATT = 0.4, STORETP = 1.0, PDT = -2.0 },
            },
        },
        Abilities = {
            ['Repair']      = { Stats = { REPAIR_POTENCY = 3 } },
            ['Maintenance'] = { Stats = { REPAIR_POTENCY = 2 } },
            ['Overdrive']   = { Base = 'Pet_TP' },
            ['Maneuver']    = { Stats = { OVERLOAD_THRESH = 2 } },
        },
    },

    DNC = {
        Fighter = true,
        Meals   = { 'Waltz', 'Step' },
        Tweaks  = {
            TP_Default = { Stats = { DUAL_WIELD = 2.0, HASTE_GEAR = 3.2, DOUBLE_ATTACK = 2.2, TRIPLE_ATTACK = 3.0, STORETP = 1.7, DEX = 0.55, CHR = 0.35, ACC = 0.8 } },
            WS_Default = { Stats = { DEX = 1.4, CHR = 0.9, ALL_WSDMG_ALL_HITS = 3.5, CRIT_DMG_INCREASE = 1.0 } },
        },
        Abilities = {
            ['Curing Waltz']     = { Base = 'Waltz' },
            ['Curing Waltz II']  = { Base = 'Waltz' },
            ['Curing Waltz III'] = { Base = 'Waltz' },
            ['Curing Waltz IV']  = { Base = 'Waltz' },
            ['Curing Waltz V']   = { Base = 'Waltz' },
            ['Divine Waltz']     = { Base = 'Waltz' },
            ['Divine Waltz II']  = { Base = 'Waltz' },
            ['Quickstep']        = { Base = 'Step' },
            ['Box Step']         = { Base = 'Step' },
            ['Stutter Step']     = { Base = 'Step' },
            ['Feather Step']     = { Base = 'Step' },
            ['Reverse Flourish'] = { Stats = { REVERSE_FLOURISH_EFFECT = 3 } },
            ['Climactic Flourish'] = { Stats = { CHR = 1.5, CRIT_DMG_INCREASE = 2.0 } },
            ['Violent Flourish'] = { Stats = { MACC = 1.5, ACC = 1.5, DEX = 0.8 } },
            ['Animated Flourish']= { Base = 'Enmity' },
        },
        Specs = {
            bladewheel = {
                Ranged = true,
                Meals  = { 'Preshot', 'Midshot', 'Waltz', 'Step' },
                Tweaks = {
                    TP_Default = {
                        Label = 'Engaged (Bladewheel Chakram)',
                        Stats = { RACC = 1.2, RATT = 1.0, AGI = 0.7, DEX = 0.7, CHR = 0.4, STORETP = 2.0, HASTE_GEAR = 3.0, CRITHITRATE = 1.6, CRIT_DMG_INCREASE = 1.2, ACC = 0.7 },
                    },
                    Midshot = {
                        Label = 'Ranged: Bladewheel Chakram Throw',
                        Stats = { RACC = 1.4, RATT = 1.2, AGI = 0.8, DEX = 0.8, CHR = 0.5, STORETP = 1.8, CRITHITRATE = 1.5, CRIT_DMG_INCREASE = 1.2 },
                    },
                    WS_Default = {
                        Stats = { DEX = 1.3, AGI = 1.3, CHR = 0.8, RATT = 1.0, RACC = 1.0, ALL_WSDMG_ALL_HITS = 3.8 },
                    },
                },
                Abilities = {
                    ['Throwing Stance'] = { Base = 'Midshot' },
                },
            },
        },
    },

    SCH = {
        Caster = true,
        Meals  = { 'Precast', 'Cure_Precast', 'Cure', 'Cursna', 'Enhancing', 'Stoneskin', 'Regen', 'Refresh', 'Helix', 'Nuke', 'Burst', 'Enfeebling', 'Dark', 'DrainAspir' },
        Tweaks = {
            Idle = { Stats = { REFRESH = 8.0, FAERIE_REFRESH = 12.0, PDT = -4.0, MDT = -3.5 } },
        },
        Abilities = {
            ['Light Arts']   = { Base = 'Enhancing' },
            ['Dark Arts']    = { Base = 'Nuke' },
            ['Sublimation']  = { Stats = { SUBLIMATION_BONUS = 4, HP = 0.05 } },
            ['Tabula Rasa']  = { Base = 'Precast' },
            ['Call Eos']     = { Base = 'Pet_Idle' },
            ['Call Titania'] = { Base = 'Pet_Magic' },
        },
        Specs = {
            medic = {
                Pet   = true,
                Meals = { 'Precast', 'Cure_Precast', 'Cure', 'Cursna', 'Enhancing', 'Stoneskin', 'Regen', 'Refresh', 'Pet_Idle' },
                Tweaks = {
                    Idle = {
                        Label = 'Idle (Medic & Eos Companion)',
                        Stats = { FAERIE_REFRESH = 16.0, REFRESH = 8.0, PDT = -4.5, MDT = -3.5, REGEN = 3.0 },
                        Pet   = { PDT = -4.0, REGEN = 3.0 },
                    },
                    Cure = {
                        Label = 'Midcast: Medic Cure',
                        Stats = { CURE_POTENCY = 4.0, CURE_POTENCY_II = 3.0, MND = 0.7, HEALING = 0.8, FAERIE_REFRESH = 5.0 },
                    },
                },
            },
            sage = {
                Pet   = true,
                Meals = { 'Precast', 'Helix', 'Nuke', 'Nuke_Acc', 'Burst', 'Enfeebling', 'Dark', 'DrainAspir', 'Pet_Magic' },
                Tweaks = {
                    Idle = {
                        Label = 'Idle (Sage & Titania Companion)',
                        Stats = { FAERIE_REFRESH = 16.0, REFRESH = 8.0, PDT = -4.0, MDT = -3.5 },
                        Pet   = { MATT = 2.0, MACC = 1.2 },
                    },
                    Nuke = {
                        Label = 'Midcast: Sage Dark Arts Nuke',
                        Stats = { MATT = 2.5, MAGIC_DAMAGE = 1.6, INT = 1.3, MACC = 1.0, ELEM = 0.7, FAERIE_REFRESH = 5.0 },
                    },
                },
            },
        },
    },

    GEO = {
        Caster = true,
        Pet    = true,
        Meals  = { 'Precast', 'Geomancy', 'Cure', 'Enhancing', 'Stoneskin', 'Nuke', 'Burst', 'Enfeebling', 'Dark', 'DrainAspir', 'Pet_Idle' },
        Tweaks = {
            Idle = {
                Stats = { REFRESH = 8.0, PDT = -4.0, MDT = -3.5 },
                Pet   = { PDT = -5.0, MDT = -4.0, REGEN = 3.5 },
            },
        },
        Abilities = {
            ['Full Circle']    = { Stats = { FULL_CIRCLE = 3 } },
            ['Life Cycle']     = { Stats = { LIFE_CYCLE_EFFECT = 3, HP = 0.08 } },
            ['Bolster']        = { Base = 'Geomancy' },
            ['Radial Arcana']  = { Base = 'Geomancy' },
            ['Mending Halation'] = { Base = 'Geomancy' },
        },
    },

    RUN = {
        Fighter = true,
        Tank    = true,
        Caster  = true,
        Meals   = { 'Precast', 'Enhancing_Precast', 'Enhancing', 'Phalanx', 'Regen', 'Stoneskin', 'Enmity', 'Midcast_Interrupt' },
        Tweaks  = {
            Idle       = { Stats = { PDT = -7.0, MDT = -6.0, MEVA = 0.18, HP = 0.06, REFRESH = 4.0, REGEN = 3.0 } },
            TP_Default = { Stats = { PDT = -5.5, MDT = -4.5, PARRY = 1.2, INQUARTATA = 2.0, HASTE_GEAR = 3.0, STORETP = 1.6, DOUBLE_ATTACK = 2.0, ENMITY = 1.2, ACC = 0.8, MEVA = 0.15 } },
            WS_Default = { Stats = { DEX = 1.3, STR = 1.1, ALL_WSDMG_ALL_HITS = 3.6, ATT = 0.6, ACC = 0.6 } },
        },
        Abilities = {
            ['Vallation']   = { Stats = { VALLATION_DURATION = 2, ENMITY = 2.5 } },
            ['Valiance']    = { Stats = { VALLATION_DURATION = 2, ENMITY = 2.5 } },
            ['Pflug']       = { Stats = { PFLUG_EFFECT = 2, ENMITY = 2.0 } },
            ['Liement']     = { Stats = { LIEMENT_DURATION = 2, ENMITY = 2.5 } },
            ['Battuta']     = { Stats = { INQUARTATA = 3, PARRY = 2.0, ENMITY = 2.0 } },
            ['Swordplay']   = { Stats = { SWORDPLAY = 2, ACC = 1.0 } },
            ['Vivacious Pulse'] = { Stats = { VIVACIOUS_PULSE_POTENCY = 2, DIVINE = 1.5, HP = 0.05 } },
            ['Gambit']      = { Base = 'Enmity' },
            ['Rayke']       = { Base = 'Enmity' },
            ['One for All'] = { Stats = { HP = 0.12, ENMITY = 2.0 } },
            ['Elemental Sforzo'] = { Base = 'Enmity' },
        },
        Specs = {
            inquisitor = {
                Tank = true,
                Tweaks = {
                    Idle       = { Stats = { PDT = -8.0, MDT = -7.0, PARRY = 1.5, INQUARTATA = 2.5, MEVA = 0.25, HP = 0.07, ENMITY = 1.0 } },
                    TP_Default = {
                        Label = 'Engaged (Inquisitor Parry/Aegis)',
                        Stats = { PDT = -6.5, MDT = -5.5, PARRY = 1.8, INQUARTATA = 3.0, HASTE_GEAR = 2.8, ENMITY = 1.8, MEVA = 0.20, HP = 0.06, ACC = 0.75, STORETP = 1.4 },
                    },
                },
                Abilities = {
                    ['Iron Battuta']      = { Base = 'Enmity' },
                    ['Runic Aegis']       = { Base = 'DT' },
                    ['Runic Convergence'] = { Base = 'Enmity' },
                },
            },
            spellblade = {
                Tank  = false,
                Meals = { 'Nuke', 'Nuke_Acc', 'Burst' },
                Tweaks = {
                    TP_Default = {
                        Label = 'Engaged (Spellblade Hybrid DPS)',
                        Stats = { HASTE_GEAR = 3.4, DOUBLE_ATTACK = 2.6, TRIPLE_ATTACK = 3.4, STORETP = 2.0, MATT = 1.2, MACC = 0.8, STR = 0.45, DEX = 0.45, INT = 0.40, ACC = 0.85, PDT = -2.0 },
                    },
                    WS_Default = {
                        Stats = { DEX = 1.3, STR = 1.2, INT = 0.8, MATT = 1.2, ALL_WSDMG_ALL_HITS = 3.8, ATT = 0.65 },
                    },
                },
                Abilities = {
                    ['Runic Bolt']  = { Base = 'Nuke' },
                    ['Runic Sever'] = { Base = 'Burst' },
                },
            },
            lifebinder = {
                Tank = true,
                Tweaks = {
                    Idle       = { Stats = { PDT = -7.0, MDT = -6.0, HP = 0.08, REGEN = 4.5, CURE_POTENCY_RCVD = 3.0, REFRESH = 5.0 } },
                    TP_Default = {
                        Label = 'Engaged (Lifebinder Sustain Ward)',
                        Stats = { PDT = -6.0, MDT = -5.0, HP = 0.08, CURE_POTENCY = 2.5, CURE_POTENCY_RCVD = 2.5, REGEN = 3.0, HASTE_GEAR = 2.8, ENMITY = 1.5, ACC = 0.75 },
                    },
                },
                Abilities = {
                    ['Font of Life']    = { Base = 'Cure' },
                    ['Sanctified Ward'] = { Base = 'Enhancing' },
                },
            },
        },
    },
}

-- Build a Weaponskill Mode dynamically from OverlordsXI WS catalog + invested WS Talents
local function buildWsMode(ws, jobTweaks, wsBonus)
    local m = {
        Name     = 'WS_' .. db.CleanSetKey(ws.name),
        Label    = 'WS: ' .. ws.name,
        Category = 'Weaponskills',
        Drawn    = true,
        Stats    = {},
    }
    local s = m.Stats

    -- Base WSC from OverlordsXI catalog
    for stat, coeff in pairs(ws.wsc or {}) do
        s[stat] = (s[stat] or 0) + coeff * 2.2
    end

    -- Apply job WS_Default base weights lightly
    local jobWs = jobTweaks and jobTweaks.WS_Default and jobTweaks.WS_Default.Stats
    if jobWs then
        for k, v in pairs(jobWs) do
            s[k] = (s[k] or 0) + v * 0.35
        end
    end

    local kind = (wsBonus and wsBonus.Kind) or ws.kind or 'physical'
    if kind == 'magical' then
        s.MATT = (s.MATT or 0) + 2.2
        s.MAGIC_DAMAGE = (s.MAGIC_DAMAGE or 0) + 1.4
        s.MACC = (s.MACC or 0) + 0.8
        s.INT = (s.INT or 0) + 0.6
        s.ALL_WSDMG_FIRST_HIT = (s.ALL_WSDMG_FIRST_HIT or 0) + 3.5
        s.ALL_WSDMG_ALL_HITS = (s.ALL_WSDMG_ALL_HITS or 0) + 3.5
        s.TP_BONUS = 0.01
    elseif kind == 'hybrid' then
        s.MATT = (s.MATT or 0) + 1.6
        s.MAGIC_DAMAGE = (s.MAGIC_DAMAGE or 0) + 1.0
        s.MACC = (s.MACC or 0) + 0.6
        s.ATT = (s.ATT or 0) + 0.55
        s.ACC = (s.ACC or 0) + 0.50
        s.ALL_WSDMG_FIRST_HIT = (s.ALL_WSDMG_FIRST_HIT or 0) + 3.5
        s.ALL_WSDMG_ALL_HITS = (s.ALL_WSDMG_ALL_HITS or 0) + 3.5
        s.TP_BONUS = 0.01
    elseif ws.skill == 25 or ws.skill == 26 or ws.skill == 27 then
        s.RATT = (s.RATT or 0) + 0.75
        s.RACC = (s.RACC or 0) + 0.65
        s.AGI  = (s.AGI or 0) + 0.45
        s.ALL_WSDMG_FIRST_HIT = (s.ALL_WSDMG_FIRST_HIT or 0) + 3.2
        s.ALL_WSDMG_ALL_HITS = (s.ALL_WSDMG_ALL_HITS or 0) + 3.5
        s.TP_BONUS = 0.01
    else
        s.ATT = (s.ATT or 0) + 0.55
        s.ACC = (s.ACC or 0) + 0.45
        s.WSACC = (s.WSACC or 0) + 0.45
        s.TP_BONUS = 0.01
        if (ws.hits or 1) > 1 then
            s.ALL_WSDMG_ALL_HITS = (s.ALL_WSDMG_ALL_HITS or 0) + 3.5
            s.ALL_WSDMG_FIRST_HIT = (s.ALL_WSDMG_FIRST_HIT or 0) + 1.8
            s.DOUBLE_ATTACK = (s.DOUBLE_ATTACK or 0) + 1.0
            s.TRIPLE_ATTACK = (s.TRIPLE_ATTACK or 0) + 1.5
            s.ANY_FTP_BONUS = 0.12
        else
            s.ALL_WSDMG_ALL_HITS = (s.ALL_WSDMG_ALL_HITS or 0) + 3.8
            s.ALL_WSDMG_FIRST_HIT = (s.ALL_WSDMG_FIRST_HIT or 0) + 3.0
            s.ANY_FTP_BONUS = 0.06
        end
    end

    if ws.crit then
        s.CRITHITRATE = (s.CRITHITRATE or 0) + 1.8
        s.CRIT_DMG_INCREASE = (s.CRIT_DMG_INCREASE or 0) + 1.4
        s.DEX = (s.DEX or 0) + 0.5
    end

    -- Apply live OverlordsXI WS Talent Node bonuses if synced
    if wsBonus and wsBonus.Stats then
        for statName, bonusWeight in pairs(wsBonus.Stats) do
            s[statName] = (s[statName] or 0) + bonusWeight
        end
    end

    return m
end

-- Returns an ordered list of mode definitions to build for the player's current Job, SubJob, Level, Spec, and Weapons
function jobs.PlanSets(who, currentEquip)
    local jobAbbr = db.JOB_ABBR[who.Job] or 'WAR'
    local jobDef  = jobs.Catalog[jobAbbr] or jobs.Catalog.WAR
    local specDef = (who.SpecKey and jobDef.Specs) and jobDef.Specs[who.SpecKey] or nil

    -- Combine level-band tweaks -> job tweaks -> active OverlordsXI Crystal Spec tweaks
    local combinedTweaks = {}
    for _, b in ipairs(GLOBAL_BANDS) do
        if (who.Level or 99) <= b.To then
            for modeKey, t in pairs(b.Tweaks or {}) do
                combinedTweaks[modeKey] = deepCopy(t)
            end
            break
        end
    end
    for modeKey, t in pairs(jobDef.Tweaks or {}) do
        combinedTweaks[modeKey] = combinedTweaks[modeKey] or {}
        mergeTweaks(combinedTweaks[modeKey], t)
    end
    if specDef and specDef.Tweaks then
        for modeKey, t in pairs(specDef.Tweaks) do
            combinedTweaks[modeKey] = combinedTweaks[modeKey] or {}
            mergeTweaks(combinedTweaks[modeKey], t)
        end
    end

    local function makeMode(key)
        local base = deepCopy(roles.Modes[key] or roles.Modes.Idle)
        base.Name = key
        if combinedTweaks[key] then
            mergeTweaks(base, combinedTweaks[key])
        end
        return base
    end

    local planned = {}
    local added   = {}
    local function addMode(key, customMode)
        if added[key] then return end
        added[key] = true
        planned[#planned + 1] = customMode or makeMode(key)
    end

    -- 1. Core Standing & Defense Sets (every job)
    for _, k in ipairs({ 'Idle', 'Idle_DT', 'Idle_Regen', 'Idle_Refresh', 'Resting', 'DT', 'DT_Physical', 'DT_Magic', 'Movement' }) do
        addMode(k)
    end

    -- 2. Melee / Tank / Ranged Sets
    local function resolveRoleFlag(field)
        if specDef and specDef[field] ~= nil then
            return specDef[field]
        end
        return jobDef[field] or false
    end
    local isFighter = resolveRoleFlag('Fighter')
    local isTank    = resolveRoleFlag('Tank')
    local isRanged  = resolveRoleFlag('Ranged')
    local isCaster  = resolveRoleFlag('Caster')
    local isPet     = resolveRoleFlag('Pet')

    -- Subjob checks (e.g. /NIN, /DNC, /WHM, /RDM, /BLM, /SCH, /WAR)
    local subAbbr = db.JOB_ABBR[who.Sub or 0]
    if subAbbr == 'WHM' or subAbbr == 'RDM' or subAbbr == 'BLM' or subAbbr == 'SCH' or subAbbr == 'NIN' or subAbbr == 'BLU' then
        isCaster = true
    end

    addMode('TP_Default')
    addMode('TP_Hybrid')
    addMode('TP_Acc')
    if isTank then
        addMode('Tank_Engaged')
        addMode('Enmity')
    end
    addMode('TH')

    if isRanged or (currentEquip and currentEquip[3] and currentEquip[3].Skill and currentEquip[3].Skill >= 25) then
        addMode('Preshot')
        addMode('Midshot')
    end

    -- 3. Weaponskill Sets for currently equipped Main & Ranged weapon skills
    addMode('WS_Default')
    local activeSkills = {}
    if currentEquip then
        if currentEquip[1] and (currentEquip[1].Skill or 0) > 0 then
            activeSkills[currentEquip[1].Skill] = true
        else
            -- Barehanded H2H
            activeSkills[1] = true
        end
        if currentEquip[3] and (currentEquip[3].Skill or 0) >= 25 then
            activeSkills[currentEquip[3].Skill] = true
        end
        if currentEquip[4] and (currentEquip[4].Skill or 0) == 27 then
            activeSkills[27] = true
        end
    end
    if specDef and who.SpecKey == 'bladewheel' then
        activeSkills[27] = true
    elseif specDef and who.SpecKey == 'necromancer' then
        activeSkills[7] = true
    elseif specDef and who.SpecKey == 'sensei' then
        activeSkills[12] = true
    end

    for _, ws in pairs(db.Weaponskills()) do
        if activeSkills[ws.skill] then
            local wsBonus = ox_sync.State.WsBonuses[ws.id]
            local wm = buildWsMode(ws, combinedTweaks, wsBonus)
            addMode(wm.Name, wm)
        end
    end

    -- 4. Job-Specific & Spec-Specific Meal Sets (Spells, Pet, Ranged)
    if isCaster then
        addMode('Precast')
        addMode('Midcast_Interrupt')
    end
    for _, k in ipairs(jobDef.Meals or {}) do
        addMode(k)
    end
    if specDef and specDef.Meals then
        for _, k in ipairs(specDef.Meals) do
            addMode(k)
        end
    end

    -- Subjob utility sets
    if subAbbr == 'NIN' then
        addMode('Precast')
        addMode('Ninjutsu_Buff')
    elseif subAbbr == 'DNC' then
        addMode('Waltz')
        addMode('Step')
    elseif subAbbr == 'WAR' then
        addMode('Enmity')
    elseif subAbbr == 'WHM' or subAbbr == 'RDM' or subAbbr == 'SCH' then
        addMode('Cure')
        addMode('Enhancing')
        addMode('Stoneskin')
    end

    if isPet then
        addMode('Pet_Idle')
        addMode('Pet_TP')
        addMode('Pet_Magic')
    end

    -- 5. Job Ability Sets (from Job + Active Crystal Spec)
    local abils = {}
    for aName, aDef in pairs(jobDef.Abilities or {}) do
        abils[aName] = aDef
    end
    if specDef and specDef.Abilities then
        for aName, aDef in pairs(specDef.Abilities) do
            abils[aName] = aDef
        end
    end
    for aName, aDef in pairs(abils) do
        local setKey = 'JA_' .. db.CleanSetKey(aName)
        local baseKey = aDef.Base or 'Idle'
        local m = makeMode(baseKey)
        m.Name = setKey
        m.Label = 'JA: ' .. aName
        m.Category = 'Job Abilities & Pets'
        if aDef.Stats then
            m.Stats = deepCopy(aDef.Stats)
        end
        addMode(setKey, m)
    end

    return planned
end

return jobs
