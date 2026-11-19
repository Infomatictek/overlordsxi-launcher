package.path = './?.lua;' .. package.path
local p = require('soul_packet')
local b = require('soul_bridge')
local m = require('soul_identity_map')

local function packet(job, soul)
    return string.char(0, 0, 0, 0) .. 'OXHD'
        .. string.char(1, 1, job, #soul, 0, 0, 0, 0) .. soul
end

-- Legacy alias normalization
assert(p.canonicalKey('kurogane') == 'shinobi')
assert(p.canonicalKey('Kurogane') == 'shinobi')
assert(p.canonicalKey('shinobi') == 'shinobi')
assert(p.canonicalKey('aegistemplar') == 'defender')
assert(p.canonicalKey('soulbeast') == 'alphawarden')
assert(p.canonicalKey('gladiator') == 'spartan')
assert(p.canonicalKey('marionettist') == 'vanguard')
assert(p.canonicalKey('caller') == 'celestial')
assert(p.canonicalKey('huntsman') == 'huntsman')

-- All 22 x 3 = 66 active Souls agree across packet path and DLL branch fallback path
local count = 0
for job = 1, 22 do
    local jobCount = 0
    for branch, entry in pairs(m.ACTIVE_BY_JOB[job]) do
        count = count + 1
        jobCount = jobCount + 1
        local fromPacket = assert(p.decode(packet(job, entry.storageKey), job))
        assert(fromPacket.soul == entry.key, 'packet mismatch for ' .. entry.storageKey)
        local fromDll = b.resolve({ enabled = 1, known = 1, job = job, branch = branch, character_id = 42 }, job, 42)
        assert(fromDll == entry.key, 'dll fallback mismatch for job ' .. job .. ' branch ' .. branch)
    end
    assert(jobCount == 3, 'job ' .. job .. ' must have exactly 3 active Souls')
end
assert(count == 66, 'expected 66 active Souls, got ' .. tostring(count))

-- Specific audited discrepancies: NIN, PLD, BST, PUP, DNC, RNG
assert(p.decode(packet(13, 'kurogane'), 13).soul == 'shinobi')
assert(p.decode(packet(13, 'kurogane'), 11) == nil)
assert(p.decode(packet(7, 'aegistemplar'), 7).soul == 'defender')
assert(p.decode(packet(9, 'alphawarden'), 9).soul == 'alphawarden')
assert(p.decode(packet(9, 'soulbeast'), 9).soul == 'alphawarden')
assert(b.resolve({ enabled = 1, known = 1, job = 9, branch = 2, character_id = 42 }, 9, 42) == 'alphawarden')
assert(b.resolve({ enabled = 1, known = 1, job = 18, branch = 2, character_id = 42 }, 18, 42) == 'animist')
assert(b.resolve({ enabled = 1, known = 1, job = 18, branch = 3, character_id = 42 }, 18, 42) == 'pugilist')
assert(b.resolve({ enabled = 1, known = 1, job = 19, branch = 2, character_id = 42 }, 19, 42) == 'vampire')
assert(b.resolve({ enabled = 1, known = 1, job = 19, branch = 3, character_id = 42 }, 19, 42) == 'bladewheel')
assert(b.resolve({ enabled = 1, known = 1, job = 19, branch = 4, character_id = 42 }, 19, 42) == 'miragesentinel')

-- Retired DNC branch 1 (Freelancer) never silently maps to Mirage Sentinel
assert(b.resolve({ enabled = 1, known = 1, job = 19, branch = 1, character_id = 42 }, 19, 42) == nil)
local retired = assert(p.decode(packet(19, 'freelancer'), 19))
assert(retired.soul == nil and retired.retired == 'freelancer')

-- Empty / absent / wrong-character / wrong-job safety
assert(p.decode(packet(13, ''), 13).soul == nil)
assert(p.decode(packet(13, 'flintlock'), 13) == nil)
assert(b.resolve({ enabled = 1, known = 1, job = 13, branch = 1, character_id = 42 }, 13, 99) == nil)
assert(b.resolve({ enabled = 1, known = 0, job = 13, branch = 1, character_id = 42 }, 13, 42) == nil)
assert(b.resolve(nil, 13, 42) == nil)

print('Soul packet and bridge identity tests passed (66 active Souls + retired DNC 1).')
