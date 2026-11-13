# Ohmie: Circuit Adventure — Game Design Document

## 1. Pitch

Ohmie is a small striped resistor with legs, loose in an old electrical workshop. Every room has an unfinished circuit wired across the wall, some batteries and resistors lying around, and a locked door. Carry parts to the circuit's slots until the circuit does what the mission asks, and the door opens.

The long-term aim is a full electronics game. World 1 covers basic DC networks. World 2 covers basic electronics (section 11). Later worlds add more part families (switches, capacitors, logic gates, AC) as new parts, new meters and new goal quantities on the same engine and room format.

### Pillars

1. **Real circuits.** A board is a complete, closed network. The engine solves all of it exactly and the game never special-cases a room. Any arrangement that satisfies the mission wins, so most rooms have several answers.
2. **Every slot takes any part.** Batteries and resistors are both carried. A wrong placement gives whatever physics says: usually no current, sometimes a short.
3. **Meters state the mission.** Ammeters, voltmeters and ohmmeters are fixed on the board and show live readings. Lamps light, stay dark or blow.
4. **Short missions.** One line, like a note left on a bench: "Draw 2 A." The title may hint. The mission never explains the method.
5. **The whole circuit is on screen.** Every room is one screen. You plan with your eyes and execute with your feet.
6. **Platforming chooses the circuit.** Where a part lies and how hard a slot is to reach decide which answer is practical. The handy part is often the wrong one.
7. **Exact numbers.** Values are fractions, never rounded.

## 2. Core loop

1. Enter the room. Read the mission, the board and its meters.
2. Spot the parts around the room and decide which go where.
3. Fetch one, carry it to a slot, plug it in. Meters update at once.
4. Swap, pull out and try again until the mission holds.
5. The door opens. Walk through it.

### Interaction rules

- Ohmie carries at most **one** part. It floats above their head.
- Ohmie must be **standing** on a floor or platform to interact. In the air nothing is highlighted and the interact key does nothing, so a part or slot on a ledge cannot be reached by hopping underneath it.
- Ohmie must also be standing **at the target's level**: on the surface a loose part rests on, or on the surface a slot sits above. A part on a ledge cannot be taken from the floor beneath it.
- With empty hands the valid targets are loose parts and filled slots. While carrying, the valid targets are slots. The nearest valid target within 56 px of Ohmie's body centre is highlighted and shows a small name tag with its value.
- The interact key (E):
  - empty hands at a loose part: pick it up;
  - carrying at an empty slot: plug it in;
  - empty hands at a filled slot: pull the part out;
  - carrying at a filled slot: swap;
  - carrying with nothing in range: put the part down at Ohmie's feet. It always ends up fully on screen, fully supported, and clear of other loose parts, pads and hazards; it slides a little to manage that, or the action is refused.
- R restarts the room. Esc returns to the map.
- The door is open exactly while the mission holds. Break the circuit and it shuts.
- Falling off the screen or touching an enemy or hazard zaps Ohmie: a short freeze, then a respawn at the room's start. A carried part returns to where it first lay. The circuit is untouched. There are no lives.

## 3. Circuits

### Parts and board elements

Carried parts:

| Kind | Value | Notes |
|---|---|---|
| Resistor | ohms | Dedicated art for 1/2, 1, 2, 3, 4, 6 and 10 Ω; other values use a blank resistor with the value printed |
| Battery | volts | Ideal source. Its positive end faces the slot's `from` node; the slot shows + and − badges while a battery is in it |

Board elements:

| Type | Meaning |
|---|---|
| `wire` | Zero resistance |
| `slot` | Holds one part of any kind. Empty is an open circuit |
| `resistor` | Fixed resistor |
| `battery` | Fixed battery, plus at `from` |
| `lamp` | A fixed resistor drawn as a bulb. Lit while its current is inside its rated range, dark below, blown above |
| `ammeter` | Ideal. Reads the current flowing `from` → `to` |
| `voltmeter` | Ideal. Reads V(`from`) − V(`to`). Shows `---` when its two ends are not connected to each other |
| `ohmmeter` | Ideal. Reads the resistance between its ends with all sources off (a battery counts as a wire). Shows `OL` when open |

