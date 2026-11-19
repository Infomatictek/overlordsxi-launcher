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
    if type(data) ~= 'string' then return nil, 'not_string' end
    if data:sub(5,8) ~= 'OXSI' then return nil, 'magic_mismatch' end
    if #data < 24 then return nil, 'envelope_short' end
    if #data > 160 then return nil, 'envelope_long' end
    local ver,op = data:byte(9,10)
    local actor = u32(data, 11)
    local character = u32(data, 15)
    local job,branch,nlen,slen = data:byte(19,22)
    if ver ~= 1 or (op ~= 0 and op ~= 1) then return nil, 'version_or_operation' end
    if not actor or actor == 0 or not character or character == 0 then
        return nil, 'actor_identity'
    end
    if not job or job < 1 or job > 22 or not branch or branch > 3
        or not nlen or nlen > 24 or not slen or slen > 64 then
        return nil, 'header_fields'
    end
    local payloadSize = 22 + nlen + slen
    if #data < payloadSize or #data > payloadSize + 3 then
        return nil, 'packet_length'
    end
    local padding = data:sub(payloadSize + 1)
    if padding ~= '' and padding:find('[^%z]') then return nil, 'nonzero_padding' end
    local name = data:sub(23,22+nlen)
    local soul = data:sub(23+nlen,22+nlen+slen)
    if not validName(name) then return nil, 'actor_name' end
    if op == 1 and (branch == 0 or not validSoul(soul)) then
        return nil, 'soul_fields'
    end
    if op == 0 and (branch ~= 0 or slen ~= 0) then
        return nil, 'revoke_fields'
    end
    return {op=op,actor=actor,character=character,job=job,branch=branch,
        name=name,soul=(op == 1 and soul or nil)}
end
function M.new()
    return {byName={},byActor={},count=0}
end
function M.clear(cache)
    cache.byName,cache.byActor,cache.count = {},{},0
end
function M.observe(cache, data, now, resolvePair, canonicalKey)
    local payload, reason = M.decode(data)
    if not payload then return false, reason end
    if type(now) ~= 'number' or type(resolvePair) ~= 'function' then
        return false, 'resolver_unavailable'
    end
    if payload.op == 1 and type(canonicalKey) == 'function' then
        local canonical = canonicalKey(payload.soul)
        if not validSoul(canonical) then return false, 'unknown_canonical_key' end
        payload.soul = canonical
    end
    -- Reject inconsistent Soul announcements before touching a valid cache.
    if payload.op == 1 then
        local job, branch = resolvePair(payload.soul)
        if job ~= payload.job or branch ~= payload.branch then return false, 'soul_job_branch_mismatch' end
    end
    local key = payload.name:lower()
    local previous = cache.byActor[payload.actor]
    if previous then
        cache.byName[previous.name:lower()] = nil
        cache.byActor[payload.actor] = nil
        cache.count = cache.count - 1
    end
    if payload.op == 0 then return true, 'revoked' end
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
    return true, 'accepted'
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
