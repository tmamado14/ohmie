# Asset audit

Audited 2026-11-11 against Godot 4.7.2 (Compatibility renderer). Maintained by the `asset-integrator` agent.

**Rules**

- Everything under `assets/` (except `assets/processed/`) and everything under `assets-new/` is an original and is read-only. Never edit, move, or delete those files. Only the `.import` sidecars Godot writes next to them may be edited.
- Derived or new art goes in `assets/processed/` (new-pack art in `assets/processed/v2/`). Godot resources built from art (`.tres`) go in `resources/` (new-pack resources in `resources/themes/`).
- Project-wide texture filtering is Nearest (`rendering/textures/canvas_textures/default_texture_filter=0` in `project.godot`), which suits the old pack. The new pack needs **Linear**: set `texture_filter = TEXTURE_FILTER_LINEAR` on the nodes that draw it (or switch the project default when the old pack is retired).

---

# New pack (`assets/`), in use from Milestone 1.1

"Ohmie: The Five Circuits (v3)": hand-inked 1940s rubber-hose cartoon style, watercolour texture, five themed worlds. Everything is drawn at **exactly 2x** the old pack (64 px tiles, 256 px player frames, 1920x1080 backgrounds, 192x128 resistors, 216x320 door).

**How it is used:** the game keeps its 1280x720 logical viewport, 32 px grid and all existing pixel coordinates. New art is drawn at **scale 0.5 with Linear filtering**, so it lands on the old art's footprint and shows at full detail on a 1080p window (`stretch/mode = canvas_items`). All pixel numbers below are in the image's own (2x) pixels unless marked "on screen".

**Import result:** `--headless --path . --import` processed the whole folder with exit code 0 and no `ERROR` or `WARNING` lines. All PNGs are RGBA except the five backgrounds, the painted originals and the overview preview (RGB, fully opaque). All WAVs are PCM mono, 22050 Hz, 16-bit.

**Measurement convention:** "opaque box" is the bounding box of pixels with alpha >= 16 (>= 128 where stated), given as x0-x1 / y0-y1 inclusive.

## Player (`assets/player/`)

All 256x256 RGBA, transparent background, side poses face right. These are key poses, not cycles (same as the old pack).

| File | What it is | Opaque box (a >= 128) | Lowest row | Verdict |
|---|---|---|---|---|
| `front.png` | Neutral standing pose | x 75-178, y 59-249 | 249 (shoes) | **Usable as is.** `idle`. |
| `walk.png` | Mid-stride | x 65-189, y 83-249 | 249 | **Usable with changes.** A stray 21 px sliver of the atlas neighbour sits on row 73 above the head; cropped out in the SpriteFrames. `run` frame 0. |
| `run.png` | Sprint with dust puffs and speed lines | x 29-226, y 61-225 | 225 (dust; shoes end at 222) | **Usable with changes.** Both feet are off the ground (24 px above the shared baseline) and fragments of the atlas row below sit on rows 245-249. Cropped and shifted down 24 px in the SpriteFrames. `run` frame 1. |
| `jump.png` | Arms-up leap, motion lines under the feet | x 38-216, y 73-246 | 246 (motion lines; shoes end at 223) | **Usable as is.** Airborne pose, not shifted. `jump`. |
| `victory.png` | Arms-up cheer with stars | x 44-210, y 66-249 | 249 | **Usable as is.** `victory`. |
| `back.png` | Back view | x 71-184, y 59-249 | 249 | **Usable as is.** `back`. |
| `idle.png` | Startled, shake marks by the feet | x 68-187, y 64-229 (+ strays) | 229 | **Usable with changes.** Strays on row 53 and rows 245-249; feet 20 px above the baseline. Cropped and shifted down 20 px. `notice`. |
| `side.png` | Side view | x 92-162, y 58-249 | 249 | **Usable as is.** Spare. |
| `push_scene.png` | Pushing a baked-in crate | x 9-245, y 73-249 | 249 | **Not usable.** Same reason as the old pack: the crate is part of the sprite. |
| `ohmie_poses_atlas_256.png` | 768x768, 3x3 grid of the nine poses | | | **Not usable.** Redundant, and its cells bleed into each other (the source of the strays above). |

## Environment and tiles

| File | What it is | Technical | Verdict |
|---|---|---|---|
| `environment/tileset_64px.png` | 256x256, 4x4 grid of 64 px tiles, IDs 0-15, same layout and names as the old set | RGBA | **Usable as is.** Source of the `old_workshop` TileSet. |
| `worlds/level_0N_<name>/tileset_64px.png` (4 files) | Same tiles per world | RGBA, 256x256 | **Usable as is.** Sources of the other four TileSets. They are **not** distinct themes: identical geometry and alpha, only a slight tint (max per-channel difference 21-30 levels from `old_workshop`; mean RGB 132/94/67 workshop, 142/100/72 foundry, 124/102/82 switchyard, 131/98/82 clocktower, 135/92/71 transmitter). |
| `*/tiles/*.png` (16 per set) | Individual 64x64 tiles | | Redundant: pixel-identical to the atlas cells. |
| `environment/tileset_preview_3x.png` | 768x768 enlarged preview | | Reference only. |
| `environment/old_workshop_background_1920x1080.png` | World 1 backdrop | 1920x1080, RGB, opaque | **Usable with changes** (dim, see Backgrounds). |
| `environment/old_workshop_painted_background_original.png` | Same scene at 1672x941 | RGB | **Not usable.** Wrong size, redundant. |