An element may carry a `label` (for example `top`), shown beside its row on the readout.

### Solving

All values are exact rationals. The engine uses modified nodal analysis with exact elimination and returns every node voltage, branch current and power. It reports one of:

| Status | Meaning | What the player sees |
|---|---|---|
| OK | A unique solution | Live readings. Wires brighten when current flows and turn teal while the mission holds |
| SHORT | A source with nothing to limit it, or sources that contradict each other | Meters read `SHORT`, wires flash, a buzz. The door stays shut. No damage |
| INDETERMINATE | Consistent but not unique, for example two ammeters in parallel | Meters read `???`. Rooms are designed so this cannot happen |

### Goals

A room's goal is a list of conditions, all of which must hold. Each names an element, a quantity (`current`, `voltage`, `resistance`, `power`) and either an exact value or an inclusive range.

The readout plaque lists each condition with its live value and target, green when met. The mission sign shows only the mission line and reads MISSION COMPLETE while the goal holds.

## 4. Movement

| Quantity | Value |
|---|---|
| Collider | 36 × 88 px, origin at the feet |
| Run speed | 240 px/s |
| Gravity | 1800 px/s² |
| Jump | 660 px/s; apex about 126 px with the key held, about 41 px on a tap |
| Variable jump | Releasing the key while rising halves upward speed |
| Coyote time, jump buffer | 0.10 s each |
| One-way platforms | Jump up through; hold down to drop through |
| Bounce pad | Launches about 224 px high whatever the jump key is doing |

Level design limits: a required jump rises at most 3 tiles (96 px) and crosses at most 4 tiles. Leave 3 tiles of headroom under solid ceilings.

## 5. Enemies and utilities

Enemies never interact with the circuit or the parts. They exist to make trips costly.

| Object | Behaviour |
|---|---|
| Bounce pad | Landing on it launches Ohmie upward, carried part and all |
| Patroller (jelly, bot) | Walks back and forth on its surface between two points |
| Floater (spark orb) | Drifts along a straight line in the air and back |
| Hazard (spikes, live wire) | Static; sits on a surface |

Hurtboxes are noticeably smaller than the sprites. World 1 uses these only in the overtime rooms.

## 6. Room format

One JSON file per room in `levels/`. A room is 40 × 23 tiles of 32 px (1280 × 720; the bottom row is half off-screen). Positions are pixels from the top-left corner.

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
    { "id": "b6", "kind": "battery",  "value": "6", "pos": [208, 640] },
    { "id": "r3", "kind": "resistor", "value": "3", "pos": [208, 551] }
  ],
  "circuit": {
    "nodes": { "a": [320, 596], "n1": [528, 596] },
    "edges": [
      { "id": "s1",  "type": "slot",    "from": "a",  "to": "n1" },
      { "id": "am1", "type": "ammeter", "from": "m1", "to": "m2" },
      { "id": "w1",  "type": "wire",    "from": "n1", "to": "n2" }
    ]
  },
  "objects": [
    { "type": "bounce_pad", "pos": [400, 640] },
    { "type": "patroller", "kind": "jelly", "pos": [600, 640], "left": 520, "right": 760, "speed": 60 }
  ]
}
```

- `spawn`, `door`, part `pos` and object `pos` are the point on the floor under the thing.
- Tile characters: `.` empty, `#` solid ground, `=` one-way platform, `B` reinforced block, `W` wall panel, `!` warning panel, `|` support beam (decoration).
- A one-way platform in row r has its standing surface at y = 32r + 7.
- Circuit edges are straight lines between nodes and must be horizontal or vertical; use extra nodes and wires for corners. Slots, fixed parts, lamps and meters are 104 × 72 and sit at the midpoint of a horizontal edge whose nodes are at least 128 px apart (224 where space allows).
- A slot must sit at standing height: its centre 44 px above a surface Ohmie can stand on.
- A goal value is a string holding an exact number: `"2"`, `"3/2"`, `"0.5"`. A range uses `"min"` and `"max"` in place of `"equals"`.
- `levels/campaign.json` lists the worlds and the order of rooms. A room whose file does not exist yet is shown as "soon".

