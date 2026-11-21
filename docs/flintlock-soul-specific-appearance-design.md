# SoulspireXI — Soul-Specific Appearance Feasibility & Architecture Design

Branch: `fix/flintlock-akimbo-blink-audit`  
Status: **Feasibility Complete — Blocked on Native `FFXiMain.dll` Model-Loader Hook (Not Achievable with Global XIPivot Alone)**

---

## 1. Feasibility Conclusion

**True Soul-specific dual-pistol visuals (where COR Flintlock + Silver Gun +1 displays two pistols while WAR Berserker / COR Gambler / COR Buccaneer + Silver Gun +1 display one normal pistol) is NOT technically possible using Ashita v4 XIPivot and the current global DAT overlay alone.**

Attempting to fake Soul-specific behavior via XIPivot toggles or Lua addons does not prevent leakage because:
1. **XIPivot is process-global and boot-time**: `polplugins/pivot.dll` intercepts Win32 file opens globally for the entire FFXI process with zero actor, job, or Soul context.
2. **The 182 firearm DATs overwrite vanilla firearm paths**: Every job/Soul equipping one of the 26 firearm models loads the exact same `ROM/<dir>/<file>.DAT` path, which has `info[30]` flipped from `0x03` (vanilla `lc03`/`ls03`) to `0x07` (dual-pistol `lc07`/`ls07`) and embeds `wep7`/`wep8` hip pistols.
3. **Pure unused `MId` remapping cannot cover all 26 firearms without patching `FTABLE.DAT`**:
   - Querying `item_equipment` (`slot = 4`) in SoulspireXI's database shows `MId` spans `0..144` with **124 of 145 slots occupied**, leaving only **21 gaps** (`16..23, 29..30, 39, 42, 49, 73, 87..89, 102, 112, 125, 141`) — fewer than the 26 firearm appearances, and unallocated in retail `FTABLE.DAT`.
   - Overlaying `FTABLE.DAT` + `VTABLE.DAT` replaces FFXI's master file table globally and breaks on every Square Enix retail patch.

---

## 2. Exact Asset Classification (What Leaks vs. What Is Safe Globally)

Auditing all 278 DATs in `dat-overlays/flintlock-akimbo-compact/ROM/`:

| Layer | Count | Files | Global Leakage? | Reason |
|---|---|---|---|---|
| **Player Skeletons** | 7 | `ROM/27/82.DAT`, `32/58.DAT`, `37/31.DAT`, `42/4.DAT`, `46/93.DAT`, `51/89.DAT`, `56/59.DAT` | **No (Safe)** | Leaves vanilla `lc03`/`ls03` untouched; only *adds* `lc07`/`ls07` + `q3d*`/`q3h*`/`q3a*` (plus `0xa3` blink fix on this branch). |
| **Stock Gun WS / Quick Draw** | 89 | `ROM/164/*`, WS action DATs | **No (Safe)** | Only hides `wep8` (absent on vanilla guns) and emits `q4*` callbacks (no-ops on vanilla guns). |
| **Firearm Models** | 182 | 26 firearm models × 7 skeletons | **YES (Source of Leakage)** | Replaces vanilla `ROM/<dir>/<file>.DAT` with `info[30]=0x07` + `wep2` twin + `wep6`/`wep7`/`wep8` hip holsters for every actor. |

---

## 3. Recommended Reusable Architecture — Native Soul Appearance System (`crystaljobs.dll`)

Rather than building a fragile Flintlock-only hack or patching `FTABLE.DAT`, extend the existing **`native/crystaljobs/crystaljobs.dll`** infrastructure (24 verified hooks) with a **generic Soul-scoped model DAT redirector** reusable by all 66 Souls:

### A. Two-Layer Asset Layout (Reversible, Zero Global Leakage)
1. **Shared animation layer** (loaded via XIPivot): the 7 skeleton DATs + 89 stock WS DATs. Zero effect on any vanilla weapon or non-Flintlock Soul.
2. **Soul-scoped model layer** (NOT listed in XIPivot `[overlays]`):
   - `polplugins/DATs/soulspirexi-souls/flintlock/ROM/...` (the 182 firearm DATs).
   - Future Souls follow the same layout: `polplugins/DATs/soulspirexi-souls/<soul_key>/ROM/...`.

### B. Required Native Client Support (`native/crystaljobs/`)
1. **Reverse-engineering prerequisite (on Windows `FFXiMain.dll`)**:
   - Locate and signature-verify the `FFXiMain.dll` equipment model DAT loader function where both the **target actor/entity** (or `server_id`) and the **equipment slot / resolved `ROM\...\*.DAT` path** are known.
   - Verify the safe per-actor appearance reload / cache-invalidation call so switching Souls refreshes the actor's ranged model cleanly without relogging.
2. **Generic `crystaljobs.dll` C ABI (v1)**:
   - `CrystalJobsRegisterAppearanceRule(const CrystalJobsAppearanceRule* rule)` — registers `(job, branch, equip_slot_mask, relative_overlay_root)` (e.g., `job=17, branch=1, SLOT_RANGE, "soulspirexi-souls\\flintlock"`).
   - `CrystalJobsClearAppearanceRules(void)` — reversible teardown.
   - `CrystalJobsSetPeerSoul(uint32_t character_id, uint8_t job, uint8_t branch)` — fed by existing `soulspire_soul_actions/peer_souls.lua` and `crystalsocket` so nearby players' Souls are also known natively.
3. **Runtime Redirect Flow**:
   - When `FFXiMain.dll` loads an equipment model DAT for actor `A`:
     - Look up `A`'s active `(job, branch)` in `crystaljobs.dll` (local player via existing `CrystalJobsGetStatus` state; nearby players via `CrystalJobsSetPeerSoul`).
     - If a registered appearance rule matches `(job, branch, slot)` AND `<Ashita>\polplugins\DATs\<rule.overlay_root>\ROM\...\*.DAT` exists on disk, set a thread-local redirect path for that single load call.
     - Otherwise, load the untouched vanilla retail firearm DAT (`info[30]=0x03`, single gun, vanilla `lc03`/`ls03`).
   - Result:
     - **COR Flintlock + Silver Gun +1** → loads `flintlock/ROM/...` → 2 pistols + `lc07`/`ls07`.
     - **COR Gambler / COR Buccaneer / WAR Berserker + Silver Gun +1** → loads vanilla retail DAT → 1 pistol + `lc03`/`ls03`.
     - **Simultaneous multiplayer**: Flintlock and Berserker standing next to each other with Silver Gun +1 render dual pistols and single gun respectively at the same time.
     - **No server combat changes, no equipment rule changes, no `FTABLE.DAT` patching, no XIPivot hot-swapping.**

---

## 4. Acceptance Criteria Verification Gate
Do not mark Soul-specific Flintlock visuals complete until the native model-loader hook is implemented, compiled on Windows CI, and verified in-game against all 7 acceptance tests:
- [ ] COR Flintlock + gun → two pistols + dual-pistol `/ra` animations
- [ ] COR Gambler + same gun → one pistol + vanilla `/ra`
- [ ] COR Buccaneer + same gun → one pistol + vanilla `/ra`
- [ ] WAR Berserker + Silver Gun +1 → normal single-gun appearance
- [ ] Switching Souls → appearance updates cleanly without instability
- [ ] Zoning / relogging → no visual corruption or crashes
- [ ] Rollback / disable → cleanly restores vanilla visuals
