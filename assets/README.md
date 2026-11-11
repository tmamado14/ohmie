# OHMIE — THE FIVE CIRCUITS (v3)

A standalone, engine-neutral **five-level asset pack** for the ECE-themed
platformer. All art uses the approved original 1940s hand-inked, rubber-hose,
watercolor-cartoon direction. The previous complete classic-cartoon v2 base
pack is included; no need to download an earlier ZIP separately.

## Worlds and increasing danger

1. **Old Electric Workshop** — 2 Ω || 2 Ω = 1 Ω. Introduces basic resistor
   combinations, movement, gaps, and an exit gate.
2. **Copper Foundry** — 0.5 Ω + 0.5 Ω = 1 Ω. Series networks, motorized
   conveyors, molten-copper cartoon traps, and stamping pistons.
3. **Substation Switchyard** — 3 Ω || 3 Ω || 3 Ω = 1 Ω. Three-way current
   division, live-wire cartoon hazards, rain puddles, and grounding equipment.
4. **Signal Clocktower** — 2 Ω || 3 Ω || 6 Ω = 1 Ω. Mixed values, timed relay
   switches, analog waves, pendulum hazards, and moving platforms.
5. **High-Voltage Transmitter** — ((2 Ω || 2 Ω) + (2 Ω || 2 Ω)) || 2 Ω = 1 Ω.
   Nested networks, synchronized voltage arcs, a final gate, and the original
   cartoon boss **Shorty the Short-Circuit Baron**.

## Files to import

- `player/`, `props/`, `hazards/`, `effects/`, `platforms/`, `interactive/`,
  `ui/`, `environment/` — all shared assets from the classic v2 pack.
- `worlds/level_02_...` through `worlds/level_05_...`: per-world 1920×1080
  backgrounds; 12 transparent illustrated unique objects; source atlas;
  distinct world-tinted 64×64 tile set; and two JSON descriptors.
- `worlds/level_01_old_workshop/`: Level 1 JSON, with refs to shared assets.
- `worlds/world_progression.json`: progression order, topic, target and paths.
- `boss/shorty_*.png`: six 320×320 Shorty key poses, source sheet, and atlas.
- `audio/`: original shared SFX, swing/chiptune cues and four new original
  world-specific 16-second music loops.
- `preview/`: five static illustrative game-scene compositions and a five-world
  overview. These are not running gameplay screenshots.
- `data/asset_manifest.json`: every file with path and byte size; PNG dimensions.

## Engine import and accuracy

- PNG character frames 256×256, Shorty frames 320×320, modular collision
  tiles 64×64, backgrounds 1920×1080, WAV mono 22.05 kHz audio.
- For hand-inked sprites, use **Linear** filtering and preserve alpha.
- Tile IDs 0–15 are row-major 4×4; per-world JSON lists collisions and
  illustrative object locations. Add your own controller and collision code.
- All five sample solutions are **validated with exact rational arithmetic**.
  Treat resistor values as nominal; 4th gold band indicates ±5% tolerance,
  not random variation in the educational puzzle solver.

## Production limitations

- This is a complete **asset collection for five prototype levels**, not a
  functioning game or completed gameplay implementation.
- Nine Ohmie poses and six Shorty poses are keyframes, not smooth frame-by-frame
  animation sequences. Interpolation or manually drawn in-between frames are
  still required for polished motion.
- Level JSON provides illustrative geometry and mechanics, not tested game
  physics, enemy AI, safety validation, or a finished level-design campaign.
- The five worlds use hand-painted art. Decorative platform sprites may not
  tile seamlessly; use the exact 64px collision tiles behind them.
- All artwork was made for Ohmie, with use subject to image-generation terms.
