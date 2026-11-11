# Asset audit

Audited 2026-11-11 against Godot 4.7.2 (Compatibility renderer). Maintained by the `asset-integrator` agent.

**Rules**

- Everything under `assets/` (except `assets/processed/`) is an original and is read-only. Never edit, move, or delete those files.
- Derived or new art goes in `assets/processed/`. Godot resources built from art (`.tres`) go in `resources/`.
- Texture filtering is set project-wide to Nearest, so no per-file import overrides are needed.

**Import result:** `godot --headless --import` processed all 91 files (78 PNG, 13 WAV) with exit code 0 and no errors or warnings.

**Scale finding (applies to the whole pack):** there are two pixel densities. Tiles and UI are true low-res pixel art on a 32 px grid. Player, props, hazards and effects are downsampled illustrations with much finer detail. They do not match pixel-for-pixel, but the pack's own preview shows them together at 1:1 and it reads fine for a prototype. Decision: use everything at 1:1 in a 1280×720 viewport and revisit art direction after the vertical slice.

## Player (`assets/player/`)

All are 128×128 RGBA with a transparent background. Feet sit on y=124 in every pose, so a shared bottom-centre pivot works. Side poses face right.

| File | What it is | Content box | Verdict |
|---|---|---|---|
| `front.png` | Neutral standing pose, facing camera | 62×98 | **Usable as is.** Use as the idle frame. |
| `idle.png` | Standing with "!" alert marks | 62×106 | **Usable with changes.** The alert marks make it wrong for a resting idle. Use as a one-shot "notice/interact" frame. |
| `side.png` | Standing, side view | 58×98 | **Usable as is.** Spare frame. |
| `back.png` | Standing, back view | 58×98 | **Usable as is.** Use when walking through the exit door. |
| `walk.png` | Mid-stride | 64×92 | **Usable as is.** Run cycle frame 1. |
| `run.png` | Sprint with dust puff | 90×106 | **Usable with changes.** Dust is baked in and the pose is wider. Run cycle frame 2; accept the pop for now. |
| `jump.png` | Arms-up jump with baked motion lines | 76×98 | **Usable as is.** Single air frame. |
| `push_scene.png` | Pushing a baked-in resistor block | 114×96 | **Not usable** for the slice. The pushed object is part of the sprite and we have no push mechanic. |
| `victory.png` | Arms-up cheer with sparkles | 70×98 | **Usable as is.** Level-complete frame. |
| `ohmie_poses_atlas_128.png` | 384×384 atlas, strict 3×3 grid of the nine poses | | **Usable as is**, but redundant. We use the individual files. |

These are key poses, not animation cycles. The slice gets a 2-frame run (walk, run) and single frames elsewhere.

## Environment (`assets/environment/`)

| File | What it is | Technical | Verdict |
|---|---|---|---|
| `tileset_32px.png` | 128×128 atlas, 4×4 grid of 32 px tiles, IDs 0–15 | RGBA, true pixel art | **Usable as is.** Source for the TileSet. |
| `tiles/*.png` (16 files) | The same tiles as individual 32×32 files | RGBA | **Usable as is**, redundant with the atlas. |
| `tileset_preview_4x.png` | 512×512 enlarged preview | | **Not usable** in game. Reference only. |
| `copper_works_background_1280x720.png` | Illustrated factory backdrop | 1280×720, opaque | **Usable with changes.** Very busy and bright. Dim it with a modulate at runtime so wires and platforms read clearly. Does not tile, so levels stay one screen wide. |
| `copper_works_background_original.png` | Same image at 1672×941 | Opaque | **Not usable** for now. Wrong size, redundant. |

Tile notes: ground tiles (0–3) and panels (12–14) fill the full 32×32 and take full-cell collision. Platform tiles (4–7) only occupy rows 7–20 and need a thin one-way collision shape there. Wire tiles (8–11) and the support beam (15) are decorative with no collision. There is no vertical wall or ceiling-edge tile; `ground_fill` and `reinforced_block` stand in.

## Resistors (`assets/interactive/resistors/`)

Seven icons, each 96×64 RGBA: 0.5, 1, 2, 3, 4, 6 and 10 Ω. Each has colour bands and a baked value label underneath.

Verdict: **Usable as is.** Limitation: only these seven values have art. The first ten levels use only these values. Any other value needs a generated icon (blank body plus a text label).

## Props (`assets/props/`)

All RGBA illustrations with transparent backgrounds.

