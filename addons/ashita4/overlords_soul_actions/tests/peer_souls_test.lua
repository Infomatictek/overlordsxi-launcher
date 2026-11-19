package.path = './?.lua;' .. package.path
local peers = require('peer_souls')
local soulPacket = require('soul_packet')
local nativeActions = require('native_actions')
local catalog = require('catalog')
local builtins = require('builtin_profiles')
local combatLog = require('combat_log')

local function u32(v)
    return string.char(v%256, math.floor(v/256)%256, math.floor(v/65536)%256, math.floor(v/16777216)%256)
end

-- Exact wire format matching server overlords_soul_action_peers.cpp makePacket()
local function packet(op, name, soul, job, branch, actor, character)
    local raw = 22 + #name + #soul
    local padded = math.floor((raw + 3) / 4) * 4
    local pad = string.rep('\0', padded - raw)
    return string.rep('\0',4) .. 'OXSI' .. string.char(1,op) .. u32(actor)
        .. u32(character) .. string.char(job,branch,#name,#soul)
        .. name .. soul .. pad
end

local cache = peers.new()
local raw = packet(1, 'OtherNinja', 'shinobi', 13, 1, 54321, 54321)
assert(#raw % 4 == 0)
assert(peers.decode(raw).name == 'OtherNinja')
assert(peers.observe(cache, raw, 100, nativeActions.soulToPair, soulPacket.canonicalKey))
assert(cache.count == 1)
assert(peers.get(cache, 'OtherNinja', 101).soul == 'shinobi')
assert(peers.get(cache, 'OtherNinja', 221) == nil)
assert(cache.count == 0)

-- Rejection diagnostics must distinguish malformed envelopes from valid
-- packets whose Soul/job/branch pair is inconsistent with the catalog.
local malformed, malformedReason = peers.decode(raw:sub(1, #raw - 6))
assert(malformed == nil and malformedReason == 'packet_length')
local badPair, pairReason = peers.observe(cache,
    packet(1, 'OtherNinja', 'shinobi', 13, 2, 54322, 54322),
    102, nativeActions.soulToPair, soulPacket.canonicalKey)
assert(not badPair and pairReason == 'soul_job_branch_mismatch')
local badHeader, headerReason = peers.decode(
    packet(1, 'OtherNinja', 'shinobi', 13, 1, 54322, 54322):gsub('OXSI', 'OXZZ'))
assert(badHeader == nil and headerReason == 'magic_mismatch')
local shortPacket, shortReason = peers.decode('----OXSI')
assert(shortPacket == nil and shortReason == 'envelope_short')
-- Ashita may provide the whole fixed 512-byte incoming buffer.
-- Only the header-declared payload may be interpreted as a Soul identity.
local padded512 = raw .. string.rep('\\0', 512 - #raw)
local parsed512, reason512 = peers.decode(padded512)
assert(parsed512 and parsed512.name == 'OtherNinja' and reason512 == nil)
local accepted512, acceptedReason = peers.observe(cache, padded512, 101,
    nativeActions.soulToPair, soulPacket.canonicalKey)
assert(accepted512 and acceptedReason == 'accepted')
local corruptedTail = padded512:sub(1, 511) .. string.char(1)
local rejectedTail, tailReason = peers.decode(corruptedTail)
assert(rejectedTail == nil and tailReason == 'host_buffer_nonzero')
local longPacket, longReason = peers.decode(raw .. string.rep('\\0', 513 - #raw))
assert(longPacket == nil and longReason == 'envelope_long')

-- Legacy key kurogane normalizes to shinobi over the wire.
local legacyPkt = packet(1, 'Kage', 'kurogane', 13, 1, 60001, 60001)
assert(peers.observe(cache, legacyPkt, 250, nativeActions.soulToPair, soulPacket.canonicalKey))
assert(peers.get(cache, 'Kage', 251).soul == 'shinobi')
assert(cache.count == 1)

-- Repeated packet refreshes cleanly without duplicating count.
assert(peers.observe(cache, legacyPkt, 251, nativeActions.soulToPair, soulPacket.canonicalKey))
assert(cache.count == 1)

-- Inconsistent branch is rejected without removing existing valid identity.
assert(not peers.observe(cache, packet(1, 'Kage', 'shinobi', 13, 2, 60001, 60001), 252, nativeActions.soulToPair, soulPacket.canonicalKey))
assert(cache.count == 1)
assert(peers.get(cache, 'Kage', 252).soul == 'shinobi')

-- Wrong magic (e.g., OXHD / OXZZ) is rejected.
assert(not peers.observe(cache, packet(1, 'Kage', 'shinobi', 13, 1, 60001, 60001):gsub('OXSI', 'OXHD'), 253, nativeActions.soulToPair, soulPacket.canonicalKey))

-- Soul swap (shinobi -> kagemusha) updates identity for same actor.
assert(peers.observe(cache, packet(1, 'Kage', 'kagemusha', 13, 2, 60001, 60001), 254, nativeActions.soulToPair, soulPacket.canonicalKey))
assert(peers.get(cache, 'Kage', 255).soul == 'kagemusha')
assert(cache.count == 1)

-- Entity-ID reuse: same actor ID now belongs to a different character name.
assert(peers.observe(cache, packet(1, 'NewChar', 'nightblade', 13, 3, 60001, 60001), 256, nativeActions.soulToPair, soulPacket.canonicalKey))
assert(peers.get(cache, 'Kage', 257) == nil)
assert(peers.get(cache, 'NewChar', 257).soul == 'nightblade')
assert(cache.count == 1)

-- Revoke (range exit / job change / disconnect / zone out) clears actor.
assert(peers.observe(cache, packet(0, 'NewChar', '', 13, 0, 60001, 60001), 261, nativeActions.soulToPair, soulPacket.canonicalKey))
assert(cache.count == 0)

-- Multi-caster combat-log isolation: two nearby players share vanilla spell 338 (Utsusemi: Ichi)
-- with DIFFERENT Souls, while an unannounced third player keeps the vanilla name.
catalog.clear()
builtins.install(catalog)
assert(catalog.register('kagemusha', 'spell', 338, {
    name = 'Decoy Shadows: Ichi',
    description = 'Kagemusha shadow decoy.',
}))
local function getVanilla(kind, id)
    if kind == 'spell' and id == 338 then return 'Utsusemi: Ichi' end
    return nil
end

assert(peers.observe(cache, packet(1, 'Kage', 'shinobi', 13, 1, 70001, 70001), 300, nativeActions.soulToPair, soulPacket.canonicalKey))
assert(peers.observe(cache, packet(1, 'Mirage', 'kagemusha', 13, 2, 70002, 70002), 300, nativeActions.soulToPair, soulPacket.canonicalKey))

local function rewritePeerLine(line, now)
    for _, peer in pairs(cache.byActor) do
        if peers.get(cache, peer.name, now) then
            local rep = combatLog.rewriteLine(line, peer.name, catalog, peer.soul, getVanilla)
            if rep then return rep end
        end
    end
    return line
end

local pfx = string.char(0x1F, 0x30)
assert(rewritePeerLine(pfx .. 'Kage starts casting Utsusemi: Ichi on Kage.', 305)
    == pfx .. 'Kage starts casting Shadow Squadron: Ichi on Kage.')
assert(rewritePeerLine(pfx .. 'Mirage starts casting Utsusemi: Ichi on Mirage.', 305)
    == pfx .. 'Mirage starts casting Decoy Shadows: Ichi on Mirage.')
assert(rewritePeerLine(pfx .. 'Vanilla starts casting Utsusemi: Ichi on Vanilla.', 305)
    == pfx .. 'Vanilla starts casting Utsusemi: Ichi on Vanilla.')

-- Colorized spell name inside combat log line (Phase 4 regression guard).
local colored = string.char(0x1F, 0x30) .. 'Rin starts casting ' .. string.char(0x1E, 0x02) .. 'Utsusemi: Ichi' .. string.char(0x1E, 0x01) .. ' on Rin.'
local coloredOut = combatLog.rewriteLine(colored, 'Rin', catalog, 'shinobi', getVanilla)
assert(coloredOut == string.char(0x1F, 0x30) .. 'Rin starts casting ' .. string.char(0x1E, 0x02) .. 'Shadow Squadron: Ichi' .. string.char(0x1E, 0x01) .. ' on Rin.')

-- Zone clear empties cache.
peers.clear(cache)
assert(cache.count == 0)
assert(rewritePeerLine(pfx .. 'Kage starts casting Utsusemi: Ichi on Kage.', 306)
    == pfx .. 'Kage starts casting Utsusemi: Ichi on Kage.')

print('Nearby Soul identity envelope, multi-caster isolation, and expiry tests passed.')
