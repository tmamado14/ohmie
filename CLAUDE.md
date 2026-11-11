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
assets/              Original art, audio and data. READ-ONLY.
assets/processed/    Derived and placeholder art. The only writable part of assets/.
resources/           Godot resources built from assets (.tres: TileSet, SpriteFrames, theme).
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
