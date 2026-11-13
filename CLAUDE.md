# Ohmie: Circuit Adventure

A Godot 4.7.2 (standard build, GDScript, Compatibility renderer) 2D platformer combined with electronics puzzles. Each level is one screen with a real, closed circuit on the wall. The player, Ohmie, carries parts (batteries, resistors) one at a time to slots in the circuit. The door opens while the level's mission holds, for example "Draw 2 A." Platforming decides which parts and slots are convenient to reach. The circuit is the puzzle, and a real solver decides the result.

Design source of truth: `docs/GDD.md`. Asset facts: `docs/ASSETS.md`. Decisions and their reasons: `docs/DECISIONS.md`.

## Ownership

The lead agent owns this project: architecture, design, mechanics, level design, asset choices, scope and priorities. The lead makes each call, records it as one line with a reason in `docs/DECISIONS.md`, and keeps moving without asking the user for permission. The user gets a short progress update at the end of each phase or milestone.

Stop and involve the user only for:

- Something only the user can do on their PC: restarting Claude Code, installing software, approving a permission prompt.
- An action that would destroy the user's original files.

User feedback is input. The lead still makes the final call, and explains why when going a different way.

## Workflow rule

The main agent (Fable 5.2) owns all decisions, plans, and reviews. All implementation is delegated to the Opus 5.5 subagents in small, specific tasks. The main agent doesn't use general-purpose subagents for implementation, because those may not run on Opus 5.5. Every handoff must include the files involved, the exact goal, and how to verify it, because subagents don't see this conversation.

The team, defined in `.claude/agents/` (all pinned to `claude-opus-5-5`):

| Agent | Owns |
|---|---|
| `circuit-engine` | `src/circuit/` and its tests. Pure math only. |
| `asset-integrator` | `assets/processed/`, `resources/`, import settings, `docs/ASSETS.md`. |
| `gdscript-coder` | Gameplay and UI code and scenes. |
| `level-designer` | `levels/*.json`, each proven solvable. |
| `qa-tester` | Running, breaking and reporting bugs to the lead. Never fixes game code. |

Reports: when a subagent finishes, the lead saves its final report word for word to `reports/NN_<agent>_<topic>.md` (local only, git-ignored), with a three-line header: date, agent, and the lead's verdict (accepted, accepted with follow-ups, or sent back). The user reads these. The lead still gives the user a short summary in chat.

Build order for a feature: circuit-engine, asset-integrator, gdscript-coder, level-designer, qa-tester. The lead reviews each result before the next task. A failure goes back to the same agent as a focused fix task; the lead does not rewrite it. Subagents do not commit. The lead commits after each completed task with a clear message.

## Folder structure

```
assets/              The user's art pack (hand-inked cartoon style, authored at 2x). READ-ONLY.
assets/processed/    Derived and generated art. The only writable part of assets/.
assets-old/          The first art pack. Local only (git-ignored, .gdignore). Never reference it.
resources/themes/    Per-world theme.tres and tileset.tres, plus player_frames.tres.
scenes/              .tscn scenes.
src/circuit/         Pure circuit math. RefCounted only, no nodes, no engine singletons.
src/player/          Player movement and carrying.
src/level/           Level data parsing, level building, level flow.
src/objects/         Pickups, sockets, door, circuit board.
src/ui/              HUD and menus.
src/autoload/        Autoload singletons (kept to a minimum).
levels/              Level data, one JSON file per level.
tests/               Headless tests. run_tests.gd is the runner.
tools/               Command-line tools: level validator, art generators, screenshot script.
docs/                Game design document, asset notes, decision log, README images.
```

Never edit, move, rename or delete an original file in `assets/`. Godot's `.import` sidecar files next to them may be edited to change import settings.

## Coding conventions

