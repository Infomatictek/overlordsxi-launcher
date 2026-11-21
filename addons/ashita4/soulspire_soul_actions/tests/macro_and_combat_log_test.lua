package.path = './?.lua;' .. package.path
local catalog = require('catalog')
local builtins = require('builtin_profiles')
local macroResolver = require('macro_resolver')
local combatLog = require('combat_log')
local nativeActions = require('native_actions')

catalog.clear()
assert(builtins.install(catalog) == 160)
assert(catalog.register('shinobi', 'weaponskill', 128, {
    name = 'Shadow Rend',
    description = 'Shinobi shadow-infused weapon skill.',
}))
assert(catalog.register('shinobi', 'ability', 600, {
    name = 'Phantom Veil',
    description = 'Shinobi stealth stance.',
}))

local vanilla = {
    spell = {
        [320] = 'Katon: Ichi',
        [323] = 'Hyoton: Ichi',
        [326] = 'Huton: Ichi',
        [329] = 'Doton: Ichi',
        [332] = 'Raiton: Ichi',
        [335] = 'Suiton: Ichi',
        [338] = 'Utsusemi: Ichi',
        [339] = 'Utsusemi: Ni',
    },
    weaponskill = { [128] = 'Blade: Jin' },
    ability = { [600] = 'Yonin' },
}
local function getVanilla(kind, id)
    return vanilla[kind] and vanilla[kind][id] or nil
end

-- Macro & command resolution tests.
assert(macroResolver.translate('/ma "Shadow Squadron: Ichi" <me>', catalog, 'shinobi', getVanilla)
    == '/ma "Utsusemi: Ichi" <me>')
assert(macroResolver.translate('/nin "shadow squadron: ni" <me>', catalog, 'shinobi', getVanilla)
    == '/nin "Utsusemi: Ni" <me>')
assert(macroResolver.translate('/ma "False Assault" <t>', catalog, 'shinobi', getVanilla)
    == '/ma "Katon: Ichi" <t>')
assert(macroResolver.translate('/ma "Crosscut" <t>', catalog, 'shinobi', getVanilla)
    == '/ma "Huton: Ichi" <t>')
assert(macroResolver.translate('/ma "Final Mirage" <t>', catalog, 'shinobi', getVanilla)
    == '/ma "Suiton: Ichi" <t>')
assert(macroResolver.translate('/ws "Shadow Rend" <t>', catalog, 'shinobi', getVanilla)
    == '/ws "Blade: Jin" <t>')
assert(macroResolver.translate('/ja "Phantom Veil" <me>', catalog, 'shinobi', getVanilla)
    == '/ja "Yonin" <me>')
assert(macroResolver.translate('/ma "Utsusemi: Ichi" <me>', catalog, 'shinobi', getVanilla) == nil)
assert(macroResolver.translate('/ma "Shadow Squadron: Ichi" <me>', catalog, 'kagemusha', getVanilla) == nil)
assert(macroResolver.translate('/ma "Shadow Squadron: Ichi" <me>', catalog, nil, getVanilla) == nil)

-- Local-player-only combat log rewriting tests.
assert(combatLog.rewriteLine('Nappy starts casting Utsusemi: Ichi.', 'Nappy', catalog, 'shinobi', getVanilla)
    == 'Nappy starts casting Shadow Squadron: Ichi.')
assert(combatLog.rewriteLine('Nappy casts Utsusemi: Ni.', 'Nappy', catalog, 'shinobi', getVanilla)
    == 'Nappy casts Shadow Squadron: Ni.')
assert(combatLog.rewriteLine('\x1f\x01Nappy uses Yonin.', 'Nappy', catalog, 'shinobi', getVanilla)
    == '\x1f\x01Nappy uses Phantom Veil.')
-- Never rewrite other players or prefix-colliding names.
assert(combatLog.rewriteLine('OtherNinja starts casting Utsusemi: Ichi.', 'Nappy', catalog, 'shinobi', getVanilla) == nil)
assert(combatLog.rewriteLine('NappyTwo starts casting Utsusemi: Ichi.', 'Nappy', catalog, 'shinobi', getVanilla) == nil)
assert(combatLog.rewriteLine('Nappy starts casting Utsusemi: Ichi.', 'Nappy', catalog, 'kagemusha', getVanilla) == nil)
-- The alias must be the action token, never a target or later message text.
assert(combatLog.rewriteLine('Nappy uses Provoke on Utsusemi: Ichi.',
    'Nappy', catalog, 'shinobi', getVanilla) == nil)
