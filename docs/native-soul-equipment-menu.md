# SoulspireXI — Native FFXI Equipment Menu & Controller Support (`crystaljobs.dll` Hook #24)

## Root Cause (Verified in `FFXiMain.dll`)

Disassembly of the supported retail `FFXiMain.dll` image (`TimeDateStamp = 0x6ae818b4`, `SizeOfImage = 0xC17000`, preferred base `0x10000000`) confirmed how the native Equipment menu and `/equip` commands validate Sub-slot items:

1. **Native Sub-Slot Item Listing (`0x1336CE` -> `0x21DDF0`)**:
   - Selecting the Sub slot (`equipSlot = 1`, bitmask `0x0002`) in the native Equipment menu checks only server Encumbrance (`0xFD4A0` -> `[player + 0x40EA0]`) and calls `0x21DDF0(0x0002, 2, 0x12, 0)` across Inventory and Wardrobes 1–8.
   - `0x21DF85` filters strictly by `item->Slots & 0x0002`. One-handed weapons with the Sub bit (`Slots = 3`, e.g., `Onion Sword`, `Wind Knife +1`) and Shields (`Slots = 2`) **already appear natively** in the Sub-slot menu and are colored equippable via `CanEquipItem` (`0x133450`).
2. **Shields Under Two-Handed Weapons (`0x133CFF`)**:
   - Inside `EquipMenu::TryEquipItem` (`0x133BD0`), the Dual Wield and `IsTwoHanded` (`0x15C040`) checks at `0x133D18..0x133DC9` execute **only** when `equipSlot == 1` (`SLOT_SUB`), item `Type == 4` (`ITEM_WEAPON`), and `Slots & 1`.
   - Shields (`Type == 5`) branch directly from `0x133D03` to `0x133E17` (`CanEquipItem` -> `CanEquipItemInSlot` -> `Send0x50`), so **WAR Spartan / Gladiator Polearm + Size-1 Buckler** works natively through the original FFXI Equipment menu and `/equip sub` without any custom popup; the server (`0030-polearm-buckler-equip.patch`) authoritatively keeps Size-1 Bucklers paired with Polearms and rejects larger shields.
3. **Single Dual Wield Gate (`0x133D18..0x133D56`)**:
   - Both the native Equipment menu (controller & keyboard) and `/equip sub` route through `EquipMenu::TryEquipItem` (`0x133BD0`), the sole caller of `Send0x50` (`0xE5480`).
   - At `0x133D21..0x133D4E`, `FFXiMain.dll` checks `main_job` (`base + 0x4867F0`) and `sub_job` (`base + 0x4867F2`) against vanilla Dual Wield jobs `{0x0D NIN, 0x06 THF, 0x13 DNC, 0x10 BLU}`.
   - Non-vanilla jobs fall through to `RVA 0x133D56` (`68 8b 00 00 00` — `push 0x8b`, zero relocations), which calls `0x12B2C0` to display the "cannot equip" message and aborts before `0x133D65`.

## Native Hook Design (`crystaljobs.dll` Hook #24)

- **Detour Site**: `PrologueDetour` at `RVA 0x133D56` (`first_opcode = 0x68`), verified by 24-byte signatures in `native/crystaljobs/layout.h` for:
  - `0x133D56` (`EquipMenu::TryEquipItem` Dual Wield rejection branch, 0 relocations)
  - `0xEB5D0` (`GetInventoryItem(container, slot)`, 4-byte absolute relocation at `+2`)
  - `0x15D210` (`GetItemResource(item_id)`, `__thiscall` with `this = *(base + 0x6229C0)`, 0 relocations)
