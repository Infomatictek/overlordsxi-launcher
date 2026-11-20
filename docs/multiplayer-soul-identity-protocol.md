# SoulspireXI nearby-caster Soul action identity (OXSI v1)

Purpose: let observers see **the caster's Soul-specific spell, Job Ability, and weapon-skill names** while retaining stock vanilla gameplay packets. The client's own OXHD / 0x1FC Soul HUD feed does not supply other actors' Souls.

## Transport and boundaries

- Server-to-client custom FFXI packet `0x1FC` with magic `OXSI` in bytes 5..8. The OXHD packet uses the same type but is differentiated by its four-byte magic.
- Header offsets, **0-based from the FFXI packet start**:
  - `0x04..07`: ASCII `OXSI`
  - `0x08`: protocol version `1`
  - `0x09`: operation `1` upsert / `0` revoke
  - `0x0A..0D`: uint32 LE actor/server entity ID
  - `0x0E..11`: uint32 LE character identity ID (nonzero; v1 may mirror entity ID if no separate character ID is exposed)
  - `0x12`: uint8 base job ID (1–22)
  - `0x13`: uint8 Soul branch (1–3, zero on revoke)
  - `0x14`: uint8 ASCII character-name length (2–24)
  - `0x15`: uint8 Soul key length (2–64, zero on revoke)
  - `0x16...`: ASCII character name followed by canonical Soul key. Optional 0–3 zero padding bytes to four-byte boundary
- Client validates packet type, magic, exact field bounds, lengths, name syntax, known Soul-to-job/branch mapping and zero-only padding. Never use the client's own `OXHD` key to infer a peer's identity. Never trust an arbitrary chat statement as an identity update.
- Server should announce only visible, nearby players within the server's combat-log relevance radius; never send a global roster. Rate-limit changes and refresh active peer identities more often than the 120-second client expiry. Revoke identities on range exit or Soul change; zone/logout clears local cache.
- The addon uses actor name only as a text-rendering lookup **after** an authoritative packet creates the actor-ID/name/Soul association. Missing or expired identities preserve stock chat text. Actor IDs remain in the cache to replace stale names safely.

## Implemented on launcher main

`soulspire_soul_actions/peer_souls.lua` is a bounded verified in-memory cache (maximum 128 entries, 120-second expiry). `soulspire_soul_actions.lua` listens for OXSI announcements, matches known peers to incoming native combat text, resolves action IDs from `data/soul_actions.tsv`, and changes only the local visual text. It does not send packets or control gameplay. A confirmed cast line belonging to the local character continues to use the local Soul path.

**Server sender staged, not deployed:** `Infomatictek/overlordsxi` draft PR #23 (`feat/multiplayer-soul-action-identity`) adds `soulspire_soul_action_peers.cpp`, registers it in `modules/init.append.txt`, and adds `hud.buildIdentityData`. It has NOT been compiled, merged into server `main`, or verified with two players. Until that occurs, only local action names can be expected to change. Multi-client validation must cover two players using the same vanilla action ID with *different* Soul identities, zoning, range entry/exit, Soul swaps, and actor ID reuse.

## Non-goals

No global DAT string replacement, gameplay action ID changes, PvP intelligence beyond already-visible nearby actors, unverified peer-name inference, or automatic per-caster VFX. Soul action definitions remain editable TSV data rather than C++ constants.
