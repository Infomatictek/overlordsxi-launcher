# Native Equipment Menu Soul Name + Search Reliability

## Intended behavior
The native Equipment menu should show the full active Soul name in place of the underlying job name, e.g. Astromancer rather than Black Mage. Existing search results should continue showing Soul abbreviations/full names as appropriate.

## Existing native path
- `native/crystaljobs/crystaljobs.cpp` already hooks native lookup and text/sprite paths, including `item_label`, `draw_branch`, and `full_branch`.
- `native/crystaljobs/labels.h` holds the job/branch -> full and abbreviated Soul names.
- `addons/ashita4/crystalsocket/job_labels.lua` synchronizes the active Soul state to `crystaljobs.dll`.
- Native hooks are signature-gated to a specific FFXI client build. Do not guess additional offsets.

## Search bug fixed in source
A mixed search response may decode a character row containing the Soul extension, followed by a row without the extension. Previously the second row erased the valid Soul branch. The cache now retains the known branch when the same character/job row lacks the extension, while still allowing an explicit extension to update it and invalidating when the job changes.

**Important:** This is a source fix only. It requires rebuilding and distributing `crystaljobs.dll`, and has not been validated against live search traffic. A search request can still clear cached rows; this change is not a complete search audit.

## Equipment-menu investigation
Do **not** assume `full_branch` is called by the Equipment screen. Determine the exact text lookup or render path from a supported client build first, then extend the existing DLL with:
1. A read-only Equipment menu context check.
2. The active local character/job/branch from the existing native state, guarded by its session lease.
3. Full `label_for(job, branch, true)` for the native Equipment job-name field.
4. Fallback to stock job text on unknown Soul, zoning, invalid session, unsupported build, or hook failure.
5. No changes to the underlying job ID, equipment restrictions, or combat actions.

## Verification matrix
- Equipment: active Soul, switching Souls within same job, changing jobs, logout/login, zoning, menu already open during a switch.
- Search: multiple pages, duplicate rows, character changes job, row without extension, hidden/invalid entries, mixed old/new client packets.
- Safety: stock fallback, disabled DLL, unsupported executable, no extra per-frame polling.
- Release: compile native DLL, run existing tests, inspect new DLL exports, update launcher manifest checksum and size, verify launcher installs it, then test in-game.

Do not claim Equipment-menu replacement is complete until its actual native call site is identified and validated.