| File | Size | Verdict |
|---|---|---|
| `exit_door_closed.png`, `exit_door_open.png` | 108×160 | **Usable as is.** Same canvas and content box, so they swap cleanly. |
| `series_console.png` | 128×104 | **Usable as is**, not needed for the slice. Reserved for a later mechanic. |
| `parallel_console.png` | 136×104 | Same as above. |
| `lever_switch.png` | 104×104 | **Usable with changes.** One state only. Needs a flipped or recoloured "on" frame. Milestone 3. |
| `pressure_button.png` | 112×76 | **Usable with changes.** One state only. Later. |
| `checkpoint.png` | 88×128 | **Usable as is.** Not needed in one-screen levels. |
| `battery_pickup.png` | 64×64 | **Usable as is.** Use as the source terminal marker on the circuit board. |
| `ohm_orb.png` | 72×72 | **Usable as is.** Possible optional collectible. Later. |
| `resistor_crate.png` | 120×120 | **Usable as is.** Possible pushable or dispenser. Later. |
| `lift_platform.png` | 160×112 | **Usable as is.** Moving platform. Later. |
| `insulated_bridge.png` | 160×100 | **Usable as is.** Later. |

## Hazards (`assets/hazards/`) and effects (`assets/effects/`)

Eight hazards (76–112 px, single frame each) and four 64×64 effects. All RGBA with clean transparency.

Verdict: **Usable as is** as static sprites, none needed for the slice. They have one frame each, so movement comes from code (bobbing, rotation, flashing). `spark_burst.png` and `victory_sparkle.png` can be used as particle textures in Milestone 2.

## UI (`assets/ui/`)

True pixel art, RGBA.

| File | Size | Verdict |
|---|---|---|
| `hud_blank.png` | 256×72 | **Usable as is.** Frame for the live readout, with text drawn by Labels. Works as a nine-patch. |
| `hud_target_1ohm.png` | 384×72 | **Usable with changes.** "1 Ω" and "? Ω" are baked into the image, so it cannot show a live value. Use `hud_blank.png` instead. |
| `circuit_panel.png` | 448×144 | **Not usable** for the slice. Baked title and exactly three baked slots. Our circuit lives in the world, not in a panel. |
| `resistor_slot_empty.png`, `resistor_slot_selected.png` | 72×72 | **Usable with changes.** Square, but a resistor icon is 96×64. Use as the basis for a 104×72 world socket in `assets/processed/`. |
| `button_*.png` (5 files) | 112×44 | **Usable as is.** Baked labels. Needed from Milestone 2 (menus, pause). |
| `heart_full.png`, `heart_empty.png` | 32×32 | **Usable as is.** Not needed until hazards exist. |
| `victory_banner.png` | 320×96 | **Usable as is.** Level-complete banner. |

## Audio (`assets/audio/`)

All 13 files are PCM WAV, mono, 22050 Hz, 16-bit. Godot imports them as `AudioStreamWAV`.

| File | Length | Verdict |
|---|---|---|
| `music_copper_works_loop_16s.wav` | 16.0 s | **Usable with changes.** Imported with looping off. Set `edit/loop_mode` to Forward in its `.import` file. Short loop, so play it quietly. |
| `sfx_jump`, `sfx_land`, `sfx_pickup`, `sfx_place_resistor`, `sfx_connect`, `sfx_invalid`, `sfx_door_open`, `sfx_win` | 0.10–0.58 s | **Usable as is.** All used in the slice. |
| `sfx_bounce`, `sfx_enemy_zap`, `sfx_hurt`, `sfx_switch` | 0.12–0.21 s | **Usable as is.** Later milestones. |

## Data, preview and source sheets

| File | Verdict |
|---|---|
| `data/circuit_puzzles.json` | **Not usable** directly. It describes finished circuits as trees, with no layout and no puzzle. The ideas are reused in the level curve. |
| `data/sample_level.json` | **Not usable** directly. Illustrative positions only, and no circuit topology. Its tile ID table is correct and is adopted. |
| `data/resistor_color_codes.json` | **Usable as is.** Reference if we generate resistor icons for new values. |
| `data/asset_manifest.json` | Reference only. Its dimensions match what was measured. |
| `preview/illustrative_level_scene.png` | Reference only. Target look for the slice. |
| `source_sheets/*.png` (3 files) | Not used in game. High-resolution sources for future art edits. Excluded from export later. |

## Missing for the vertical slice

| Gap | Decision |
|---|---|
| World socket that fits a 96×64 resistor, in empty and highlighted states | Placeholder made by `asset-integrator` in `assets/processed/`, based on the UI slot style. |
| Wires connecting sockets, terminals and junctions | Drawn in code with `Line2D` from level data, in the tileset's copper colour. Wire tiles stay decorative. |
| Circuit terminals (the two points resistance is measured between) | `battery_pickup.png` for the source, a small generated node dot for junctions. |
| "Carrying" indicator | The resistor icon shown above Ohmie's head. No new art. |
| Interact prompt ("E") | Text label. No new art. |
| UI font with an Ω glyph | Godot's default font, which includes Ω. A pixel font is a Milestone 2 task. |
| True run and idle animation cycles | Not filled. 2-frame run from existing poses. |
| TileSet resource with collision, SpriteFrames for the player | Built by `asset-integrator` in `resources/`. |
| Resistor icons for values other than the seven supplied | Not needed yet. Levels 1–10 are restricted to the seven values. |
