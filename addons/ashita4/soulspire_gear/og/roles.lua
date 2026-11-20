--[[
* SoulspireXI Gear Manager (soulspire_gear) - Base Role Modes & Stat Weights
* Defines default stat weights and caps for Standing, Melee, Weaponskill,
* Precast/Midcast Spell, Ranged, Job Ability, and Pet sets.
--]]

local roles = {}

local DT_CAPS = { PDT = -50, MDT = -50 }

roles.Modes = {
    -- ========================= Standing & Defense =========================
    Idle = {
        Category = 'Standing & Defense',
        Label    = 'Idle (Default)',
        Drawn    = false,
        Stats    = { PDT = -3.0, MDT = -2.5, REFRESH = 6.0, REGEN = 2.5, MOVE_SPEED_GEAR_BONUS = 1.5, HP = 0.02, MEVA = 0.04, DEF = 0.02 },
        Caps     = DT_CAPS,
    },
    Idle_DT = {
        Category = 'Standing & Defense',
        Label    = 'Idle (Tank / DT)',
        Drawn    = false,
        Stats    = { PDT = -10.0, MDT = -8.0, HP = 0.05, MEVA = 0.12, DEF = 0.03, REFRESH = 2.0, REGEN = 1.5 },
        Caps     = DT_CAPS,
    },
    Idle_Regen = {
        Category = 'Standing & Defense',
        Label    = 'Idle (Regen)',
        Drawn    = false,
        Stats    = { REGEN = 6.0, PDT = -2.0, MDT = -1.5, HP = 0.02 },
        Caps     = DT_CAPS,
    },
    Idle_Refresh = {
        Category = 'Standing & Defense',
        Label    = 'Idle (Refresh)',
        Drawn    = false,
        Stats    = { REFRESH = 8.0, FAERIE_REFRESH = 12.0, PDT = -2.0, MDT = -1.5, MP = 0.02 },
        Caps     = DT_CAPS,
    },
    Resting = {
        Category = 'Standing & Defense',
        Label    = 'Resting (hHP / hMP)',
        Drawn    = false,
        Stats    = { MPHEAL = 3.0, HPHEAL = 1.5, REFRESH = 4.0, REGEN = 2.0 },
    },
    DT = {
        Category = 'Standing & Defense',
        Label    = 'Damage Taken (Hybrid DT)',
        Stats    = { PDT = -10.0, MDT = -8.0, HP = 0.05, MEVA = 0.12, DEF = 0.03, EVA = 0.04 },
        Caps     = DT_CAPS,
    },
    DT_Physical = {
        Category = 'Standing & Defense',
        Label    = 'Physical Damage Taken (PDT)',
        Stats    = { PDT = -12.0, DEF = 0.05, HP = 0.05, EVA = 0.05, MDT = -2.0 },
        Caps     = DT_CAPS,
    },
    DT_Magic = {
        Category = 'Standing & Defense',
        Label    = 'Magic Damage Taken (MDT)',
        Stats    = { MDT = -12.0, MEVA = 0.20, MDEF = 0.6, HP = 0.05, PDT = -2.0 },
        Caps     = DT_CAPS,
    },
    Movement = {
        Category = 'Standing & Defense',
        Label    = 'Movement Speed / Kite',
        Drawn    = false,
        Stats    = { MOVE_SPEED_GEAR_BONUS = 15.0, PDT = -3.0, MDT = -2.0, EVA = 0.05 },
        Caps     = { MOVE_SPEED_GEAR_BONUS = 18, PDT = -50, MDT = -50 },
    },

    -- ========================= Engaged / Melee =========================
    TP_Default = {
        Category = 'Engaged / Melee',
        Label    = 'Engaged (Default)',
        Drawn    = true,
        Stats    = {
            HASTE_GEAR = 3.2, TRIPLE_ATTACK = 3.2, QUAD_ATTACK = 4.2, DOUBLE_ATTACK = 2.2,
            STORETP = 1.6, ACC = 0.65, ATT = 0.30, CRITHITRATE = 1.0,
            DEX = 0.35, STR = 0.28, PDT = -0.35, MDT = -0.25,
        },
        Caps     = { HASTE_GEAR = 25, PDT = -50, MDT = -50 },
    },
    TP_Hybrid = {
        Category = 'Engaged / Melee',
        Label    = 'Engaged (Hybrid DT)',
        Drawn    = true,
        Stats    = {
            PDT = -3.5, MDT = -2.5, HASTE_GEAR = 3.0, DOUBLE_ATTACK = 1.8, TRIPLE_ATTACK = 2.6,
            STORETP = 1.3, ACC = 0.65, ATT = 0.25, MEVA = 0.08, HP = 0.03, DEX = 0.30, STR = 0.20,
        },
        Caps     = { HASTE_GEAR = 25, PDT = -50, MDT = -50 },
    },
    TP_Acc = {
        Category = 'Engaged / Melee',
        Label    = 'Engaged (High Accuracy)',
        Drawn    = true,
        Stats    = {
            ACC = 1.8, DEX = 0.70, HASTE_GEAR = 2.8, STORETP = 1.1,
            DOUBLE_ATTACK = 1.4, TRIPLE_ATTACK = 2.0, ATT = 0.25, PDT = -0.35,
        },
        Caps     = { HASTE_GEAR = 25, PDT = -50, MDT = -50 },
    },
    Tank_Engaged = {
        Category = 'Engaged / Melee',
        Label    = 'Engaged (Tank / Enmity)',
        Drawn    = true,
        Stats    = {
            PDT = -7.0, MDT = -5.5, HASTE_GEAR = 2.2, ENMITY = 1.2, HP = 0.05,
            DEF = 0.04, MEVA = 0.10, PARRY = 0.8, SHIELD = 0.6, ACC = 0.45, STORETP = 0.8,
        },
        Caps     = { HASTE_GEAR = 25, PDT = -50, MDT = -50 },
    },
    TH = {
        Category = 'Engaged / Melee',
        Label    = 'Treasure Hunter',
        Stats    = { TREASURE_HUNTER = 25.0, PDT = -1.5, ACC = 0.4, HASTE_GEAR = 1.0 },
        Caps     = { TREASURE_HUNTER = 4, HASTE_GEAR = 25, PDT = -50 },
    },

    -- ========================= Weaponskills =========================
    WS_Default = {
        Category = 'Weaponskills',
        Label    = 'Weaponskill (Default)',
        Drawn    = true,
        Stats    = {
            ALL_WSDMG_ALL_HITS = 3.5, ALL_WSDMG_FIRST_HIT = 2.5,
            STR = 1.1, DEX = 0.5, ATT = 0.55, ACC = 0.45, WSACC = 0.45,
            DOUBLE_ATTACK = 1.0, TRIPLE_ATTACK = 1.4, TP_BONUS = 0.01, CRIT_DMG_INCREASE = 0.5,
        },
    },

    -- ========================= Spells & Casting =========================
    Precast = {
        Category = 'Spells & Casting',
        Label    = 'Precast (Fast Cast)',
        Stats    = { FASTCAST = 3.5, UFASTCAST = 2.5, PDT = -0.3, HASTE_GEAR = 0.5 },
        Caps     = { FASTCAST = 80, HASTE_GEAR = 25, PDT = -50 },
    },
    Cure_Precast = {
        Category = 'Spells & Casting',
        Label    = 'Precast (Cure)',
        Stats    = { CURE_CAST_TIME = 3.5, FASTCAST = 3.0, PDT = -0.2 },
        Caps     = { FASTCAST = 80, CURE_CAST_TIME = 80, PDT = -50 },
    },
    Enhancing_Precast = {
        Category = 'Spells & Casting',
        Label    = 'Precast (Enhancing)',
        Stats    = { FASTCAST = 3.5, UFASTCAST = 2.5, PDT = -0.2 },
        Caps     = { FASTCAST = 80, PDT = -50 },
    },
    Song_Precast = {
        Category = 'Spells & Casting',
        Label    = 'Precast (Songs)',
        Stats    = { SONG_SPELLCASTING_TIME = 3.5, FASTCAST = 3.0 },
        Caps     = { FASTCAST = 80, SONG_SPELLCASTING_TIME = 80 },
    },
    Midcast_Interrupt = {
        Category = 'Spells & Casting',
        Label    = 'Spell Interruption Down',
        Stats    = { SPELLINTERRUPT = 2.0, PDT = -2.5, MDT = -2.0 },
        Caps     = { SPELLINTERRUPT = 102, PDT = -50, MDT = -50 },
    },
    Cure = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Cure',
        Stats    = { CURE_POTENCY = 3.5, CURE_POTENCY_II = 2.5, MND = 0.55, HEALING = 0.65, VIT = 0.15, CONSERVE_MP = 0.25, ENMITY = -0.3 },
        Caps     = { CURE_POTENCY = 50, CURE_POTENCY_II = 30 },
    },
    Cursna = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Cursna / Status',
        Stats    = { ENHANCES_CURSNA = 3.5, HEALING = 1.2, MND = 0.3, FASTCAST = 0.5 },
    },
    Enhancing = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Enhancing Magic',
        Stats    = { ENH_MAGIC_DURATION = 2.5, ENHANCE = 1.2, MND = 0.25, CONSERVE_MP = 0.25 },
    },
    Stoneskin = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Stoneskin',
        Stats    = { STONESKIN_BONUS_HP = 1.5, MND = 0.5, ENHANCE = 0.5 },
    },
    Phalanx = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Phalanx',
        Stats    = { PHALANX_RECEIVED = 5.0, ENHANCE = 0.8, ENH_MAGIC_DURATION = 1.0 },
    },
    Regen = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Regen',
        Stats    = { REGEN_DURATION = 2.5, ENH_MAGIC_DURATION = 1.5, MND = 0.2 },
    },
    Refresh = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Refresh',
        Stats    = { ENHANCES_REFRESH = 3.5, ENH_MAGIC_DURATION = 1.8, CONSERVE_MP = 0.2 },
    },
    Enfeebling = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Enfeebling Magic',
        Stats    = { MACC = 1.5, ENFEEBLE = 1.2, MND = 0.65, INT = 0.65 },
    },
    Nuke = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Elemental Nuke (Power)',
        Stats    = { MATT = 2.2, MAGIC_DAMAGE = 1.4, INT = 1.1, MACC = 0.75, ELEM = 0.5, MAGIC_CRITHITRATE = 0.3 },
    },
    Nuke_Acc = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Elemental Nuke (Accuracy)',
        Stats    = { MACC = 1.8, ELEM = 1.0, INT = 1.0, MATT = 1.2, MAGIC_DAMAGE = 0.8 },
    },
    Burst = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Magic Burst',
        Stats    = { MAGIC_BURST_BONUS = 3.0, MAGIC_BURST_BONUS_CAPPED = 2.5, MATT = 1.8, INT = 1.0, MACC = 0.9, MAGIC_DAMAGE = 1.2 },
        Caps     = { MAGIC_BURST_BONUS_CAPPED = 40 },
    },
    Dark = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Dark Magic',
        Stats    = { DARK = 1.4, MACC = 1.4, INT = 0.7, HASTE_GEAR = 0.5 },
        Caps     = { HASTE_GEAR = 25 },
    },
    DrainAspir = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Drain & Aspir',
        Stats    = { DRAIN_ASPIR = 2.5, DARK = 1.4, MACC = 1.2, INT = 0.6 },
    },
    Helix = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Helix (SCH)',
        Stats    = { MATT = 2.0, MAGIC_DAMAGE = 1.5, INT = 1.1, MACC = 0.8, HELIX_DURATION = 1.5 },
    },
    Divine = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Divine Magic',
        Stats    = { MATT = 1.8, MACC = 1.2, DIVINE = 1.2, MND = 0.9, ENMITY = 0.4 },
    },
    Song = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Bard Songs (Buff)',
        Stats    = { ALL_SONGS_BONUS = 20.0, SONG_DURATION_BONUS = 1.5, SINGING = 1.0, WIND = 0.8, STRING = 0.8, CHR = 0.4 },
    },
    Song_Debuff = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Bard Songs (Debuff)',
        Stats    = { ALL_SONGS_BONUS = 15.0, MACC = 1.6, SINGING = 1.0, WIND = 0.8, CHR = 0.8 },
    },
    Ninjutsu_Buff = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Utsusemi / Nin Buff',
        Stats    = { UTSUSEMI_BONUS = 15.0, HASTE_GEAR = 2.5, FASTCAST = 1.5, NINJUTSU = 0.5, EVA = 0.3, PDT = -1.0 },
        Caps     = { HASTE_GEAR = 25, FASTCAST = 80, PDT = -50 },
    },
    Ninjutsu_Nuke = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Elemental Ninjutsu',
        Stats    = { NIN_NUKE_BONUS = 2.0, MATT = 2.0, MAGIC_DAMAGE = 1.2, INT = 1.0, MACC = 1.0, NINJUTSU = 0.8 },
    },
    Ninjutsu_Debuff = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Enfeebling Ninjutsu',
        Stats    = { MACC = 1.8, NINJUTSU = 1.2, INT = 0.6 },
    },
    Blue_Physical = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Blue Magic (Physical)',
        Stats    = { ATT = 0.6, ACC = 0.6, STR = 1.0, DEX = 0.6, BLUE = 0.8 },
    },
    Blue_Magical = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Blue Magic (Magical)',
        Stats    = { MATT = 2.0, MAGIC_DAMAGE = 1.3, INT = 1.0, MACC = 0.9, BLUE = 0.6 },
    },
    Geomancy = {
        Category = 'Spells & Casting',
        Label    = 'Midcast: Geomancy & Indi',
        Stats    = { GEOMANCY_BONUS = 15.0, GEOMANCY_SKILL = 1.2, HANDBELL_SKILL = 1.2, INDI_DURATION = 1.5, CONSERVE_MP = 0.3, PDT = -1.0 },
        Caps     = { GEOMANCY_SKILL = 450, HANDBELL_SKILL = 450, PDT = -50 },
    },
    Summoning_BP_Phys = {
        Category = 'Spells & Casting',
        Label    = 'Blood Pact: Rage (Physical)',
        Stats    = { BP_DAMAGE = 3.0, SUMMONING = 0.8 },
        Pet      = { ATT = 0.6, ACC = 0.5, DOUBLE_ATTACK = 1.5, CRITHITRATE = 1.2 },
    },
    Summoning_BP_Mag = {
        Category = 'Spells & Casting',
        Label    = 'Blood Pact: Rage (Magical)',
        Stats    = { BP_DAMAGE = 3.0, SUMMONING = 0.8 },
        Pet      = { MATT = 2.0, MACC = 0.8 },
    },
    Summoning_Ward = {
        Category = 'Spells & Casting',
        Label    = 'Blood Pact: Ward',
        Stats    = { SUMMONING = 2.0, BP_DELAY = -1.5, BP_DELAY_II = -1.5 },
        Caps     = { BP_DELAY = -15, BP_DELAY_II = -15 },
    },

    -- ========================= Ranged =========================
    Preshot = {
        Category = 'Ranged & Abilities',
        Label    = 'Ranged: Preshot (Snapshot)',
        Stats    = { SNAPSHOT = 3.0, RAPID_SHOT = 1.5 },
        Caps     = { SNAPSHOT = 70 },
    },
    Midshot = {
        Category = 'Ranged & Abilities',
        Label    = 'Ranged: Midshot',
        Stats    = { RACC = 0.8, RATT = 0.7, STORETP = 1.4, AGI = 0.4, CRITHITRATE = 1.0, DOUBLE_SHOT_RATE = 1.5, TRIPLE_SHOT_RATE = 2.0 },
    },

    -- ========================= Job Abilities & Pets =========================
    Enmity = {
        Category = 'Job Abilities & Pets',
        Label    = 'Ability: Enmity / Provoke',
        Stats    = { ENMITY = 3.5, PDT = -2.0, MDT = -1.5, HP = 0.04 },
        Caps     = DT_CAPS,
    },
    Waltz = {
        Category = 'Job Abilities & Pets',
        Label    = 'Ability: Curing Waltz',
        Stats    = { WALTZ_POTENCY = 3.0, CHR = 0.6, VIT = 0.4, PDT = -1.0 },
        Caps     = { WALTZ_POTENCY = 50, PDT = -50 },
    },
    Step = {
        Category = 'Job Abilities & Pets',
        Label    = 'Ability: Dancer Steps',
        Stats    = { STEP_ACCURACY = 2.0, ACC = 1.5, DEX = 0.7, HASTE_GEAR = 1.0 },
        Caps     = { HASTE_GEAR = 25 },
    },
    Jump = {
        Category = 'Job Abilities & Pets',
        Label    = 'Ability: Dragoon Jumps',
        Stats    = { JUMP_TP_BONUS = 1.5, JUMP_ATT_BONUS = 1.5, STORETP = 2.0, DOUBLE_ATTACK = 2.0, TRIPLE_ATTACK = 2.8, STR = 0.6, DEX = 0.5, ACC = 0.6, ATT = 0.4 },
    },
    Pet_Idle = {
        Category = 'Job Abilities & Pets',
        Label    = 'Pet: Idle & Sustain',
        Stats    = { PDT = -3.0, MDT = -2.0, REFRESH = 3.0, FAERIE_REFRESH = 12.0 },
        Pet      = { PDT = -4.0, MDT = -3.0, REGEN = 2.5 },
        Caps     = DT_CAPS,
        PetCaps  = { PDT = -50, MDT = -50 },
    },
    Pet_TP = {
        Category = 'Job Abilities & Pets',
        Label    = 'Pet: Engaged / Ready',
        Stats    = { PDT = -2.0, HASTE_GEAR = 1.5, ACC = 0.3 },
        Pet      = { HASTE_GEAR = 2.5, ACC = 0.8, ATT = 0.5, DOUBLE_ATTACK = 2.0, STORETP = 1.2, PDT = -2.0 },
        Caps     = { HASTE_GEAR = 25, PDT = -50 },
        PetCaps  = { HASTE_GEAR = 25, PDT = -50 },
    },
    Pet_Magic = {
        Category = 'Job Abilities & Pets',
        Label    = 'Pet: Magic / Breath',
        Stats    = { PDT = -1.5, FAERIE_REFRESH = 10.0 },
        Pet      = { MATT = 2.2, MACC = 1.2 },
        Caps     = DT_CAPS,
    },
}

return roles
