# SoulspireXI — COR Flintlock Dual Pistols Phase 1 Progress

Branch: `feat/flintlock-dual-pistols-phase1`  
Repository: `Infomatictek/soulspirexi-launcher`  
Scope: Phase 1 visual-only dual pistols for **COR Flintlock** (`job = 17`, `branch = 1`). Vanilla ranged damage, TP, ammunition, equipment rules, and combat timing remain untouched.

---

## Audit Summary (Completed)

### 1. Supplied Asset Package Verification
All 5 uploaded archives verified against their SHA256 checksums:
- `Flintlock-Docs-and-Source.zip` (`52c831e4...`) — docs, `AkimboAim.lua`, `AkimboRA-Source/`, `Crossfire-Waltz/` (future phase).
- `Flintlock-AkimboRA-Compact-Part-01-of-04.zip` (`9e9ba77d...`) through `Part-04-of-04.zip` (`c97f1334...`) — combined into `AkimboRA-v3.7-compact/ROM/`.
- Total compact overlay payload: **278 DAT files** (`141,248,752` bytes / ~134.7 MiB uncompressed; largest single file is `ROM/56/59.DAT` at `3,583,152` bytes).

### 2. Compatible Player Models & Firearms
From `AkimboRA-Source/work/ra-rigs/build_v3.py` and `START-HERE.md`:
- **7 player skeletons** (shared M/F Tarutaru rig):
  - `ROM/27/82.DAT` (3.02 MB), `ROM/32/58.DAT` (3.05 MB), `ROM/37/31.DAT` (3.38 MB), `ROM/42/4.DAT` (3.24 MB), `ROM/46/93.DAT` (3.06 MB), `ROM/51/89.DAT` (3.30 MB), `ROM/56/59.DAT` (3.58 MB).
  - Adds `q3d0..2`, `q3h0..2`, `q3a0..2`, `lc07`, `ls07`, and `splg` cancel cleanup while keeping vanilla `lc03`/`ls03` untouched.
- **271 firearm DATs** (26 firearm appearances across 7 skeletons, including Death Penalty):
  - Scales guns to 75%, adds offhand/hip pistols + Mariner holster loops (`wep6`/`wep7`/`wep8`/`q3lt`) + dual muzzle flashes (`q3f1`/`q3f2`).
  - Sets `info[30] = 0x07` (replacing `0x03`) so the FFXI `/ra` scheduler plays `lc07`/`ls07`.
  - Stock single-gun weapon skills (Slug Shot, Last Stand, etc.) draw the primary pistol while the second remains holstered.

### 3. Conflict Check Against Existing SoulspireXI DATs
- Existing `dat-overlay/ROM/` contains 8 files (`ROM/118/108.DAT`, `118/114.DAT`, `119/57.DAT`, `180/102.DAT`, `181/72..75.DAT`).
- **0 path conflicts** with the 278 `AkimboRA-v3.7-compact/ROM/` DATs.

### 4. Ashita v4 Launcher & Overlay Architecture
- **XIPivot under Ashita v4**: Loaded as a POL plugin (`polplugins/pivot.dll`) via `config/boot/soulspirexi.ini` (`[ashita.polplugins] pivot = 1`, `[ashita.polplugins.args] pivot = soulspirexi`) reading `config/pivot/soulspirexi.ini` (`root_path=<Ashita>\polplugins\DATs`).
- **Why assets are staged in `dat-overlays/flintlock-akimbo-compact/` instead of `dat-overlay/`**:
  - `dat-overlay/ROM/` is unconditionally synced to `polplugins/DATs/soulspirexi/ROM/` and active for all players and all Souls.
  - Because firearm DATs are keyed by `(race, model_id)` and carry `info[30] = 0x07`, putting them in the global overlay would replace gun visuals for COR Gambler, COR Buccaneer, RNG Sniper/Huntsman/ArcaneArcher, and all other firearm users.
  - Staging them under `dat-overlays/flintlock-akimbo-compact/ROM/` and tracking them in `manifest.json` under `optionalOverlays` (with `defaultEnabled: false`) preserves backward compatibility with existing launcher binaries, avoids forcing a 135 MiB download on non-Flintlock players, and keeps activation strictly opt-in and reversible.

### 5. Soul Identity Synchronization
- `crystalsocket/soul_identity.lua` decodes `0x1FC` (`OXHD`) packets; COR Flintlock is `job = 17, branch = 1` (`flintlock`).
- `native/crystaljobs/crystaljobs.dll` exposes `CrystalJobsGetStatus` (read via LuaJIT FFI in `soulspire_soul_actions/soul_bridge.lua`), providing authoritative `enabled`, `known`, `job`, `branch`, and `character_id`.

---

## Stage Status

