# OverlordsXI Soul HUD (Ashita v4)

A server-authoritative, modular HUD for OverlordsXI Soul Crystal specializations.

## Install
Copy this directory into `Ashita/addons/`, then run `/addon load overlords_soulhud`.
The server must also load `modules/custom/lua/overlords_soul_hud.lua` and `modules/custom/commands/soulhud.lua` from the matching server branch.

## Commands
- `/soulhud toggle` — show or hide the HUD.
- `/soulhud compact` — toggle compact mode.
- `/soulhud sync` — request a fresh snapshot.
- `/soulhud reset` — reset window geometry.

## Coverage
- All 66 keys in the canonical 22-job Soul catalog are registered client-side, so every catalog Soul can be recognized by the HUD.
- Live resource providers currently exist for **Gambler** and **Mirage Sentinel** only.
- Other Souls show their correct title and an explicit “No live resource provider…” message instead of fabricated or permanently-zero counters.
- Flintlock is recognized but has no resource meters until its gameplay implementation exposes authoritative state.

The client framework supports: stack, gauge, charges, cooldown, timer, toggle, combo, counter, and status.

## Protocol
The client reads the server's `[OXHUD]|<job>|<soul-key>|<unlocked>|key=value;key=value` SYSTEM_3 payload.
It does not predict or modify gameplay state. The client clears cached state on zoning or logout; timers count down locally from the latest server-authoritative snapshot.

## Extending
1. Add or update a provider with `xi.overlords.hud.registerProvider(soulKey, collectorFn)` in the server module.
2. Return only scalar state that is genuinely maintained by server gameplay code.
3. Add matching element definitions in `souls.lua`.
4. Keep the provider key identical to the active Soul key in `overlords_job_specs.lua`.
