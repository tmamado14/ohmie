# Bug list

Owned by `qa-tester`. One entry per bug. Severity: blocker, major, minor, cosmetic.
Each "Expected" cites the GDD section. "Evidence" names a failing check in
`tests/play_break.gd` (run: `godot --headless --path . --fixed-fps 60 --script res://tests/play_break.gd`)
or a screenshot from `tools/qa_screenshots.gd` in `tests/screenshots/qa/`.

## QA pass 1: vertical slice (2026-11-11)

Baseline: unit tests 127/127, play_movement 11/11, play_slice 30/30, play_slice_01 25/25,
boot check clean (no ERROR or WARNING lines), `validate_level.gd` OK for both levels (1 solution each).
No blocker or major bugs found. slice_01 can be completed start to finish.

| ID | Title | Severity | Status |
|---|---|---|---|
| BUG-001 | An empty socket takes the interact target from a loose resistor in reach | minor | Fixed |
| BUG-002 | A resistor can be put down hanging in mid-air past a platform's end or over the pit | minor | Fixed |
| BUG-003 | A resistor put down at the screen edge is partly off screen | cosmetic | Fixed |
| BUG-004 | A resistor sent home after a fall can land exactly on another loose resistor | minor | Fixed |
| BUG-005 | "Press R to play again" is drawn over socket s2 on the level-complete screen | cosmetic | Fixed |
| BUG-006 | Ohmie hides the value in a socket or on a pickup while standing at it | cosmetic | Fixed |
| BUG-007 | 1/2 Ω is labelled "0.5Ω" on the resistor but fractions everywhere else | cosmetic | Won't fix |
| BUG-008 | Putting a resistor down in mid-air is refused, which GDD section 2 does not allow for | minor | Resolved by design change |

---

### BUG-001: An empty socket takes the interact target from a loose resistor in reach

- **Severity:** minor
- **Steps (slice_01):**
  1. Walk to the floor 1 Ω (x ≈ 1008) and press E to pick it up.
  2. Walk left to x ≈ 670, just left of the bottom socket s3, before s3 highlights, and press E. The resistor is put down at x = 670.
  3. Walk right until Ohmie stands between the resistor and s3 (x ≈ 702 to 724).
  4. Press E.
- **Expected:** GDD section 2: "Empty hands at a loose resistor: pick it up." The resistor is in reach (43.7 px at x = 712; reach is 56 px), so it should be highlighted and picked up. An empty socket can do nothing for empty hands, so it should not be a target.
- **Actual:** The empty socket s3 is highlighted (24 px away, so nearer), and E plays the invalid sound. Nothing is picked up. With empty hands, every empty socket is highlighted whenever it is the nearest object, which suggests an action that does not exist.
- **Evidence:** FAIL `A3 empty hands with a loose resistor in reach: the resistor is the highlighted target, not the empty socket` (target socket s3) and FAIL `A3 interact with empty hands there picks up the loose resistor (picked 0, invalid 1)`. Screenshot `tests/screenshots/qa/qa_10_empty_socket_steals_target.png` shows s3 highlighted while the 1 Ω sits beside Ohmie.
- **Cause (for the fixer):** `PlayerCarry._find_target()` treats every socket as a candidate. `CircuitSocket` does not override `is_available()`, and with empty hands an empty socket is never usable.
- **Status: Fixed.** `Interactable.can_interact(carrying)` decides the valid targets: with empty hands, loose resistors and filled sockets; while carrying, sockets only (empty or filled). `PlayerCarry._find_target()` picks the nearest valid one in reach. Both A3 checks pass.

### BUG-002: A resistor can be put down hanging in mid-air past a platform's end or over the pit

- **Severity:** minor
- **Steps (slice_01):**
  1. Pick up the 1/2 Ω on the left ledge (x = 272).
  2. Walk right to the very end of the ledge. Ohmie still stands on it at x = 368 (the ledge ends at x = 352).
  3. Press E.
