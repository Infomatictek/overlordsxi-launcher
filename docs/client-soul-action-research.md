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

## 2026-11-19: Shinobi native action inventory gate

Live client validation has confirmed the native Equipment job name is shown as `Lv25 Shinobi`. The native Equipment hook is real, but it does **not** establish that spell/ability menus use the same renderer or call site.

Ashita v4's resource API exposes `GetSpellById` and `GetAbilityById`, including English names and descriptions, mana cost, spell cast time, recast and other metadata; see its official SDK. Soul Actions v0.3.0 therefore offers a **read-only inventory export** in the existing panel, with no new overlay and no shell commands:

1. Open the Soul Actions panel.
2. Click **Export native spell and ability IDs**.
3. Wait for the single completion chat message. The bounded job processes 20 IDs per rendered frame.
4. The client writes `addons/overlords_soul_actions/native-actions-audit.tsv`, listing client resource IDs and vanilla display strings. This is local diagnostic data, not a deployed Soul whitelist, gameplay authority, or proof of native menu interception.

The export contains all available spell IDs in 0..1023 and abilities in 0..2047. It deliberately does **not** guess which entries Shinobi is allowed to cast. Actual allowed action names, JA IDs and level progression require checking the current gameplay definitions, independently of the client's resources, before writing the client profile. No custom labels are automatically invented.

### Required native FFXI binary study

Use the identical validated `FFXiMain.dll` binary build from the Equipment hook (timestamp `0x6ae818b4`, `SizeOfImage=0xC17000`). Find the actual **Magic** and **Abilities** menu state/list rendering sites (both list row labels and description panel) and record:

- Menu identifier, object/vtable, rendering function and relevant RVA
- How each visible row resolves a spell/ability ID, name, icon, availability and description
- Whether the resource strings are copied into mutable buffers, or rendered directly
- The exact function prototype and x86 stack/register ABI and a 24-byte code signature
- How target selection, macro command resolution and recast UI obtain the action ID
- Whether the same resource ID can be shown differently for two distinct active Souls without global DAT renaming

Implement a scoped read-only selection/identity tracer first and validate it with one Shinobi spell and one Shinobi JA. Do not ship unverified pointer patches, overwrite resource table strings globally, or rename actions in unrelated jobs. Scope custom names to active Soul; preserve native action IDs and stock fallback. Add x86 ABI tests before packaging any new native hook. The existing DLL is currently at 10 hooks; don't change that count without a verified additional patch.

**Status:** Client resource inventory and discovery path implemented in Lua. Native spell/ability menu replacements, cast bar, logs, macros and VFX remain pending binary research and actual tests.
