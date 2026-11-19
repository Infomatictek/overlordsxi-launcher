package.path = './?.lua;' .. package.path
local profiles = require('profiles')
local catalog = require('catalog')
local good = 'astromancer\tspell\t42\tTsunami\tA tidal wave.\n'
local rows = assert(profiles.parse(good))
assert(#rows == 1 and rows[1].name == 'Tsunami')
assert(profiles.parse('astromancer\tspell\t-1\tBad\tInvalid.\n') == nil)
assert(profiles.parse('astromancer\tspell\t42\tBad\n') == nil)
assert(profiles.parse(('x'):rep(262145)) == nil)
print('Soul profile parser tests passed.')
