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

### Stage 2 — Flintlock-Only Activation (Pending)
- Document exact technical blocker preventing live runtime DAT hot-swapping via XIPivot/FFXI DAT cache.
- Implement `addons/ashita4/soulspire_flintlock/` reusing existing `crystaljobs.dll` / `0x1FC` Soul identity:
  - Flintlock-only Ashita v4 port of `AkimboAim` (auto-face `/ra` target only when `job == 17, branch == 1` and a Gun/Cannon is equipped).
  - Safe overlay status/toggle helper (`/flintlock status`, `/flintlock aim on|off`, `/flintlock overlay on|off` for next client restart) with non-spammy Soul-transition guidance and clean reset on zone/logout/Soul change.
- Commit and push Stage 2 separately.

### Stage 3 — Validation (Pending)
- Run focused automated tests (manifest verification, asset mapping/integrity, Flintlock-only gating, CrystalSocket / Soul Actions / `crystaljobs.dll` compatibility).
- Provide manual Windows in-game test checklist.
- Commit and push Stage 3 separately.

---

## Future Phases (Document Only — Out of Scope for Phase 1)
- **Independent pistol firing**: Separate main-hand / off-hand shot cadence and animation state machine.
- **Shared ammunition**: Dual-shot ammo consumption accounting against the single ranged ammo slot.
- **Independent TP mechanics**: Per-shot or split TP gain balancing on the server.
- **Rapid single-target bullet spam**: Flintlock rapid-fire ability/stance mechanics.
- **Crossfire Waltz weapon skill**: Reserve unused WS ID on `soulspirexi` server, wire `Crossfire-Waltz-motion.DAT` (`cfw0`/`cfw1`/`cfw2`) and `Crossdraw-Trump-Gun.DAT`, plus multi-race retargeting beyond Mithra.
- **Flintlock Soul HUD integration**: Dedicated ammo/chamber/stance indicators in `soulspire_soulhud`.
