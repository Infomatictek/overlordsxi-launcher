-- Run from the crystalsocket directory: lua tests/soul_identity_test.lua
package.path = './?.lua;' .. package.path
local identity = require('soul_identity')
local function packet(job, soul)
    return string.char(0, 0, 0, 0) .. 'OXHD'
        .. string.char(1, 1, job, #soul, 0, 0, 0, 0) .. soul
end
local a = assert(identity.decode(packet(13, 'kurogane'), 13))
assert(a.branch == 1 and a.soul == 'shinobi')
assert(identity.decode(packet(13, 'shinobi'), 13).branch == 1)
assert(identity.decode(packet(13, 'kagemusha'), 13).branch == 2)
assert(identity.decode(packet(11, 'huntsman'), 11).branch == 2)
-- Server storage keys that differ from native labels.h names
assert(identity.decode(packet(9, 'alphawarden'), 9).branch == 2)
assert(identity.decode(packet(9, 'soulbeast'), 9).branch == 2)
assert(identity.decode(packet(7, 'aegistemplar'), 7).branch == 2)
assert(identity.decode(packet(7, 'defender'), 7).branch == 2)
-- Retired Freelancer is never mapped to Mirage Sentinel
assert(identity.decode(packet(19, 'freelancer'), 19) == nil)
assert(identity.decode(packet(19, 'miragesentinel'), 19).branch == 1)
-- Negative / mismatch cases
assert(identity.decode(packet(13, 'kurogane'), 11) == nil)
assert(identity.decode(packet(13, 'flintlock'), 13) == nil)
assert(identity.decode('garbage', 13) == nil)
assert(identity.decode(packet(13, ''), 13).branch == 0)
print('Crystal Socket HUD identity tests passed.')