Every room must pass the validator, which lists every arrangement of parts that satisfies the mission, and have a scripted playthrough in `tests/`.

## 7. World 1: the Old Workshop

Basic DC networks. Ten rooms, then three optional overtime rooms that open after room 10.

| # | Title | Mission | Board | Idea |
|---|---|---|---|---|
| 1 | Closing Time | Light the lamp. | One loop: a slot and a lamp | Carry, plug in, close a loop |
| 2 | Resistance Is Futile | Draw 2 A. | One loop: two slots and an ammeter | Ohm's law: pick the resistor |
| 3 | Ohm Sweet Ohm | Draw 3 A. | One loop: two slots and an ammeter | Pick the source too. Two answers; the room makes one cheaper |
| 4 | Chain Gang | Make 6 Ω. | Two slots in series on an ohmmeter | Series resistors add |
| 5 | Parallel Parking | 3 A on top. 2 A below. | A fixed battery feeding two branches, each a slot with its own ammeter | Each parallel branch carries its own current |
| 6 | Divide and Conquer | Put 2 V on the meter. | A fixed battery, two slots in series, a voltmeter across one | Voltage divider |
| 7 | Half and Half | Make 1 Ω. | An ohmmeter across one slot in series with two in parallel | Series and parallel together |
| 8 | Assault and Battery | Put 9 V on the meter. | Two slots in series for sources, a fixed resistor with a voltmeter across it | Series sources add |
| 9 | Light Duty | Light the lamp. Don't blow it. | One loop: two slots and a lamp with a narrow rating | A safe operating range. Many answers; the easy ones pop the bulb |
| 10 | Ohm Stretch | Draw 2 A. Put 4 V on the meter. | A source slot, a series slot and two parallel slots, with an ammeter and a voltmeter | Everything so far, two conditions at once |
| 11 | Watt's Up | Burn 12 W in the heater. | A source slot, a series slot and a fixed heater | Power |
| 12 | A Bridge Too Far | Zero the bridge. Keep 3 A flowing. | A Wheatstone bridge with two fixed arms and two slots | A balanced bridge, which series and parallel rules cannot reduce |
| 13 | Loop Hole | Put 4 V on the meter. | Two loops sharing a resistor, a source slot in each | Two sources at once |

Mission variety is deliberate: the player lights lamps (1, 9), sets a current (2, 3), builds a resistance (4, 7), sets branch currents (5), sets a voltage (6, 8, 13), meets two conditions at once (5, 10, 12), hits a power (11) and zeroes a bridge (12). No more than two rooms in a row ask for the same kind of reading.

Platforming rises alongside: room 1 is flat; rooms 2 and 3 each add a ledge or two that need a held jump; from room 4 slots sit at different heights and the order of trips matters; the overtime rooms add bounce pads, enemies and hazards.

## 8. Screens and flow

Splash (engine card, then the producer card) → title → world select → level select → room.

- Worlds 2–5 are shown locked. Rooms unlock in order; the overtime rooms open together after room 10. Progress is saved.
- After a room: E for the next room, Esc for the map, R to play again.

## 9. Presentation

- **Art.** A hand-inked 1940s cartoon look with watercolour texture. Art is authored at twice its on-screen size and drawn at half scale on a 1280 × 720 layout, so it stays sharp on a 1080p window.
- **Readability.** The background is dimmed slightly. Ohmie draws in front of the board; the part being carried draws in front of everything. The highlighted target's name tag keeps its value readable while Ohmie stands over it. All numerals are full-height lining figures.
- **Sound.** Jump, land, pick up, place, invalid action, mission met, door, win, bounce, hurt. One looping music track per world.

