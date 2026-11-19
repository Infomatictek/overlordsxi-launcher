# Shinobi client-only action identity: native Magic menu milestone

## Exact mapping agreed for first live test

| Main job | Active Soul | Internal spell ID | Native FFXI resource label | Soul-only visible name | Soul-only description |
|---|---|---:|---|---|---|
| 13 (NIN) | Shinobi (branch 1 / legacy key `kurogane`) | 338 | Utsusemi: Ichi | Shadow Squadron: Ichi | Summon 2 offensive shadow clones. They copy your appearance and independently attack your engaged target. Maximum 5 active clones. |
| 13 (NIN) | Shinobi (branch 1 / legacy key `kurogane`) | 339 | Utsusemi: Ni | Shadow Squadron: Ni | Summon 3 offensive shadow clones. They copy your appearance and independently attack your engaged target. Maximum 5 active clones. |

**Names describe the current Soul behavior, not the original FFXI effect.** The client map is included in `addons/ashita4/overlords_soul_actions/builtin_profiles.lua` and installed automatically. IDs 338 and 339 are vanilla client action IDs, not new spells. The mapping does not change casting, recasts, clones, skill levels, targeting, packet IDs, animation IDs or server rules.

## Current implementation boundary

The built-in data is visible in the optional `overlords_soul_actions` ImGui viewer. **It does not yet replace native Magic menu entries.** Do not globally modify `spells.names`, FFXI spell DAT strings or other resources shared by Ninja/subjobs/other Souls. Do not advertise the menu as renamed until it is actually intercepted in-game.

## Native implementation task (Windows / installed FFXiMain.dll)

Work in `Infomatictek/overlordsxi-launcher`, client-only. Keep the validated native Equipment status hook intact.

1. Inspect the installed supported 32-bit `FFXiMain.dll` (timestamp `0x6ae818b4`; image size `0xC17000`). Identify native Magic list and spell-description presentation call sites via menu structs, vtables, and cross-references to the ID 338/339 resource lookups. Record real RVAs, call signatures, register/stack ABI and machine-code signature bytes. Do not guess.
2. Add a Soul-aware display resolver in `native/crystaljobs` for job=13, branch=1 only. Its output for spell IDs 338/339 is the two Shadow Squadron names and descriptions above. It must resolve from the already-synchronized local Soul state with valid lease and job, and leave original IDs intact.
3. Hook **display only** in native Magic spell rows and descriptions, preserving selection/cast dispatch, recasts, inventory costs, the original menu layout, and any subjob entries. Longer labels must be constrained to available native text width; never write past an existing buffer.
4. Validate that Ninja with another Soul (Kagemusha/Nightblade), no Soul, a different base job, expired lease, zoning, and unsupported client build get unmodified resource names. If an unrelated job could use the underlying spell IDs, it must never receive Shinobi's labels.
5. Trace whether native cast-start, action-result logs and in-world visuals have *separate* name/effect paths; they are NOT implicitly covered by menu names. Do not suppress or spoof combat logs until packet parsing is established.
6. Add x86 adapter ABI tests and scoped resolver tests. Rebuild with `native/crystaljobs/build.cmd`, preserve all existing exports and verified Equipment hooks, regenerate `manifest.json`, run manifest and launcher tests, then verify real game casting, target selection and tooltips.
7. Do not change the server repo. Keep a clean stock fallback and no permanent overlay. Require explicit in-game verification before claiming completion.

## Acceptance test

Equip Shinobi. Open Magic/Ninjutsu. Entries at IDs 338/339 appear as Shadow Squadron: Ichi / Shadow Squadron: Ni with clone-specific descriptions. Casting either uses its original action ID and summons the corresponding existing clones. Switch to Kagemusha or deactivate the Soul; the custom descriptions disappear and native action selection still works. The DLL must continue showing the Soul name in Equipment after an idle period.

This document is the implementation contract and does not prove the native Magic menu hook exists.
