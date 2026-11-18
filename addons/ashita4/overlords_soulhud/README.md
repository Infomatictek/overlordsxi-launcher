# OverlordsXI Soul HUD (Ashita v4)

A server-authoritative, modular HUD for Soul Crystal resources.

## Install
Copy this directory into `Ashita/addons/`, then run `/addon load overlords_soulhud`.
The server must also load `modules/custom/lua/overlords_soul_hud.lua`.

## Commands
- `/soulhud toggle` — show or hide the HUD.
- `/soulhud compact` — toggle compact mode.
- `/soulhud sync` — request a fresh snapshot.
- `/soulhud reset` — reset window geometry.

## Protocol
The client reads the server's silent SYSTEM_3 payload:
`[OXHUD]|<job>|<soul-key>|<unlocked>|key=value;key=value`.
It does not predict or modify gameplay state. The client clears cached state on zoning or logout; timers count down locally from the latest server-authoritative snapshot.

## Extending
Add a matching provider key in the server module and a definition in `souls.lua`. The framework is reusable across all Soul keys; the initial resource definitions currently cover Flintlock, Gambler, and Mirage Sentinel.
Supported resource types: stack, gauge, charges, cooldown, timer, toggle, combo, counter, status.
