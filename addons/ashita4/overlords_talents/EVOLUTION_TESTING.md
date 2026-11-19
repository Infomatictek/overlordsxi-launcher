# Weapon Skill Evolution client playtest

Use with server branch `feature/ws-evolution-playtest` in `Infomatictek/overlordsxi`.

The UI displays a **five-stage illustrated constellation** for Combo (#1) and Sanguine Blade (#47), while every other WS retains the existing tree canvas. The sigils are rendered graphically through Ashita's ImDrawList and do not require a new texture loader.

## Controls

- Open `/talents` and click **Sync**; select Combo or Sanguine Blade.
- Left-click a sigil to invest the stage choice; right-click to refund it. Each stage offers two exclusive directions.
- The Skillchain Routing area lets you cycle a stage's property, including **OFF**. You can leave the WS without any skillchain properties to avoid interrupting party chains.
- A later stage requires earlier decisions. The first stage establishes a meaningful identity.

**Testing limitation:** This is an initial vector-illustrated UI, not yet the final bespoke painted icon pack. The screenshot-quality art pass can follow the first feedback from live Ashita v4 rendering. Server and client changes must be tested together.

The launcher manifest includes a checksum entry for the updated `overlords_talents.lua`.