Tile notes (all five sets): ground 0-3, panels 12-13 and reinforced block 14 are fully opaque 64x64. Platforms 4-7 occupy **rows 18-40** full width (alpha > 0, identical in all sets). Wires 8-11 occupy rows/columns 26-38; support beam 15 columns 21-43. The tiles are chunky "pixel art" with hard pixels and speckle, drawn at 64 px: a different look from the inked sprites. At 0.5 scale with Linear filtering they soften and sit acceptably with the sprites, but they are the least on-style part of the pack.

## Worlds (`assets/worlds/`)

Order and data from `world_progression.json` and each `level_config.json`:

| Level | Theme id (ours) | Folder | Background | Music (by file name; no JSON names a track) |
|---|---|---|---|---|
| 1 | `old_workshop` | `worlds/level_01_old_workshop/` (JSON only) | `environment/old_workshop_background_1920x1080.png` | `audio/music_old_workshop_swing_16s.wav` |
| 2 | `copper_foundry` | `worlds/level_02_copper_foundry/` | its `background_1920x1080.png` | `audio/music_level_02_copper_foundry_16s.wav` |
| 3 | `substation_switchyard` | `worlds/level_03_substation_switchyard/` | its `background_1920x1080.png` | `audio/music_level_03_substation_switchyard_16s.wav` |
| 4 | `signal_clocktower` | `worlds/level_04_signal_clocktower/` | its `background_1920x1080.png` | `audio/music_level_04_signal_clocktower_16s.wav` |
| 5 | `high_voltage_transmitter` | `worlds/level_05_high_voltage_transmitter/` | its `background_1920x1080.png` | `audio/music_level_05_high_voltage_transmitter_16s.wav` |

Per world (levels 2-5):

| File | Verdict |
|---|---|
| `background_1920x1080.png` | **Usable with changes**: dim per the table below. |
| `tileset_64px.png`, `tiles/` | See Environment. |
| `assets/*.png` (12 per world, 170-340 px, single frame each) | **Usable as is** as static sprites (hazards, enemies, pickups, switches, lifts, a world exit door/gate). Not needed until mechanics exist. Each world's own exit door/gate has **one state only** (no open frame). Level 5 also has `shorty_boss_idle.png` and `shorty_projectile.png`. |
| `source_assets_sheet.png`, `source_background.png` | **Not usable** in game. Sources; the sheets have red/yellow keying halos that the cut-out PNGs do not. |
| `level_config.json`, `sample_level.json` | Reference only. Illustrative geometry and a validated target circuit per world (2||2, 0.5+0.5, 3||3||3, 2||3||6, ((2||2)+(2||2))||2). |

### Backgrounds

All five are 1920x1080, RGB, fully opaque, and do not tile. Measured on the lower two thirds (y 360-1079), where wires and sockets are drawn; luminance 0-255, "edge" = mean edge-filter response (busyness).

| Theme | Lower 2/3 mean L (p10-p90) | Lower 2/3 edge | Centre (x 480-1439) mean L / edge | Character | Recommended `modulate` |
|---|---|---|---|---|---|
| `old_workshop` | 153 (109-185) | 15.6 | 175 / 10.0 | Calm plaster wall, furniture at the sides; brightest | `Color(0.82, 0.82, 0.82)` |
| `copper_foundry` | 139 (84-182) | 21.7 | 162 / 16.1 | Machines both sides, plain wall centre | `Color(0.80, 0.80, 0.80)` |
| `substation_switchyard` | 129 (87-169) | 24.8 | 135 / 20.5 | Outdoor, rain, fence and hills behind the centre; busiest centre | `Color(0.85, 0.85, 0.85)` |
| `signal_clocktower` | 125 (75-170) | 20.7 | 146 / 13.5 | Plain wall centre, consoles at sides | `Color(0.85, 0.85, 0.85)` |
| `high_voltage_transmitter` | 121 (64-169) | 22.4 | 137 / 19.3 | Darkest top, plain wall lower centre | `Color(0.85, 0.85, 0.85)` |

None is dark; all are warm mid-tones. Dimming is only to make the brass sockets and cream resistors stand forward. Checked by compositing the v2 sockets, resistors and wires over each background at these values.

Draw a background as a `Sprite2D`/`TextureRect` at scale 0.5 (1920x1080 -> 1280x720) with Linear filtering.

### Wire colours (drawn in code)

Chosen against all five backgrounds; each wire is an outline line with a narrower core line on top. Suggested widths on screen: outline 7 px, core 4 px.

| State | Core | Outline |
|---|---|---|
| Normal | `#AA532C` (copper, same as the socket lead stubs) | `#24180F` (ink brown) |
| Closed circuit | `#F7BE5A` (bright brass) | `#24180F` |
| Match (target reached) | `#5CB29C` (teal accent) | `#182822` |

## Resistors (`assets/interactive/resistors/`)

Seven icons, each 192x128 RGBA: `resistor_0p5ohm`, `resistor_1ohm`, `resistor_2ohm`, `resistor_3ohm`, `resistor_4ohm`, `resistor_6ohm`, `resistor_10ohm` (0.5, 1, 2, 3, 4, 6, 10 ohm, the same values as the old pack). Every icon has the same geometry:

- Opaque box x 7-185, y 19-124.
- Lead wires: rows 50-63 on both sides (centre y = 57.0, i.e. 28.5 on screen), from x 7 and to x 185.
- Body: x 24-168, rows 19-99. Value label plaque ("2 Ω"): x 57-135, rows 100-124.
- The leads are **not** at mid-height (64). The old icons had leads centred at y 30 of 64; the new ones sit 1.5 px higher on screen.

Verdict: **Usable as is.** Only these seven values exist.

