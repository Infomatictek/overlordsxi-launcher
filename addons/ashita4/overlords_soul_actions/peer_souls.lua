-- Server-announced nearby player Soul identities. Presentation only.
-- Packet envelope (FFXI 0x1FC custom): bytes 5..8 = OXSI, version 1.
-- Must only be populated from a verified server packet, never by guessing a
-- player's Soul from the vanilla action ID or their base job.
local M = {}
local MAX_AGE = 120
local MAX_PEERS = 128
local function u32(data, i)
    local a,b,c,d = data:byte(i, i + 3)
    if not d then return nil end
    return a + b*256 + c*65536 + d*16777216
end
local function validName(s)
    return type(s) == 'string' and #s >= 2 and #s <= 24
        and s:match('^[%a][%w_%-]*$') ~= nil
end
local function validSoul(s)
    return type(s) == 'string' and #s >= 2 and #s <= 64
        and s:match('^[%w_%-]+$') ~= nil
end
-- version, operation (1=upsert 0=remove), actor ID, character ID,
-- job, branch, nameLen, soulLen, name, Soul key.
-- No networking is initiated by this module.
function M.decode(data)
    if type(data) ~= 'string' or #data < 24 or #data > 160
        or data:sub(5,8) ~= 'OXSI' then return nil end
    local ver,op = data:byte(9,10)
    local actor = u32(data, 11)
    local character = u32(data, 15)
    local job,branch,nlen,slen = data:byte(19,22)
    if ver ~= 1 or (op ~= 0 and op ~= 1) or not actor or actor == 0
        or not character or character == 0 or not job or job < 1 or job > 22
        or not branch or branch > 3 or not nlen or nlen > 24
        or not slen or slen > 64 or #data ~= 22+nlen+slen then return nil end
    local name = data:sub(23,22+nlen)
    local soul = data:sub(23+nlen,22+nlen+slen)
    if not validName(name) then return nil end
    if op == 1 and (branch == 0 or not validSoul(soul)) then return nil end
    if op == 0 and (branch ~= 0 or slen ~= 0) then return nil end
    return {op=op,actor=actor,character=character,job=job,branch=branch,
        name=name,soul=(op == 1 and soul or nil)}
end
function M.new()
    return {byName={},byActor={},count=0}
end
function M.clear(cache)
    cache.byName,cache.byActor,cache.count = {},{},0
end
function M.observe(cache, data, now, resolvePair)
    local payload = M.decode(data)
    if not payload or type(now) ~= 'number' or type(resolvePair) ~= 'function' then return false end
    local key = payload.name:lower()
    local previous = cache.byActor[payload.actor]
    if previous then
        cache.byName[previous.name:lower()] = nil
        cache.byActor[payload.actor] = nil
        cache.count = cache.count - 1
    end
    if payload.op == 0 then return true end
    local job, branch = resolvePair(payload.soul)
    if job ~= payload.job or branch ~= payload.branch then return false end
    local other = cache.byName[key]
    if other then
        cache.byActor[other.actor] = nil
        cache.count = cache.count - 1
    end
    if cache.count >= MAX_PEERS then M.clear(cache) end
    local entry={actor=payload.actor,character=payload.character,job=payload.job,
        branch=payload.branch,name=payload.name,soul=payload.soul,expires=now+MAX_AGE}
    cache.byName[key],cache.byActor[payload.actor] = entry,entry
    cache.count = cache.count + 1
    return true
end
function M.get(cache, name, now)
    if not validName(name) or type(now) ~= 'number' then return nil end
    local entry = cache.byName[name:lower()]
    if not entry then return nil end
    if now <= entry.expires then return entry end
    cache.byName[name:lower()] = nil
    cache.byActor[entry.actor] = nil
    cache.count = cache.count - 1
    return nil
end
return M
