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
assert(identity.decode(packet(13, 'kurogane'), 11) == nil)
assert(identity.decode(packet(13, 'flintlock'), 13) == nil)
assert(identity.decode('garbage', 13) == nil)
assert(identity.decode(packet(13, ''), 13).branch == 0)
print('Crystal Socket HUD identity tests passed.')
