package.path = './?.lua;' .. package.path
local config = require('presentation_config')
local function withFile(contents)
    local originalOpen = io.open
    io.open = function(path)
        assert(path == 'root/data/presentation.cfg')
        return {read=function() return contents end,close=function() end}
    end
    local value, why = config.load('root')
    io.open = originalOpen
    return value, why
end
local value, why = withFile('# comment\naction_row_max_chars=16\n')
assert(value == 16 and why == nil)
assert(withFile('action_row_max_chars=8\n') == 8)
assert(withFile('action_row_max_chars=48\n') == 48)
assert(withFile('action_row_max_chars=7\n') == nil)
assert(withFile('action_row_max_chars=49\n') == nil)
assert(withFile('action_row_max_chars=16\naction_row_max_chars=17\n') == nil)
assert(withFile('unsafe_native_hook=1\n') == nil)
print('External native row presentation settings tests passed.')
