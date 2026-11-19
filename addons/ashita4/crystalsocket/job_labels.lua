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

local function loaded_function(name, signature)
    local module = ffi.C.GetModuleHandleA('crystaljobs.dll')
    if module == nil then return nil end
    local address = ffi.C.GetProcAddress(module, name)
    if address == nil then return nil, 'DLL export unavailable.' end
    return ffi.cast(signature, address)
end

local function loaded_export()
    local set_state, why = loaded_function('CrystalJobsSetState', 'uint32_t (__stdcall *)(const uint8_t*, uint32_t)')
    if not set_state then return nil, why end
    return function(bytes) return set_state(ffi.new('uint8_t[8]', bytes), 8) end
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

        local get_status = loaded_function('CrystalJobsGetStatus', 'uint32_t (__stdcall *)(void*, uint32_t)')
        if get_status then
            local st = ffi.new(status_type)
            if get_status(st, ffi.sizeof(st)) == 0 and st[0].size == 68 and st[0].version == 1 then
                if st[0].enabled == 1 and st[0].hooks == 9 then
                    return true
                end
                if not self.init_attempted and st[0].last_error ~= 1 and st[0].last_error ~= 3 then
                    self.init_attempted = true
                    local init_fn = loaded_function('CrystalJobsInitialize', 'uint32_t (__stdcall *)(void)')
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
        local get_status = loaded_function('CrystalJobsGetStatus', 'uint32_t (__stdcall *)(void*, uint32_t)')
        if not get_status then return false end
        local status = ffi.new(status_type)
        return get_status(status, ffi.sizeof(status)) == 0 and status[0].size == 68
            and status[0].version == 1 and status[0].enabled == 1 and status[0].hooks == 9
    end)
    return ok and ready
end

function Labels:status()
    local ok, info = pcall(function()
        self:ensure_loaded()
        local get_status = loaded_function('CrystalJobsGetStatus', 'uint32_t (__stdcall *)(void*, uint32_t)')
        if not get_status then return nil end
        local st = ffi.new(status_type)
        if get_status(st, ffi.sizeof(st)) ~= 0 or st[0].size ~= 68 or st[0].version ~= 1 then
            return nil
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
    return ok and info or nil
end

function Labels:clear_hud_hint()
    self.hud_hint = nil
end

-- A valid, job-matched HUD identity is an alternative client presentation source.
-- Never use it for gameplay or action permissions.
function Labels:observe_hud(data, job, character_id)
    if not integer(job, 1, 22) or not integer(character_id, 1, 4294967295) then return false end
    local decoded = soulIdentity.decode(data, job)
    if not decoded then return false end
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
    self.error = not sent and 'DLL call unavailable.' or result ~= 0 and 'DLL state rejected.' or nil
end

return Labels
