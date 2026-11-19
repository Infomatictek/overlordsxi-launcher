local Labels = {}
Labels.__index = Labels
local ffi = require('ffi')
local soulIdentity = require('soul_identity')
pcall(ffi.cdef, 'void* __stdcall GetModuleHandleA(const char* name);')
pcall(ffi.cdef, 'void* __stdcall LoadLibraryA(const char* path);')
pcall(ffi.cdef, 'void* __stdcall GetProcAddress(void* module, const char* name);')
local status_type = ffi.typeof([=[struct {
    uint32_t size, version, enabled, hooks, character_id, job, known, branch;
    uint32_t search_rows, decoded_rows, item_labels, search_labels, full_labels;
    uint32_t queries_sent, replies_accepted, replies_rejected, last_error;
}[1]]=])

-- Cache named function-pointer types once. Re-parsing an anonymous FFI
-- function-pointer signature on every render/sync can exhaust LuaJIT's type
-- table after prolonged idle time ("table overflow").
local signature_types = {
    CrystalJobsGetStatus = ffi.typeof('uint32_t (__stdcall *)(void*, uint32_t)'),
    CrystalJobsSetState = ffi.typeof('uint32_t (__stdcall *)(const uint8_t*, uint32_t)'),
    CrystalJobsInitialize = ffi.typeof('uint32_t (__stdcall *)(void)'),
}
local exported = {}
local state_bytes_type = ffi.typeof('uint8_t[8]')
local function loaded_function(name)
    local module = ffi.C.GetModuleHandleA('crystaljobs.dll')
    if module == nil then
        exported = {}
        return nil, 'crystaljobs.dll is not loaded'
    end
    local address = ffi.C.GetProcAddress(module, name)
    if address == nil then
        exported[name] = nil
        return nil, 'DLL export unavailable.'
    end
    local entry = exported[name]
    -- A new address means the DLL may have been unloaded/reloaded: recast only
    -- on change, and never keep an obsolete function pointer.
    if entry and entry.module == module and entry.address == address then
        return entry.fn
    end
    local sig = signature_types[name]
    if not sig then return nil, 'Unrecognized DLL export.' end
    local fn = ffi.cast(sig, address)
    exported[name] = { module = module, address = address, fn = fn }
    return fn
end

local function loaded_export()
    local set_state, why = loaded_function('CrystalJobsSetState')
    if not set_state then return nil, why end
    return function(bytes) return set_state(ffi.new(state_bytes_type, bytes), 8) end
end

local function integer(value, minimum, maximum)
    return type(value) == 'number' and value >= minimum and value <= maximum and value % 1 == 0
end

function Labels.new(resolve, dll_path)
    return setmetatable({
        resolve = resolve or loaded_export,
        custom_resolve = resolve ~= nil,
        dll_path = dll_path,
        known = false,
        branch = 0,
        native = false,
        load_failed = false,
        init_attempted = false,
        init_rc = nil,
        hud_hint = nil,
        hud_packets = 0,
        hud_decoded = 0,
        hud_rejected = 0,
        last_hud_job = nil,
        last_hud_length = nil,
        last_hud_error = nil,
        send_count = 0,
        last_send_result = nil,
        last_status_error = nil,
        status_failures = 0,
        status_successes = 0,
    }, Labels)
end

function Labels:set_dll_path(path)
    if type(path) == 'string' and path ~= '' then
        self.dll_path = path
        self.load_failed = false
    end
end

function Labels:ensure_loaded()
    if self.custom_resolve then return true end
    local ok, ready = pcall(function()
        local module = ffi.C.GetModuleHandleA('crystaljobs.dll')
        if module == nil and self.dll_path and not self.load_failed then
            module = ffi.C.LoadLibraryA(self.dll_path)
            if module == nil then
                self.load_failed = true
                self.error = 'DLL LoadLibraryA failed.'
                return false
            end
        end
        if module == nil then return false end

        local get_status = loaded_function('CrystalJobsGetStatus')
        if get_status then
            local st = ffi.new(status_type)
            if get_status(st, ffi.sizeof(st)) == 0 and st[0].size == 68 and st[0].version == 1 then
                if st[0].enabled == 1 and st[0].hooks >= 9 then
                    return true
                end
                if not self.init_attempted and st[0].last_error ~= 1 and st[0].last_error ~= 3 then
                    self.init_attempted = true
                    local init_fn = loaded_function('CrystalJobsInitialize')
                    if init_fn then
                        self.init_rc = tonumber(init_fn())
                        if self.init_rc ~= 0 then
                            self.error = ('CrystalJobsInitialize returned %s.'):format(tostring(self.init_rc))
                        end
                    end
                end
            end
        end
        return true
    end)
    return ok and ready == true
end

function Labels:native_decoder_ready()
    local ok, ready = pcall(function()
        self:ensure_loaded()
        local get_status = loaded_function('CrystalJobsGetStatus')
        if not get_status then return false end
        local status = ffi.new(status_type)
        return get_status(status, ffi.sizeof(status)) == 0 and status[0].size == 68
            and status[0].version == 1 and status[0].enabled == 1 and status[0].hooks >= 9
    end)
    return ok and ready