- **Same in dev_room:** carry the 4 Ω to the lip of the pit, walk right until just before falling (x = 976; the pit starts at x = 960), and press E.
- **Expected:** GDD section 2: "put the resistor down at Ohmie's feet", meaning a resistor lying on something. A put-down resistor should rest on a tile, for example snapped back onto the edge, or the put-down refused.
- **Actual:** The resistor is placed at Ohmie's origin, 16 px past the last tile. It is drawn with half its body over empty air (left ledge) or over the pit (dev_room). It can still be picked up, so nothing is lost, but it looks broken.
- **Evidence:** FAIL `C1 a put-down resistor rests on a tile (put down at (368.0, 455.0); ledge ends at x=352, so it floats in mid-air)` and FAIL `C5 a resistor put down at the pit's lip rests on ground (at (976.0, 640.0); the pit starts at x=960)`. Screenshots `qa_08_put_down_edge_cases.png` (0.5 Ω hanging off the left ledge) and `qa_12_dev_room_pit_lip.png` (4 Ω over the pit edge).
- **Status: Fixed.** A put-down resistor has an 80 px footprint (floor point ± 40). `ResistorPlacement` (`src/objects/resistor_placement.gd`) requires support under the floor point and under both ends, at the surface Ohmie stands on, found by ray queries against physics layers 1 and 2. If Ohmie's x fails, the resistor slides to the nearest valid x within 64 px; if there is none, the put-down is invalid and Ohmie keeps carrying. The left-ledge case lands at x = 312 (footprint 272..352), the pit-lip case at x = 920 (footprint 880..960). C1 and C5 pass, plus new checks that the whole footprint is supported.

### BUG-003: A resistor put down at the screen edge is partly off screen

- **Severity:** cosmetic
- **Steps (slice_01):**
  1. Carry any resistor.
  2. Walk left until Ohmie stops at the screen edge (x = 18) and press E.
  3. Repeat at the right edge (x = 1262, to the right of the door).
- **Expected:** GDD section 1, pillar 1, and section 6: everything is on one 1280 px screen. A loose resistor should be fully visible.
- **Actual:** The 96 px icon spans x = -30..66 (left edge) or 1214..1310 (right edge), so about 30 px of it is cut off. It can still be picked up again.
- **Evidence:** FAIL `C4 a resistor put down at the left edge is fully on screen (icon spans x -30..66)` and FAIL `C4 ... right edge ... (icon spans x 1214..1310)`. Screenshot `qa_08_put_down_edge_cases.png` (1 Ω clipped at the left edge).
- **Status: Fixed.** The floor point must lie within x = 48..1232, so the 96 px icon is fully on screen. A put-down at the edge slides inward, to 48 or 1232. Both C4 checks pass.

### BUG-004: A resistor sent home after a fall can land exactly on another loose resistor

