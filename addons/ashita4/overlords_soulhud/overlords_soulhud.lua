addon.name = 'overlords_soulhud'
addon.author = 'OverlordsXI'
addon.version = '0.1.0'
addon.desc = 'Universal server-authoritative Soul Crystal HUD.'

require('common')
local settings = require('settings')
local Registry = require('registry')
local Render = require('render')
local definitions = require('souls')

local defaults = {
    visible = true, compact = false,
    x = 40, y = 240, width = 260, opacity = 0.88,
}
local config = settings.load(defaults)
local registry = Registry.new()
local snapshot, lastPacketAt = nil, 0
local STALE_AFTER = 15

for key, definition in pairs(definitions) do
    local ok, err = pcall(registry.registerSoul, registry, key, definition)
    if not ok then print('[soulhud] registration failed: ' .. tostring(err)) end
end

local function parsePayload(payload)
    local job, soul, unlocked, kv = payload:match('^(%d+)|([^|]*)|(%d+)|?(.*)$')
    if not job then return nil end
    local state = {}
    for pair in kv:gmatch('[^;]+') do
        local key, value = pair:match('^([^=]+)=(.*)$')
        if key then state[key] = value end
    end
    return { job = tonumber(job), soul = soul, unlocked = tonumber(unlocked) == 1, state = state }
end

local function reset()
    snapshot, lastPacketAt = nil, 0
end

ashita.events.register('packet_in', 'overlords_soulhud_packet', function(e)
    local data, size = e.data_modified or e.data, e.size
    if type(data) ~= 'string' or type(size) ~= 'number' or size < 1 or size > #data then return end
    data = data:sub(1, size)
    local marker = data:find('[OXHUD]|', 1, true)
    if not marker then return end
    local payload = data:sub(marker + 8):match('^([^%z\r\n]*)')
    if not payload then return end
    local parsed = parsePayload(payload)
    if parsed then
        snapshot = parsed
        lastPacketAt = os.clock()
    end
end)

ashita.events.register('packet_in', 'overlords_soulhud_zone_in', function(e)
    if e.id == 0x00A or e.id == 0x00B then reset() end
end)
ashita.events.register('packet_out', 'overlords_soulhud_zone_out', function(e)
    if e.id == 0x00D then reset() end
end)

ashita.events.register('d3d_present', 'overlords_soulhud_present', function()
    if not snapshot or not snapshot.unlocked or os.clock() - lastPacketAt > STALE_AFTER then return end
    local soul = registry:getSoul(snapshot.soul)
    if not soul then return end
    local items = registry:normalize(snapshot.soul, snapshot.state)
    if items then Render.draw(soul.title, items, config) end
end)

ashita.events.register('command', 'overlords_soulhud_command', function(e)
    local args = e.command:args()
    if #args == 0 or args[1]:lower() ~= '/soulhud' then return end
    e.blocked = true
    local action = args[2] and args[2]:lower() or 'toggle'
    if action == 'toggle' then
        config.visible = not config.visible
    elseif action == 'compact' then
        config.compact = not config.compact
    elseif action == 'sync' then
        AshitaCore:GetChatManager():QueueCommand(1, '!soulhud sync')
    elseif action == 'reset' then
        config.x, config.y, config.width, config.opacity =
            defaults.x, defaults.y, defaults.width, defaults.opacity
    else
        print('[soulhud] /soulhud [toggle|compact|sync|reset]')
        return
    end
    settings.save()
end)

print('[soulhud] Loaded; waiting for authoritative [OXHUD] state.')