### Stage 1 — Asset Integration (Completed)
- [x] Verify uploaded ZIP SHA256 checksums and extract compact 75% AkimboRA pack.
- [x] Verify 0 DAT path conflicts with `dat-overlay/ROM/`.
- [x] Stage 278 DATs under `dat-overlays/flintlock-akimbo-compact/ROM/` with overlay README.
- [x] Extend `scripts/update-launcher-manifest.py` and `scripts/verify-launcher-manifest.py` for `optionalOverlays` (SHA256, size, completeness, zero-conflict checks).
- [x] Add opt-in, reversible overlay support to `SoulspireLauncher` (`LauncherManifest`, `LauncherSettings`, `ManifestUpdateService`, `AshitaConfigGenerator`, `MainViewModel`, `MainWindow.xaml`) — **disabled by default**.
- [x] Regenerate and verify `manifest.json` (1110 core + 278 optional overlay entries, 9/9 manifest tests passing).

### Stage 2 — Flintlock-Only Activation (Completed)

#### Technical Blocker for Pure Runtime DAT Hot-Swapping
True live runtime switching of the 278 dual-pistol DATs on Soul change (without restarting FFXI) is **not supported by Ashita v4 + XIPivot + vanilla FFXI DAT caching**:
1. **XIPivot boot-time scope**: `polplugins/pivot.dll` is a PlayOnline plugin loaded before `FFXiMain.dll`. It reads `config/pivot/soulspirexi.ini` at startup and intercepts Win32 file opens globally for the entire FFXI process with no actor, job, or Soul awareness.
2. **FFXI in-memory DAT cache**: FFXI caches loaded race skeleton/motion DATs (containing `lc07`/`ls07`/`q3*`) and firearm model DATs (containing `info[30] = 0x07`, 75% dual meshes, and Mariner hip holsters) in memory. Changing overlays mid-session does not evict cached models/motions on Soul swap and risks client crashes across zone transitions (explicitly warned in upstream `START-HERE.md`).
3. **Model-ID keying**: Because `info[30] = 0x07` is baked into the 271 firearm DATs keyed by `(race, model_id)`, any active XIPivot overlay affects all characters rendering those 26 firearm models in that client session. Achieving per-actor/per-Soul runtime animation switching would require new native `FFXiMain.dll` DAT/model-loader hooks (out of scope for Phase 1).

#### Safest Achievable Implementation (Zero Impact on Other Souls)
- **DAT overlay stays opt-in (`defaultEnabled: false`)** via `EnableFlintlockDualPistolsOverlay` in SoulspireXI Launcher and `optionalOverlays` in `manifest.json`. Non-Flintlock players never download or activate the 278 DATs.
- **New client-only Ashita v4 addon `addons/ashita4/soulspire_flintlock/`** (auto-loaded via `AutoLoadFlintlockAddon`, completely inert on non-Flintlock Souls):
  - `flintlock_state.lua`: Reuses existing `crystaljobs.dll` (`CrystalJobsGetStatus`) and `0x1FC` (`OXHD`) Soul identity to gate activation strictly to **COR Flintlock (`job == 17, branch == 1`)**. Ports `AkimboAim` auto-facing (`0x01A` category `0x10` + `0x0028` category `12`/`2`, respecting `0x7073` cancel) to Ashita v4, gated strictly to COR Flintlock + equipped firearm + local actor. Resets cleanly on zone (`0x000A`/`0x000B`), logout, or Soul change.
  - `pivot_config.lua`: Safely parses and reversibly updates `config/pivot/soulspirexi.ini` (`0=flintlock-akimbo-compact`, `1=soulspirexi` vs `0=soulspirexi`) for the **next** client launch without touching live DATs in memory.
  - `soulspire_flintlock.lua`: Provides `/flintlock status`, `/flintlock aim on|off`, `/flintlock overlay on|off`, and one-time non-spammy Soul-transition guidance when active Soul and session overlay state disagree.
  - `tests/flintlock_spec.lua`: Pure-Lua unit tests covering Soul gating, `0x01A`/`0x0028` packet parsing, cancel handling, firearm classification, yaw math, zone reset, and reversible Pivot INI toggling.
- **Compatibility**: Zero modifications to `native/crystaljobs/crystaljobs.dll`, `crystalsocket`, `soulspire_soul_actions`, equipment rules, or server combat mechanics.

### Stage 3 — Validation (Completed — Automated; Windows In-Game Verification Pending)

