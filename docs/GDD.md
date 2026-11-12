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
- Ohmie must be **standing** on a floor or platform to interact. In the air, nothing is highlighted and `interact` does nothing. This keeps a socket or resistor on a ledge from being reached by hopping underneath it.
- With empty hands the valid targets are loose resistors and filled sockets. While carrying, the valid targets are sockets.
- `interact` (E) acts on the nearest valid target within 56 px, which is highlighted:
  - Empty hands at a loose resistor: pick it up.
  - Carrying at an empty socket: plug it in.
  - Empty hands at a filled socket: pull the resistor out.
  - Carrying at a filled socket: swap.
  - Carrying with nothing in range: put the resistor down at Ohmie's feet. It always ends up fully on screen, fully supported by the surface, and not on top of another loose resistor; it slides a little to manage that, or the action is refused.
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

## 11. Goals and missions (added 2026-11-11)

"Exactly 1 Ω" is no longer the only win condition. Every level states a **goal**, shown on screen as a **mission**, and the door opens while the goal is met.

```json
"goal": { "type": "resistance", "value": "3/2", "mission": "Make exactly 3/2 Ω between A and B." }
```

- A goal has a `type`. This version implements one: `resistance`, met when the network between A and B is exactly `value`. The value can be any positive rational, not only 1.
- A level with the old `target` field and no `goal` is treated as a resistance goal.
- The readout plaque shows `GOAL` and the live reading. A mission sign shows the sentence and switches to a "complete" state while the goal is met.

Planned goal types, each arriving with the parts it needs:

| Type | Met when | Needs |
|---|---|---|
| `current` | The current through a named part is within a range, for example "light the LED with 10–20 mA and do not burn it" | Voltage sources, LEDs, nodal analysis |
| `voltage` | A named node sits at an exact voltage, for example a divider giving 3 V | Voltage sources, nodal analysis |
| `logic` | A named output has the required value for every input row shown | Logic gates, switches as inputs |
| `power` | A part dissipates no more than its rating | Power ratings on parts |

Exactness stays a pillar: where a goal is a single value it is matched as a rational; where real parts have tolerances the goal is a stated range.

## 12. Version 2 design: real circuits (added 2026-11-12)

This section supersedes sections 3 (model and results), 6 (level format), 7 (difficulty curve) and 11 (goal format) wherever they differ. Sections 2 (carrying and interaction rules) and 5 (movement) still hold, with "resistor" read as "part".

Ohmie is becoming a full electronics game. World 1 covers basic DC networks. Later worlds add more part families (LEDs and diodes, capacitors, switches and logic gates, AC), each as new parts, new meters and new goal quantities on the same engine and the same room format.

### 12.1 Principles

1. **Closed circuits.** A board is a complete loop or network. Nothing is measured "between A and B" any more; there are no terminal stubs.
2. **A real solver decides.** The engine solves the whole network exactly (nodal analysis with rationals) and gives every node voltage, branch current and power. The game never special-cases a level. Any arrangement that satisfies the mission wins, so most rooms have several solutions.
3. **Every slot takes any part.** Batteries and resistors are both carried and plugged in. A battery in the wrong slot, or a resistor where the source should be, gives whatever physics says: usually 0 A, sometimes a short.
4. **Meters state the mission.** Ammeters, voltmeters and ohmmeters are fixed on the board and show live readings. A mission is one short line that refers to them.
5. **Short missions.** "Draw 2 A." Never an explanation of the method. The title can hint; the mission does not teach.

### 12.2 Parts and board elements

Carried parts (`parts` in the level file):

| Kind | Value | Notes |
|---|---|---|
| `resistor` | ohms, exact | Art exists for 1/2, 1, 2, 3, 4, 6, 10. Other values use a blank resistor with the value printed. |
| `battery` | volts, exact | Ideal source. The positive end faces the slot's `from` node, which the board marks with a `+` badge when a battery is in. |

Board elements (`circuit.edges`):

| Type | Meaning |
|---|---|
| `wire` | Zero resistance. |
| `slot` | Holds one part of any kind. Empty is an open circuit. |
| `resistor` | Fixed resistor, cannot be removed. |
| `battery` | Fixed battery, plus at `from`. |
| `lamp` | A fixed resistor drawn as a bulb. Lit while its current is inside its rated range, dark below, blown above. |
| `ammeter` | Ideal. Reads the current flowing `from` → `to`. |
| `voltmeter` | Ideal. Reads V(`from`) − V(`to`). |
| `ohmmeter` | Ideal. Reads the resistance between its two nodes with all sources off (a battery counts as a wire). Shows `OL` when open. |

Circuit states the player can see: no current (wires plain), energized (wires bright), mission met (wires teal), and **short** (a source with no resistance in its loop, or conflicting sources): meters show `SHORT`, wires flash, the invalid sound plays, the door stays shut. A short does no damage in World 1.

### 12.3 Goals

```json
"mission": "Draw 2 A.",
"goal": [ { "of": "am1", "quantity": "current", "equals": "2" } ]
```

A goal is a list of conditions, all of which must hold. Each names an element, a quantity (`current`, `voltage`, `resistance`, `power`) and either `equals` (exact) or a `min`/`max` range (inclusive). The door is open while every condition holds.

The readout plaque lists each condition: its target and the live value, green when met. The mission sign shows only the mission line.

### 12.4 Level format (version 2)

