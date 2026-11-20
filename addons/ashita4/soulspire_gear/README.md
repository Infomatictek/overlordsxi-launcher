# soulspire_gear (SoulspireXI Gear Manager)

`soulspire_gear` (`/og` or `/ogear`) is a clean-room, ground-up Ashita v4 equipment set builder, packet-driven action swapper, and ImGui loadout manager built specifically for **SoulspireXI**.

## Key Features

- **100% Standalone Swapper**: Uses native `0x050` / `0x051` equip packets, `0x053` Lockstyle packets, and `0x01A` / `0x028` action packet interception for seamless Precast, Midcast, Weaponskill, Job Ability, Ranged, Idle, Engaged, and Resting swaps—no external `luashitacast` addon required.
- **SoulspireXI Soul Crystal Spec Integration**: Passively syncs your active SoulspireXI Soul Crystal (`0x1FF` `CRYS`, `[OXSPEC]|`, and `crystaljobs.dll` FFI) and dynamically adapts set weights, abilities, and weapon eligibility for:
  - **WAR**: `Commander` (Tactical Buffer/Tank), `Berserker` (Fury Burst DPS), `Gladiator` (Club & Shield Tank)
  - **MNK**: `Sensei` (Staff Evasion, Parry & Counter Tank)
  - **BLM**: `Necromancer` (Scythe Melee & Undead Pet Summoner)
  - **DNC**: `Bladewheel` (Ranged Chakram Dancer)
  - **SCH**: `Medic` (Light Arts & Eos Companion) and `Sage` (Dark Arts & Titania Companion), including `Orphic Egg` (`FAERIE_REFRESH`) scoring
  - **RUN**: `Inquisitor` (Parry/Aegis Tank), `Spellblade` (Elemental/Multi-Attack Hybrid DPS), `Lifebinder` (Sustain Ward Tank)
- **SoulspireXI Weaponskill Talent Sync**: Reads invested WS Talent nodes (`[OXTAL]|`) and combines them with the SoulspireXI 207-WS catalog to build tailored sets for every weaponskill your equipped weapons can use.
- **Cap-Aware Coordinate-Ascent Solver**: Automatically respects stat caps (`25%` Gear Haste, `-50%` PDT/MDT, `80%` Fast Cast, `50%` Cure Potency, `18%` Movement Speed), multi-slot encumbrance (`rslot` Cloaks/Tunics), Ring/Ear uniqueness, active Latent effects, Gear Set Bonuses, and item Augments.
- **Weapon Protection & Advisor**: Generated sets never overwrite your `Main`, `Sub`, `Range`, or `Ammo` slots behind your back. The **Weapon Advisor** tab ranks all weapons, shields, grips, ranged weapons, and ammo in your bags with one-click equipping.
- **Storage Bag Upgrade Scanner**: Scans `Mog Safe`, `Safe 2`, `Storage`, `Mog Locker`, `Mog Satchel`, `Mog Sack`, and `Mog Case` for items that would upgrade your active sets.

## Commands

| Command | Description |
| :--- | :--- |
| `/og` or `/ogear` | Toggle the SoulspireXI Gear Manager window |
| `/og build` | Rebuild all sets for your current job, level, and Crystal Spec |
| `/og dt [off\|all\|pdt\|mdt]` | Cycle or set Damage Taken override mode |
| `/og tp [default\|hybrid\|acc\|tank]` | Cycle or set Engaged melee TP mode |
| `/og idle [auto\|normal\|dt\|regen\|refresh]` | Cycle or set Idle standing mode |
| `/og nuke [power\|acc]` | Toggle Elemental magic mode between Power and Accuracy |
| `/og burst [on\|off]` | Toggle Magic Burst midcast overlay |
| `/og kite [on\|off]` | Toggle Movement Speed / Kite overlay |
| `/og th [on\|off]` | Toggle Treasure Hunter overlay |
| `/og spec [auto\|none\|<spec>]` | Follow your equipped Soul Crystal or preview a specific Spec profile |
| `/og wear <SetName>\|off` | Hold a specific set continuously until `/og wear off` |
| `/og equip <SetName>` | Equip a set once immediately |
| `/og dress` | Pause auto-swapping to manually equip gear, then `/og save <SetName>` |
| `/og save <SetName>` | Save currently worn equipment to `<SetName>` and resume swapping |
| `/og look <SetName>\|off` | Lock visual character appearance (Lockstyle) to `<SetName>` |
| `/og upgrades` | Scan non-equippable storage bags for upgrades |

## Rebuilding the Server Gear Database

When server items, mods, or custom SQL tables change, run:

```powershell
python scripts/build_gear_db.py
```