## Props (`assets/props/`)

| File | Size | Verdict |
|---|---|---|
| `exit_door_closed.png` | 216x320 | **Usable as is.** See measurements below. |
| `exit_door_open.png` | 216x320 | **Not usable as is**: does not line up with the closed door. Use `assets/processed/exit_door_open_aligned.png`. |
| `battery_pickup.png` | 128x128 | Usable as is. Decorative source marker. |
| `series_console.png`, `parallel_console.png` | 256x208, 272x208 | Usable as is, later mechanics. |
| `lever_switch.png`, `pressure_button.png` | 208x208, 224x152 | Usable with changes (one state each). Later. |
| `checkpoint.png`, `ohm_orb.png`, `resistor_crate.png`, `lift_platform.png`, `insulated_bridge.png` | 144-320 px | Usable as is. Later. |

**Exit door measurements**

| | Opaque box (a >= 128) | Floor contact (lowest plinth row) | Threshold (door bottom, x 100-115) |
|---|---|---|---|
| `exit_door_closed.png` | x 6-209, y 60-258 | left plinth 257, right plinth 258 | 250 |
| `exit_door_open.png` | x 6-209, y 67-251 | left 248, right 251 | 239 |
| `processed/exit_door_open_aligned.png` | x 6-209, y 59-260 | left 257, right 258 (open leaves reach 260) | 250 |

The two originals do **not** share a box: the open door is the same drawing at 0.917x scale, about 11 px further right and 7 px higher, with its right insulator cut by the canvas edge and its left base plinth broken (a piece sits at x 6-11, y 229-249). Registering it onto the closed door gives scale 1.09 and offset (-21, -14), with 95% overlap of the arch. The aligned image is built from that (see Processed).

Placement: with `centered = false`, `scale = 0.5`, use `offset = Vector2(-108, -259)` (texture px) so the floor contact (bottom edge of row 258) is at the node origin and the door is centred on it. On screen the door is 108x160, the same footprint as the old door, but the floor line is 129.5 px below the top instead of 140.

## Hazards (`hazards/`), effects (`effects/`), platforms (`platforms/`), boss (`boss/`)

- Hazards: 8 sprites, 152-224 px, single frame. Effects: 4 sprites, 128x128. **Usable as is** as static sprites; none needed yet.
- Platforms: 12 decorative pieces (wood platforms, shelves, ladder, bridge, pennant), 128-320 px. **Usable with changes**: the README warns they do not tile; collision stays on the 64 px tiles.
- Boss: six 320x320 poses of "Shorty the Short-Circuit Baron" (idle, attack, stomp, taunt, hurt, defeated), bottom row 313, plus a 960x640 atlas and the source sheet. **Usable as is** for a later boss; not in scope now.

## UI (`assets/ui/`)

Hand-inked, soft edges.

| File | Size | Verdict |
|---|---|---|
| `decor/blank_resistor_slot.png` (identical to `resistor_slot_empty.png`) | 160x160 | **Usable with changes.** Square; the source for the 208x144 v2 sockets. |
| `resistor_slot_selected.png` | 160x160 | **Not used.** Its only change is a flat gold rim in place of the ink outline: too weak as a highlight. The v2 highlight is derived instead. |
| `decor/blank_hud_plaque.png` (identical to `hud_blank.png`) | 600x220 | **Usable as is.** HUD frame. |
| `hud_target_1ohm.png` | 600x220 | Not usable: baked text. |
| `decor/blank_victory_ribbon.png` | 600x195 | **Usable as is.** Level-complete banner. (`victory_banner.png` has baked text.) |
| `decor/blank_goal_sign.png` | 360x180 | **Usable with changes.** Its left edge is a straight cut (looks cropped) and there are a few stray marks right of the board (x 300-337). |
| `decor/blank_puzzle_panel.png` | 640x400 | Usable as is (`circuit_panel.png` has baked text). |
| `decor/blank_teal_button.png` | 240x95 | Usable as is: a text-free button. `button_*.png` have baked labels. |
| `decor/heart_*`, `heart_*` (identical pairs), `energy_bolt`, `inventory_pouch`, `pause_icon`, `restart_icon` | 90-130 px | Usable as is. Later. |

**Text areas** (where Labels can go; source px, halve for screen). "Region" is the parchment or wood area found by colour; "safe rect" is inset from its torn edges.

| File | Region | Safe text rect (x, y, w, h) | On screen at 0.5 |
|---|---|---|---|
| `blank_hud_plaque.png` | x 166-436, y 99-197 | (184, 112, 236, 72) | (92, 56, 118, 36) |
| `blank_victory_ribbon.png` | x 115-478, y 23-147 (centre band) | (140, 44, 312, 70) | (70, 22, 156, 35) |
| `blank_goal_sign.png` | x 22-298, y 50-167 | (48, 74, 228, 76) | (24, 37, 114, 38) |
| `blank_puzzle_panel.png` | x 85-552, y 48-364 | (159, 83, 355, 240) | (79.5, 41.5, 177.5, 120) |
| `blank_teal_button.png` | x 30-210, y 13-79 | (51, 22, 139, 45) | (25.5, 11, 69.5, 22.5) |

## Audio (`assets/audio/`)

| File | Length | Verdict |
|---|---|---|
| `music_old_workshop_swing_16s.wav` and `music_level_0N_<world>_16s.wav` (4) | 16.0 s each | **Done.** `.import` sidecars set to `edit/loop_mode=2` (Forward), `loop_begin=0`, `loop_end=-1`. Loads as `AudioStreamWAV`, `LOOP_FORWARD` over all 352800 frames. One track per world (table above). |
| `music_copper_works_loop_16s.wav` | 16.0 s | Byte-identical to the old pack's track. Loop set the same way. Spare. |
| 12 `sfx_*.wav` | 0.10-0.58 s | Byte-identical to the old pack. Usable as is. |