## 10. Roadmap

1. **World 1 complete:** all thirteen rooms, enemies and bounce pads in the overtime rooms, a full QA pass.
2. **Collapse replay:** after a resistance room is solved, the network simplifies on screen one series or parallel merge at a time, with the arithmetic shown.
3. **World 2 (Copper Foundry):** basic electronics, designed in section 11. Diodes, LEDs, Zeners, transistors as switches and closed-loop op-amp circuits.
4. **Later worlds:** switches and fuses, capacitors, inductors and timing (the 555), logic gates, AC and transformers, and a final encounter with Shorty the Short-Circuit Baron.
5. **Release polish:** animation cycles, a custom logotype, settings, a Windows export.

## 11. World 2: the Copper Foundry (planned, not built)

Basic electronics at DC. Ten rooms, then three overtime rooms. The art for the parts and their schematic symbols is the user's set in `assets/interactive/electronics/` (`manifest.json` gives sizes and terminals).

### Units and numbers

World 2 works in volts, milliamps and kilohms. The engine still computes in exact rationals in base units; only the text changes:

- A part value may be written with a prefix: `"1k"`, `"4.7k"`, `"220"`.
- Readings pick the prefix that gives a number from 1 to under 1000: `4.3 mA`, `2.2 kΩ`, `12 V`.
- A value whose denominator has only factors of 2 and 5 is shown as an exact decimal (`0.7 V`, `4.3 mA`). Any other value stays a fraction (`10/3 mA`). Nothing is ever rounded. World 1 rooms keep showing fractions.

### Device models

Every device is piecewise linear: it is in one of a few states, each state is a linear element, and each state has a condition that must hold. The engine tries the combinations of states and keeps the one whose conditions all hold. No combination: `ERROR`. More than one with different readings: `???` (rooms are designed so this cannot happen).

| Device | States | Fixed numbers |
|---|---|---|
| Diode (rectifier, signal) | Off: no current, voltage below the drop. On: voltage equals the drop, current flows anode to cathode | Drop 0.7 V |
| Schottky diode | Same | Drop 0.3 V |
| LED | Same as a diode. Lit while its current is inside its rated range, dark below, blown above (a blown LED still conducts, like a blown lamp) | Red 2 V, green 3 V; rated 5 to 20 mA unless the room says otherwise |
| Zener diode | Off; forward on (0.7 V); breakdown: reverse voltage equals the Zener voltage, current flows cathode to anode | Zener voltage printed on the part, for example 5.1 V |
| NPN and PNP transistor | Cutoff: no currents. Active: base-emitter 0.7 V, collector current = β × base current, collector-emitter above 0.2 V. Saturated: base-emitter 0.7 V, collector-emitter 0.2 V, collector current at most β × base current. PNP is the same with every polarity reversed | β = 100 |
| Op-amp | Linear: both inputs at the same voltage, output between the rails. High: output at the positive rail, + input above − input. Low: output at the negative rail, + input below − input. The inputs draw no current | Rails ±12 V unless the room says otherwise |

### Board and parts

- **Two-terminal parts** (diodes, LEDs, Zeners) are carried and go in the ordinary slots, next to resistors and batteries. Every slot still takes any two-terminal part.
- **Direction.** A diode's anode faces the slot's `from` node, as a battery's plus does. The slot shows a small arrow badge while a diode is in it. There is no flip action: which slot a diode goes in is the puzzle, and rooms offer slots facing both ways.
- **Fixed devices.** A transistor or op-amp fixed to the board is drawn with its schematic symbol on a board plate, with a wire meeting each labelled terminal. Op-amps are always fixed; the player chooses the resistors around them. The supply rails are part of the op-amp element and are printed on its plate, not wired.
- **Device bays.** A bay is a three-terminal slot (base, collector, emitter). It takes any three-terminal part: NPN, PNP, and later the MOSFET. Ohmie carries the illustrated part; a filled bay shows the part's symbol. A wrong device gives whatever physics says.
- **New goal words.** A condition can name an LED like a lamp (`lit`), and a voltmeter can read an op-amp output or a transistor terminal like any node.

