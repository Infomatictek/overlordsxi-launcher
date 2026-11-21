# AkimboRA v3.7 Dual-Pistol Defect Investigation & Audit

Branch: `fix/flintlock-akimbo-blink-audit` (not merged to `main` pending live Windows FFXI verification)

## Executive Summary

Live Windows FFXI playtesting of COR Flintlock (`Rin`, HumeF) revealed two visual defects:
1. **Entire character briefly disappears (blinks)** during `/ra`.
2. **Pistol hip positions look incorrect** (one pistol protruding forward, the other far behind the hip).

**Both defects originate in the upstream `AkimboRA-Source` package — neither was introduced by the 75% compact conversion or by SoulspireXI's Ashita v4 XIPivot integration.**

---

## Defect 1 — Character Blink During `/ra` (Targeted DAT Fix Applied)

### Root Cause
In upstream `AkimboRA-Source/work/ra-rigs/build_v3.py` (lines 124–128, 144, 148):
```python
unblock = weapon_visibility(2, False, opcode=0xa3)
events.extend(belt_events(0) + [(0, weapon_visibility(2, True, opcode=0xa3)),
                                (0, weapon_visibility(2, True)), (1, weapon_visibility(2, True)), (1, unblock)])
```
- Across all 7 player skeleton DATs, **0 vanilla FFXI routines use scheduler opcode `0xa3`**. Standard FFXI per-slot weapon visibility (`wep0`–`wep8`) uses opcode **`0x75`**, which `lc07`, `ls07`, and `splg` already emit.
- The original author injected 4 `0xa3` commands per race (`lc07` at `t=0` `hidden=1`, `lc07` at `t=1` `hidden=0`, `ls07` at `t=0` `hidden=0`, `splg` at `t=0` `hidden=0`) intending an independent `wep2` flag.
- In live `FFXiMain.dll`, `0xa3` toggles actor-wide model visibility rather than weapon slot 2 — hiding the entire character at `t=0` and unhiding at `t=1`, producing the 1-tick blink at `/ra` start.
- Motion clip audit across all 7 skeleton DATs (`q3d0..2`, `q3h0..2`, `q3a0..2`) confirmed **0 NaN/Inf values**, strictly positive bone scales (`[0.1786, 1.8214]`), and bounded translations (`max |T| <= 2.173`).

### Targeted Fix Applied
- Added reproducible tool [tools/patch_flintlock_skeleton_blink.py](file:///mnt/user/appdata/soulspirexi-launcher/tools/patch_flintlock_skeleton_blink.py) and stripped all 28 erroneous `0xa3` commands (4 per race) while preserving all `0x75` weapon visibility timing, all `q3*`/`q4*` animation cues, and every other DAT section byte-for-byte.
- **Exact modified DATs** (7 player skeletons only; 182 firearm DATs and 89 stock WS DATs had 0 `0xa3` hits and remain untouched):
  - `dat-overlays/flintlock-akimbo-compact/ROM/27/82.DAT` (HumeM)
  - `dat-overlays/flintlock-akimbo-compact/ROM/32/58.DAT` (HumeF)
  - `dat-overlays/flintlock-akimbo-compact/ROM/37/31.DAT` (ElvaanM)
  - `dat-overlays/flintlock-akimbo-compact/ROM/42/4.DAT` (ElvaanF)
  - `dat-overlays/flintlock-akimbo-compact/ROM/46/93.DAT` (Tarutaru)
  - `dat-overlays/flintlock-akimbo-compact/ROM/51/89.DAT` (Mithra)
  - `dat-overlays/flintlock-akimbo-compact/ROM/56/59.DAT` (Galka)
- **Verification status**: Automated DAT/manifest/regression checks pass; **live Windows FFXI testing is still required** to confirm the character blink is eliminated in-game (and to check whether `0x75` alone cleanly suppresses any `wep2` tick-0 flash).

---

## Defect 2 — Incorrect / Asymmetric Pistol Hip Positions (Requires Upstream Rebuild)

### Root Cause
In upstream `AkimboRA-Source/work/ra-rigs/v3_holster.py` (lines 16–75), `_CARRY` places the two hip pistols (`wep8` left hip, `wep7` right hip) at FFXI's native sheathed-dagger coordinates (`EID 99`) rather than symmetric side-hip holsters:

| Race | Side 0 (`wep8`) Pos `(X, Y, Z)` | Side 1 (`wep7`) Pos `(X, Y, Z)` | `|ΔZ|` Asymmetry |
|---|---|---|---|
| HumeM | `(+0.169, -0.093, +0.065)` | `(-0.192, -0.062, +0.085)` | `0.020` (nearly symmetric) |
| **HumeF (`Rin`)** | `(+0.180, -0.040, +0.082)` | `(-0.133, -0.092, -0.234)` | **`0.316` (front vs rear hip)** |
| **ElvaanM** | `(+0.177, -0.121, +0.023)` | `(-0.186, -0.066, -0.301)` | **`0.324` (front vs rear hip)** |
| **ElvaanF** | `(+0.213, -0.117, -0.273)` | `(-0.173, -0.100, +0.061)` | **`0.334` (rear vs front hip)** |
| Tarutaru | `(+0.179, -0.029, -0.138)` | `(-0.175, -0.010, -0.176)` | `0.038` (nearly symmetric) |
| **Mithra** | `(+0.225, -0.024, -0.053)` | `(-0.206, -0.071, -0.205)` | **`0.152` (asymmetric)** |
| Galka | `(+0.347, -0.023, -0.383)` | `(-0.305, -0.049, -0.466)` | `0.083` (nearly symmetric) |

### Compact 75% Conversion Check
- `native_gun.py:scale_equipped_gun(data, 0.75)` scales `wep2` vertices uniformly around the grip origin `(0, 0, 0)` before generating `wep2`, `wep7`, `wep8`, and Mariner leather loops (`wep6`, `q4m0`, `q4m1`). It did **not** introduce the hip offset asymmetry.

### Why This Cannot Be Hot-Patched Without Rebuilding from Stock FFXI DATs
Moving `wep7`/`wep8` alone in the binary DATs would desynchronize:
1. The arm IK pickup/docking reach baked into `q3d*` and `q3a*` (`v3_holster.py:apply()`).
2. The static Mariner leather hanger (`wep6`) and animated morphing leather straps (`q4m0`, `q4m1`) fitted to `_CARRY` (`v3_leather.py:holster_art()`).

**Clean fix path for Defect 2**: Edit `_CARRY` in `AkimboRA-Source/work/ra-rigs/v3_holster.py` (symmetrizing `Z`/`Y` hip sockets for HumeF, ElvaanM, ElvaanF, and Mithra) and rebuild the compact overlay on a Windows machine with stock FFXI DATs via:
```powershell
python build.py --ffxi "<PATH_TO_FINAL_FANTASY_XI>"
```
(Also remove the 4 `0xa3` lines from `AkimboRA-Source/work/ra-rigs/build_v3.py` before rebuilding so future builds never reintroduce Defect 1.)
