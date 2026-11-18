# OverlordsXI Universal Soul HUD (`overlords_soulhud`)

A modular, data-driven Ashita v4 HUD addon for OverlordsXI supporting all 66 Soul Crystal specializations.

## Installation

### Client (Ashita v4)
1. Copy the `overlords_soulhud` folder into `<Ashita4>/addons/overlords_soulhud/`.
2. Load in-game or via `Default.txt`:
   ```
   /addon load overlords_soulhud
   ```

### Server (LandSandBoat / OverlordsXI)
1. Ensure `modules/custom/lua/overlords_soul_hud.lua` and `modules/custom/commands/soulhud.lua` are present and listed in `modules/init.txt` (automated via `scripts/setup-local-server.ps1`).
2. Restart `xi_map` if adding the module for the first time.

## Commands
- `/soulhud` or `/shud` — Toggle HUD visibility (`auto` <-> `hide`)
- `/soulhud show | hide | auto` — Set visibility mode
- `/soulhud compact | expanded` — Switch layout density
- `/soulhud lock | unlock` — Lock or unlock window dragging
- `/soulhud scale <0.75-2.0>` — Set HUD scale
- `/soulhud opacity <0.25-1.0>` — Set HUD opacity
- `/soulhud config` — Open settings & per-element visibility window
- `/soulhud preview <soul_key|off>` — Preview any registered Soul HUD
- `/soulhud sync` — Request immediate server state resync
- `/soulhud status` — Print diagnostics
- `/soulhud reset` — Reset settings to defaults

## Adding a New Soul (Developer Guide)

### 1. Client Registration (`souls/<job>_<soul>.lua`)
Create a new file in `souls/` and add its module name to `souls/init.lua`:

```lua
return function(registry)
    registry.registerSoul({
        key         = 'my_soul_key', -- must match overlords_job_specs.lua key
        name        = 'My Soul',
        jobId       = 1,             -- FFXI job ID
        jobAbr      = 'WAR',
        branchId    = 1,             -- Crystal branch ID (1..3)
        accentColor = 0xFFD9C38C,    -- Packed ABGR
        resources   = {
            {
                id            = 'my_stack',
                label         = 'My Resource',
                shortLabel    = 'Res',
                type          = 'stack',      -- stack|gauge|charges|cooldown|timer|toggle|combo|counter|status
                style         = 'segmented',  -- segmented|bar|radial|linear|pill|badge|numeric
                min           = 0,
                max           = 5,
                serverKey     = 'res',        -- key in [OXHUD] payload
                warnThreshold = 0,
                warnMode      = 'low',        -- low|high|active
                compact       = true,
            },
            {
                id         = 'my_cd',
                label      = 'My Ability',
                shortLabel = 'Abil',
                type       = 'cooldown',
                style      = 'radial',
                duration   = 30,
                recastId   = 150,            -- Ashita native recast ID (zero extra packet traffic)
                compact    = true,
            },
        },
    })
end
```

### 2. Server State Provider (`modules/custom/lua/overlords_soul_hud.lua`)
Register a lightweight read-only collector for `my_soul_key`:

```lua
hud.registerProvider('my_soul_key', function(player)
    return {
        res = player:getLocalVar('OX_MY_RESOURCE') or 0,
    }
end)
```

The server framework automatically hashes the state, suppresses duplicate packets, and pushes updates on ability use, status gain/lose, damage, zone-in, job/spec change, death/raise, and `!soulhud sync`.