end

function Labels:status()
    local loadOk, loadResult = pcall(self.ensure_loaded, self)
    if not loadOk then
        self.last_status_error = 'load exception: ' .. tostring(loadResult)
        self.status_failures = self.status_failures + 1
        return nil
    end
    local ok, info, failure = pcall(function()
        local module = ffi.C.GetModuleHandleA('crystaljobs.dll')
        if module == nil then return nil, 'crystaljobs.dll is not loaded' end
        local get_status = loaded_function('CrystalJobsGetStatus')
        if not get_status then return nil, 'CrystalJobsGetStatus export missing' end
        local st = ffi.new(status_type)
        local rc = get_status(st, ffi.sizeof(st))
        if rc ~= 0 then return nil, 'CrystalJobsGetStatus returned ' .. tostring(rc) end
        if st[0].size ~= 68 or st[0].version ~= 1 then
            return nil, ('DLL ABI mismatch: size=%d version=%d'):format(
                tonumber(st[0].size), tonumber(st[0].version))
        end
        return {
            enabled = tonumber(st[0].enabled),
            hooks = tonumber(st[0].hooks),
            character_id = tonumber(st[0].character_id),
            job = tonumber(st[0].job),
            known = tonumber(st[0].known),
            branch = tonumber(st[0].branch),
            search_rows = tonumber(st[0].search_rows),
            decoded_rows = tonumber(st[0].decoded_rows),
            item_labels = tonumber(st[0].item_labels),
            search_labels = tonumber(st[0].search_labels),
            full_labels = tonumber(st[0].full_labels),
            queries_sent = tonumber(st[0].queries_sent),
            replies_accepted = tonumber(st[0].replies_accepted),
            replies_rejected = tonumber(st[0].replies_rejected),
            last_error = tonumber(st[0].last_error),
        }
    end)
    if not ok or not info then
        self.last_status_error = ok and failure or ('DLL status exception: ' .. tostring(info))
        self.status_failures = self.status_failures + 1
        return nil
    end
    self.last_status_error = nil
    self.status_successes = self.status_successes + 1
    return info
end

function Labels:clear_hud_hint()
    self.hud_hint = nil
end

-- A valid, job-matched HUD identity is an alternative client presentation source.
-- Never use it for gameplay or action permissions.
function Labels:observe_hud(data, job, character_id)
    self.hud_packets = self.hud_packets + 1
    self.last_hud_job = job
    self.last_hud_length = type(data) == 'string' and #data or -1
    if not integer(job, 1, 22) or not integer(character_id, 1, 4294967295) then
        self.hud_rejected = self.hud_rejected + 1
        self.last_hud_error = 'invalid player context'
        return false
    end
    local decoded = soulIdentity.decode(data, job)
    if not decoded then
        self.hud_rejected = self.hud_rejected + 1
        self.last_hud_error = 'invalid or mismatched HUD identity'
        return false
    end
    self.hud_decoded = self.hud_decoded + 1
    self.last_hud_error = nil
    self.hud_hint = { job = job, character_id = character_id, branch = decoded.branch }
    return true
end

function Labels:sync(snapshot, character_id, now)
    self:ensure_loaded()
    local id = snapshot.session_key and integer(character_id, 1, 4294967295) and character_id or 0
    local job = integer(snapshot.current_job, 0, 23) and snapshot.current_job or 0
    if id == 0 then self:clear_hud_hint() end
    local verified = id ~= 0 and job >= 1 and job <= 23
        and snapshot.loaded == true and integer(snapshot.active, 0, 7)
    local fallback = not verified and self.hud_hint
        and self.hud_hint.job == job and self.hud_hint.character_id == id
    self.known = verified or fallback or false
    self.branch = verified and snapshot.active or (fallback and self.hud_hint.branch or 0)
    self.source = verified and 'crystal catalog' or (fallback and 'Soul HUD packet' or 'none')
    local bytes = { 1, self.known and 1 or 0, job, self.branch,
        id % 256, math.floor(id / 256) % 256, math.floor(id / 65536) % 256, math.floor(id / 16777216) }
    local key = string.char(unpack(bytes))
    local ok, set_state, why = pcall(self.resolve)
    self.native = ok and set_state ~= nil
    if not self.native then
        self.key = nil
        self.error = not ok and 'DLL lookup unavailable.' or why
        return
    end
    -- Resolve loaded exports each time; never retain a pointer across DLL unload/reload.
    if self.key == key and self.last_send and now - self.last_send < 1 then return end
    self.key, self.last_send = key, now
    local sent, result = pcall(set_state, bytes)
    self.send_count = self.send_count + 1
    self.last_send_result = sent and result or tostring(result)
    self.error = not sent and 'DLL call unavailable.' or result ~= 0 and 'DLL state rejected.' or nil
end

return Labels
