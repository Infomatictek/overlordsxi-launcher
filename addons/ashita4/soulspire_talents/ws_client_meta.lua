-- SoulspireXI WS Talent Client Metadata (Auto-generated from Foundation 2.1 Manifest)
-- Lean read-only presentation lookup for all 66 canonical Souls.
-- Server remains authoritative for all eligibility, allocation, and persistence.
local M = {}

M.SCHEMA_VERSION = '2.0.0'
M.SKILL_NAMES = {
    [1] = 'Hand-to-Hand',
    [2] = 'Dagger',
    [3] = 'Sword',
    [4] = 'Great Sword',
    [5] = 'Axe',
    [6] = 'Great Axe',
    [7] = 'Scythe',
    [8] = 'Polearm',
    [9] = 'Katana',
    [10] = 'Great Katana',
    [11] = 'Club',
    [12] = 'Staff',
    [25] = 'Archery',
    [26] = 'Marksmanship',
    [27] = 'Throwing',
}

M.SOULS = {
    adventurer = { name = 'Adventurer', job = 'BRD', role = 'Damage', tier = 'Damage', primary = { 2 }, secondary = { 3 }, mechanic = 'Cadence Stack' },
    alphawarden = { name = 'Alpha Warden', job = 'BST', role = 'Tank', tier = 'Tank', primary = { 5 }, secondary = {  }, mechanic = 'Alpha Pack Mend' },
    animist = { name = 'Animist', job = 'PUP', role = 'Healer', tier = 'CombatHealer', primary = { 1 }, secondary = {  }, mechanic = 'Aether Cell Pulse' },
    arcanearcher = { name = 'Arcane Archer', job = 'RNG', role = 'Support', tier = 'Support', primary = { 25 }, secondary = {  }, mechanic = 'Attunement Mark' },
    archivist = { name = 'Archivist', job = 'SCH', role = 'Support', tier = 'Support', primary = { 12 }, secondary = { 11 }, mechanic = 'Stratagem Pulse' },
    astromancer = { name = 'Astromancer', job = 'BLM', role = 'Damage', tier = 'Damage', primary = { 12 }, secondary = {  }, mechanic = 'Celestial Siphon' },
    azurebastion = { name = 'Azure Bastion', job = 'BLU', role = 'Tank', tier = 'Tank', primary = { 3 }, secondary = { 11 }, mechanic = 'Azure Surge' },
    bandit = { name = 'Bandit', job = 'THF', role = 'Damage', tier = 'Damage', primary = { 2 }, secondary = { 3 }, mechanic = 'Find the Gap' },
    beastspeaker = { name = 'Beastspeaker', job = 'BST', role = 'Support', tier = 'Support', primary = { 5 }, secondary = {  }, mechanic = 'Pack Rally' },
    berserker = { name = 'Berserker', job = 'WAR', role = 'Damage', tier = 'Damage', primary = { 6 }, secondary = { 5 }, mechanic = 'Bloodlust Surge' },
    bishop = { name = 'Bishop', job = 'WHM', role = 'Healer', tier = 'Healer', primary = { 11 }, secondary = { 12 }, mechanic = 'Solace Grace' },
    blackbelt = { name = 'Black Belt', job = 'MNK', role = 'Damage', tier = 'Damage', primary = { 1 }, secondary = {  }, mechanic = 'Impetus Chain' },
    bladewheel = { name = 'Bladewheel', job = 'DNC', role = 'Damage', tier = 'Damage', primary = { 27 }, secondary = { 2 }, mechanic = 'Chakram Momentum' },
    buccaneer = { name = 'Buccaneer', job = 'COR', role = 'Tank', tier = 'Tank', primary = { 3 }, secondary = {  }, mechanic = 'Point-Blank Grapeshot' },
    celestial = { name = 'Celestial', job = 'SMN', role = 'Healer', tier = 'Healer', primary = { 12 }, secondary = { 11 }, mechanic = 'Starlight Mend' },
    channeler = { name = 'Channeler', job = 'BLM', role = 'Support', tier = 'HybridSupport', primary = { 12 }, secondary = {  }, mechanic = 'Arcane Resonance' },
    chiweaver = { name = 'Chi Weaver', job = 'MNK', role = 'Healer', tier = 'Healer', primary = { 1 }, secondary = {  }, mechanic = 'Chi Harmony' },
    commander = { name = 'Commander', job = 'WAR', role = 'Support', tier = 'Support', primary = { 6 }, secondary = { 3 }, mechanic = 'Tactical Breach' },
    crimsonduelist = { name = 'Crimson Duelist', job = 'RDM', role = 'Tank', tier = 'Tank', primary = { 3 }, secondary = {  }, mechanic = 'Crimson Flow' },
    defender = { name = 'Defender', job = 'PLD', role = 'Tank', tier = 'Tank', primary = { 11 }, secondary = { 3 }, mechanic = 'Zeal Stack' },
    diviner = { name = 'Diviner', job = 'GEO', role = 'Support', tier = 'Support', primary = { 11 }, secondary = { 12 }, mechanic = 'Meridian Pulse' },
    dreadnought = { name = 'Dreadnought', job = 'DRK', role = 'Tank', tier = 'Tank', primary = { 7 }, secondary = {  }, mechanic = 'Blood-Pool Charge' },
    flintlock = { name = 'Flintlock', job = 'COR', role = 'Damage', tier = 'Damage', primary = { 26 }, secondary = {  }, mechanic = 'Deadeye Detonation' },
    gambler = { name = 'Gambler', job = 'COR', role = 'Support', tier = 'Support', primary = { 26 }, secondary = { 2 }, mechanic = 'Loaded Dice' },
    herald = { name = 'Herald', job = 'SMN', role = 'Support', tier = 'Support', primary = { 12 }, secondary = { 11 }, mechanic = 'Herald Boon' },
    huntsman = { name = 'Huntsman', job = 'RNG', role = 'Tank', tier = 'Tank', primary = { 25 }, secondary = { 26 }, mechanic = 'Warden\'s Ration' },
    imperialarcher = { name = 'Imperial Archer', job = 'SAM', role = 'Support', tier = 'Support', primary = { 10 }, secondary = { 25 }, mechanic = 'Drawn Oisoya' },
    inquisitor = { name = 'Inquisitor', job = 'RUN', role = 'Tank', tier = 'Tank', primary = { 4 }, secondary = {  }, mechanic = 'Runic Verdict' },
    kagemusha = { name = 'Kagemusha', job = 'NIN', role = 'Tank', tier = 'Tank', primary = { 9 }, secondary = {  }, mechanic = 'Shadow Veil' },
    kurogane = { name = 'Shinobi', job = 'NIN', role = 'Damage', tier = 'Damage', primary = { 9 }, secondary = {  }, mechanic = 'Clone Sync' },
    lancer = { name = 'Lancer', job = 'DRG', role = 'Damage', tier = 'Damage', primary = { 8 }, secondary = {  }, mechanic = 'Vault Momentum' },
    lifebinder = { name = 'Lifebinder', job = 'RUN', role = 'Healer', tier = 'Healer', primary = { 4 }, secondary = {  }, mechanic = 'Runic Lifetap' },
    magus = { name = 'Magus', job = 'BLU', role = 'Healer', tier = 'CombatHealer', primary = { 3 }, secondary = { 11 }, mechanic = 'Azure Mending' },
    medic = { name = 'Medic', job = 'SCH', role = 'Healer', tier = 'Healer', primary = { 11 }, secondary = { 12 }, mechanic = 'Eos Triage' },
    minstrel = { name = 'Minstrel', job = 'BRD', role = 'Tank', tier = 'Tank', primary = { 2 }, secondary = { 3 }, mechanic = 'Taunting Anthem' },
    miragesentinel = { name = 'Mirage Sentinel', job = 'DNC', role = 'Tank', tier = 'Tank', primary = { 2 }, secondary = {  }, mechanic = 'Fan Dance Refresh' },
    musician = { name = 'Musician', job = 'BRD', role = 'Support', tier = 'HybridSupport', primary = { 2 }, secondary = { 12 }, mechanic = 'Harmonic Pulse' },
    necromancer = { name = 'Necromancer', job = 'BLM', role = 'Tank', tier = 'Tank', primary = { 7 }, secondary = {  }, mechanic = 'Dark Pact' },
    nightblade = { name = 'Nightblade', job = 'NIN', role = 'Support', tier = 'Support', primary = { 9 }, secondary = {  }, mechanic = 'Reactive Seal' },
    oathbreaker = { name = 'Oathbreaker', job = 'PLD', role = 'Damage', tier = 'Damage', primary = { 4 }, secondary = {  }, mechanic = 'Reckoning Charge' },
    phantom = { name = 'Phantom', job = 'THF', role = 'Tank', tier = 'Tank', primary = { 2 }, secondary = { 9 }, mechanic = 'Phantom Decoy' },
    primalist = { name = 'Primalist', job = 'SMN', role = 'Damage', tier = 'Damage', primary = { 12 }, secondary = { 11 }, mechanic = 'Primal Conduit' },
    pugilist = { name = 'Pugilist', job = 'PUP', role = 'Damage', tier = 'Damage', primary = { 1 }, secondary = {  }, mechanic = 'Tandem Sync' },
    reaper = { name = 'Reaper', job = 'DRK', role = 'Damage', tier = 'Damage', primary = { 7 }, secondary = {  }, mechanic = 'Finality Mark' },
    ronin = { name = 'Ronin', job = 'SAM', role = 'Tank', tier = 'Tank', primary = { 10 }, secondary = {  }, mechanic = 'Mushin Purify' },
    royaltactician = { name = 'Royal Tactician', job = 'RDM', role = 'Support', tier = 'Support', primary = { 3 }, secondary = {  }, mechanic = 'Tactical Sabotage' },
    sage = { name = 'Sage', job = 'SCH', role = 'Damage', tier = 'Damage', primary = { 12 }, secondary = { 11 }, mechanic = 'Helix Theorem' },
    scarletweaver = { name = 'Scarlet Weaver', job = 'RDM', role = 'Damage', tier = 'Damage', primary = { 3 }, secondary = {  }, mechanic = 'Yin/Yang Weave' },
    scourge = { name = 'Scourge', job = 'DRK', role = 'Support', tier = 'Support', primary = { 7 }, secondary = {  }, mechanic = 'Scourge Blight' },
    sensei = { name = 'Sensei', job = 'MNK', role = 'Tank', tier = 'Tank', primary = { 12 }, secondary = {  }, mechanic = 'Dojo Counter' },
    skyborn = { name = 'Skyborn', job = 'DRG', role = 'Tank', tier = 'Tank', primary = { 8 }, secondary = {  }, mechanic = 'Grounding Cry' },
    sniper = { name = 'Sniper', job = 'RNG', role = 'Damage', tier = 'Damage', primary = { 26 }, secondary = {  }, mechanic = 'Sightline Focus' },
    spartan = { name = 'Spartan', job = 'WAR', role = 'Tank', tier = 'Tank', primary = { 8 }, secondary = {  }, mechanic = 'Spartan Grit' },
    spellblade = { name = 'Spellblade', job = 'RUN', role = 'Damage', tier = 'Damage', primary = { 4 }, secondary = {  }, mechanic = 'Conduction Surge' },
    templar = { name = 'Templar', job = 'PLD', role = 'Healer', tier = 'CombatHealer', primary = { 11 }, secondary = {  }, mechanic = 'Beacon of Light' },
    terramancer = { name = 'Terramancer', job = 'GEO', role = 'Damage', tier = 'Damage', primary = { 11 }, secondary = { 12 }, mechanic = 'Faultline Rupture' },
    trickster = { name = 'Trickster', job = 'THF', role = 'Support', tier = 'Support', primary = { 2 }, secondary = { 3 }, mechanic = 'Pass the Blame' },
    untamed = { name = 'Untamed', job = 'BST', role = 'Damage', tier = 'Damage', primary = { 6 }, secondary = { 5 }, mechanic = 'Feral Tandem' },
    valkyrie = { name = 'Valkyrie', job = 'WHM', role = 'Support', tier = 'Support', primary = { 8 }, secondary = {  }, mechanic = 'Wingmate Surge' },
    vampire = { name = 'Vampire', job = 'DNC', role = 'Healer', tier = 'CombatHealer', primary = { 2 }, secondary = { 27 }, mechanic = 'Crimson Feast' },
    vanguard = { name = 'Vanguard', job = 'PUP', role = 'Tank', tier = 'Tank', primary = { 1 }, secondary = {  }, mechanic = 'Clockwork Bulwark' },
    verdant = { name = 'Verdant', job = 'GEO', role = 'Healer', tier = 'Healer', primary = { 11 }, secondary = { 12 }, mechanic = 'Nature\'s Surge' },
    warlord = { name = 'Warlord', job = 'SAM', role = 'Support', tier = 'HybridSupport', primary = { 10 }, secondary = {  }, mechanic = 'Ashura\'s Edge' },
    warmage = { name = 'Warmage', job = 'BLU', role = 'Damage', tier = 'Damage', primary = { 3 }, secondary = { 11 }, mechanic = 'Chain Surge' },
    wyvernheart = { name = 'Wyvernheart', job = 'DRG', role = 'Healer', tier = 'CombatHealer', primary = { 8 }, secondary = {  }, mechanic = 'Wyrmscale Breath' },
    zealot = { name = 'Zealot', job = 'WHM', role = 'Damage', tier = 'Damage', primary = { 12 }, secondary = {  }, mechanic = 'Sanctified Judgment' },
}

M.NAME_TO_KEY = {}
for k, v in pairs(M.SOULS) do
    M.NAME_TO_KEY[string.lower(v.name)] = k
    M.NAME_TO_KEY[k] = k
end
M.NAME_TO_KEY['aegis templar'] = 'defender'
M.NAME_TO_KEY['aegistemplar'] = 'defender'
M.NAME_TO_KEY['shinobi'] = 'kurogane'

function M.resolveSoul(soulKey, specName)
    if type(soulKey) == 'string' and soulKey ~= '' then
        local k = M.NAME_TO_KEY[string.lower(soulKey)]
        if k then return k, M.SOULS[k] end
    end
    if type(specName) == 'string' and specName ~= '' then
        local k = M.NAME_TO_KEY[string.lower(specName)]
        if k then return k, M.SOULS[k] end
    end
    return nil, nil
end

return M
