package.path = './?.lua;' .. package.path
local p = require('soul_packet')
assert(p.canonicalKey('kurogane') == 'shinobi')
assert(p.canonicalKey('Kurogane') == 'shinobi')
assert(p.canonicalKey('shinobi') == 'shinobi')
assert(p.canonicalKey('huntsman') == 'huntsman')
local header = string.char(0, 0, 0, 0) .. 'OXHD'
    .. string.char(1, 1, 13, 8, 0, 0, 0, 0)
local decoded = assert(p.decode(header .. 'kurogane', 13))
assert(decoded.soul == 'shinobi')
assert(p.decode(header .. 'kurogane', 11) == nil)
print('Soul packet legacy key tests passed.')
