# SoulspireXI Soul Actions — client prototype

This is a safe Ashita v4 **identity viewer prototype**, not a complete native action replacement system. It never blocks actions or modifies packets, animations, cast bars, resource DATs, or the game's combat log.

## Install / test
Copy this folder to Ashita's addons directory and run:
```
/addon load soulspire_soul_actions
/soulactions demo
/soulactions status
/soulactions clear
```
Demo uses a fictional mapping to show the intended presentation, **not** a verified spell ID or live Astromancer configuration.

## Architecture
- `catalog.lua`: Soul/action-ID keyed presentation registry with spell, ability, and weaponskill support.
- `soulspire_soul_actions.lua`: minimal UI and session lifecycle. It clears stale identities on zoning and main-job changes.
- Gameplay authority remains in the server's `soulspire_soul_actions.lua` module.

## Not implemented
Server identity sync; native spell/ability menu replacement; original chat-line substitution; native cast bar replacement; synchronized third-party spell names; DAT/animation replacement; manifest packaging. These require separately validated Ashita API / packet and server contracts.

## Follow-up integration
1. Define a versioned server-to-client identity packet with strict length and session validation.
2. Populate the authoritative server registry for the canonical Soul roster.
3. Build client sync and nearby-caster identity cache, with zone/job/Soul-change invalidation.
4. Prototype native action menu/resource hooks in isolation. Prefer safe overlay if unsupported.
5. Validate all visual substitutions with two real clients before enabling.