#### Automated Test Results (All Passing)
- `scripts/verify-launcher-manifest.py`: **PASSED** (1,114 core entries + 278 optional overlay entries verified, read-only, 0 conflicts with base `dat-overlay/ROM/`).
- `tests/test_flintlock_dual_pistols.py`: **4/4 PASSED** (asset count/mapping for 7 skeletons + 271 firearms, 0 base DAT conflicts, `defaultEnabled: false` & `soulGate` checks, conflict rejection, Flintlock Lua spec).
- `tests/test_manifest_verification.py`: **9/9 PASSED**.
- `tests/test_soul_spell_dat_and_actions.py`: **5/5 PASSED**.
- `tests/test_native_equipment_hook.py`: **5/5 PASSED** (`crystaljobs.dll` Win32 x86 PE32 with all 21 exports intact and untouched).
- LuaJIT addon regression suite: **12/12 PASSED** (`crystalsocket` 2/2, `soulspire_soul_actions` 9/9, `soulspire_flintlock` 1/1).
- Note: `SoulspireLauncher.Tests` (C# / .NET WPF) and live FFXI client rendering require Windows and have not yet been executed in-game; do not claim live animation compatibility until the checklist below is verified on Windows.

#### Manual Windows In-Game Test Checklist
1. **Default / Non-Flintlock Safety**:
   - Launch SoulspireXI Launcher with default settings (`Enable Flintlock Dual Pistols DAT overlay` unchecked).
   - Verify `config/pivot/soulspirexi.ini` has only `0=soulspirexi` and `polplugins/DATs/flintlock-akimbo-compact/` is NOT synced.
   - Log in as COR Gambler/Buccaneer or RNG with a gun; confirm normal single-gun idle, holster, and `/ra <t>`. Run `/flintlock status` and confirm `FlintlockActive=false`.
2. **Opt-In Sync & Idle / Holster**:
   - Close FFXI, check **Enable Flintlock Dual Pistols DAT overlay (75% compact, COR Flintlock opt-in)** in the launcher, sync, and launch a fresh FFXI client.
   - Equip COR **Flintlock** Soul + **Silver Gun** + **Bronze Bullet**.
   - Stand, walk, and run in a 3/4 camera view: verify 75% matching dual pistols on both hips in the Mariner leather-and-brass loops.
   - Equip a second firearm (e.g., Troll Gun or Death Penalty) and verify both pistols update together; unequip firearm to confirm both disappear.
3. **Ranged Attacks & Auto-Facing**:
   - Face away from a mob and execute `/ra <t>` (and `/ra <stnpc>`): verify character turns toward the target (Flintlock auto-aim), draws both pistols from the hip loops, fires two visual recoil beats with dual muzzle flashes, and returns both guns to the holsters while resolving one vanilla ranged attack (damage, TP, 1 ammo).
   - Move mid-ready to cancel `/ra`: verify clean interrupted return and no stuck weapons.
   - Fire a stock single-gun WS (e.g., Slug Shot / Last Stand): verify primary pistol draws while second remains holstered.
4. **Soul Switching**:
   - Switch COR Soul from **Flintlock** to **Gambler** or **Buccaneer**: verify `/flintlock status` shows `FlintlockActive=false`, auto-facing stops immediately, and the one-time restart advisory appears.
   - Run `/flintlock overlay off`, restart FFXI, and confirm vanilla single-gun animations are restored with no residual artifacts.
5. **Zoning & Relogging**:
   - With Flintlock overlay enabled, zone across 2–3 zones (town ↔ field ↔ mog house) and perform a full `/logout` + relog.
   - Confirm no client crash, no corrupted skeleton/weapon state, and `/flintlock status` re-syncs cleanly after zone/relog.
6. **Controller / Gamepad Operation**:
   - Trigger `/ra <t>` via gamepad macro/menu and navigate the Equipment + CrystalSocket menu (`crystalsocket`) and Magic/Ability menus (`soulspire_soul_actions`) with controller D-pad/confirm/cancel.
   - Confirm zero input conflicts with `soulspire_flintlock`, `crystalsocket`, or `crystaljobs.dll`.

---

## Future Phases (Document Only — Out of Scope for Phase 1)
- **Independent pistol firing**: Separate main-hand / off-hand shot cadence and animation state machine.
- **Shared ammunition**: Dual-shot ammo consumption accounting against the single ranged ammo slot.
- **Independent TP mechanics**: Per-shot or split TP gain balancing on the server.
- **Rapid single-target bullet spam**: Flintlock rapid-fire ability/stance mechanics.
- **Crossfire Waltz weapon skill**: Reserve unused WS ID on `soulspirexi` server, wire `Crossfire-Waltz-motion.DAT` (`cfw0`/`cfw1`/`cfw2`) and `Crossdraw-Trump-Gun.DAT`, plus multi-race retargeting beyond Mithra.
- **Flintlock Soul HUD integration**: Dedicated ammo/chamber/stance indicators in `soulspire_soulhud`.
