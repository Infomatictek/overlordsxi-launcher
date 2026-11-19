-- Single explicit storage-key-to-display/profile-key mapping for OverlordsXI Souls.
-- Covers all 22 jobs x 3 active Souls (66 active keys) plus retired DNC branch 1.
-- Used by both the 0x1FC HUD packet path (soul_packet.lua) and the Crystal Jobs DLL
-- fallback path (soul_bridge.lua). Metadata only; server remains authoritative.
local M = {}

-- Indexed by [jobId][serverBranch] matching server OX_SPEC_<JOB> stored branch IDs.
M.ACTIVE_BY_JOB = {
    [1] = {
        [1] = { key = 'commander', storageKey = 'commander', name = 'Commander', abr = 'CDR' },
        [2] = { key = 'berserker', storageKey = 'berserker', name = 'Berserker', abr = 'BRZ' },
        [3] = { key = 'spartan', storageKey = 'spartan', name = 'Spartan', abr = 'SPT' },
    },
    [2] = {
        [1] = { key = 'sensei', storageKey = 'sensei', name = 'Sensei', abr = 'SEN' },
        [2] = { key = 'chiweaver', storageKey = 'chiweaver', name = 'Chi Weaver', abr = 'CWV' },
        [3] = { key = 'blackbelt', storageKey = 'blackbelt', name = 'Black Belt', abr = 'BLK' },
    },
    [3] = {
        [1] = { key = 'bishop', storageKey = 'bishop', name = 'Bishop', abr = 'BSH' },
        [2] = { key = 'zealot', storageKey = 'zealot', name = 'Zealot', abr = 'ZEL' },
        [3] = { key = 'valkyrie', storageKey = 'valkyrie', name = 'Valkyrie', abr = 'VLK' },
    },
    [4] = {
        [1] = { key = 'astromancer', storageKey = 'astromancer', name = 'Astromancer', abr = 'AST' },
        [2] = { key = 'channeler', storageKey = 'channeler', name = 'Channeler', abr = 'CHN' },
        [3] = { key = 'necromancer', storageKey = 'necromancer', name = 'Necromancer', abr = 'NEC' },
    },
    [5] = {
        [1] = { key = 'crimsonduelist', storageKey = 'crimsonduelist', name = 'Crimson Duelist', abr = 'DLS' },
        [2] = { key = 'royaltactician', storageKey = 'royaltactician', name = 'Royal Tactician', abr = 'RYT' },
        [3] = { key = 'scarletweaver', storageKey = 'scarletweaver', name = 'Scarlet Weaver', abr = 'SCW' },
    },
    [6] = {
        [1] = { key = 'trickster', storageKey = 'trickster', name = 'Trickster', abr = 'TRK' },
        [2] = { key = 'bandit', storageKey = 'bandit', name = 'Bandit', abr = 'BND' },
        [3] = { key = 'phantom', storageKey = 'phantom', name = 'Phantom', abr = 'PHN' },
    },
    [7] = {
        [1] = { key = 'templar', storageKey = 'templar', name = 'Templar', abr = 'TMP' },
        [2] = { key = 'defender', storageKey = 'defender', name = 'Defender', abr = 'DFN' },
        [3] = { key = 'oathbreaker', storageKey = 'oathbreaker', name = 'Oathbreaker', abr = 'OTB' },
    },
    [8] = {
        [1] = { key = 'reaper', storageKey = 'reaper', name = 'Reaper', abr = 'RPR' },
        [2] = { key = 'dreadnought', storageKey = 'dreadnought', name = 'Dreadnought', abr = 'DRN' },
        [3] = { key = 'scourge', storageKey = 'scourge', name = 'Scourge', abr = 'SCR' },
    },
    [9] = {
        [1] = { key = 'untamed', storageKey = 'untamed', name = 'Untamed', abr = 'UNT' },
        [2] = { key = 'alphawarden', storageKey = 'alphawarden', name = 'Alpha Warden', abr = 'ALW' },
        [3] = { key = 'beastspeaker', storageKey = 'beastspeaker', name = 'Beastspeaker', abr = 'BSP' },
    },
    [10] = {
        [1] = { key = 'adventurer', storageKey = 'adventurer', name = 'Adventurer', abr = 'ADV' },
        [2] = { key = 'musician', storageKey = 'musician', name = 'Musician', abr = 'MUS' },
        [3] = { key = 'minstrel', storageKey = 'minstrel', name = 'Minstrel', abr = 'MIN' },
    },
    [11] = {
        [1] = { key = 'sniper', storageKey = 'sniper', name = 'Sniper', abr = 'SNP' },
        [2] = { key = 'huntsman', storageKey = 'huntsman', name = 'Huntsman', abr = 'HNT' },
        [3] = { key = 'arcanearcher', storageKey = 'arcanearcher', name = 'Arcane Archer', abr = 'ACA' },
    },
    [12] = {
        [1] = { key = 'ronin', storageKey = 'ronin', name = 'Ronin', abr = 'RON' },
        [2] = { key = 'imperialarcher', storageKey = 'imperialarcher', name = 'Imperial Archer', abr = 'IMP' },
        [3] = { key = 'warlord', storageKey = 'warlord', name = 'Warlord', abr = 'WRL' },
    },
    [13] = {
        [1] = { key = 'shinobi', storageKey = 'kurogane', name = 'Shinobi', abr = 'KRG' },
        [2] = { key = 'kagemusha', storageKey = 'kagemusha', name = 'Kagemusha', abr = 'KGM' },
        [3] = { key = 'nightblade', storageKey = 'nightblade', name = 'Nightblade', abr = 'NGB' },
    },
    [14] = {
        [1] = { key = 'lancer', storageKey = 'lancer', name = 'Lancer', abr = 'LNC' },
        [2] = { key = 'skyborn', storageKey = 'skyborn', name = 'Skyborn', abr = 'SKY' },
        [3] = { key = 'wyvernheart', storageKey = 'wyvernheart', name = 'Wyvernheart', abr = 'WYV' },
    },
    [15] = {
        [1] = { key = 'primalist', storageKey = 'primalist', name = 'Primalist', abr = 'PRM' },
        [2] = { key = 'celestial', storageKey = 'celestial', name = 'Celestial', abr = 'CEL' },
        [3] = { key = 'herald', storageKey = 'herald', name = 'Herald', abr = 'HLD' },
    },
    [16] = {
        [1] = { key = 'warmage', storageKey = 'warmage', name = 'Warmage', abr = 'WMG' },
        [2] = { key = 'magus', storageKey = 'magus', name = 'Magus', abr = 'MAG' },
        [3] = { key = 'azurebastion', storageKey = 'azurebastion', name = 'Azure Bastion', abr = 'AZB' },
    },
    [17] = {
        [1] = { key = 'flintlock', storageKey = 'flintlock', name = 'Flintlock', abr = 'FLT' },
        [2] = { key = 'gambler', storageKey = 'gambler', name = 'Gambler', abr = 'GMB' },
        [3] = { key = 'buccaneer', storageKey = 'buccaneer', name = 'Buccaneer', abr = 'BUC' },
    },
    [18] = {
        [1] = { key = 'vanguard', storageKey = 'vanguard', name = 'Vanguard', abr = 'VNG' },
        [2] = { key = 'animist', storageKey = 'animist', name = 'Animist', abr = 'ANM' },
        [3] = { key = 'pugilist', storageKey = 'pugilist', name = 'Pugilist', abr = 'PGL' },
    },
    [19] = {
        -- Branch 1 is retired Freelancer; preserved in persistence only and never remapped.
        [2] = { key = 'vampire', storageKey = 'vampire', name = 'Vampire', abr = 'VMP' },
        [3] = { key = 'bladewheel', storageKey = 'bladewheel', name = 'Bladewheel', abr = 'BLW' },
        [4] = { key = 'miragesentinel', storageKey = 'miragesentinel', name = 'Mirage Sentinel', abr = 'MRS' },
    },
    [20] = {
        [1] = { key = 'medic', storageKey = 'medic', name = 'Medic', abr = 'MDC' },
        [2] = { key = 'sage', storageKey = 'sage', name = 'Sage', abr = 'SAG' },
        [3] = { key = 'archivist', storageKey = 'archivist', name = 'Archivist', abr = 'ARC' },
    },
    [21] = {
        [1] = { key = 'diviner', storageKey = 'diviner', name = 'Diviner', abr = 'DIV' },
        [2] = { key = 'verdant', storageKey = 'verdant', name = 'Verdant', abr = 'VRD' },
        [3] = { key = 'terramancer', storageKey = 'terramancer', name = 'Terramancer', abr = 'TRM' },
    },
    [22] = {
        [1] = { key = 'spellblade', storageKey = 'spellblade', name = 'Spellblade', abr = 'SPB' },
        [2] = { key = 'lifebinder', storageKey = 'lifebinder', name = 'Lifebinder', abr = 'LFB' },
        [3] = { key = 'inquisitor', storageKey = 'inquisitor', name = 'Inquisitor', abr = 'INQ' },
    },
}