- **Severity:** minor
- **Steps (dev_room):**
  1. Pick up r1 (2 Ω on the floor at x = 200) and plug it into the bottom socket (stand on the floor at x ≈ 640).
  2. Jump onto the lower platform and pick up r2 (2 Ω at x = 384).
  3. Drop to the floor, walk to x = 200 (r1's home) and press E to put r2 down. This is allowed because r1 is in the socket.
  4. Walk to the socket and press E to pull r1 out.
  5. Walk right into the pit.
- **Expected:** GDD section 2: "A carried resistor returns to where it originally lay." `PlayerCarry` also promises that "resistors never stack". The returned resistor should not cover another one completely; for example, the spot should be checked and the resistor nudged aside.
- **Actual:** r1 is placed at (200, 640), exactly on top of r2. One icon fully hides the other, so a player sees one resistor where there are two. Both can still be picked up one after the other, so nothing is lost.
- **Evidence:** FAIL `D4 after the fall r1 goes home without landing on r2 (r1 (200.0, 640.0), r2 (200.0, 640.0), 0.0 px apart)`. Conservation still holds (PASS `D4 conservation after the fall`).
- **Note:** slice_01 has no pit, so this needs a level with a pit. The same applies to every future level that has one.
- **Status: Fixed.** If another loose resistor lies within 60 px of the home position, the returning resistor goes to the nearest valid spot along the same surface at offsets ±64, ±128, … px (on screen, fully supported, at least 60 px from every loose resistor). In D4, r1 lands at (264, 640). The same 60 px spacing applies to a put-down, which slides away from a nearby loose resistor (C2: 60 px). This slide replaces the old rule that refused a put-down with a loose resistor in reach.

### BUG-005: "Press R to play again" is drawn over socket s2 on the level-complete screen

- **Severity:** cosmetic
- **Steps (slice_01):** solve the level and walk into the door.
- **Expected:** GDD section 8: the HUD stays readable. Victory text should not sit on top of the board.
- **Actual:** The "Press R to play again" label (screen-centred, y ≈ 376..412) overlaps the top edge of socket s2 (frame y ≈ 375..447). The word "again" is drawn over the socket and its resistor, with no backing panel, on the busy background.
- **Evidence:** `tests/screenshots/qa/qa_06_level_complete.png`.
- **Status: Fixed.** The level-complete screen adds a full-screen dim (black at 55% alpha, HUD node `VictoryDim`). It draws above the game world, the title and the hint, and below the readout frame and the banner, so both banner lines are readable.

### BUG-006: Ohmie hides the value in a socket or on a pickup while standing at it

- **Severity:** cosmetic
- **Steps (slice_01):** stand on the S1 platform at s1 after plugging in the 1/2 Ω. Or stand on the floor at s3 with something in it, or stand next to the 2 Ω decoy so it highlights.
- **Expected:** GDD section 1, pillar 1 ("plan with your eyes") and section 8: the board stays readable. The value of the socket or pickup you are about to use should be visible.
- **Actual:** The player is drawn in front of the board and the pickups, and the sockets are exactly where Ohmie stands to use them. The socket's resistor and its value label are almost fully covered (s1, s2, s3), and a highlighted pickup's label is half covered. The HUD readout still updates.
- **Evidence:** `qa_02_carry_at_highlighted_socket.png`, `qa_04_two_sockets_3_2.png` (s2 hidden behind Ohmie), `qa_09_pickup_highlight.png` (2 Ω label half covered), `qa_11_ohmie_at_floor_socket.png` (s3 contents hidden).
- **Status: Fixed.** Sockets (with the resistor inside) and loose resistors with their highlight frames draw in front of Ohmie (`z_index = 1`). The carried resistor draws in front of everything in the world (`z_index = 2`). Wires, terminals, junction dots and the door stay behind Ohmie. Fixed resistors are unchanged (no current level has one).

### BUG-007: 1/2 Ω is labelled "0.5Ω" on the resistor but fractions everywhere else

- **Severity:** cosmetic
- **Steps:** start slice_01 and look at the resistor on the left ledge. Plug it in next to a 1 Ω.
- **Expected:** GDD section 1, pillar 3 ("Values are fractions, never rounded"), and section 3, Results: values are shown as integers or fractions (`3/2 Ω`).
- **Actual:** The resistor art has "0.5Ω" baked into it, while the readout shows fractions ("3/2 Ω"). Both the pickup and the socket icon show 0.5. A player adds 0.5 + 1 and reads 3/2.
- **Evidence:** `qa_01_initial.png` (ledge resistor "0.5Ω"), `qa_04_two_sockets_3_2.png` (socket "0.5Ω", readout "3/2 Ω").
- **Status: Won't fix.** The "0.5Ω" label is baked into the supplied art (lead's decision).

### BUG-008: Putting a resistor down in mid-air is refused, which GDD section 2 does not allow for

- **Severity:** minor (a mismatch between spec and code. Either side may be right, but they must agree.)
- **Steps (slice_01):** carry any resistor to an open stretch of floor (for example x = 1100), jump, and press E in mid-air. Pressing E on the same frame as jump does the same.
- **Expected:** GDD section 2: "Carrying with nothing in range: put the resistor down at Ohmie's feet." No floor condition is stated.
- **Actual:** The invalid sound plays and Ohmie keeps the resistor (`PlayerCarry` only puts down when `body.is_on_floor()`). This is sensible behaviour, because it avoids resistors hanging in the air, but it is not in the GDD or `DECISIONS.md`.
- **Evidence:** `INFO B3 interact while airborne carrying with nothing in reach (airborne true): dropped 0, invalid 1, still carrying true` and `INFO B4 jump + interact on the same frame, carrying: dropped 0, invalid 1`.
- **Suggested resolution:** keep the code and add "on the floor only" to GDD section 2.
- **Status: Resolved by design change.** New rule: Ohmie must stand on a floor or platform to interact at all. Every `interact` press in mid-air is invalid (invalid sound, nothing changes), and nothing is highlighted in mid-air. B3 and B4 are now checks, and B5 to B7 cover the other mid-air cases. GDD section 2 does not state the rule yet (lead).

