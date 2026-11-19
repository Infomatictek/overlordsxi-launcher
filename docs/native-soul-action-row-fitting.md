# Native Soul Action list-row fitting

**Status: source staged for Windows x86 build and live menu verification; not deployed.**

The 18 existing verified hooks keep their call sites and dispatch unchanged. This patch compacts **only** Magic/Ninjutsu and Ability/Weapon Skill menu-row labels, preserving complete names in target selection and in `data/soul_actions.tsv` (and therefore in macro resolution and Soul combat logs). No Soul-specific name is compiled into the DLL.

## Editable layout setting

File: `addons/ashita4/overlords_soul_actions/data/presentation.cfg`

```ini
action_row_max_chars=16
```

Value must be a whole number from 8 through 48; `/soulactions reload` reapplies the setting via the optional `CrystalJobsSetActionRowLimit(uint32)` export, without recompilation. It does **not** modify the underlying Soul spell name or edit the vanilla resource DATs.

For a 16-character row budget:

| Full name | Compact native list label | Target-select and combat-log name |
| --- | --- | --- |
| Shadow Squadron: Ichi | Shadow Sq.: Ichi | Shadow Squadron: Ichi |
| Shadow Squadron: Ni | Shadow Sq.: Ni | Shadow Squadron: Ni |
| Utsusemi: Ichi (unmapped) | Utsusemi: Ichi | Utsusemi: Ichi |

The first screenshot showed an overflow to the right of the classic menu; 16 is an **unverified starting estimate**, not a measured pixel width. Different fonts, languages, or UI scaling may require adjustment. Native display-width measurement or scissor clipping would be necessary for a guaranteed pixel-perfect solution; do not claim that a character limit guarantees no clipping for all glyphs.

## Build and test gate

1. On Antigravity's Windows x86 development environment, checkout `feat/native-soul-action-row-fitting` and inspect changes against `main`.
2. Run `native/crystaljobs/build.cmd`. The native `selftest.exe` must pass with the revised row/full-target assertions; inspect all 14 exported symbols, including `CrystalJobsSetActionRowLimit`.
3. Validate the installed supported `FFXiMain.dll` hook signatures, existing 18/18 hook count, ability/WS fallback, and zone/logout.
4. Regenerate the complete launcher manifest **after** compilation, including both DLL copies, all changed Lua, new config, and tests; run launcher manifest verification. Do not commit a stale manifest.
5. Verify on a real FFXI client: Magic/Ninjutsu names stay inside the menu, action tooltips and target selection retain full names, casts and macros work, and switching Souls restores stock rows correctly.
6. Test `/soulactions reload` after changing `action_row_max_chars` (e.g., 16 to 15), ensuring it works without a DLL rebuild. Retain this as a generic UI setting for all 66 Souls.
7. Merge and push to launcher `main` only after compilation and static tests succeed. If native tests fail, keep this branch isolated and report the errors.

No server changes or multiplayer testers are required for this menu-row task.