- **Behavior**:
  - Vanilla Dual Wield jobs (NIN/THF/DNC/BLU main or sub) and non-weapon Sub items (Shields, Grips) never reach `0x133D56`.
  - When a non-vanilla job selects a Sub-slot weapon, `soul_allows_sub_weapon` checks:
    1. Active confirmed Soul via existing `active_action_soul(job, branch)` and live effective level (`*(base + 0x4867F1)`).
    2. Currently equipped Main-hand item via `[esp + 0x10]` (`main_slot_index`) and `[esp + 0x18]` (`main_container_id`) -> `GetInventoryItem` -> `GetItemResource` (`main_skill = u16(res + 0x10)`).
    3. Candidate Sub weapon (`esi` = `CItemResource*`, `sub_item_id = u16(esi)`, `sub_skill = u16(esi + 0x10)`).
    4. Reusable `WeaponRuleCatalog::allows_sub_weapon(...)` loaded via C-ABI `CrystalJobsReplaceWeaponRules`.
  - **Allow**: restores all registers/flags and jumps to `base + 0x133D65`, where `FFXiMain.dll` still enforces main-hand presence, `IsTwoHanded`, `CanEquipItem` (job/level/race), `CanEquipItemInSlot`, Wardrobe unlock bits, and sends native `0x050`.
  - **Deny**: restores all registers/flags, executes the stolen `push 0x8b`, and jumps to `base + 0x133D5B` (normal retail rejection).
- **Server Authority**: The server (`soulspire_weapon_config.lua` + `0072-soul-weapon-config.patch`) remains 100% authoritative for all equipment validation, Soul-switch reconciliation, zoning/relogging persistence, and combat mechanics.

## Data-Driven C-ABI (`native/crystaljobs/crystaljobs.h`)

- Capability bit: `CRYSTALJOBS_CAP_SOUL_SUB_WEAPON = 1u << 13`
- Structs: `CrystalJobsWeaponRule` (24 bytes), `CrystalJobsWeaponStatus` (36 bytes)
- Exports (`crystaljobs.def` & `build.cmd`):
  - `CrystalJobsReplaceWeaponRules(const CrystalJobsWeaponRule* entries, uint32_t count)`
  - `CrystalJobsClearWeaponRules(void)`
  - `CrystalJobsGetWeaponStatus(CrystalJobsWeaponStatus* status, uint32_t size)`
- Total hooks reported by `expected_hooks`: `24` (21 `CALL` patches + 3 `PrologueDetour` hooks).

## CrystalSocket Scope Cleanup

- Removed `addons/ashita4/crystalsocket/buckler.lua`, `##crystal_buckler` ImGui popup, `open_buckler`/`close_buckler`, native Sub-slot Enter capture (`SUB_NATIVE_SLOT`), and `/equip sub` command interception.
- CrystalSocket now handles **Soul Crystal selection, equipping, descriptions, and one-shot native rule synchronization** (`labels:sync_weapon_rules(WeaponConfig.native_rules())`) only.

## Build & Manual Controller Verification Checklist

1. **Windows CI Build**: Push `feat/soul-weapon-config` to `Infomatictek/soulspirexi-launcher` so `.github/workflows/build-launcher.yml` (`build-crystaljobs` on `windows-latest`) compiles `crystaljobs.dll` with MSVC `/std:c++17 /W4 /WX`, runs `selftest.exe` (including `weapon_rule_checks` + `sub_weapon_abi` + `expected_hooks == 24`), and produces the updated `crystaljobs-win-x86` binary.
2. **Deploy Updated DLL**: Replace `plugins/ashita4/crystaljobs.dll` with the CI-built 24-hook binary and regenerate `manifest.json`.
3. **Controller Verification (Windows Client)**:
   - On `Rin` (`BRD10/WAR5`, `Adventurer` Soul): open native Equipment menu with controller, navigate to Main -> equip `Onion Sword` or `Wind Knife +1`, navigate to Sub -> verify permitted Daggers, Swords, and Shields appear directly in the native FFXI Sub list with zero custom popup.
   - Select permitted offhand Dagger/Sword with controller Confirm -> verify immediate equip, visual dual-wield models, and both attack swings; verify disallowed weapon (e.g., Club) is rejected natively.
   - Verify `/equip sub "Onion Sword"` and `/equip sub none` work natively without CrystalSocket interception.
   - Verify Soul Crystal selection via CrystalSocket still works cleanly with controller/mouse; switch from `Adventurer` to `Musician` -> verify server auto-unequips offhand and native Sub-slot menu rejects offhand weapons again.
   - Verify `WAR10+` `Spartan` / `Gladiator` equips Polearm + Size-1 Buckler via native Equipment menu with controller and rejects Size-2/3 shields on server.
   - Verify vanilla `NIN` Dual Wield, `BRD9` (level sync below Lv10), zoning, and relogging preserve expected behavior.
