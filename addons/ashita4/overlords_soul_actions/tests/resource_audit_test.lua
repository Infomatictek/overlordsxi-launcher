package.path = './?.lua;' .. package.path
local audit = require('resource_audit')
local spell = {Name = {[2] = 'Utsusemi: Ichi'}, Description = {[2] = 'Creates shadows.'}, ManaCost = 18, CastTime = 16, RecastDelay = 120}
local ability = {Name = {[2] = 'Test Ability'}, Description = {[2] = 'Performs an action.'}, ManaCost = 0}
local mock = {}
function mock:GetSpellById(id) if id == 338 then return spell end end
function mock:GetAbilityById(id) if id == 150 then return ability end end
local root = '.'
assert(audit.start(mock, root))
assert(audit.running())
local complete
for i = 1, 100 do
    complete = audit.step(40)
    if complete.complete then break end
end
assert(complete and complete.complete and complete.count == 2)
assert(not audit.running())
local f = assert(io.open(complete.path, 'rb'))
local data = f:read('*a')
f:close()
assert(data:find('spell\t338\tUtsusemi: Ichi', 1, true))
assert(data:find('ability\t150\tTest Ability', 1, true))
os.remove(complete.path)
print('Soul native action resource audit tests passed.')
