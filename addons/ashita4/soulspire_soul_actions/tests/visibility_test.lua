package.path = './?.lua;' .. package.path
local M = require('visibility')
local policy, err = M.parse(table.concat({
    '# comment',
    'shinobi\tspell\t338\t10\tunlock',
    'shinobi\tspell\t339\t37\tunlock',
    'kagemusha\tspell\t339\t1\thidden',
    'shinobi\tability\t512\t37\tunlock',
    'shinobi\tweaponskill\t128\t75\tunlock',
}, '\n'))
assert(policy and not err and policy.count == 5)
assert(M.decide(policy,'shinobi','spell',338,10)=='show')
assert(M.decide(policy,'shinobi','spell',339,10)=='hide')
assert(M.decide(policy,'shinobi','spell',339,36)=='hide')
assert(M.decide(policy,'shinobi','spell',339,37)=='show')
assert(M.decide(policy,'shinobi','spell',339,75)=='show')
assert(M.decide(policy,'kagemusha','spell',339,75)=='hide')
assert(M.decide(policy,'nightblade','spell',339,37)=='unmanaged')
assert(M.decide(policy,'shinobi','ability',512,36)=='hide')
assert(M.decide(policy,'shinobi','weaponskill',128,74)=='hide')
assert(M.decide(policy,'shinobi','spell',339,nil)=='unmanaged')
assert(M.decide(policy,'shinobi','spell',339,76)=='unmanaged')
assert(M.decide(policy,'shinobi','spell',340,75)=='unmanaged')
assert(M.parse('shinobi\tspell\t339\t37\tunlock\nshinobi\tspell\t339\t37\tunlock')==nil)
assert(M.parse('shinobi\tspell\t339\t0\tunlock')==nil)
assert(M.parse('shinobi\tspell\t339\t37\tshow')==nil)
assert(M.parse('shinobi\tspell\t1024\t37\tunlock')==nil)
print('Soul visibility policy validation and level-sync decisions passed.')