assert(combatLog.rewriteLine('Nappy starts casting Provoke on Utsusemi: Ichi.',
    'Nappy', catalog, 'shinobi', getVanilla) == nil)
assert(combatLog.rewriteLine('Nappy casts Utsusemi: Ichi on Utsusemi: Ichi.',
    'Nappy', catalog, 'shinobi', getVanilla)
    == 'Nappy casts Shadow Squadron: Ichi on Utsusemi: Ichi.')
assert(combatLog.rewriteLine('Nappy casts Utsusemi: Ichi.',
    'Nappy', catalog, 'kagemusha', getVanilla) == nil)
local function stoneName(kind, id)
    return kind == 'spell' and id == 160 and 'Stone II' or nil
end
assert(combatLog.rewriteLine('Rin starts casting Stone II on Goblin Butcher.',
    'Rin', catalog, 'terramancer', stoneName)
    == 'Rin starts casting Shallow Fault on Goblin Butcher.')
assert(combatLog.rewriteLine('Rin starts casting Stone II on Goblin Butcher.',
    'Rin', catalog, 'shinobi', stoneName) == nil)
assert(combatLog.rewriteLine('Rin uses Provoke on Stone II.',
    'Rin', catalog, 'terramancer', stoneName) == nil)

-- Actual local cast lines include targets, and resource managers can expose
-- multiple localized names for one underlying spell ID.
local function aliases(kind, id)
    if kind == 'spell' and id == 338 then return {'Faux shadow name', 'Utsusemi: Ichi'} end
    return getVanilla(kind, id)
end
local repaired, reason = combatLog.rewriteLine(
    'Rin starts casting Utsusemi: Ichi on Rin.', 'Rin', catalog, 'shinobi', aliases)
assert(repaired == 'Rin starts casting Shadow Squadron: Ichi on Rin.')
assert(reason == 'rewritten')
assert(combatLog.rewriteLine(
    'Other starts casting Utsusemi: Ichi on Rin.', 'Rin', catalog, 'shinobi', aliases) == nil)
local _, mismatch = combatLog.rewriteLine(
    'Rin starts casting Unknown Spell on Rin.', 'Rin', catalog, 'shinobi', aliases)
assert(mismatch == 'name_mismatch')
local _, unknown = combatLog.rewriteLine(
    'Rin starts casting Utsusemi: Ichi on Rin.', 'Rin', catalog, 'shinobi', function() return nil end)
assert(unknown == 'vanilla_unavailable')
assert(combatLog.rewriteLine(
    'Rin starts casting Utsusemi: IchiX on Rin.', 'Rin', catalog, 'shinobi', aliases) == nil)

-- Live FFXI text can begin with color markers with printable parameters.
local colorPrefix = string.char(0x1F, 0x30)
local localCast = colorPrefix .. 'Rin starts casting Utsusemi: Ichi on Rin.'
assert(combatLog.rewriteLine(localCast, 'Rin', catalog, 'shinobi', aliases)
    == colorPrefix .. 'Rin starts casting Shadow Squadron: Ichi on Rin.')
assert(combatLog.rewriteLine('Other Rin starts casting Utsusemi: Ichi.',
    'Rin', catalog, 'shinobi', aliases) == nil)
assert(combatLog.rewriteLine('NinRin starts casting Utsusemi: Ichi.',
    'Rin', catalog, 'shinobi', aliases) == nil)
assert(combatLog.rewriteLine(colorPrefix .. 'OtherRin starts casting Utsusemi: Ichi.',
    'Rin', catalog, 'shinobi', aliases) == nil)

-- Real client messages can carry longer digit/punctuation color parameters
-- and optional timestamps ahead of the caster. They must not be mistaken
-- for another player's name.
local extended = string.char(0x1F) .. '30:20' .. string.char(0x1E, 0x02)
local expected = 'Rin starts casting Shadow Squadron: Ichi on Rin.'
local vanillaCast = 'Rin starts casting Utsusemi: Ichi on Rin.'
assert(combatLog.rewriteLine(extended .. vanillaCast, 'Rin', catalog, 'shinobi', aliases)
    == extended .. expected)
