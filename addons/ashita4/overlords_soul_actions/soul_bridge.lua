-- Client-only active Soul bridge via the existing crystaljobs.dll status export.
-- Does not send packets, alter the server, or inspect arbitrary client memory.
local identityMap = require('soul_identity_map')
local M = {}
function M.resolve(status, job, character)
    if type(status) ~= 'table' or type(job) ~= 'number' or type(character) ~= 'number'
        or character <= 0 or job <= 0 or job > 22 then return nil end
    if status.enabled ~= 1 or status.known ~= 1 or status.job ~= job
        or status.character_id ~= character then return nil end
    return identityMap.resolveBranch(job, status.branch)
end
local okFfi, ffi = pcall(require, 'ffi')
local status_t
if okFfi and ffi then
    pcall(ffi.cdef, 'void* __stdcall GetModuleHandleA(const char*);')
    pcall(ffi.cdef, 'void* __stdcall GetProcAddress(void*, const char*);')
    local ok, tp = pcall(ffi.typeof, [=[struct {
        uint32_t size, version, enabled, hooks, character_id, job, known, branch;
        uint32_t search_rows, decoded_rows, item_labels, search_labels, full_labels;
        uint32_t queries_sent, replies_accepted, replies_rejected, last_error;
    }[1]]=])
    if ok then status_t = tp end
end
function M.read()
    if not (ffi and status_t) then return nil end
    local ok, status = pcall(function()
        local handle = ffi.C.GetModuleHandleA('crystaljobs.dll')
        if handle == nil then return nil end
        local addr = ffi.C.GetProcAddress(handle, 'CrystalJobsGetStatus')
        if addr == nil then return nil end
        local fn = ffi.cast('uint32_t (__stdcall *)(void*, uint32_t)', addr)
        local buf = ffi.new(status_t)
        if fn(buf, ffi.sizeof(buf)) ~= 0 or buf[0].size ~= 68 or buf[0].version ~= 1 then return nil end
        return {enabled=tonumber(buf[0].enabled),known=tonumber(buf[0].known),
            job=tonumber(buf[0].job),branch=tonumber(buf[0].branch),
            character_id=tonumber(buf[0].character_id)}
    end)
    return ok and status or nil
end
return M
