-- Client-only reader for the existing OverlordsXI HUD identity packet (0x1FC).
-- Its soul key is metadata, not authority to cast or grant actions.
local identityMap = require('soul_identity_map')
local M = {}
function M.canonicalKey(key)
    return identityMap.canonicalKey(key)
end
function M.decode(data, currentJob)
    if type(data) ~= 'string' or #data < 16 or #data > 4096
        or data:sub(5, 8) ~= 'OXHD' then return nil end
    local version, unlocked, job, keyLength, kvLo, kvHi = data:byte(9, 14)
    if version ~= 1 or (unlocked ~= 0 and unlocked ~= 1)
        or not job or job < 1 or job > 22
        or not keyLength or keyLength > 64 or not kvLo or not kvHi then return nil end
    local kvLength = kvLo + 256 * kvHi
    if #data < 16 + keyLength + kvLength then return nil end
    if type(currentJob) == 'number' and currentJob > 0 and job ~= currentJob then return nil end
    local soul = data:sub(17, 16 + keyLength)
    if keyLength == 0 then return {job = job, soul = nil, unlocked = unlocked == 1} end
    if not soul:match('^[%w_%-]+$') then return nil end
    if identityMap.isRetiredKey(soul) then
        return {job = job, soul = nil, retired = soul:lower(), unlocked = unlocked == 1}
    end
    local resolved = identityMap.resolveForJob(job, soul)
    if not resolved then return nil end
    return {job = job, soul = resolved, unlocked = unlocked == 1}
end
return M
