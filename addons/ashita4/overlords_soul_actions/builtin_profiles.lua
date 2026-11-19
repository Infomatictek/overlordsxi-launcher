-- Built-in client presentation identities for Souls with verified action mappings.
-- Internal action IDs remain vanilla FFXI; names and descriptions describe
-- the current Soul, not the base spell. This does not change gameplay.
local M = {}
M.actions = {
    shinobi = {
        spell = {
            [338] = {
                name = 'Shadow Squadron: Ichi',
                description = 'Summon 2 offensive shadow clones. They copy your appearance and independently attack your engaged target. Maximum 5 active clones.',
            },
            [339] = {
                name = 'Shadow Squadron: Ni',
                description = 'Summon 3 offensive shadow clones. They copy your appearance and independently attack your engaged target. Maximum 5 active clones.',
            },
        },
    },
}
function M.install(catalog)
    local count = 0
    for soul, kinds in pairs(M.actions) do
        for kind, entries in pairs(kinds) do
            for id, info in pairs(entries) do
                assert(catalog.register(soul, kind, id, info))
                count = count + 1
            end
        end
    end
    return count
end
return M