## Data, preview and source sheets

| File | Verdict |
|---|---|
| `world_progression.json`, `worlds/*/level_config.json` | Reference: world order, names, ECE topic, target, background path. |
| `data/*.json` | Same roles as in the old pack. `asset_manifest.json` dimensions match the files. |
| `preview/*.png` | Reference only (illustrative scenes, not gameplay). |
| `source_sheets/*.png` | Not used in game. Several have red/yellow keying halos; the cut-out PNGs do not. |

## Missing from the new pack

- Open state for the per-world exit doors and gates (levels 2-5 have one state each). The shared exit door has both states, but they need the aligned derivative.
- World-distinct tilesets: the five sets differ only by a slight tint.
- Animation cycles: keyframes only (2-frame run, single frames elsewhere), same as before.
- Socket, highlight, junction and terminal art for the circuit: generated in `assets/processed/`.
- Resistor icons beyond 0.5, 1, 2, 3, 4, 6, 10 ohm. Covered by the generated `part_resistor_blank.png` with the value drawn as text.
- Circuit parts other than resistors (carried battery, meters, lamps, polarity marks): generated in `assets/processed/`.
- A font with the pack's look (and an Ω glyph).
- Wall and ceiling-edge tiles (same gap as before).

## Processed and generated (new pack)

Rebuilt by scripts in `tools/`. Do not hand-edit the outputs; change the script and re-run it, then run `--headless --path . --import`.

| Command | Produces |
|---|---|
| `--headless --path . --script res://tools/build_tilesets.gd` | `resources/themes/<theme>/tileset.tres` (5) |
| `--headless --path . --script res://tools/build_player_frames.gd` | `resources/themes/player_frames.tres` |
| `--headless --path . --script res://tools/generate_art.gd` | the seven socket/door PNGs in `assets/processed/` |
| `--headless --path . --script res://tools/generate_parts_art.gd` | the ten part, meter, lamp and polarity PNGs in `assets/processed/` (see "Parts, meters and lamps") |
| `--headless --path . --script res://tools/check_resources.gd` | nothing; verifies all of the above plus the six music loops (557 checks, exit 0 = pass) |

None of these touch the old-pack resources; `tools/build_tileset.gd`, `build_player_frames.gd`, `generate_placeholders.gd` and `check_resources.gd` are unchanged.

### TileSets: `res://resources/themes/<theme>/tileset.tres`

Themes: `old_workshop`, `copper_foundry`, `substation_switchyard`, `signal_clocktower`, `high_voltage_transmitter`.

- One `TileSetAtlasSource`, **source id 0**, `tile_size` and `texture_region_size` 64x64, 16 tiles, alternative 0 only, `use_texture_padding = true` (stops Linear filtering bleeding neighbouring tiles in).
- **Same IDs as the old set: tile ID n is at atlas coords `Vector2i(n % 4, n / 4)`.** Level files and `set_cell` calls do not change.
- Physics layer 0: `collision_layer = 1`, `collision_mask = 0`. Full 64x64 square on IDs 0, 1, 2, 3, 12, 13, 14.
- Physics layer 1: `collision_layer = 2`, `collision_mask = 0`. One `one_way = true` rectangle on IDs 4, 5, 6, 7 covering rows 18-40 full width (local points y -14 to +9).
- No collision: IDs 8-11, 15.
- Use on a `TileMapLayer` with `scale = Vector2(0.5, 0.5)` and `texture_filter = TEXTURE_FILTER_LINEAR`. A 64 px tile then covers one 32 px cell, and cell (cx, cy) is still at pixel (32 cx, 32 cy). The tile map's own coordinates are in 64 px units, so convert cells with `map_to_local` / `local_to_map` on the layer (or multiply by 32 in parent space) rather than assuming 32 px tiles.

**Platform surface finding:** the platform art's top row is 18 of 64, so at scale 0.5 the standing surface is **9.0 px** below the top of the 32 px cell. Game logic assumes 7 px (old art, rows 7-20). **The new surface is 2 px lower.** The underside is at 20.5 px (old 21). The collision follows the art, so anything that hard-codes the 7 px offset (spawn heights, pickup rest positions, reach measurements) is 2 px off.

### Player animations: `res://resources/themes/player_frames.tres`

`SpriteFrames` with the same animations as the old resource. No `default` animation.

| Animation | Frames | FPS | Loop |
|---|---|---|---|
| `idle` | front.png | 1 | yes |
| `run` | walk.png, run.png | 8 | yes |
| `jump` | jump.png | 1 | no |
| `victory` | victory.png | 1 | no |
| `back` | back.png | 1 | no |
| `notice` | idle.png | 1 | no |

Every frame is 256x256. `walk`, `run` and `idle` frames are `AtlasTexture`s over the original PNGs (`filter_clip = true`). The region crops the stray fragments, and the margin moves `run.png` down 24 px and `idle.png` down 20 px. Every grounded frame's lowest opaque pixel (alpha >= 0.5) is therefore on **row 249**. `jump` is airborne and not shifted: its shoes end at row 223 (13 px above the origin on screen) and its motion lines reach row 246.