---

## Observations and suggestions (not bugs)

1. **Mid-air interaction skips the intended route.** Interact works in mid-air, which the GDD allows, so two platforming steps of slice_01 can be skipped:
   - Standing on the floor under the left ledge (x = 272) and jumping brings Ohmie's body centre 46.4 px from the 1/2 Ω on the ledge, inside the 56 px reach, so it can be grabbed in mid-air without ever reaching the ledge (`INFO B1 ... grabbed in mid-air: true`).
   - Socket s1 can be filled by hopping from the floor under it, so the S1 platform is not needed (`INFO B2 ... true`).

   The level is still solved the same way, but pillar 2 ("platforming chooses the circuit") is weaker. The level designer may want pickups on ledges 185 px up to sit more than about 132 px above the floor below, or interaction may need to be limited to standing on a surface.

   **Resolved:** interaction now needs Ohmie on a surface (see BUG-008). B1 and B2 are now checks that both shortcuts fail.
2. **Jump numbers.** The full jump apex is 126.6 px, not the "about 121 px" in GDD section 5 (discrete integration). Variable jump works: holding jump for 1 / 3 / 6 / 12 frames gives an apex of 41.3 / 56.6 / 76.6 / 106.6 px. Every 96 px jump on the route needs about 10 frames (0.17 s) of hold, and a short tap fails all of them. That is fine on a keyboard, but a hint line such as "hold Space to jump higher" would help new players. Full jumps clear each landing surface by 30.6 px (37.6 px for floor to S1).
3. **Interaction windows** are comfortable: each pickup can be used from a 109 px wide standing range and each socket from 113 px (see `tools/measure_reach.gd`).
4. **Overlapping loose resistors.** The nearest allowed put-down beside another resistor is 55 px away, so the two 96 px icons overlap by about 41 px. The value labels stay readable (`qa_08_put_down_edge_cases.png`). A put-down right beside s3 also overlaps the socket frame (`qa_10`).
5. **Standing in the doorway when the door opens** completes the level at once. That is consistent with "walking into the open door", and not reachable in either current level, because no socket can be used from the doorway (`INFO E3`).
6. **The victory banner has "R EQ = 1 Ω" baked into the art.** It will be wrong for any future level whose target is not 1 Ω. In the victory pose Ohmie stands at x = 1160, off-centre in the door at x = 1180.
7. **The carried icon is drawn at 0.75 scale**, so its value label is about 8 px tall. It is readable, but only just (`qa_02`).
8. **The dev_room pit reads as a dark wall, not a hole** (`qa_12`). Dev only.
9. **The unit test runner prints 98 ERROR lines** from deliberate negative tests (`Rational.parse: 'abc' is not a number`, and so on). The rule "read the output for ERROR" is then noisy, and a real error is easy to miss. Suggest muting `push_error` during expected-error tests, or prefixing their output.
10. **Godot rewrites `project.godot`** on `--import` or on a windowed run. It drops `window/stretch/aspect="keep"` (the default value) and moves `default_texture_filter`. There is no change in behaviour. QA restored the committed file. Committing the normalised form once would stop the churn.
   **Resolved:** the committed `project.godot` is already in the normalised form. Two `--import` runs and the windowed screenshot runs left it unchanged.
11. **For test writers:** a scripted `Input.action_press` or `action_release` takes effect on the next physics frame. Calling `Input.action_release` on every frame stops `is_action_just_released` from ever firing, which hides variable jump. Release once.
12. **Everything else that was tried held up:** 60 to 100 rapid interact presses at pickups and sockets, 20 swaps, 50 pull-and-replug cycles (door opened and closed exactly 50 times each), all 73 socket assignments (text, colour, wires and door all correct, door open only for the two exact 1 Ω assignments), pit falls (once per fall, carried resistor home, circuit untouched), restart mid-jump, mid-carry, in the victory state and 6 times in a row or twice in one frame (exact initial state, one room, no errors), lockout after completion, entering the door while carrying the decoy, left and right held together, jump held, down held, the screen edges, the top of the screen, coyote time and the jump buffer.