### Rooms

| # | Title | Mission | Board | Idea |
|---|---|---|---|---|
| 1 | One Way Street | Light the lamp. | A fixed battery, a lamp and two slots facing opposite ways on parallel paths; one diode and a few resistors | A diode conducts one way only |
| 2 | Drop It | Put 4.3 V on the meter. | A fixed 5 V battery, a slot, a fixed resistor with a voltmeter across it; a silicon diode, a Schottky and decoy resistors | The forward drop |
| 3 | Glow Up | Light the LED. Don't blow it. | A fixed battery, an LED slot and a series slot | The current-limiting resistor |
| 4 | Zener Garden | Hold 5.1 V on the meter. | A fixed 12 V battery, a series slot, a slot across a fixed load with a voltmeter | A Zener in reverse holds its voltage; forwards it is only a diode |
| 5 | Base Camp | Light the lamp. Keep the base under 1 mA. | A fixed NPN with a lamp in its collector, a base slot, ammeters on base and collector | A small current switches a large one |
| 6 | Opposites Attract | Light both lamps. | Two bays, one switching the low side of its lamp and one the high side; an NPN and a PNP to carry | PNP is NPN with everything reversed |
| 7 | Compare and Contrast | Swing the output high. | An op-amp with no feedback, a fixed reference on one input, a two-slot divider on the other, a voltmeter on the output | The comparator |
| 8 | Flip the Script | Put −6 V on the meter. | An inverting amplifier with a fixed input voltage, an input slot and a feedback slot | Inverting gain: −Rf / Rin |
| 9 | Gain Train | Put 6 V on the meter. | A non-inverting amplifier with a fixed input voltage, a feedback slot and a ground slot | Non-inverting gain: 1 + Rf / Rg. A wire for Rf makes a follower |
| 10 | Sum of Its Parts | Put −9 V on the meter. | A summing amplifier with two fixed input voltages, an input slot for each and a feedback slot | Weighted sums; several answers, the room makes most of them awkward |
| 11 | Bias for Action | Put 6 V on the collector. | A fixed NPN on a 12 V supply with a base slot and a collector slot | Biasing in the active region, the first step to an amplifier |
| 12 | Difference of Opinion | Put 4 V on the meter. | A difference amplifier with four slots | Matching ratios |
| 13 | Full Bridge Ahead | Light the LED, whichever way the battery goes. | Four diode slots in a bridge feeding an LED, and a source slot whose direction the room does not let you choose | The bridge rectifier |

Rooms 11 to 13 are overtime. Ideas held in reserve: a red and a green LED steered by the battery's direction, a fuse that must survive, a switch Ohmie flips, the MOSFET as a switch, and a photoresistor under a light.

Left for later worlds because they need time or AC: capacitors, inductors, the transformer and the 555. The AND gate waits for a logic world.

### Build order

1. Engine: the piecewise-linear framework with diodes, LEDs and Zeners; then the transistor; then the op-amp; prefixed and decimal reading text; the puzzle search over the new parts.
2. Assets: document and import the electronics set; generate what is missing (a blown LED, the arrow badge, board plates for fixed devices, the Copper Foundry door's open state).
3. Game: new part kinds and their slot behaviour, LED states, fixed devices, the bay, the Copper Foundry theme, unlocking World 2 after World 1's room 10.
4. Rooms 1 to 4 (diodes) first, as a playable slice; then 5 and 6; then 7 to 10; then overtime.
5. QA after each group.
