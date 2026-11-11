# Ohmie: Circuit Works — 2D Pixel Platformer Asset Pack (v1)

A coherent first-level **starter kit** for a resistor-combination 2D platformer.
The main challenge is to connect resistors in series/parallel until the circuit
has **exactly 1 Ω** equivalent resistance.

## What is included

- `player/`: nine trimmed 128×128 transparent character poses, plus a 3×3 atlas.
- `environment/`: 1280×720 Copper Works background; original background; 16
  deterministic 32×32 tiles, a tileset atlas, and an enlarged tileset preview.
- `props/`: 12 individual illustrated interaction sprites.
- `hazards/`: 8 individual enemies/obstacles; `effects/`: 4 effect sprites.
- `interactive/resistors/`: seven labeled, accurately color-coded resistor icons.
- `ui/`: HUD, puzzle panel, buttons, resistor slot, hearts, victory banner.
- `audio/`: 12 original synthesized WAV sound effects and an original simple
  16-second chiptune music loop.
- `data/`: sprite manifest, resistor color codes, four VALIDATED 1 Ω circuit
  puzzles, and a sample tile/object level layout.
- `preview/illustrative_level_scene.png`: a static composition showing the
  visual assets together, not a running game screenshot.
- `source_sheets/`: original full-resolution generated artwork for further art edits.

## Quick game-engine import

1. Import the PNG and WAV assets from this folder into Godot, Unity or another
   engine. Set texture **filter to Nearest/Point** to preserve pixel edges.
2. Use a **32×32** tile grid and the atlas `environment/tileset_32px.png`.
   Atlas order is left-to-right, top-to-bottom; tile IDs 0–15 match `data/sample_level.json`.
3. Use `player/*.png` as an initial pose-based character. Each is **128×128**;
   the atlas is 384×384 in a strict 3×3 grid, indexed in this order:
   front, side, back / idle, walk, run / jump, push_scene, victory.
4. Import `data/sample_level.json` for an illustrative example, or build your
   own tile map. World-space coordinates assume a 1280×720 viewport.
5. Build circuit interaction from `data/circuit_puzzles.json` and evaluate
   series resistance `R = sum(R_i)`; parallel resistance `1/R = sum(1/R_i)`.
   Do not round intermediate results; use exact rational arithmetic where possible.

## Important art/gameplay notes

- Character poses are **illustration-derived key poses**, *not* a verified
  temporal animation cycle. Add in-between frames and test pivots/hitboxes before
  shipping. The `push_scene` pose contains a drawn resistor block: if pushing an
  independent physics object, create an alternate arm-only push frame.
- The source artwork is deliberately larger and more detailed than small pixel
  sprites; the export is sampled with nearest-neighbor scaling. Inspect the
  sprites at actual game scale before finalizing your art direction.
- Source props are not inherently mechanically functional: you must code
  collisions, current-path validation, switches, doors, and interaction rules.
- The 32px tiles are hand-defined for stable engine geometry. Some end-cap tiles
  are decorative; place middle tiles between caps for longer platforms.
- Numeric resistor icons and color bands are exact 4-band nominal values with
  gold tolerance (±5%). For example, **2 Ω = red-black-gold-gold**.
- Audio is a small original synthetic prototype set; mix/master for production.

## Suggested controls

- A/D or arrows: move; Space: jump; E: interact or place resistor.
- Tab: open the circuit editor; 1/2: select series or parallel wiring.
- R: restart puzzle. Use the `ui` assets for buttons and HUD displays.

## Content and scope

This is a **playable-prototype asset starter pack**, not a complete shipped game's
animation library or level collection. All generated illustrations were made
for Ohmie; their use remains subject to the applicable image-generation terms.
