# Ohmie: Circuit Works

A Godot 4.7.2 (standard build, GDScript, Compatibility renderer) 2D platformer combined with resistor-network puzzles. Each level is one screen. The player, Ohmie, carries resistors one at a time to sockets wired into the level. The level's door opens when the circuit's equivalent resistance is exactly the target, normally 1 Ω. Platforming decides which resistors and sockets are convenient to reach. The circuit math is the puzzle.

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
| `qa-tester` | Running, breaking, reporting in `docs/BUGS.md`. Never fixes game code. |

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
docs/                GDD, asset audit, decisions, bugs.
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
| Check the game boots without errors | `& $godot --headless --path . --quit-after 120` |
| Validate a level is solvable | `& $godot --headless --path . --script res://tools/validate_level.gd -- res://levels/<file>.json` |
| Play the game | `& $godot --path .` |

Always read the output for `ERROR`, `SCRIPT ERROR` and `WARNING` lines. An exit code of 0 alone is not proof for the boot check.

Tests live in `tests/test_*.gd`. Each is a script with `test_*` methods, discovered and run by `tests/run_tests.gd`. Every change to `src/circuit/` needs tests. No third-party test addon.

## Current state

Update this section whenever a milestone step completes.

- Art: the game uses only the new pack in `assets/`. Sprites, tiles and props are drawn at scale 0.5 with Linear filtering on the unchanged 1280×720 / 32 px grid; the 1920×1080 background is scaled to fit (2/3). Platform tiles use `texture_origin` so the art lines up with a standing surface 7 px below the cell top. Rebuild resources with `tools/build_tilesets.gd` and `tools/build_player_frames.gd`; verify with `tools/check_resources.gd` (485 checks).
- Scope for this version: World 1 (Old Workshop) only, holding all ten rooms. A level's optional `world` field picks `resources/themes/<world>/theme.tres`; only `old_workshop` has a theme. Worlds 2–5 and the boss are for later versions.
- Levels 1–4 and 6–10 are not designed yet (two `level-designer` tasks were started and stopped early to save usage; nothing of theirs was kept). Briefs are in `docs/GDD.md` section 7. After that: level-to-level flow, then the collapse replay.
- Run play tests with `--fixed-fps 60`. Current counts: 127 unit, 11 movement, 31 dev room, 25 slice_01, 95 adversarial.
- Milestone 1 (vertical slice) is playable. The game boots into `levels/slice_01.json` ("Half and Half"). `levels/dev_room.json` is a development room used by the play tests.
- Passing as of 2026-11-11: 127 unit tests (`tests/run_tests.gd`), and the scripted play tests `tests/play_movement.gd` (11 checks), `tests/play_slice.gd` (30) and `tests/play_slice_01.gd` (25). Run each with `--headless --path . --script res://tests/<name>.gd`.
- After adding a script with `class_name`, run `--import` once before any `--script` command, or the class name will not resolve.
- Autoloads are not visible to scripts started with `--script`; gameplay code looks up `Sfx` at `/root/Sfx` and tolerates it being absent.
- A test or tool selects a level by setting `Room.level_override` before the main scene loads, or with `-- --level=res://levels/x.json`.
- All subagents that have run reported model `claude-opus-5-5`.
- QA pass done; bugs and their status are in `docs/BUGS.md`. Known rough edges: the readout plaque text is small at 720p; shelves painted in the background can be mistaken for platforms; `docs/ASSETS.md` still has a few stale lines above its "New pack" section.
- Git: remote `origin` is https://github.com/tmamado14/ohmie (branch `master`). Commit as the user only, with no Claude co-author or attribution lines. Push after each completed task.