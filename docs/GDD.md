# Ohmie: Circuit Works — Game Design Document

Version 0.1, 2026-11-11. Owned by the lead. Reasons for decisions are logged in `DECISIONS.md`.

## 1. Pitch and pillars

Ohmie is a small battery-backed robot in a copper factory. Every room has a half-built circuit on the wall and a locked door. Carry resistors to the circuit's sockets until its equivalent resistance is exactly 1 Ω, and the door opens.

1. **The whole circuit is always on screen.** Every level is one screen. You plan with your eyes, then execute with your feet.
2. **Platforming chooses the circuit.** Where a resistor sits and how hard a socket is to reach decide which solution is practical.
3. **Exact, honest math.** Values are fractions, never rounded. 1/3 + 2/3 is 1.
4. **You learn by watching it collapse.** After each solve, the network simplifies step by step in front of you.

## 2. Core loop

1. Enter the room. Read the board: the wires, the sockets, the two terminals, the target.
2. Spot the resistors lying around the room. Decide which go where.
3. Fetch one, carry it to a socket, plug it in. The readout updates instantly.
4. Repeat, swap, or pull one back out, until the readout matches the target.
5. The door opens. Walk through it.
6. Watch the collapse replay, then go to the next room.

### How resistors are placed: options considered

| Option | How it works | For | Against |
|---|---|---|---|
| A. Carry to sockets in the world | The circuit is wired into the level with empty sockets. Ohmie carries one resistor at a time and plugs it in. | Platforming and puzzle are the same activity. Circuit is always visible. Simple controls (one button). | Topology is fixed by the level, so the player chooses values and which sockets to use, not the wiring itself. |
| B. Stand on terminals | Ohmie holds a resistor and stands on pads to bridge two points. | Free-form wiring. | Needs many pads, fiddly to read, and connections vanish when you walk away. |
| C. Build-mode overlay | Collect resistors into an inventory, then open an editor screen and arrange them. | Full wiring freedom. | Splits the game into two disconnected halves. Platforming becomes a fetch quest. |

**Chosen: A.** It is the only option where a jump is also a circuit decision. The fixed topology is a strength for teaching: each level shows one network shape clearly. Wiring freedom comes back in Milestone 3 through lever switches that open and close wires.

### Interaction rules

- Ohmie carries at most **one** resistor. It floats above their head.
- `interact` (E) acts on the nearest interactable within 56 px, which is highlighted:
  - Empty hands at a loose resistor: pick it up.
  - Carrying at an empty socket: plug it in.
  - Empty hands at a filled socket: pull the resistor out.
  - Carrying at a filled socket: swap.
  - Carrying with nothing in range: put the resistor down at Ohmie's feet.
- `restart` (R) resets the room.
- The door is open exactly while the readout equals the target. Change the circuit and it shuts again.
- Walking into the open door completes the level, whether or not Ohmie is carrying something.
- Falling off the bottom of the screen respawns Ohmie at the start. A carried resistor returns to where it originally lay. The circuit is untouched.

## 3. Circuit rules

### Model

A circuit is a **graph**: named nodes joined by edges. Two nodes are the **terminals**, A and B. The answer is the equivalent resistance between A and B.

Edge types:

| Type | Meaning |
|---|---|
| `wire` | Zero resistance. Its two nodes are electrically the same point. |
| `socket` | Holds one resistor. **Empty means open circuit**: the edge is absent. |
| `fixed` | A resistor soldered in by the level. Cannot be removed. |

### Arithmetic

All values are exact rationals: an integer numerator and a positive integer denominator, always reduced. No floats anywhere in circuit code. Values in data files are strings: `"2"`, `"1/2"`, or `"0.5"` (parsed exactly as 1/2).

- Series: R = R₁ + R₂
- Parallel: R = (R₁ · R₂) / (R₁ + R₂)

### Solving (Milestone 1: series-parallel reduction)

1. Drop empty sockets. Merge nodes joined by wires.
2. If A and B have become the same node, the result is 0 Ω (short).
3. Repeat until nothing changes:
   - **Prune**: remove any edge that cannot carry current (a self-loop, or a dead end at a non-terminal node).
   - **Parallel merge**: two edges between the same pair of nodes become one.
   - **Series merge**: a non-terminal node with exactly two edges is removed and its edges become one.