assert(combatLog.rewriteLine('[16:32:04] ' .. vanillaCast,
    'Rin', catalog, 'shinobi', aliases) == '[16:32:04] ' .. expected)
assert(combatLog.rewriteLine(extended .. 'Other Rin starts casting Utsusemi: Ichi on Other Rin.',
    'Rin', catalog, 'shinobi', aliases) == nil)
assert(combatLog.rewriteLine(extended .. 'OtherRin starts casting Utsusemi: Ichi on OtherRin.',
    'Rin', catalog, 'shinobi', aliases) == nil)
assert(combatLog.rewriteLine('Offset starts casting Utsusemi: Ichi on Rin.',
    'Rin', catalog, 'shinobi', aliases) == nil)
assert(combatLog.rewriteLine('Rin asks: Offset starts casting Utsusemi: Ichi on Offset.',
    'Offset', catalog, 'shinobi', aliases) == nil)

-- Exact 15-byte prefix captured from Rin's 16:39:04 Ashita text_in event:
-- 1E 51 5B 31 36 3A 33 39 3A 30 34 5D 1E 01 20
local actualTimestamp = string.char(0x1E) .. 'Q[16:39:04]'
    .. string.char(0x1E, 0x01) .. ' '
assert(#actualTimestamp == 15)
assert(combatLog.rewriteLine(actualTimestamp .. vanillaCast,
    'Rin', catalog, 'shinobi', aliases) == actualTimestamp .. expected)
assert(combatLog.rewriteLine(actualTimestamp .. 'Offset starts casting Utsusemi: Ichi on Rin.',
    'Rin', catalog, 'shinobi', aliases) == nil)
assert(combatLog.rewriteLine(actualTimestamp .. 'OtherRin starts casting Utsusemi: Ichi on OtherRin.',
    'Rin', catalog, 'shinobi', aliases) == nil)
assert(combatLog.rewriteLine(actualTimestamp .. 'Rin starts casting '
    .. string.char(0x1F, 0x30) .. 'Utsusemi: Ichi on Rin.',
    'Rin', catalog, 'shinobi', aliases)
    == actualTimestamp .. 'Rin starts casting ' .. string.char(0x1F, 0x30)
        .. 'Shadow Squadron: Ichi on Rin.')
assert(combatLog.rewriteLine(string.char(0x1E) .. 'Q[16:39:04] Other '
    .. vanillaCast, 'Rin', catalog, 'shinobi', aliases) == nil)

-- Verify all 66 Souls resolve to distinct valid (job, branch) pairs.
local seen = {}
local count = 0
local allSouls = {
    'commander','berserker','spartan','sensei','chiweaver','blackbelt','bishop','zealot','valkyrie',
    'astromancer','channeler','necromancer','crimsonduelist','royaltactician','scarletweaver',
    'trickster','bandit','phantom','templar','defender','oathbreaker','reaper','dreadnought','scourge',
    'untamed','soulbeast','beastspeaker','adventurer','musician','minstrel','sniper','huntsman','arcanearcher',
    'ronin','imperialarcher','warlord','shinobi','kagemusha','nightblade','lancer','skyborn','wyvernheart',
    'primalist','celestial','herald','warmage','magus','azurebastion','flintlock','gambler','buccaneer',
    'vanguard','pugilist','animist','miragesentinel','vampire','bladewheel','medic','sage','archivist',
    'diviner','verdant','terramancer','spellblade','lifebinder','inquisitor',
}
for _, key in ipairs(allSouls) do
    local job, branch = nativeActions.soulToPair(key)
    assert(job and job >= 1 and job <= 22 and branch and branch >= 1 and branch <= 3, 'Bad pair for ' .. key)
    local tag = job .. ':' .. branch
    assert(not seen[tag], 'Duplicate pair ' .. tag)
    seen[tag] = true
    count = count + 1
end
assert(count == 66)

print('Macro resolver, local combat log, and 66-Soul mapping tests passed.')
