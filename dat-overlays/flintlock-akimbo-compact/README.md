# COR Flintlock Dual Pistols — AkimboRA v3.7 Compact (75%) Overlay

Optional, visual-only Ashita v4 XIPivot DAT overlay for **COR Flintlock** Phase 1.

- **Variant**: `AkimboRA-v3.7-compact` (75% stock firearm length in both hands and on both Mariner hip holsters).
- **Contents**: 278 DAT files (~134.7 MiB uncompressed):
  - **7 player skeleton/motion DATs** (`HumeM`, `HumeF`, `ElvaanM`, `ElvaanF`, `Tarutaru` shared M/F, `Mithra`, `Galka`): `ROM/27/82.DAT`, `ROM/32/58.DAT`, `ROM/37/31.DAT`, `ROM/42/4.DAT`, `ROM/46/93.DAT`, `ROM/51/89.DAT`, `ROM/56/59.DAT`. Adds custom dual-pistol motion layers (`q3d*`, `q3h*`, `q3a*`), action routines (`lc07`, `ls07`), and `splg` cancel cleanup without altering vanilla `lc03`/`ls03`.
  - **271 firearm DATs** (26 firearm appearances across 7 skeletons, including Death Penalty): adds matching offhand/hip pistols, Mariner leather-and-brass hip loops (`wep6`, `wep7`, `wep8`, `q3lt`), dual muzzle flashes (`q3f1`/`q3f2`), and switches `info[30]` from `0x03` to `0x07` so `/ra` plays `lc07`/`ls07`.
- **Conflict check**: 0 path overlaps with the base `dat-overlay/ROM/` overlay (`ROM/118`, `119`, `180`, `181`).
- **Default state**: **Disabled by default** (`defaultEnabled: false` in `manifest.json`, `EnableFlintlockDualPistolsOverlay = false` in `LauncherSettings`). Because FFXI firearm DATs are keyed by `(race, model_id)` rather than job/Soul, enabling this overlay affects all firearm models for the duration of the FFXI client session.

## Ashita v4 XIPivot Layout & Rollback

When enabled in the SoulspireXI Launcher:
- DATs sync to `<Ashita>/polplugins/DATs/flintlock-akimbo-compact/ROM/...`.
- `<Ashita>/config/pivot/soulspirexi.ini` lists:
  ```ini
  [overlays]
  0=flintlock-akimbo-compact
  1=soulspirexi
  ```
- **Rollback**: Uncheck **Enable Flintlock Dual Pistols DAT overlay (75% compact)** in the launcher (or run `/flintlock overlay off` in game) and start a fresh FFXI client. Stock FFXI DATs and the base `soulspirexi` overlay are never modified.
