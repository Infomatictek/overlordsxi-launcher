-- Read-only native menu inspection. Unknown layouts hide the socket.
local Menu = {}
Menu.__index = Menu

local function address(value, span)
    return type(value) == 'number' and value >= 0x10000
        and value <= 0xFFFFFFFF - span + 1 and value % 1 == 0
end

local function pointer(value, span)
    return address(value, span) and value % 4 == 0
end

function Menu.new(memory, scaling, operand)
    local self = setmetatable({ memory = memory, scaling = scaling }, Menu)
    local ok, manager = pcall(function()
        if not address(operand, 4) then return nil end
        local storage = memory.read_uint32(operand)
        -- shortcut: these are native structure fields; revalidate after a client update.
        return pointer(storage, 4) and pointer(storage - 0x54, 4) and storage - 0x54 or nil
    end)
    self.manager = ok and manager or nil
    return self
end

function Menu:anchor()
    if not self.manager or not self.scaling then return nil end
    local ok, anchor = pcall(function()
        local memory, scaling = self.memory, self.scaling
        local node = memory.read_uint32(self.manager)
        local seen, equipment, description = {}, false, nil
        for _ = 1, 128 do
            if node == 0 then break end
            if not pointer(node, 0x15) or seen[node] then return nil end
            seen[node] = true
            if memory.read_uint8(node + 0x14) == 0 then
                local window = memory.read_uint32(node + 0x10)
                if not pointer(window, 0x6F) then return nil end
                if memory.read_uint8(window + 0x69) ~= 0
                    and memory.read_uint8(window + 0x6E) == 0 then
                    local form = memory.read_uint32(window + 4)
                    if not pointer(form, 86) then return nil end
                    local name = memory.read_string(form + 70, 16):gsub('%z', ''):gsub('%s+$', '')
                    if name == 'menu    equip' then equipment = true end
                    if name == 'menu    iteminfo' or name:match('^menu    item[4-9]inf$')
                        or name:match('^menu    item1[0-2]in$') then
                        local left = memory.read_int16(window + 0x3A)
                        local top = memory.read_int16(window + 0x3C)
                        local right = memory.read_int16(window + 0x3E)
                        local bottom = memory.read_int16(window + 0x40)
                        if left < 0 or top < 0 or right <= left or bottom <= top
                            or right > scaling.menu.w or bottom + 52 > scaling.menu.h then
                            return nil
                        end
                        description = { x = scaling.scale_w(left), y = scaling.scale_h(bottom + 8) }
                    end
                end
            end
            node = memory.read_uint32(node)
            if node ~= 0 and seen[node] then return nil end
        end
        if node ~= 0 or not equipment then return nil end
        return description
    end)
    return ok and anchor or nil
end

return Menu
