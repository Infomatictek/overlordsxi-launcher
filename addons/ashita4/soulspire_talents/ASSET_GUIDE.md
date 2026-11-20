# Weapon Mastery artwork handoff (Gemini)

The addon code is complete and uses optional **real PNG textures** via Ashita v4's Direct3D8 loader. Place generated assets in:

`addons/ashita4/soulspire_talents/assets/`

Missing assets are safe: the addon draws a readable dark-metal fallback. File names **must match** those below (lowercase ASCII, underscores) and be PNG with transparency where appropriate. Art should contain **no text**; the game renders live text over the assets.

## Global art (recommended first)

| Filename | Target dimensions | Purpose |
|---|---:|---|
| `background_main.png` | 1600 x 1000 | Dark fantasy master window backdrop, subdued detail where text sits |
| `header_ornament.png` | 1200 x 110 | Decorative top header, transparent |
| `panel_browser.png` | 350 x 1000 | Left arsenal list frame, dark center safe for text |
| `panel_inspector.png` | 400 x 1000 | Right details panel frame |
| `hero_frame.png` | 1000 x 220 | Main skill hero framing; central transparent/deep-dark text zone |
| `tier_panel.png` | 1000 x 300 | Ornate dark frame behind each chapter |
| `card_frame.png` | 600 x 220 | Reusable node choice border/face with generous clean text zone |
| `card_selected.png` | 600 x 220 | Semi-transparent gold/arcane selected-node overlay |
| `detail_art.png` | 500 x 240 | Framing behind selected node portrait |

## WS art

`hero_1.png` (1200x350): Combo, kinetic martial strikes, brass and ivory, clear left-to-right motion; dark readable right.
`hero_47.png` (1200x350): Sanguine Blade, single blood-red arcane sword cutting through shadow, black garnet/gothic steel; dark readable right.
`ws_1.png`, `ws_47.png` (256x256): high-detail square icon with central silhouette and no text.

For any WS id, `ws_<id>.png` supplies its icon and `hero_<id>.png` supplies a hero background. All other WS IDs are already supported automatically by the code.

## Per-node illustration hooks

Use `node_<server-node-key>.png` (256x256), e.g.:
- `node_e_co_open.png` / `node_e_co_flow.png`
- `node_e_co_break.png` / `node_e_co_storm.png`
- `node_e_sg_arcane.png` / `node_e_sg_blood.png`
- `node_e_sg_eclipse.png` / `node_e_sg_hunger.png`

These are optional and take priority over the WS icon on node choice cards and inspector portraits.

Stage decoration hooks: `stage_1.png` through `stage_5.png` at 1000x80, transparent, ornaments only.

## Gemini prompts

### Global UI art

> Create a production-quality dark-fantasy RPG user-interface asset, inspired by premium AAA action-RPG progression screens without copying any existing game's UI. The asset must be **[ASSET NAME]**, designed for a **[DIMENSIONS]** PNG. Materials: charcoal forged steel, antique bronze, polished obsidian, subtle cyan crystal inlays, restrained luminous gold highlights, elegant hand-tooled engraved ornamentation. Sophisticated depth, tasteful metallic edge lighting, intricate microdetail focused near borders, quiet near-black middle region suitable for UI text. **Absolutely no text, letters, numbers, logos, icons of real brands, interface labels, or watermarks.** Transparent background wherever appropriate. Orthographic straight-on UI asset, precise rectangular geometry; no perspective.

### WS-specific hero

> Create a single cinematic dark fantasy RPG weapon mastery hero banner, 1200x350, for **[COMBO / SANGUINE BLADE]**. Painterly high-end game key art, sophisticated lighting, dramatic focal action on left, right half stays deep, dark, and low contrast so that UI text can be overlaid. No text or UI labels, no watermarks. Export PNG.

### Node icon

> Create a premium 256x256 square dark-fantasy weapon mastery talent icon for **[TALENT NAME AND MECHANIC]**. One instantly recognizable visual symbol, expertly painted, strong silhouette and vibrant but restrained magical material contrast, readable when displayed at 70x70. No letters, numbers, logos, or watermarks. PNG, ideally transparent background.

## Important UI behavior

- The new interface serves every weaponskill, not only Combo and Sanguine Blade. Old non-evolution talent mechanics still use the existing server data.
- The left browser, central stage cards, and right inspector are all code-driven.
- Left-click a card to **inspect**. Invest and refund deliberately using the inspector buttons; right-click a selected card to refund directly.
- Skillchain selections remain independently configurable, including OFF on the evolution prototype. This is vital for avoiding unwanted party skillchains.
- New files placed directly into a local Ashita addon directory can be tested without changing `manifest.json`; if distributing to players via the launcher, every PNG must receive its own correct manifest entry (sourcePath, targetPath, size, SHA256). Existing manifest entries for Lua modules are maintained separately.
- Reload `soulspire_talents` after adding textures; missing assets are cached as unavailable until reload.

## Art technical guidelines

- PNG-32 preferred; alpha transparency for ornaments, card frames, icons, overlays
- No baked text anywhere
- Avoid fully opaque bright/complex art behind interactive text
- Avoid character likenesses or licensed game logos
- Keep margins safe (8-16 px for borders on original asset)
- The art loader stretches each image to its allotted panel. Avoid delicate 1px lines that may distort; use thickness and edge anchors.

The server talent protocol and GitHub server repository do **not** need to change for these images.
