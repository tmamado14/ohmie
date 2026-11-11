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