-- Retired historical slots: recognized for persistence diagnostics, never active.
M.RETIRED_SLOTS = {
    [19] = { [1] = 'freelancer' },
}

M.RETIRED_KEYS = {
    freelancer = { job = 19, branch = 1 },
}

-- Explicit storage/legacy key -> canonical profile key mapping.
M.ALIASES = {
    kurogane = 'shinobi',
    aegistemplar = 'defender',
    soulbeast = 'alphawarden',
    gladiator = 'spartan',
    marionettist = 'vanguard',
    caller = 'celestial',
}

local byJobKey = {}
for job, branches in pairs(M.ACTIVE_BY_JOB) do
    byJobKey[job] = {}
    for branch, entry in pairs(branches) do
        entry.job = job
        entry.branch = branch
        byJobKey[job][entry.key] = entry
        byJobKey[job][entry.storageKey] = entry
    end
end

function M.canonicalKey(key)
    if type(key) ~= 'string' then return nil end
    local lower = key:lower()
    if lower == '' then return nil end
    return M.ALIASES[lower] or lower
end

function M.isRetiredKey(key)
    if type(key) ~= 'string' then return false end
    return M.RETIRED_KEYS[key:lower()] ~= nil
end

function M.isRetiredBranch(job, branch)
    return M.RETIRED_SLOTS[job] ~= nil and M.RETIRED_SLOTS[job][branch] ~= nil
end

function M.resolveBranch(job, branch)
    if type(job) ~= 'number' or type(branch) ~= 'number' then return nil end
    if M.isRetiredBranch(job, branch) then return nil end
    local branches = M.ACTIVE_BY_JOB[job]
    local entry = branches and branches[branch] or nil
    return entry and entry.key or nil
end

function M.resolveForJob(job, key)
    if type(job) ~= 'number' or type(key) ~= 'string' then return nil end
    local lower = key:lower()
    if M.RETIRED_KEYS[lower] then return nil end
    local canonical = M.ALIASES[lower] or lower
    local entries = byJobKey[job]
    local entry = entries and (entries[canonical] or entries[lower]) or nil
    return entry and entry.key or nil
end

return M