4. One edge left between A and B: that is the answer. No edges left: **open**. Anything else: the network is not series-parallel (**unsupported** until Milestone 3).

Every merge is recorded as a **reduction step** (kind, the edges consumed, the edge produced, its value). The step list is the script for the collapse replay, so it must be deterministic: prefer prune, then parallel, then series, and break ties by edge id order.

### Results

| Status | Readout |
|---|---|
| OK | The value as an integer or fraction: `1 Ω`, `3/2 Ω`, `0 Ω` |
| OPEN | `OPEN` |
| UNSUPPORTED | `???` (should never appear in a shipped level) |

The level is solved only when status is OK and the value equals the target exactly.

### Puzzle solver

A separate pure function takes a level's circuit, its sockets, the available resistors and the target, tries every way of assigning resistors to sockets (each resistor used at most once, sockets may stay empty), and returns every assignment that hits the target. The level validator and level designer use it to prove solvability and count solutions.

### Later: general networks (Milestone 3)

Bridges and Wheatstone networks do not reduce by series and parallel alone. Plan: nodal analysis with rational Gaussian elimination. Inject 1 A at terminal A, ground B, solve the conductance matrix exactly, read R = V(A). Delta-Y transforms are used only in the replay, to show the player how such a network collapses. The nodal solver also becomes a cross-check for the reduction solver in tests.

## 4. Educational layer: the collapse replay (Milestone 2)

After the door is entered, the board is redrawn large in the centre of the screen and the recorded reduction steps play one at a time:

- The edges about to merge pulse.
- A caption names the rule and shows the arithmetic with the real numbers: `Parallel: (2 × 2) / (2 + 2) = 1 Ω` or `Series: 1/2 + 1/2 = 1 Ω`.
- The edges slide together into one resistor showing the new value.
- The last step leaves a single resistor between A and B reading the target.

The player can step with `interact` or skip. Unused resistors and empty sockets fade out first, with the caption "An empty socket is an open circuit. No current flows here."

## 5. Player movement

| Quantity | Value |
|---|---|
| Collider | 36 × 88 px, origin at bottom centre |
| Run speed | 240 px/s |
| Gravity | 1800 px/s² |
| Jump velocity | 660 px/s (apex about 121 px) |
| Variable jump | Releasing jump while rising halves upward speed |
| Coyote time, jump buffer | 0.10 s each |
| One-way platforms | Jump up through; hold `move_down` to drop through |

**Level design limits (with safety margin):** jump up at most **3 tiles** (96 px). Jump across gaps of at most **4 tiles** (128 px) at equal height. Leave **3 tiles** of headroom under solid ceilings wherever Ohmie must walk (one-way platforms do not block from below, so they are exempt).

Controls: A/D or arrow keys move, Space/W/Up jumps, S/Down drops through, E interacts, R restarts.

## 6. Level format

One JSON file per level in `levels/`. The room is 40 columns × 23 rows of 32 px tiles (the bottom row is half off-screen). Positions are in pixels from the top-left corner.

```json
{
  "id": "slice_01",
  "title": "Half and Half",
  "teaches": "Series and parallel together",
  "target": "1",
  "tiles": ["40 characters per row, 23 rows"],
  "spawn": [96, 640],
  "door": [1180, 640],
  "pickups": [
    { "id": "r1", "ohms": "1/2", "pos": [300, 640] }
  ],
  "circuit": {
    "nodes": { "A": [400, 200], "n1": [520, 200], "B": [880, 200] },
    "terminals": ["A", "B"],
    "edges": [
      { "id": "w1", "type": "wire",   "from": "A",  "to": "n1" },
      { "id": "s1", "type": "socket", "from": "n1", "to": "n2" },
      { "id": "f1", "type": "fixed",  "from": "n2", "to": "B", "ohms": "2" }
    ]
  }
}
```

- `spawn`, `door` and pickup `pos` are the point on the floor under the object (bottom centre).
- Circuit node positions are centres. Edges are drawn as straight lines between their nodes, so use extra nodes and wires for corners. Keep every edge horizontal or vertical.
- A socket or fixed resistor is drawn at the midpoint of its edge. Its two nodes must be at least 128 px apart.
- Tile characters: `.` empty, `#` solid ground (drawn with a top surface when the cell above is empty, otherwise as fill), `=` one-way platform (end caps chosen automatically), `B` reinforced block (solid), `W` wall panel (solid), `!` warning panel (solid), `|` support beam (decoration, no collision).

