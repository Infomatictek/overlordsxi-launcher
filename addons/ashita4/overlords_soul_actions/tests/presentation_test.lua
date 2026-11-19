-- Run from the addon directory with Lua 5.1+: lua tests/presentation_test.lua
package.path = './?.lua;' .. package.path
local catalog = require('catalog')
local presentation = require('presentation')
assert(catalog.register('astromancer', 'spell', 42, {
    name = 'Tsunami', description = 'A devastating tidal wave.' }))
assert(catalog.register('channeler', 'spell', 42, {
    name = 'Undertow', description = 'A sustained water current.' }))
assert(presentation.label(catalog, 'astromancer', 'spell', 42) == 'Tsunami')
assert(presentation.label(catalog, 'channeler', 'spell', 42) == 'Undertow')
assert(presentation.label(catalog, 'astromancer', 'spell', 99) == nil)
assert(presentation.label(catalog, nil, 'spell', 42) == nil)
assert(presentation.formatCast(catalog, 'astromancer', 'spell', 42, 'Caster') ==
    'Caster begins casting Tsunami.')
assert(presentation.description(catalog, 'channeler', 'spell', 42) ==
    'A sustained water current.')
catalog.clear()
assert(presentation.label(catalog, 'astromancer', 'spell', 42) == nil)
print('Soul presentation tests passed.')
