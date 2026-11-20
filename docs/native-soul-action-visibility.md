# Soul-aware native action visibility — integration contract

**Status:** Native visibility engine implemented, compiled (`crystaljobs.dll` 20/20 hooks), self-tested, and live-verified against installed `FFXiMain.dll`. Full live UI acceptance screenshots remain for in-game testing.

## Verified native `FFXiMain.dll` list-filtering sites (`TS=0x6ae818b4`, `SizeOfImage=0xC17000`)

| Hook # | RVA | Callee RVA | ABI | Behavior |
|---:|---|---|---|---|
| 19 | `0x22DAB9` | `0x22CDE0` (`CanShowSpell`) | `__cdecl`, `ret` | Filters spells inside `Magic::Populate` (`0x1022D9B0`) **before** row append, preserving native compaction, scroll bounds, selection, descriptions, recasts, and vanilla action IDs. |
| 20 | `0x22562F` | `0x223090` (`SetListCount`) | `__thiscall`, `ret 8` | Compacts `AbilityMenu`'s display index array (`[ecx+0x20]`) in-place inside `Ability::Populate` (`0x102254D0`) before `SetListCount`, remapping `saved_sel` (`[esp+0x1c]`) and leaving persistent sort order (`0x10668308`) untouched. |

- Effective main level (including Level Sync) is read directly from `FFXiMain.dll` `base + 0x4867F1`.
- Versioned native C-ABI exports: `CrystalJobsReplaceVisibility`, `CrystalJobsClearVisibility`, `CrystalJobsGetVisibilityStatus` (capability flags `1u << 10` and `1u << 11`).
- Server audit (`overlordsxi-main/modules/custom/lua/nin_specs.lua`): confirms server grants spell IDs `338` (Utsusemi: Ichi) and `339` (Utsusemi: Ni) via `player:addSpell`; `data/visibility.tsv` governs Shinobi's Lv. 10 / Lv. 37 progression while leaving all unspecified actions `unmanaged` (fail-open to vanilla).

## Expected player behavior

- Actions that have not reached their server-verified unlock level must be **completely absent** from native Magic/Ninjutsu, Job Ability and Weapon Skill menus. Do not show dimmed, locked or empty rows.
- Shinobi (NIN job 13 / branch 1) Utsusemi: Ichi ID 338 is known to cast at Lv. 10; Utsusemi: Ni ID 339 is reported blocked below Lv. 37. Initial policy: Ichi unlocks at 10, Ni at 37. Verify Ni's true authoritative unlock against the current server before shipping.
- Effective level, including level sync, determines visibility. Lv. 36 hides Ni; Lv. 37 shows Ni if otherwise eligible; synced down to 36 hides it again.
- Changing Soul must immediately change action visibility, keeping underlying vanilla IDs intact.
- Action temporary unusability (MP, recast, silence, range, disarm or targeting) must **not** hide an otherwise unlocked action.
- Server authorization always governs real casts; the client never grants permission.
- If no active Soul or the server's authoritative eligibility data is unavailable/stale, use normal FFXI behavior; never blank the entire menu.
- Main/subjob visibility must honor the server's actual rules. Do not accidentally remove abilities allowed through subjob, or grant another Soul's level-10 unlock to Shinobi.
- Soul-specific client names/descriptions/icons already work and must keep their 18/18 existing signature-gated native hooks, scroll behavior, row fitting, target display, and command dispatch.

## External policy data already staged

File: `addons/ashita4/overlords_soul_actions/data/visibility.tsv`

Five columns: `soul<TAB>kind<TAB>id<TAB>min_effective_level<TAB>rule`

`rule` supports `unlock` (visible at or above level) and `hidden` (always absent for this Soul). Parser: `visibility.lua`, with `tests/visibility_test.lua`. Current entries exist only for the reported Shinobi Ichi/Ni progression. Unspecified entries are `unmanaged`, **not presumed visible and eligible**. The installed native DLL currently does not read this file; the engineering pass must integrate it with a versioned visibility API.

Do not hardcode Soul-specific action IDs, names, levels, or visibility rules in C++.

## Native engineering sweep (Antigravity / Windows installed FFXiMain.dll)

1. Inspect the **installed exact x86 FFXiMain.dll** already supported by `crystaljobs.dll`. Reverse-engineer native Magic/Ninjutsu list **population**, count, index arrays, selected-row ID lookup, scrolling, descriptions, recasts and action execution. Do the same for Job Ability and Weapon Skill lists. Preserve the verified 18 existing hooks. Record real RVAs/signatures/ABI for any new sites; do not invent them.
2. Implement native list filtering at or before list construction, without skipping only the draw call. A hidden row must not consume space, tab count, highlight position, scroll slot or stale selection. Validate action dispatch always uses the original ID (339 remains ID 339).
3. Provide a versioned, atomic, bounded native visibility catalog API. Its records include Soul job, canonical branch, action kind, underlying ID, minimum effective level, and hide/show rule. Hot-reload via Ashita, no native rebuild for new entries. Add capabilities/status reporting.
4. Extend the Ashita addon to load and validate the external policy on load and `/soulactions reload`. Resolve active Soul and effective level with a verified source (including sync/subjob rules), then update the native catalog/active state safely. Avoid per-frame LuaJIT FFI type creation and unbounded polling. When eligibility state is unknown, preserve vanilla rows.
5. Determine server-authoritative eligibility rules from actual Lua/C++ modules, not a guessed global FFXI resource level. Make a reproducible exporter or test that compares all 66 Souls' visibility policies to real server eligibility, including overridden magic/JA access, subjob restrictions, upgrades and level sync.
6. Add x86 selftests for native index compaction, zero/one/large list, missing IDs, menu switch mid-selection, scroll boundaries, active Soul switching, 36/37 transition, downsync, reload, zoning and unsupported-build fallback. Verify native hooks and full target/cast descriptions remain intact. Unit-test `visibility.lua` with LuaJIT.
7. Compile x86 DLL and run installed-FXXiMain integration test, verify launcher manifest including built binaries/config/module files, and run all launcher tests. Merge the feature branch only after native build and regression tests pass. Full live UI acceptance still requires the user.

### Acceptance screenshots to collect

At Lv. 10–36 as Shinobi, Magic > Ninjutsu shows Ichi and omits Ni entirely, not a blank row. At Lv. 37, Ni appears; both share readable row fitting and full target labels. Syncing below 37 hides Ni. Switching Soul displays the other Soul's correct list. Current working Equipment Soul names and Shadow Squadron chat logs remain unchanged.

## Branch safety

Launcher `main` is the playable environment. This feature branch is preparatory only. Server `main` remains untouched. No unsafe, uncompiled native hooks should land on `main`. The currently deployed 18-hook DLL must continue to be distributed until validation.