**`AnimatedSprite2D` settings:** `scale = Vector2(0.5, 0.5)`, `centered = true`, `offset = Vector2(0, -122)`, `position = Vector2(0, 0)`, `texture_filter = TEXTURE_FILTER_LINEAR`. This puts the bottom edge of row 249 on the node origin. Equivalently, keep `offset = (0, 0)` and set `position = Vector2(0, -61)`. Side poses face right; use `flip_h` for left.

On screen at 0.5 (origin = feet, x from the frame centre):

| Frame | x extent | Top above origin |
|---|---|---|
| idle (front) | -26.5 to +25.5 | 95.5 (antenna tips; head top 80.5) |
| run 0 (walk) | -31.5 to +31.0 | 83.5 |
| run 1 (run) | -49.5 to +49.5 (dust and speed lines) | 82.5 |
| jump | -45.0 to +44.5 | 88.5 |
| victory | -42.0 to +41.5 | 92.0 |
| back | -28.5 to +28.5 | 95.5 |
| notice (idle.png) | -30.0 to +30.0 | 82.5 |

**Collider fit (36x88 at (0, -44)):** the torso is about 29 px wide and the head top is 80.5 px up, so the body fits. Antenna tips poke 7.5 px above the collider (the old art poked 10 px). Arms and shoes reach wider than 36 px in every pose, as they did with the old art.

### Processed art (`assets/processed/`, from `tools/generate_art.gd`)

Authored at 2x for scale 0.5 with Linear filtering; anti-aliased edges. Palette sampled from the pack: ink `#24180F`, brass `#C79042` / light `#FCCF77` / dark `#8A5A24`, copper `#AA532C` / light `#EFA26B` / dark `#6E3418`, porcelain `#EED6B2`, oxblood `#963E30`, glow `#FFDE78`, iron `#5C645E`, walnut `#5C3822`.

| Resource path | Size (on screen) | What it is |
|---|---|---|
| `res://assets/processed/socket_empty.png` | 208x144 (104x72) | `blank_resistor_slot.png` reshaped by a notch-preserving nine-slice: the 40 px corners (screws) and the notch band (source rows 66-95) are copied 1:1, and only the plain edge runs and parchment are resampled. The parchment window is toned down into a shaded recess so a cream resistor reads against it. Copper lead stubs on both sides, open at the outer edge. |
| `res://assets/processed/socket_highlight.png` | 208x144 | Same frame with a pale-gold glow filling the 7-8 px margin, brighter brass and a lit window with light pooling at the rim. |
| `res://assets/processed/fixed_backing.png` | 208x144 | Same shape in gunmetal iron with a dark walnut plank window. Rivets replace the screws and three more sit on the top and bottom bars; silver solder blobs sit on the notches. Means "soldered in, cannot be removed". |
| `res://assets/processed/pickup_highlight.png` | 208x144 | Inked brass hoop with a soft glow, transparent centre. Draw it with the same centre as a loose resistor (resistor at hoop position + (8, 8) in 2x px). Verified not to overlap any of the seven icons. |
| `res://assets/processed/node_dot.png` | 32x32 (16x16) | Copper junction ball with ink outline and a brass solder ring. Centre it on the junction. |
| `res://assets/processed/terminal.png` | 64x64 (32x32) | Porcelain knob with an oxblood glaze ring and a brass binding post (nut, cap, dark hole), in the style of the pack's insulators. Centre it on the terminal point. |
| `res://assets/processed/exit_door_open_aligned.png` | 216x320 (108x160) | Open door on the closed door's footprint, built by the generator: the closed door is the base (complete insulators, pipes, plinths); the open door is scaled 1.09 and moved (-21, -14); the open door's arch, doorway and hinges are drawn between x 44-179, and its two swung leaves (found by flood fill) are drawn outside that band. Swap with `exit_door_closed.png` using the same node settings. |

**Socket geometry** (2x px; halve for screen):

- Outer ink outline x 7-200, y 8-135. The margin outside it is transparent on `socket_empty` and `fixed_backing` and holds the glow on `socket_highlight`.
- Inner window (parchment / walnut) x 20-187, y 20-122.
- **Notch centre y = 72 (36 on screen), mid-height.** The notch art spans rows 60-84 (centre 72.5). The copper stubs cover rows 65-78 (continuous 65-79, centre 72.0), from x 0 to 26 on the left and 182 to 208 on the right. A wire ending at the socket's left or right edge at mid-height runs straight into a stub.
- **Resistor placement:** draw the 192x128 icon with its top-left at socket top-left + **(8, 15)** in 2x px, i.e. **(4, 7.5) on screen**: icon centre 3.5 px below the socket centre. Its leads (centre y 57) then land on the stubs (y 72). The body (x 32-176, y 34-114) is inside the window, so the frame never covers it. The value label (y 115-139) overlaps the bottom brass bar and is drawn over it, which looks like a tag. If the icon is instead centred on the socket, as the old code does with (4, 4) on screen, the leads sit 3.5 px above the stubs and only partly overlap them.

### Parts, meters and lamps (`assets/processed/`, from `tools/generate_parts_art.gd`)

Same rules as the other processed art: authored at 2x, draw at **scale 0.5 with Linear filtering**, anti-aliased ink edges, same palette plus three accents (teal `#407A70`, oxblood `#963E30`, mustard `#CDA537`). Import settings are Godot's defaults, identical to `socket_empty.png`. Checked by compositing every image over the dimmed Old Workshop background at on-screen size next to `resistor_2ohm.png` and `socket_empty.png`, with sample text drawn in the text rects.

Two kinds of geometry:

- **Carried / plugged parts** (192x128): the resistor icons' geometry. Leads on rows 50-63 (centre **y = 57**), from x 7 and to x 185, ink rows 50-52 and 61-63 with a `#AAA29A` core. Seat them in a socket exactly like a resistor: top-left at socket top-left + **(8, 15)** source px, (4, 7.5) on screen. Verified: leads land on the socket stubs (rows 65-78), the body sits inside the window, the plaque hangs over the bottom bar like a tag. `pickup_highlight.png` drawn at part position − (8, 8) does not overlap either part (checked by `check_resources.gd`).
- **Board fixtures** (208x144, the `socket_empty.png` footprint): socket-identical copper stubs on rows 65-78 (centre **y = 72**), x 0-26 and 182-208, open at the canvas edge, so a wire ending at the fixture's left or right edge at mid-height runs into a stub. Place them like a socket.

| Resource path | Size (on screen) | What it is | Text rect, source px (x, y, w, h) | On screen at 0.5 | Text colour / max font on screen | Lead or stub centre y | Opaque box (a >= 16) |
|---|---|---|---|---|---|---|---|
| `res://assets/processed/part_battery.png` | 192x128 (96x64) | Horizontal dry cell. **Positive end on the LEFT**: brass nub (visible x 12-29, rows 40-73) and a cream `+`; flat copper cap and `−` on the right. Copper end caps, muted teal wrapper, ink and gold bands (as on `battery_pickup.png`). **Body x 30-167, rows 19-96** (with the nub: x 12-167). Blank value plaque. | (61, 98, 72, 23); plaque interior x 59-133, y 97-122 | (30.5, 49, 36, 11.5) | `#33241D` (the icons' ink) / **11 px** (12 at most). The icons' baked text is 14 source px tall. | 57 (rows 50-63, x 7-185) | x 7-185, y 19-124 |
| `res://assets/processed/part_resistor_blank.png` | 192x128 (96x64) | `resistor_2ohm.png` with bands 1-3 turned neutral taupe `#96846E` (gold tolerance band kept) and the plaque text removed. For values with no dedicated icon. Body x 24-168, rows 19-96, same as the icons. | (61, 98, 72, 23) | (30.5, 49, 36, 11.5) | `#33241D` / **11 px** (12 at most) | 57 | x 7-185, y 19-124 |
| `res://assets/processed/meter_ammeter.png` | 208x144 (104x72) | Panel meter: walnut case, brass bezel, parchment face. Top left: letter plate (x 31-92, y 21-68) with a big cream `A` on **oxblood** enamel. Top right: arc scale with an oxblood needle and zone. Bottom: wide recessed cream display window. Brass binding posts where the stubs enter. | (36, 78, 136, 40); window interior x 33-174, y 75-120 (142x46; the top 6 rows carry a soft shadow) | (18, 39, 68, 20) | `#24180F` (ink) / **18 px** | 72 (rows 65-78) | x 0-207, y 5-138 |
| `res://assets/processed/meter_voltmeter.png` | 208x144 | Same, `V` on **teal** enamel, teal needle and zone, needle at a different angle. | (36, 78, 136, 40) | (18, 39, 68, 20) | `#24180F` / **18 px** | 72 | x 0-207, y 5-138 |
| `res://assets/processed/meter_ohmmeter.png` | 208x144 | Same, `Ω` on **mustard** enamel, mustard needle and zone, needle near vertical. | (36, 78, 136, 40) | (18, 39, 68, 20) | `#24180F` / **18 px** | 72 | x 0-207, y 5-138 |
| `res://assets/processed/lamp_off.png` | 208x144 | Grey unlit glass bulb with a dark filament on a brass screw base and flange, walnut plinth (x 52-155, y 116-138); copper wires curve from brass posts at the stub ends (30, 72) and (178, 72) down into the flange, as on the HUD plaque's bulb. | none | | | 72 | x 0-207, y 18-138 |
| `res://assets/processed/lamp_on.png` | 208x144 | Same, warm yellow glowing glass, white-hot filament, soft halo (fades out 15 px beyond the glass) and four inked brass shine wedges like `battery_pickup.png`'s. | none | | | 72 | x 0-207, y 6-138 |
| `res://assets/processed/lamp_blown.png` | 208x144 | Same, smoky dark scorched glass, ink cracks, snapped drooping filament, small grey smoke puff rising from the top right. | none | | | 72 | x 0-207, y 3-138 |
| `res://assets/processed/polarity_plus.png` | 32x32 (16x16) | Brass disc, ink outline, ink `+`. | none | | | | x 2-29, y 2-29 |
| `res://assets/processed/polarity_minus.png` | 32x32 (16x16) | Brass disc, ink outline, ink `−`. | none | | | | x 2-29, y 2-29 |

Notes:

- **Lamps swap cleanly**: the stubs, posts, wires, base and the bulb silhouette (glass circle centre (104, 47), radius 29, neck down into the screw base) are drawn by the same code in all three; only the glass fill, filament, halo, shine wedges, cracks and smoke differ from `lamp_off` (within x 55-152, y 3-93 for `lamp_on`; x 78-158, y 3-93 for `lamp_blown`). Nothing below row 93 changes, so the base never shifts.
- **Polarity badges**: centre them on the slot's corner screw on the matching side, source (25, 25) for the left and (183, 25) for the right, i.e. (12.5, 12.5) and (91.5, 12.5) on screen from the socket's top-left. The badge then sits over the screw without touching the window or the part.
- The meters differ by enamel colour, needle colour and needle angle as well as by letter, so they are distinguishable even where the letter is hard to read.
- Text in the battery plaque goes where the resistor icons have their baked value; the battery's plaque is pixel-copied from the blank resistor, so both blank plaques are identical.

---

# Old pack (`assets/`): superseded, files retained

Everything below describes the original pack the vertical slice was built on. The files and resources stay in place (the game still runs on them until the switch to the new pack). Do not delete them.

## Player (`assets/player/`) (superseded, files retained)

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

## Environment (`assets/environment/`) (superseded, files retained)

**Import result (old pack):** `godot --headless --import` processed all 91 files (78 PNG, 13 WAV) with exit code 0 and no errors or warnings.

**Scale finding (old pack):** there are two pixel densities. Tiles and UI are true low-res pixel art on a 32 px grid. Player, props, hazards and effects are downsampled illustrations with much finer detail. Decision at the time: use everything at 1:1 in a 1280×720 viewport.

| File | What it is | Technical | Verdict |
|---|---|---|---|
| `tileset_32px.png` | 128×128 atlas, 4×4 grid of 32 px tiles, IDs 0–15 | RGBA, true pixel art | **Usable as is.** Source for the TileSet. |
| `tiles/*.png` (16 files) | The same tiles as individual 32×32 files | RGBA | **Usable as is**, redundant with the atlas. |
| `tileset_preview_4x.png` | 512×512 enlarged preview | | **Not usable** in game. Reference only. |
| `copper_works_background_1280x720.png` | Illustrated factory backdrop | 1280×720, opaque | **Usable with changes.** Very busy and bright. Dim it with a modulate at runtime so wires and platforms read clearly. Does not tile, so levels stay one screen wide. |
| `copper_works_background_original.png` | Same image at 1672×941 | Opaque | **Not usable** for now. Wrong size, redundant. |

Tile notes: ground tiles (0–3) and panels (12–14) fill the full 32×32 and take full-cell collision. Platform tiles (4–7) only occupy rows 7–20 and need a thin one-way collision shape there. Wire tiles (8–11) and the support beam (15) are decorative with no collision. There is no vertical wall or ceiling-edge tile; `ground_fill` and `reinforced_block` stand in.

## Resistors (`assets/interactive/resistors/`) (superseded, files retained)

Seven icons, each 96×64 RGBA: 0.5, 1, 2, 3, 4, 6 and 10 Ω. Each has colour bands and a baked value label underneath.

Verdict: **Usable as is.** Limitation: only these seven values have art. The first ten levels use only these values. Any other value needs a generated icon (blank body plus a text label).

## Props (`assets/props/`) (superseded, files retained)

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

## Hazards (`assets/hazards/`) and effects (`assets/effects/`) (superseded, files retained)

Eight hazards (76–112 px, single frame each) and four 64×64 effects. All RGBA with clean transparency.

Verdict: **Usable as is** as static sprites, none needed for the slice. They have one frame each, so movement comes from code (bobbing, rotation, flashing). `spark_burst.png` and `victory_sparkle.png` can be used as particle textures in Milestone 2.

## UI (`assets/ui/`) (superseded, files retained)

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

## Audio (`assets/audio/`) (superseded, files retained)

All 13 files are PCM WAV, mono, 22050 Hz, 16-bit. Godot imports them as `AudioStreamWAV`.

| File | Length | Verdict |
|---|---|---|
| `music_copper_works_loop_16s.wav` | 16.0 s | **Done.** Its `.import` sidecar now has `edit/loop_mode=2` (Forward), `loop_begin=0`, `loop_end=-1` (end of file). The WAV itself is unchanged. Loads as `AudioStreamWAV` with `loop_mode == LOOP_FORWARD` across the whole file. Short loop, so play it quietly. |
| `sfx_jump`, `sfx_land`, `sfx_pickup`, `sfx_place_resistor`, `sfx_connect`, `sfx_invalid`, `sfx_door_open`, `sfx_win` | 0.10–0.58 s | **Usable as is.** All used in the slice. |
| `sfx_bounce`, `sfx_enemy_zap`, `sfx_hurt`, `sfx_switch` | 0.12–0.21 s | **Usable as is.** Later milestones. |

## Data, preview and source sheets (superseded, files retained)

| File | Verdict |
|---|---|
| `data/circuit_puzzles.json` | **Not usable** directly. It describes finished circuits as trees, with no layout and no puzzle. The ideas are reused in the level curve. |
| `data/sample_level.json` | **Not usable** directly. Illustrative positions only, and no circuit topology. Its tile ID table is correct and is adopted. |
| `data/resistor_color_codes.json` | **Usable as is.** Reference if we generate resistor icons for new values. |
| `data/asset_manifest.json` | Reference only. Its dimensions match what was measured. |
| `preview/illustrative_level_scene.png` | Reference only. Target look for the slice. |
| `source_sheets/*.png` (3 files) | Not used in game. High-resolution sources for future art edits. Excluded from export later. |

## Processed and generated (old pack) (superseded, files retained)

Everything here is rebuilt by a script in `tools/`. Do not hand-edit the outputs; change the script and re-run it. All commands run from the project root with the console Godot build; run `--headless --path . --import` after regenerating PNGs.

| Command | Produces |
|---|---|
| `--headless --path . --script res://tools/build_tileset.gd` | `resources/tileset.tres` |
| `--headless --path . --script res://tools/build_player_frames.gd` | `resources/player_frames.tres` |
| `--headless --path . --script res://tools/generate_placeholders.gd` | the five PNGs in `assets/processed/` |
| `--headless --path . --script res://tools/check_resources.gd` | nothing; verifies all of the above plus the music loop (exit 0 = pass) |

### TileSet: `res://resources/tileset.tres`

- One `TileSetAtlasSource`, **source id 0**, texture `res://assets/environment/tileset_32px.png`, `tile_size` and `texture_region_size` 32×32, 16 tiles, alternative 0 only.
- **Tile ID n is at atlas coords `Vector2i(n % 4, n / 4)`.** Example: `layer.set_cell(cell, 0, Vector2i(id % 4, id / 4))`.
- Physics layer 0: `collision_layer = 1` ("world"), `collision_mask = 0`. Full 32×32 square on IDs 0 ground_top_left, 1 ground_top, 2 ground_top_right, 3 ground_fill, 12 wall_panel, 13 warning_panel, 14 reinforced_block.
- Physics layer 1: `collision_layer = 2` ("one-way platform"), `collision_mask = 0`. One polygon with `one_way = true` on IDs 4 platform_left, 5 platform_middle, 6 platform_right, 7 platform_single, covering pixel rows 7–20 full width (local points y −9 to +5). `check_resources.gd` confirms the platform art really occupies rows 7–20.
- No collision: IDs 8 wire_horizontal, 9 wire_vertical, 10 wire_corner, 11 wire_t_junction, 15 support_beam.
- Both masks are 0 on purpose: static tiles never need to scan, and a non-zero tile mask would make the platforms collide with the player even after the player clears bit 2 from its own mask (Godot collides a pair if either side's mask matches). The player should use mask `1 | 2` normally and drop bit 2 to fall through a platform.

### Player animations: `res://resources/player_frames.tres`

`SpriteFrames` built from the 128×128 poses in `assets/player/`. No `default` animation exists, so set `animation` explicitly (start with `idle`). Feet sit on y=124 of each frame, so use a bottom-centre offset (for example `offset = Vector2(0, -60)` with `centered = true`, or `centered = false` with `offset = Vector2(-64, -124)`). Side poses face right; use `flip_h` for left.

| Animation | Frames | FPS | Loop |
|---|---|---|---|
| `idle` | front.png | 1 | yes |
| `run` | walk.png, run.png | 8 | yes |
| `jump` | jump.png | 1 | no |
| `victory` | victory.png | 1 | no |
| `back` | back.png | 1 | no |
| `notice` | idle.png | 1 | no |

### Placeholder art (`assets/processed/`, from `tools/generate_placeholders.gd`)

Palette sampled from the tileset and UI slot: dark teal `#182E3A` outline, panel `#102A36`, copper `#B66B39`, orange `#ECAA57`, gold `#EAB940`, cream `#FFE2A0`, cyan `#4BD3C2`. Every pixel is set directly: hard edges, no anti-aliasing, transparent background.

| Resource path | Size | What it is |
|---|---|---|
| `res://assets/processed/socket_empty.png` | 104×72 | World socket for a 96×64 resistor icon. Dark outline, 1 px cyan border, gold corner dots, semi-opaque (alpha 200) dark inner panel. Copper lead stubs on both side edges, rows 34–37 (centred on y=36), open at the outer edge so a wire ending at (0, 36) or (103, 36) looks connected. Draw the resistor icon at offset (4, 4). |
| `res://assets/processed/socket_highlight.png` | 104×72 | Same layout with a 3 px gold/cream/gold border and cyan corner dots. Swap in when the socket is the interaction target. |
| `res://assets/processed/pickup_highlight.png` | 104×72 | Gold/cream/gold 3 px frame with a dark 1 px outline and a fully transparent centre (the frame is the outer 4 px). Draw centred on a loose 96×64 resistor icon, that is at icon position − (4, 4). |
| `res://assets/processed/node_dot.png` | 16×16 | Copper junction dot, about 14 px across, dark outline, orange highlight. Centre it on the junction point. |
| `res://assets/processed/terminal.png` | 32×32 | Gold terminal post, about 30 px across: dark outline, shaded gold rim, inner cap with a dark centre hole. No plus or minus sign, so it can mark either end. Centre it on the terminal point. |

## Missing for the vertical slice (old pack) (superseded, files retained)

| Gap | Decision | Status |
|---|---|---|
| World socket that fits a 96×64 resistor, in empty and highlighted states | Placeholder in `assets/processed/`, based on the UI slot style. | **Filled:** `socket_empty.png`, `socket_highlight.png`. |
| Highlight around a loose resistor that is the interaction target | Placeholder frame. | **Filled:** `pickup_highlight.png`. |
| Wires connecting sockets, terminals and junctions | Drawn in code with `Line2D` from level data, in the tileset's copper colour (`#B66B39`, outline `#182E3A`). Wire tiles stay decorative. | Code task (gdscript-coder). |
| Circuit terminals (the two points resistance is measured between) | Generated gold terminal post; generated copper dot for junctions. `battery_pickup.png` stays available as a decorative source marker. | **Filled:** `terminal.png`, `node_dot.png`. |
| "Carrying" indicator | The resistor icon shown above Ohmie's head. No new art. | No art needed. |
| Interact prompt ("E") | Text label. No new art. | No art needed. |
| UI font with an Ω glyph | Godot's default font, which includes Ω. A pixel font is a Milestone 2 task. | Deferred. |
| True run and idle animation cycles | 2-frame run from existing poses. | Not filled (accepted). |
| TileSet resource with collision | Built in `resources/`. | **Filled:** `resources/tileset.tres`. |
| SpriteFrames for the player | Built in `resources/`. | **Filled:** `resources/player_frames.tres`. |
| Looping music | `.import` sidecar edit only. | **Filled:** loop mode Forward. |
| Resistor icons for values other than the seven supplied | Not needed yet. Levels 1–10 are restricted to the seven values. | Deferred. |