- Static typing everywhere: variables, parameters, return types, typed arrays. Treat untyped-declaration warnings as errors.
- Signals over tight coupling. A node announces what happened; it does not reach into other nodes. Parents connect children. No `get_node("../../Something")`.
- One script per responsibility. If a script needs "and" to describe it, split it.
- Circuit code is exact. Resistance is always a `Rational` (integer numerator and denominator). No `float` in `src/circuit/`, and no circuit math anywhere else.
- Names: files and functions `snake_case`, classes `PascalCase` with `class_name`, constants `UPPER_SNAKE`, signals in past tense (`resistor_placed`), private members prefixed `_`.
- Tunable numbers are `@export` variables or named constants, never magic numbers inline.
- Input goes through input map actions (`move_left`, `move_right`, `move_down`, `jump`, `interact`, `restart`), never raw key codes.
- Small scenes. Prefer composing a few small scenes over one large one.
- Keep scope small. Working and simple beats ambitious and broken.

## Commands

Godot executable (console build, prints errors to the terminal):

```
C:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
```

In PowerShell, set `$godot` to that path first, then:

| Purpose | Command |
|---|---|
| Re-import assets after adding files | `& $godot --headless --path . --import` |
| Run all tests (exit code 0 means pass) | `& $godot --headless --path . --script res://tests/run_tests.gd` |
| Check the menus boot without errors (reaches the title) | `& $godot --headless --path . --fixed-fps 60 --quit-after 480` |
| Load one room directly | `& $godot --headless --path . --fixed-fps 60 --quit-after 300 res://scenes/main.tscn -- --level=res://levels/<file>.json` |
| Delete saved progress (for a fresh first run) | `& $godot --headless --path . --script res://tools/reset_progress.gd -- --yes` |
| Validate a level is solvable | `& $godot --headless --path . --script res://tools/validate_level.gd -- res://levels/<file>.json` |
| Play the game | `& $godot --path .` |

Always read the output for `ERROR`, `SCRIPT ERROR` and `WARNING` lines. An exit code of 0 alone is not proof for the boot check.

Tests live in `tests/test_*.gd`. Each is a script with `test_*` methods, discovered and run by `tests/run_tests.gd`. Every change to `src/circuit/` needs tests. No third-party test addon.

## Current state

Update this section whenever a milestone step completes. Last updated 2026-11-12.

**Design.** `docs/GDD.md` is the single, current design: closed DC circuits solved by a real engine, batteries and resistors both carried as parts, every slot takes any part, fixed meters and lamps on the board, a goal is a list of conditions, and the mission is one short line. The long-term aim is a full ECE game. World 1 (Old Workshop) is basic DC networks: ten rooms plus three overtime rooms, listed in GDD section 7. Missions are deliberately varied; do not add another plain "Draw X A" room.

**Engine (`src/circuit/`).** `DcNetwork`, `DcSolver`, `DcSolution`, `GoalCondition`, `DcPuzzleSearch`. Sign conventions are in the header of `dc_solution.gd`. The older `CircuitGraph` / `CircuitSolver` (series-parallel reduction with recorded steps) are not used by gameplay and are kept for the planned collapse replay. A full puzzle search on six slots and nine different parts takes about 39 s, so it is for the offline validator only.

**Game.** Level model in `src/level/` (`Part`, `LevelPart`, `LevelObject`, `LevelData`, `LevelCircuit`, `LevelGoal`, `Campaign`, `Progress`, `GameSession`, `PlayerRespawn`). Board and world objects in `src/objects/` (`CircuitBoard`, `CircuitSocket`, `PartPickup`, `BoardMeter`, `BoardLamp`, `BouncePad`, `Patroller`, `Floater`, `StaticHazard`, `Hurtbox`). Menus and HUD in `src/ui/`. One level format (GDD section 6). A battery's plus faces its slot's `from` node. Ohmie must be standing to interact. A zap and a pit fall share one respawn path; there are no lives.

**Flow.** The project boots `scenes/boot.tscn`: splash → title → world select → level select → room. `scenes/main.tscn` is the gameplay scene and is what tests load. Progress saves to `user://progress.json`; tests and tools use temporary save paths. The producer card text is the project setting `application/config/producer` ("TUP ECE").

