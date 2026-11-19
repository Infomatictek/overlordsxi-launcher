# Soul action client modification: feasibility and investigation

**Scope: client only.** No server behavior, spell damage, permission enforcement or sync is in scope for this phase.

## Verified from this repository
- `crystalsocket/job_labels.lua` uses FFI exports from `crystaljobs.dll` to modify native job labels, so a native extension path already exists.
- `native/crystaljobs/labels.h` maps job/branch to Soul labels.
- `overlords_soul_actions` is currently an ImGui identity viewer, not a native menu replacement.
- `presentation.lua` can resolve the same numeric action ID differently for different Souls without mutating global resources.

## Client surface matrix
| Surface | Candidate approach | Evidence needed before implementation |
| --- | --- | --- |
| Soul-specific spell/JA/WS lists | Ashita ImGui overlay; eventually native menu interception | Native menu layout, selection, action dispatch, resource lookup |
| Name and description | Overlay first; native resource lookup hook second | Ashita resource API and client string lookup call sites |
| Cast bar | Custom overlay or tested native cast-text hook | Cast start/interruption events, entity identification |
| Combat log | Render supplemental Soul messages; suppress native only if safe | Message IDs, actor IDs, action packet parsing, duplication rules |
| Other players | Actor-specific Soul mapping in client cache | Authoritative identity source; without it cannot distinguish identical base IDs |
| Animation and VFX | DAT asset replacement or validated per-cast effect substitution | Effect ID tables, animation packet structure, test on two clients |
| Macros | Optional Soul-name command translator to underlying action | Exact Ashita command event behavior, escaping, target syntax |
| Icons | Custom textures in overlay | Icon resource formats and packaging |
| Recast and costs | Display metadata in overlay | Client recast API and authoritative values |

## Non-negotiable safety
- Do not globally overwrite the shared spell name: Water may represent different actions for different Souls.
- Never fabricate another player's Soul from a spell ID alone.
- No blind packet-byte editing, unverified pointer writes or global DAT substitutions.
- Fallback must preserve native action execution and the original client when the extension is disabled.
- Add debug probes separately and opt-in; do not poll expensive memory scans every frame.

## Validation plan
1. Inventory Ashita v4 resource APIs and existing native `crystaljobs` hooks.
2. Prove local identity rendering, action selection, target selection and casting with existing IDs.
3. Prove menu name/description changes without altering the underlying action command.
4. Prove combat log and cast bar with a second client, including interruption and zone transitions.
5. Investigate per-caster VFX; if impossible with supported hooks, document the native extension or DAT work required.
6. Integrate client-only catalog distribution in the launcher manifest after tests and checksum generation.

**Status:** This document is an investigation plan, not a claim that native replacement has been achieved.
