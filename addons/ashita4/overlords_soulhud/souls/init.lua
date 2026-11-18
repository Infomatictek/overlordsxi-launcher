-- Soul Registration Loader
-- Add new Soul registration modules to the list below.
local modules = {
    'souls.cor_flintlock',
    'souls.cor_gambler',
    'souls.dnc_mirage_sentinel',
}

return function(registry)
    for _, modName in ipairs(modules) do
        local ok, loader = pcall(require, modName)
        if ok and type(loader) == 'function' then
            pcall(loader, registry)
        end
    end
end