## 7. Difficulty curve: first ten levels

Board shapes are written with `+` for series and `∥` for parallel. S means socket. Only the seven values with art are used (1/2, 1, 2, 3, 4, 6, 10). The level designer finalises values and proves each with the solver.

| # | Title | Board | Resistors in the room | Teaches |
|---|---|---|---|---|
| 1 | Twin Resistors | S ∥ S | 2, 2 | Carry, plug in, read the display. Two equal resistors in parallel halve. |
| 2 | In a Row | S + S | 1/2, 1/2 | Series adds. Every series socket must be filled. |
| 3 | Three Branches | S ∥ S ∥ S | 3, 3, 3 | n equal resistors in parallel give R/n. |
| 4 | Odd One Out | S ∥ S ∥ S | 2, 3, 6, and a 4 as decoy | Unequal parallel: 1/2 + 1/3 + 1/6 = 1. First decoy. |
| 5 | Half and Half | S + (S ∥ S) | 1/2, 1, 1, and a 2 as decoy | Series and parallel in one network. This is the vertical slice level. |
| 6 | Leave It Empty | S ∥ S ∥ S | 2, 2, 3, 6 | An empty branch is fine. Two solutions: the easy-to-reach pair or the scattered trio. |
| 7 | Long Way Round | (S + S) ∥ S | 1, 1, 2, and a 3 as decoy | A series chain as one parallel branch. |
| 8 | Nested | ((S ∥ S) + (S ∥ S)) ∥ S | 2 × 5, and a 4 as decoy | Collapse from the inside out. |
| 9 | Ladder | S + (S ∥ (S + S)) | chosen by the designer, two decoys | A three-deep network. Order of simplification matters. |
| 10 | Works Exam | six sockets, one fixed resistor already soldered in | eight resistors, two decoys, one resistor behind a hard jump | Everything so far, and working around a part you cannot move. |

Platforming rises alongside: levels 1–3 are flat with one ledge, 4–6 add one-way platforms and a resistor placed to tempt, 7–10 put sockets at different heights so the order of trips matters.

Bridge networks, switches and hazards begin at level 11 (Milestone 3).

## 8. Presentation

- **HUD:** one frame in the top-left corner: `TARGET 1 Ω | EQUIVALENT 3/2 Ω`. The equivalent value turns green on a match. Level title top centre. Control hints along the bottom in the first levels.
- **Board:** copper wires. Terminals A and B are marked. When the circuit is closed (status OK) the wires brighten; on a match they turn cyan and pulse.
- **Sound:** jump, land, pick up, place, invalid action, connect (match reached), door open, win. Music loop at low volume.
- **Background:** the Copper Works illustration, dimmed so the board and platforms stand out.

## 9. Asset plan

Full audit in `ASSETS.md`. Summary:

- **Reuse as is:** tileset, resistor icons, exit door (closed and open), player poses (front, walk, run, jump, back, victory), `hud_blank`, victory banner, all sound effects.
- **Reuse with changes:** background (dimmed at runtime), music (enable looping on import), UI slot art (basis for a wider world socket).
- **Make as placeholders now:** world socket (empty and highlighted), junction dot, terminal markers. Wires are drawn in code.
- **Skip for now:** `circuit_panel` and `hud_target_1ohm` (text baked in), `push_scene` pose, consoles, hazards, effects, hearts, buttons.
- **Improve later:** real run and idle animation cycles, a pixel UI font, on/off states for lever and button, resistor icons for other values, one coherent pixel density across characters and tiles.

## 10. Milestones

**Milestone 1: vertical slice.** One playable room (level 5, "Half and Half"). Movement, picking up and carrying resistors, sockets, live exact readout, door that opens at exactly 1 Ω, restart, sound. Circuit engine with unit tests. Level loaded from JSON and proven solvable. Automated playthrough test.

**Milestone 2: the first world.** Levels 1–10. Level flow (complete, replay, next). The collapse replay. Title screen and pause. Music. Pixel font. Progress saved.

**Milestone 3: beyond series-parallel.** Nodal-analysis solver with rationals. Lever switches that open and close wires. Bridge and Wheatstone levels with delta-Y shown in the replay. First hazards and hearts.

**Milestone 4: polish and ship.** Animation cycles, particles, art consistency pass, settings, Windows export.