**Levels.** `levels/campaign.json` lists worlds and rooms. All thirteen World 1 rooms exist: `w1_01.json` … `w1_13.json` (11–13 are overtime). `dev_room.json` and `dev_hazards.json` are development rooms used by tests. Every room needs a validator run with all solutions reported and a scripted route in `tests/play_w1_NN.gd`. Bounce pad numbers for designers: apex 224 px above the pad's cushion (about 274 px above the floor); up to about 190 px of horizontal travel onto a platform six tiles up; a running jump clears a hurtbox up to 108 px wide.

**Art.** Only the pack in `assets/` is used (hand-inked style, authored at 2×, drawn at scale 0.5 with Linear filtering on the 1280×720 / 32 px grid; the background is scaled to fit). Generated art is in `assets/processed/`, made by the `tools/generate_*.gd` scripts. Exact paths, text rectangles and offsets are in `docs/ASSETS.md`. `assets-old/` is local only and must never be referenced.

**Repository hygiene.** The public repo holds only what the game and its tests need. Not tracked (see `.gitignore`): `tests/screenshots/` (regenerated by tools), art source sheets and previews, the pack's sample data, `assets-old/`. README images live in `docs/images/`; refresh them by copying from `tests/screenshots/` after retaking. Code is MIT (`LICENSE`); art and audio have their own terms (`LICENSE-ASSETS.md`).

**Checks (all passing).** Run play tests with `--fixed-fps 60`.

| Command | Count |
|---|---|
| `--script res://tests/run_tests.gd` | 365 |
| `--script res://tests/play_menus.gd` | 38 |
| `--script res://tests/play_movement.gd` | 11 |
| `--script res://tests/play_slice.gd` | 35 |
| `--script res://tests/play_break.gd` | 128 |
| `--script res://tests/play_menus_break.gd` | 144 |
| `--script res://tests/play_world_states.gd` | 41 |
| `--script res://tests/play_overtime_states.gd` | 16 |
| `--script res://tests/play_hazards.gd` | 69 |
| `--script res://tests/play_w1_01.gd` … `play_w1_13.gd` | 29, 54, 37, 37, 60, 34, 38, 37, 52, 68, 76, 121, 100 |
| `--script res://tools/check_resources.gd` | 727 |

**Things that bite.**
- After adding a script with `class_name`, run `--import` once before any `--script` command. While another agent is mid-change, unrelated tests can fail to compile; re-import and retry.
- Autoloads are not visible to scripts started with `--script`; gameplay looks up `Sfx` at `/root/Sfx` and tolerates its absence. `GameSession` is static for the same reason.
- A test or tool picks a level by setting `Room.level_override` before the main scene loads, or with `res://scenes/main.tscn -- --level=res://levels/x.json`.
- The next-room key reacts to a real `interact` input event, not `Input.action_press`.
- Shell heredocs containing apostrophes or backticks have mangled files; write files with the Write/Edit tools.

**Next.** A QA pass over the overtime rooms (11–13, now with bounce pads, enemies and hazards); refresh the README room images (platforms are now inked shelves from `tools/generate_platform_art.gd`; the tile atlases are the composites in `assets/processed/tileset_<theme>.png`); explain `---`, `OL` and `SHORT` to new players; then the collapse replay. Fonts: Libre Baskerville is bundled in `assets/fonts/` (OFL) and is the project default; Ω and arrows fall back to a system serif. Music: `assets/audio/Ohmie BGM.mp3` for menus and World 1. Known rough edges: shelves painted in the background look like platforms; floor and platform tiles are pixel art beside inked sprites; the logotype is styled system type, not custom lettering. The user has playtested by hand (2026-11-13) and found no issues.

**Git.** Remote `origin` is https://github.com/tmamado14/ohmie (branch `master`). Commit as the user only, with no Claude co-author or attribution lines. Push after each completed task. All subagents so far reported model `claude-opus-5-5`.
