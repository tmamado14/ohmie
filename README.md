# Ohmie: Circuit Works

A 2D platformer where the puzzle is a resistor network. Built with Godot 4.7.

Ohmie is a small robot in a copper factory. Every room has a half-built circuit on the wall and a locked door. Carry resistors to the circuit's sockets, one at a time, until the equivalent resistance is **exactly 1 Ω**. Then the door opens.

- **The whole circuit is always on screen.** Every level is one room.
- **Platforming chooses the circuit.** Where a resistor lies and how hard a socket is to reach decide which solution is practical.
- **Exact math.** Values are fractions, never rounded. 1/3 + 2/3 is 1.
- **Learn by watching.** After each solve, the network collapses step by step into a single resistor.

## Status

Early development. Milestone 1, a one-room vertical slice, is being built. See the milestone plan in [docs/GDD.md](docs/GDD.md).

## Screenshots

Screenshots will be added here once the vertical slice is playable.

## Controls

| Action | Keys |
|---|---|
| Move | A / D or arrow keys |
| Jump | Space, W or Up |
| Drop through a platform | S or Down |
| Pick up, plug in, pull out, swap | E |
| Restart the room | R |

## Running it

1. Install [Godot 4.7](https://godotengine.org/download) (standard build).
2. Clone this repository.
3. Open `project.godot` in Godot and press F5, or run `godot --path .` from the project folder.

Run the tests:

```
godot --headless --path . --script res://tests/run_tests.gd
```

## Project layout

| Folder | Contents |
|---|---|
| `assets/` | Original art, audio and data |
| `src/circuit/` | Circuit math: exact rationals, network solver, puzzle solver |
| `src/` | Player, level, objects and UI code |
| `levels/` | Level data, one JSON file per room |
| `tests/` | Headless tests |
| `docs/` | Game design document, asset audit, decision log |
