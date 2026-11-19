# Native Equipment Menu Soul Name + Search Reliability

## Intended behavior
The native Equipment menu should show the full active Soul name in place of the underlying job name, e.g. Astromancer rather than Black Mage. Existing search results should continue showing Soul abbreviations/full names as appropriate.

## Existing native path
- `native/crystaljobs/crystaljobs.cpp` already hooks native lookup and text/sprite paths, including `item_label`, `draw_branch`, and `full_branch`.
- `native/crystaljobs/labels.h` holds the job/branch -> full and abbreviated Soul names.
- `addons/ashita4/crystalsocket/job_labels.lua` synchronizes the active Soul state to `crystaljobs.dll`.
- Native hooks are signature-gated to a specific FFXI client build. Do not guess additional offsets.

## Search bug fixed in source
A mixed search response may decode a character row containing the Soul extension, followed by a row without the extension. Previously the second row erased the valid Soul branch. The cache now retains the known branch when the same character/job row lacks the extension, while still allowing an explicit extension to update it and invalidating when the job changes.

**Important:** This is a source fix only. It requires rebuilding and distributing `crystaljobs.dll`, and has not been validated against live search traffic. A search request can still clear cached rows; this change is not a complete search audit.

## Equipment-menu investigation
Do **not** assume `full_branch` is called by the Equipment screen. Determine the exact text lookup or render path from a supported client build first, then extend the existing DLL with:
1. A read-only Equipment menu context check.
2. The active local character/job/branch from the existing native state, guarded by its session lease.
3. Full `label_for(job, branch, true)` for the native Equipment job-name field.
4. Fallback to stock job text on unknown Soul, zoning, invalid session, unsupported build, or hook failure.
5. No changes to the underlying job ID, equipment restrictions, or combat actions.

## Verification matrix
- Equipment: active Soul, switching Souls within same job, changing jobs, logout/login, zoning, menu already open during a switch.
- Search: multiple pages, duplicate rows, character changes job, row without extension, hidden/invalid entries, mixed old/new client packets.
- Safety: stock fallback, disabled DLL, unsupported executable, no extra per-frame polling.
- Release: compile native DLL, run existing tests, inspect new DLL exports, update launcher manifest checksum and size, verify launcher installs it, then test in-game.

Do not claim Equipment-menu replacement is complete until its actual native call site is identified and validated.

## 2026-11-19: confirmed synchronization and Equipment observation

Live Crystal Socket diagnostics confirmed NIN (job 13), Shinobi (branch 1), 9/9 native hooks, accepted native state update. The previous Soul synchronization blocker is resolved. However, `items=0, full=0, search=0` were measured with the chat log in focus, not with a confirmed Equipment drawing interval; those counters alone are not proof that the Equipment field is unhooked.

Client-only observation is now available in Crystal Socket v0.3.5. On entering and exiting the Equipment native menu, it prints a single line such as:
```
[crystalsocket] Equipment native label hook activity: item=0 full=0 search=0
```
The same last reading is included in `/crystalsocket status` and its status log. No native memory or packets are modified by the probe. **If the reader sees no observations, inspect `Menu:context` validity rather than assuming native hooks are inactive.**

### Native investigation gate (requires actual Windows game binary)

Current `crystaljobs.cpp` has nine signature-gated CALL substitutions: two full-name searches at RVAs `0x1DEE6D` and `0x1DEEFB`, a short item label at `0x13C302`, two sprite substitutions, search protocol adapters, and networking adapters. Their search-row context cannot simply be repurposed for the local Equipment status field, which does not have the same record structure. The screenshot of the Equipment menu identifies the target as the `Lv25 Ninja` status line, **not** the search pane or Soul Crystal tooltip.

Next investigate the **exact client string producer/callee for the Equipment status field** in the supported 32-bit `FFXiMain.dll` (timestamp `0x6ae818b4`, image size `0xC17000`). Cross-reference the displayed job name and job resource table, disassemble its call site, and record the surrounding 24+ bytes and argument ABI before editing. If a CALL substitution is selected, add a verified signature to `layout.h`, an ABI-correct adapter, a fail-closed stock fallback, and an x86 selftest. Never use guessed offsets, broad global table renaming, unverified in-place string mutation, or a permanent opaque overlay. Verify that a Soul switch updates the Equipment text without leaving the menu, and that no-Soul, zone, job-change, and unsupported-executable fall back to stock.

After native source changes: run `native/crystaljobs/build.cmd`, verify exports/bitness/selftest, regenerate `manifest.json` using `scripts/update-launcher-manifest.py`, and run the launcher tests. The current probe is only Lua; it does **not** require a DLL rebuild.

### 2026-11-19: verified Equipment status-panel (`menu    persona `) native hook

Binary inspection of the unpacked 32-bit `FFXiMain.dll` (timestamp `0x6ae818b4`, `SizeOfImage = 0xC17000`, preferred base `0x10000000`) established why the Equipment probe previously saw `item=0 full=0 search=0`:

- Opening Equipment (`menu    equip   ` at `0x10370864`, RVA `0x134664..0x1346B6`) opens `menu    persona ` (`0x10370850`, global ptr `0x1057959C`, vtable `0x10335A70`).
- `menu    persona ::OnDraw` (RVA `0x1485A0`) formats `"Lv%d"` from the local main level (`base + 0x4867F1`) and draws it via `0x101CAD50` (`native_text` at `base + 0x1CAD80`, `scale_x = 1.0f`, `scale_y = 1.0f`, `center = 0`) at `(win_x + 4, win_y + 0x13)`, returning `end_x` in `EAX`.
- Rather than calling `lookup(18, job)` (`0x1544C0`), `OnDraw` loads the local main job ID from `base + 0x4867F0`, indexes the full job-name sprite table (`[edx + job*4 + 0x350]`), and invokes `DrawSpriteSimple` (RVA `0x120FF0`, `__thiscall`, 5 stack args = `ret 0x14`) from call site RVA `0x14868F` at `(end_x + 2, win_y + 0x13)` with color `edi` (`0x80808080` normal, `0x802060A0` level-synced).
- Subjob rendering follows separately at RVA `0x14870A` (`base + 0x4867F2` / `0x4867F3`) and is left untouched.

`crystaljobs.dll` now installs a 10th signature-gated CALL substitution (`persona_job_hook`) at RVA `0x14868F` (with verified 24-byte signatures at `0x14868F` and `0x120FF0`, plus base-relocation handling at `0x14868F + 6` and `+17`):
- When `alive()` is true and `state.known && state.job == *main_job_slot`, renders `label_for(job, branch, true)` via `native_text(x, y, custom, color, 1.0f, 1.0f, 0)` and increments `full_labels`, preserving level text, level-sync color, subjob, and all other Equipment UI elements.
- Falls back to stock `DrawSpriteSimple` (`0x120FF0`) whenever no Soul is active, the job mismatches, the session lease expires, or the client build is unsupported.
