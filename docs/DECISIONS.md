# Decision log

One line per decision, newest at the bottom. Made by the lead (Fable 5.2) unless noted.

| # | Date | Decision | Reason |
|---|---|---|---|
| 1 | 2026-11-11 | Godot executable is `C:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` (4.7.2 stable). | The brief's path was left as a placeholder. This is the installed copy, and the console build prints errors to the terminal. |
| 2 | 2026-11-11 | Proceed without a Godot MCP server. Run and test through the Godot command line. | No MCP is installed. The CLI gives the same run output and error logs, so it is not a blocker. |
| 3 | 2026-11-11 | Viewport 1280×720, 32 px tile grid, all art at 1:1, Nearest filtering project-wide. | Matches the asset pack's own preview. Avoids resampling illustration-derived sprites. |
| 4 | 2026-11-11 | Every level is one screen (40×22 tiles). No scrolling camera. | The whole circuit stays visible while you platform, which is what makes the puzzle readable. The background also does not tile. |
| 5 | 2026-11-11 | Resistors are placed by carrying them, one at a time, to sockets wired into the level. | Makes platforming decide the circuit. See GDD section 2 for the options rejected. |
| 6 | 2026-11-11 | Circuits are stored as a graph (nodes and edges), not a series/parallel tree. | A graph handles empty sockets, switches and bridge networks later. The tree form falls out of the reduction steps. |
| 7 | 2026-11-11 | All resistance values are exact rationals (integer numerator and denominator). No floats anywhere in circuit code. | 1/3 + 2/3 must equal exactly 1. |
| 8 | 2026-11-11 | An empty socket is an open circuit, not a wire. | Lets players leave parallel branches unused, and makes series sockets mandatory. Simple rule, rich puzzles. |
| 9 | 2026-11-11 | Tests use a small custom headless runner, not the GUT addon. | No third-party dependency. One command, exit code tells pass or fail. |
| 10 | 2026-11-11 | Levels are JSON files in `levels/`, built into a scene at runtime by one generic level scene. | Level designer can author and machine-verify levels without the editor. |
| 11 | 2026-11-11 | Levels 1–10 use only 0.5, 1, 2, 3, 4, 6 and 10 Ω. | These are the only values with resistor art. |
| 12 | 2026-11-11 | Wires are drawn with `Line2D` from level data, not wire tiles. | Wires can then light up when the circuit closes, and always match the real topology. |
| 13 | 2026-11-11 | `.import` files are committed. `.godot/` stays ignored. | Standard Godot practice. Keeps import settings (for example music looping) under version control. |
| 14 | 2026-11-11 | Subagents are pinned with `model: claude-opus-5-5` in frontmatter. Agents created mid-session are not loaded until Claude Code restarts, so implementation waits for the restart instead of using a general-purpose agent. | The workflow rule forbids implementation by agents that are not guaranteed to be Opus 5.5. |
| 15 | 2026-11-11 | Ohmie must be standing to interact. No pick-up, plug-in or put-down in mid-air. | QA showed a hop from the floor could grab a ledge resistor and fill a raised socket, skipping the platforming the level is built around. |
| 16 | 2026-11-11 | With empty hands, empty sockets are not interaction targets. | An empty socket was stealing the highlight from a loose resistor in reach, so E did nothing (BUG-001). |
| 17 | 2026-11-11 | A put-down resistor must be fully on screen, fully supported, and at least 60 px from another loose resistor. | Stops resistors hanging over ledges, sitting off screen, or stacking invisibly (BUG-002, 003, 004). |
| 18 | 2026-11-11 | Sockets and loose resistors draw in front of Ohmie; wires and the door draw behind. | Ohmie was hiding the value in the socket being used (BUG-006). |
| 19 | 2026-11-11 | The "0.5Ω" label on the supplied resistor art stays, although the readout uses fractions. | The label is baked into an original asset. A regenerated "1/2 Ω" icon is a Milestone 2 art task. |
| 20 | 2026-11-11 | Short taps do not clear the 96 px jumps in "Half and Half" (about 0.17 s of hold is needed). Kept as is. | A full jump clears with 30 px to spare, and there are no pits to punish a miss. Levels 1–4 will use lower ledges. |
| 21 | 2026-11-11 | Switch all art to the user's new pack in `assets-new/` (hand-inked 1940s cartoon style). The old pack in `assets/` is retained but no longer used. | The user supplied it as the better art and asked for it to replace the old one. |
| 22 | 2026-11-11 | Keep the 1280×720 logical viewport, 32 px grid and all level coordinates. Draw the new 2× art at scale 0.5 with Linear filtering. | No level, physics or test changes, and the art shows at full detail on a 1080p window. |
| 23 | 2026-11-11 | The ten-level curve is spread over the pack's five worlds, two levels per world, each with its own background, tileset and music. Shorty the boss is held for a later milestone. | The pack ships five themed worlds; using them as skins for the existing curve gives variety without new mechanics. |
| 24 | 2026-11-11 | Supersedes 23. This version ships World 1 (Old Workshop) only, containing all ten rooms of the curve. Worlds 2–5 and Shorty are for later versions and will bring new mechanics (switches, hazards, bridge networks). | The user set the first world as the target for now. Ten rooms in one world gives a complete first version; later worlds line up with the Milestone 3 mechanics that start at level 11. |
| 25 | 2026-11-11 | Every level has its own goal and an on-screen mission. A level file carries a `goal` object with a `type`; only `resistance` (reach an exact value, any value) exists now. The old `target` field still works. | The user wants later levels to cover voltage sources, LEDs and logic gates. A typed goal lets those arrive as new goal types without reworking the board, HUD or door. |
| 26 | 2026-11-11 | Added goal type `current` and level 2 "Ohm's Law" (6 V battery, two series sockets, goal 2 A; resistors 1, 2, decoys 4 and 6). Current is computed as V / R_eq with exact rationals. | The user asked for an Ohm's law level. A single source across A–B needs no new solver. |
| 27 | 2026-11-11 | Minimal level flow: `levels/campaign.json` orders the rooms; E after a win loads the next. | Needed so level 2 is reachable in play. Level select and saved progress wait for later. |
