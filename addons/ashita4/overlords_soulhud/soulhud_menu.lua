--[[
* OverlordsXI Soul HUD - native FFXI menu / event / interface detector.
*
* Re-uses the verified FFXiMain.dll signatures from kazenoeye (util/hidestatus.lua: game-menu,
* event-system and interface-hidden) and the pointer validation approach of crystalsocket/menu.lua.
* Everything is read-only and fails OPEN (HUD stays visible) when a signature cannot be resolved.
*
* hiddenReason(playerStatus) -> nil | 'interface' | 'event' | 'cutscene' | 'menu:<name>'
*
* Note: crystalsocket's overlay (Polearm/Buckler picker, crystal socket) only exists while the native
* Equipment menu is open, so the generic menu check below already covers it.
--]]

local M = {}

local SIG_MENU      = '8B480C85C974??8B510885D274??3B05'
local SIG_EVENT     = 'A0????????84C0741AA1????????85C0741166A1????????663B05????????0F94C0C3'
local SIG_INTERFACE = '8B4424046A016A0050B9????????E8????????F6D81BC040C3'

local pGameMenu, pEventSystem, pInterfaceHidden = 0, 0, 0
local resolved = false
local lastName, lastPollAt = '', -10

local function find(sig, offset)
    local ok, addr = pcall(function() return ashita.memory.find('FFXiMain.dll', 0, sig, offset, 0) end)
    if ok and type(addr) == 'number' then return addr end
    return 0
end

local function valid(p)
    return type(p) == 'number' and p >= 0x10000 and p <= 0xFFFFFFF0
end

local function u32(addr)
    if not valid(addr) then return 0 end
    local ok, v = pcall(ashita.memory.read_uint32, addr)
    return ok and v or 0
end

local function u8(addr)
    if not valid(addr) then return 0 end
    local ok, v = pcall(ashita.memory.read_uint8, addr)
    return ok and v or 0
end

-- Resolve signatures (call once from the addon `load` event, safe to call repeatedly).
function M.init()
    if resolved then return end
    resolved = true
    pGameMenu        = find(SIG_MENU, 16)
    pEventSystem     = find(SIG_EVENT, 0)
    pInterfaceHidden = find(SIG_INTERFACE, 0)
end

function M.available()
    return pGameMenu ~= 0 or pEventSystem ~= 0 or pInterfaceHidden ~= 0
end

local function eventActive()
    if pEventSystem == 0 then return false end
    local ptr = u32(pEventSystem + 1)
    return ptr ~= 0 and u8(ptr) == 1
end

local function interfaceHidden()
    if pInterfaceHidden == 0 then return false end
    local ptr = u32(pInterfaceHidden + 10)
    return ptr ~= 0 and u8(ptr + 0xB4) == 1
end

-- Name of the top-most native menu ('' when none). Names look like 'menu    equip'.
local function menuName()
    if pGameMenu == 0 then return '' end
    local sub = u32(pGameMenu)
    local node = u32(sub)
    if node == 0 then return '' end
    local header = u32(node + 4)
    if not valid(header) then return '' end
    local ok, name = pcall(ashita.memory.read_string, header + 0x46, 16)
    if not ok or type(name) ~= 'string' then return '' end
    return (name:gsub('%z.*$', ''):gsub('%s+$', ''))
end

-- Names that are always resident (bare 'menu' with no suffix) do not count as an open menu.
local function isRealMenu(name)
    if name == '' then return false end
    local rest = name:gsub('^menu%s*', '')
    return rest ~= ''
end

function M.currentMenu()
    return lastName
end

-- playerStatus: entity Status of the local player (4 == in an NPC event / cutscene).
function M.hiddenReason(playerStatus, now)
    now = now or os.clock()
    if (now - lastPollAt) >= 0.1 then
        lastPollAt = now
        lastName = menuName()
    end
    if interfaceHidden() then return 'interface' end
    if eventActive() then return 'event' end
    if playerStatus == 4 then return 'cutscene' end
    if isRealMenu(lastName) then return 'menu:' .. lastName end
    return nil
end

return M