```json
{
  "id": "w1_02",
  "title": "Resistance Is Futile",
  "world": "old_workshop",
  "mission": "Draw 2 A.",
  "goal": [ { "of": "am1", "quantity": "current", "equals": "2" } ],
  "tiles": ["40 characters per row, 23 rows"],
  "spawn": [96, 640],
  "door": [1180, 640],
  "parts": [
    { "id": "b1", "kind": "battery",  "value": "6", "pos": [300, 640] },
    { "id": "r1", "kind": "resistor", "value": "3", "pos": [520, 551] }
  ],
  "circuit": {
    "nodes": { "n1": [400, 300], "n2": [624, 300] },
    "edges": [
      { "id": "s1",  "type": "slot",    "from": "n1", "to": "n2" },
      { "id": "am1", "type": "ammeter", "from": "n2", "to": "n3" },
      { "id": "w1",  "type": "wire",    "from": "n3", "to": "n4" }
    ]
  }
}
```

Tiles, positions, reach and geometry rules are unchanged from section 6. Slots, fixed parts, lamps and meters are 104×72 and sit on horizontal edges whose nodes are 224 px apart where space allows (never under 128). There is one format; the old `terminals`, `socket`, `fixed`, `pickups` and `target` fields are gone, and existing levels are migrated.

### 12.5 World 1: the Old Workshop (DC basics)

Ten rooms, then three optional overtime rooms. Values below are the lead's starting point; the level designer tunes them with the solver and must report every solution.

| # | Title | Mission | Board | Parts in the room | Idea |
|---|---|---|---|---|---|
| 1 | Closing Time | Light the lamp. | One loop: a slot and a lamp | 6 V | Carry, plug in, close a loop |
| 2 | Resistance Is Futile | Draw 2 A. | One loop: two slots and an ammeter | 6 V; 2, 3, 6 Ω | I = V / R: pick the resistor |
| 3 | Ohm Sweet Ohm | Draw 3 A. | One loop: two slots and an ammeter | 3 V, 9 V; 1, 3, 6 Ω | Pick the source too. Two answers; the room makes one cheaper |
| 4 | Chain Gang | Make 6 Ω. | Two slots in series closed by an ohmmeter | 1, 2, 3, 4 Ω | Series resistors add |
| 5 | Parallel Parking | 3 A on top. 2 A below. | Fixed 6 V, two parallel branches, each a slot with its own ammeter | 2, 3, 6 Ω | Each parallel branch sees the full voltage and carries its own current |
| 6 | Divide and Conquer | Put 2 V on the meter. | Fixed 6 V, two slots in series, voltmeter across the second | 1, 2, 3, 4 Ω | Voltage divider. Two answers |
| 7 | Half and Half | Make 1 Ω. | Ohmmeter across one slot in series with two in parallel | 1/2, 1, 1, 2 Ω | Series and parallel together; reading resistance |
| 8 | Assault and Battery | Put 9 V on the meter. | Two slots in series for sources, a fixed 3 Ω with a voltmeter across it | 3 V, 6 V, 9 V | Series sources add |
| 9 | Light Duty | Light the lamp. Don't blow it. | One loop: two slots and a 2 Ω lamp rated 1 to 3/2 A | 6, 9, 12 V; 2, 4, 6, 10 Ω | A safe operating range. Many answers, some pop the bulb |
| 10 | Ohm Stretch | Draw 2 A. Put 4 V on the meter. | Source slot, a series slot, two parallel slots; ammeter on the main line, voltmeter across the pair | 6 V, 12 V; 1, 2, 3, 4, 4, 6 Ω | Everything so far, two conditions at once |

Overtime rooms (optional, reached after room 10):

| # | Title | Mission | Board | Idea |
|---|---|---|---|---|
| 11 | Watt's Up | Burn 12 W in the heater. | Source slot, series slot, a fixed 3 Ω heater | Power: P = I²R |
| 12 | A Bridge Too Far | Zero the bridge. Keep 3 A flowing. | Fixed source, a Wheatstone bridge with two fixed arms and two slots, an ammeter across the bridge and one on the supply | A balanced bridge. Not reducible by series and parallel |
| 13 | Loop Hole | Put 4 V on the meter. | Two loops sharing a resistor, a source slot in each, voltmeter on the shared resistor | Two sources, two loops |

Mission variety is deliberate: across the thirteen rooms the player lights lamps (1, 9), sets an exact current (2, 3), builds a resistance (4, 7), sets branch currents (5), sets a voltage (6, 8, 13), meets two conditions at once (5, 10, 12), hits a power (11) and zeroes a bridge (12). No more than two rooms in a row ask for the same kind of thing.

Platforming rises as before: rooms 1–3 are nearly flat with rises of at most two tiles; from room 4 sockets sit at different heights; from room 7 a small pit may appear; overtime rooms are the hardest to move through.

### 12.6 Order of work

1. Engine: DC solver, goal conditions, puzzle search (`circuit-engine`).
2. Art: battery part, blank resistor, meters, lamp, polarity badges (`asset-integrator`).
3. Game: part model, generic slots, version 2 level format, meters and lamps on the board, short state, readout for several conditions, validator, migration of the development room (`gdscript-coder`).
4. Levels: the thirteen rooms, each with solver output and a scripted route kept in `tests/` (`level-designer`).
5. QA pass (`qa-tester`).
6. After that: level select with saved progress, then the collapse replay for the ohmmeter rooms.
