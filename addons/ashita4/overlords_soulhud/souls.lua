local function element(id, label, kind, field, max, unit)
    return { id = id, label = label, type = kind, field = field or id, max = max, unit = unit }
end

-- Canonical 22-job / 66-Soul catalog from modules/custom/lua/overlords_job_specs.lua.
-- Souls without a provider are registered intentionally but show no fabricated meters.
local catalog = {
    commander = 'WAR · Commander', berserker = 'WAR · Berserker', spartan = 'WAR · Spartan',
    sensei = 'MNK · Sensei', chiweaver = 'MNK · Chi Weaver', blackbelt = 'MNK · Black Belt',
    bishop = 'WHM · Bishop', zealot = 'WHM · Zealot', valkyrie = 'WHM · Valkyrie',
    astromancer = 'BLM · Astromancer', channeler = 'BLM · Channeler', necromancer = 'BLM · Necromancer',
    crimsonduelist = 'RDM · Crimson Duelist', royaltactician = 'RDM · Royal Tactician', scarletweaver = 'RDM · Scarlet Weaver',
    trickster = 'THF · Trickster', bandit = 'THF · Bandit', phantom = 'THF · Phantom',
    templar = 'PLD · Templar', defender = 'PLD · Defender', oathbreaker = 'PLD · Oathbreaker',
    reaper = 'DRK · Reaper', dreadnought = 'DRK · Dreadnought', scourge = 'DRK · Scourge',
    adventurer = 'BRD · Adventurer', musician = 'BRD · Musician', minstrel = 'BRD · Minstrel',
    sniper = 'RNG · Sniper', huntsman = 'RNG · Huntsman', arcanearcher = 'RNG · Arcane Archer',
    ronin = 'SAM · Ronin', imperialarcher = 'SAM · Imperial Archer', warlord = 'SAM · Warlord',
    kurogane = 'NIN · Kurogane', kagemusha = 'NIN · Kagemusha', nightblade = 'NIN · Nightblade',
    lancer = 'DRG · Lancer', skyborn = 'DRG · Skyborn', wyvernheart = 'DRG · Wyvernheart',
    warmage = 'BLU · Warmage', magus = 'BLU · Magus', azurebastion = 'BLU · Azure Bastion',
    flintlock = 'COR · Flintlock', gambler = 'COR · Gambler', buccaneer = 'COR · Buccaneer',
    freelancer = 'DNC · Freelancer', vampire = 'DNC · Vampire', bladewheel = 'DNC · Bladewheel',
    medic = 'SCH · Medic', sage = 'SCH · Sage', archivist = 'SCH · Archivist',
    untamed = 'BST · Untamed', alphawarden = 'BST · Alpha Warden', beastspeaker = 'BST · Beastspeaker',
    primalist = 'SMN · Primalist', celestial = 'SMN · Celestial', herald = 'SMN · Herald',
    marionettist = 'PUP · Marionettist', pugilist = 'PUP · Pugilist', animist = 'PUP · Animist',
    spellblade = 'RUN · Spellblade', lifebinder = 'RUN · Lifebinder', inquisitor = 'RUN · Inquisitor',
    diviner = 'GEO · Diviner', verdant = 'GEO · Verdant', terramancer = 'GEO · Terramancer',
}

local definitions = {}
for key, title in pairs(catalog) do
    definitions[key] = { title = title, elements = {} }
end

-- Active DNC custom provider. It is currently an additional registered DNC key,
-- not one of the three DNC entries in the canonical 66-key JOB_SPECS table.
definitions.miragesentinel = {
    title = 'DNC · Mirage Sentinel',
    elements = {
        element('fm', 'Finishing Moves', 'stack', 'fm', 5),
        element('fan_act', 'Fan Dance', 'toggle', 'fan_act'),
        element('fan_dt', 'Fan Dance Mitigation', 'gauge', 'fan_dt', 45, '%'),
        element('fan_rem', 'Fan Dance Duration', 'timer', 'fan_rem', nil, 's'),
        element('issek_rem', 'Parry Window', 'timer', 'issek_rem', nil, 's'),
        element('parry_fm', 'Parry-Generated Moves', 'counter', 'parry_fm'),
        element('aegis_hp', 'Flourish Shield', 'gauge', 'aegis_hp', nil, 'HP'),
        element('aegis_rem', 'Shield Duration', 'timer', 'aegis_rem', nil, 's'),
    },
}

definitions.flintlock = {
    title = 'COR · Flintlock',
    elements = {
        element('powder', 'Black Powder', 'stack', 'powder', 3, 'rounds'),
        element('mark_rem', 'Powder Mark', 'timer', 'mark_rem', nil, 's'),
    },
}

definitions.gambler = {
    title = 'COR · Gambler',
    elements = {
        element('rolls', 'Active Phantom Rolls', 'stack', 'rolls', 3),
        element('ante_n', 'Ante / Wagers', 'counter', 'ante_n'),
        element('ante_hp', 'Ante HP', 'counter', 'ante_hp', nil, 'HP'),
        element('ante_tp', 'Ante TP', 'counter', 'ante_tp', nil, 'TP'),
        element('roll_tot', 'Current Roll', 'counter', 'roll_tot'),
        element('overdrive', 'Lucky Overdrive', 'toggle', 'overdrive'),
        element('du_rem', 'Double Up Window', 'timer', 'du_rem', nil, 's'),
        element('roll_lock', 'Roll Lock', 'cooldown', 'roll_lock', nil, 's'),
        element('last_cdr', 'Jackpot Cooldown Reduction', 'counter', 'last_cdr', nil, 's'),
        element('debt_rem', 'House Debt', 'timer', 'debt_rem', nil, 's'),
        element('snake_act', 'Snake Eye', 'toggle', 'snake_act'),
        element('cc_type', 'Deck Effect', 'counter', 'cc_type'),
        element('cc_rem', 'Deck Effect Duration', 'timer', 'cc_rem', nil, 's'),
    },
}

return definitions
