# Contributing

Thanks for your interest in Ohmie: Circuit Adventure. Bug reports, level ideas and code are all welcome.

## Getting set up

1. Install [Godot 4.7](https://godotengine.org/download), standard build (not .NET).
2. Clone the repository and open `project.godot`. The first open imports the assets, which takes a minute.
3. Press F5 to play.

From a terminal, with `godot` on your path:

```
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```

Run `--import` once after adding any script that declares a `class_name`, or command-line runs will not find the new class.

## Reporting a bug

Open an issue with: what you did, what you expected, what happened, and the room you were in. A screenshot helps. If a room can be solved in a way that looks unintended, include the arrangement of parts.

## Code

- GDScript with static typing everywhere: variables, parameters and return types.
- One script per responsibility. Nodes announce what happened with signals; parents connect their children.
- Circuit maths lives only in `src/circuit/`, is pure (no nodes, no singletons) and uses exact fractions (`Rational`). No floating point there.
- Input goes through input map actions, never raw key codes.
- Tunable numbers are exported variables or named constants.

Every change should keep these green:

```
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --fixed-fps 60 --script res://tests/play_break.gd
```

Changes to `src/circuit/` need unit tests in `tests/test_*.gd`.

## Rooms

A room is one JSON file in `levels/`. The format is described in `docs/GDD.md`. A new or changed room needs:

1. A clean run of the validator, which lists every arrangement of parts that satisfies the mission:
   ```
   godot --headless --path . --script res://tools/validate_level.gd -- res://levels/w1_05.json
   ```
2. A scripted playthrough in `tests/play_<room>.gd` that completes the room with real movement. Copy an existing one as a starting point.

Good rooms teach one idea, state the mission in one short line, and place the tempting part where it is the wrong choice.

## Art and audio

The art and audio are not under the MIT licence; see `LICENSE-ASSETS.md`. Please do not submit art you did not make or do not have the right to share.

## Licence of contributions

By submitting code you agree that it is released under the MIT licence in `LICENSE`.
