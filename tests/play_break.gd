extends SceneTree
## Adversarial scripted QA test: tries to break the rooms w1_07 ("Half and Half")
## and dev_room; section L checks the same-level rule and the name tag in w1_05.
##
## Drives Ohmie through the input map (move_left, move_right, move_down, jump,
## interact, restart). To reach a test position quickly it sometimes moves
## Ohmie with Player.respawn(at) ("teleport"); every interaction itself still
## goes through the `interact` action. The HUD sweep (section J) sets slot
## contents through the socket API to cover all 73 assignments.
##
## Invariants checked on every frame of the spam tests:
##   conservation: every part is in exactly one state (loose, carried or
##     plugged), loose <=> visible, and the level's part count never changes;
##   readout: the HUD reading and the ohmmeter on the board equal what DcSolver
##     gives for the current slot contents (LevelGoal.reading_text and
##     MeterText.reading), and the door is open exactly while LevelGoal.is_met.
##
## A check that exposes a real bug FAILS (and stays failing until the bug is
## fixed). INFO lines record behaviour that is not pass/fail.
## Every ERROR / WARNING the engine logs is counted by a Logger.
##
## Usage (exit code 0 = all checks passed; --fixed-fps 60 makes it fast):
##   godot --headless --path . --fixed-fps 60 --script res://tests/play_break.gd


## Counts engine errors and warnings (push_error, push_warning, script errors).
class ErrorCounter extends Logger:
	var _mutex: Mutex = Mutex.new()
	var _lines: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		_lines.append("type %d: %s %s (%s:%d %s)" % [error_type, code, rationale, file, line, function])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func count() -> int:
		_mutex.lock()
		var n: int = _lines.size()
		_mutex.unlock()
		return n

	func lines_since(start: int) -> PackedStringArray:
		_mutex.lock()
		var out: PackedStringArray = _lines.slice(start)
		_mutex.unlock()
		return out


const MAIN_SCENE: String = "res://scenes/main.tscn"
const HALF_AND_HALF: String = "res://levels/w1_07.json"
const DEV: String = "res://levels/dev_room.json"
const PARALLEL_PARKING: String = "res://levels/w1_05.json"
const ROOM_PATH: NodePath = ^"Room"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]
const OHM: String = " Ω"

## w1_07 layout facts (feet positions; one-way surfaces sit 7 px below the tile top).
const FLOOR_Y: float = 640.0
const LEFT_LEDGE_Y: float = 455.0  # row 14, x 192..352
const LEFT_LEDGE_RIGHT_X: float = 352.0
const S1_PLATFORM_Y: float = 551.0  # row 17, x 416..608
const S2_PLATFORM_Y: float = 455.0  # row 14, x 640..832
const RIGHT_LEDGE_Y: float = 359.0  # row 11, x 896..1056
const HALF_POS: Vector2 = Vector2(272, 455)
const TWO_POS: Vector2 = Vector2(272, 640)
const ONE_FLOOR_POS: Vector2 = Vector2(1008, 640)
const ONE_LEDGE_POS: Vector2 = Vector2(976, 359)
const AT_S1: Vector2 = Vector2(512, 551)
const AT_S2: Vector2 = Vector2(736, 455)
const AT_S3: Vector2 = Vector2(736, 640)
const DOOR_X: float = 1180.0
const OPEN_FLOOR_X: float = 1100.0  # floor spot with nothing in reach and nothing above

## dev_room layout facts.
const DEV_R1_HOME: Vector2 = Vector2(200, 640)
const DEV_R2_HOME: Vector2 = Vector2(384, 551)
const DEV_R3_HOME: Vector2 = Vector2(880, 640)
const DEV_AT_LOWER_SOCKET: Vector2 = Vector2(640, 640)
const DEV_PIT_LEFT_X: float = 960.0

## w1_05 layout facts: the 2 Ω lies on the low ledge (row 18, x 224..384).
const W5_R2_POS: Vector2 = Vector2(288, 583)
const W5_FLOOR_UNDER_R2: Vector2 = Vector2(288, 640)

const SCREEN_WIDTH: float = 1280.0
const ICON_HALF_WIDTH: float = 48.0
## A loose resistor's footprint is floor point x +- this (lead's decision for BUG-002).
const FOOTPRINT_HALF_WIDTH: float = 40.0
## Two loose resistors at the same level never lie closer than this (BUG-004, QA-14).
const MIN_SPACING: float = 100.0
## A loose part's floor point keeps this far (x) from a slot at its level: the
## slot's 120 px blocked area plus the 80 px footprint, halved (QA-06).
const SLOT_CLEARANCE: float = 100.0
const LEFT_LEDGE_LEFT_X: float = 192.0
const REACH: float = 56.0
const PLAYER_HEIGHT: float = 88.0
const POSITION_TOLERANCE: float = 3.0
const SETTLE_FRAMES: int = 20
const MAX_WALK_FRAMES: int = 600
const MAX_AIR_FRAMES: int = 180

var _passed: int = 0
var _failed: int = 0
var _logger: ErrorCounter = null
var _packed: PackedScene = null

var _room: Room = null
var _player: Player = null
var _carry: PlayerCarry = null
var _hud: Hud = null
var _door: ExitDoor = null
var _board: CircuitBoard = null
var _tiles: TileMapLayer = null
var _part_count: int = 0

var _picked: int = 0
var _placed: int = 0
var _removed: int = 0
var _swapped: int = 0
var _dropped: int = 0
var _invalid: int = 0
var _fell: int = 0
var _completed: int = 0
var _jumped: int = 0
var _opened: int = 0
var _closed: int = 0

var _air_min_distance: float = INF
var _air_frames: int = 0
var _air_highlight_frames: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_logger = ErrorCounter.new()
	OS.add_logger(_logger)
	_packed = load(MAIN_SCENE) as PackedScene
	if _packed == null:
		_check(false, "main scene loads")
	else:
		await _run_all()
	_release_all()
	var errors: PackedStringArray = _logger.lines_since(0)
	_check(errors.is_empty(), "no ERROR or WARNING was logged during the whole run (%d logged)" % errors.size())
	for i: int in mini(errors.size(), 10):
		print("      " + errors[i])
	OS.remove_logger(_logger)
	print("")
	print("play_break: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _run_all() -> void:
	await _section_a_interact_spam()
	await _section_b_mid_air()
	await _section_c_drop_spots()
	await _section_d_pit()
	await _section_e_completion()
	await _section_g_restart()
	await _section_h_swap_and_replug()
	await _section_i_movement_abuse()
	await _section_j_readout_sweep()
	await _section_k_coyote_and_buffer()
	await _section_l_same_level()


# --- A: interact spam ------------------------------------------------------------

func _section_a_interact_spam() -> void:
	print("-- A: interact spam")
	if not await _open_level(HALF_AND_HALF):
		return
	var one_floor: PartPickup = _part("r_one_floor")
	var s3: CircuitSocket = _socket("s3")

	await _teleport(ONE_FLOOR_POS)
	_reset_counters()
	var bad: int = await _spam_interact(60)
	_check(bad == 0, "A1 60 interact presses on alternate frames next to the floor 1 Ω: invariants hold every frame (%d bad frames)" % bad)
	_check(_picked == 30 and _dropped == 30 and _invalid == 0 and one_floor.is_loose(),
			"A1 the presses alternate pick up / put down exactly (picked %d, dropped %d, invalid %d)" % [_picked, _dropped, _invalid])

	await _interact()  # pick it up again
	await _teleport(AT_S3)
	_reset_counters()
	bad = await _spam_interact(60)
	_check(bad == 0, "A2 60 interact presses at socket s3 while carrying: invariants hold every frame (%d bad frames)" % bad)
	_check(_placed == 30 and _removed == 30 and _invalid == 0 and _carry.get_carried() == one_floor and not s3.is_filled(),
			"A2 the presses alternate plug in / pull out exactly (placed %d, removed %d, invalid %d)" % [_placed, _removed, _invalid])

	# Put the 1 ohm down just outside the socket's reach, then stand between the two.
	await _teleport(Vector2(670, FLOOR_Y))
	_check(_carry.get_target() == null, "A3 at x=670 nothing is in reach (target %s)" % _describe(_carry.get_target()))
	await _interact()
	# A put-down keeps clear of a slot's frame: it slides left until the part's
	# footprint is SLOT_CLEARANCE from the slot's centre.
	var clear_x: float = s3.global_position.x - SLOT_CLEARANCE
	_check(one_floor.is_loose() and absf(one_floor.global_position.x - clear_x) <= POSITION_TOLERANCE
			and absf(one_floor.global_position.y - FLOOR_Y) <= POSITION_TOLERANCE,
			"A3 the 1 Ω put down at x=670 slides clear of the empty socket s3's frame, to x=%.0f (at %s)" % [clear_x, one_floor.global_position])
	var between_x: float = (one_floor.global_position.x + s3.global_position.x) * 0.5
	await _teleport(Vector2(between_x, FLOOR_Y))
	var pickup_distance: float = _body_centre().distance_to(one_floor.get_interaction_point())
	var socket_distance: float = _body_centre().distance_to(s3.get_interaction_point())
	_info("A3 empty hands at x=%.0f: loose 1 Ω at %.1f px, empty socket s3 at %.1f px (reach 56)" % [between_x, pickup_distance, socket_distance])
	_check(_carry.get_target() == one_floor,
			"A3 empty hands with a loose resistor in reach: the resistor is the highlighted target, not the empty socket (GDD 2: empty hands at a loose resistor picks it up) (target %s)" % _describe(_carry.get_target()))
	_reset_counters()
	await _interact()
	_check(_carry.get_carried() == one_floor,
			"A3 interact with empty hands there picks up the loose resistor (picked %d, invalid %d)" % [_picked, _invalid])
	bad = await _spam_interact(40)
	_check(bad == 0, "A3 40 more presses between the loose resistor and the socket: invariants hold every frame (%d bad frames)" % bad)


# --- B: interaction in mid-air (Ohmie must stand on a surface to interact) -----------

func _section_b_mid_air() -> void:
	print("-- B: interact in mid-air")
	if not await _open_level(HALF_AND_HALF):
		return
	var half: PartPickup = _part("r_half")
	var two: PartPickup = _part("r_two")
	var s1: CircuitSocket = _socket("s1")
	var s3: CircuitSocket = _socket("s3")

	# B1: from the floor under the left ledge, jump and try to grab the 1/2 ohm lying on the ledge.
	await _teleport(TWO_POS)
	_check(_carry.get_target() == two, "B1 standing on the floor at x=272 targets the 2 Ω decoy")
	_reset_counters()
	var before: String = _contents_text()
	var presses: int = await _jump_pressing_near(half.get_interaction_point())
	_info("B1 jumping from the floor at x=272: closest approach to the 1/2 Ω on the left ledge %.1f px (reach 56); %d interact presses in reach" % [_air_min_distance, presses])
	_check(presses > 0 and _invalid == presses and _picked == 0 and not _carry.is_carrying()
			and half.is_loose() and _contents_text() == before,
			"B1 the 1/2 Ω on the left ledge cannot be picked up by jumping from the floor below it (presses %d, invalid %d, picked %d)" % [presses, _invalid, _picked])
	_check(_air_frames > 0 and _air_highlight_frames == 0,
			"B1 nothing is highlighted while airborne (%d of %d airborne frames had a highlight)" % [_air_highlight_frames, _air_frames])
	_check(_conservation_problem().is_empty(), "B1 conservation after a mid-air grab attempt (%s)" % _conservation_problem())

	# B2: carrying, jump straight up from the floor under s1 and try to plug in mid-air.
	await _teleport(HALF_POS)
	await _interact()
	_check(_carry.get_carried() == half, "B2 setup: carrying the 1/2 Ω")
	await _teleport(Vector2(AT_S1.x, FLOOR_Y))
	_check(_carry.get_target() == null, "B2 on the floor under s1 the socket is out of reach (%s)" % _describe(_carry.get_target()))
	_reset_counters()
	before = _contents_text()
	presses = await _jump_pressing_near(s1.get_interaction_point())
	_check(presses > 0 and _invalid == presses and _placed == 0 and not s1.is_filled()
			and _carry.get_carried() == half and _contents_text() == before,
			"B2 socket s1 cannot be filled by jumping from the floor below it (presses %d, invalid %d, placed %d; landed at %s)" % [presses, _invalid, _placed, _player.position])
	_check(_air_frames > 0 and _air_highlight_frames == 0,
			"B2 nothing is highlighted while airborne (%d of %d airborne frames had a highlight)" % [_air_highlight_frames, _air_frames])
	_check(_conservation_problem().is_empty() and _readout_problem().is_empty(),
			"B2 conservation and readout after a mid-air plug-in attempt")

	# B3: put down while airborne with nothing in reach.
	await _teleport(Vector2(OPEN_FLOOR_X, FLOOR_Y))
	_reset_counters()
	Input.action_press("jump")
	await _wait_physics(15)
	var airborne: bool = not _player.is_on_floor()
	await _interact()
	Input.action_release("jump")
	await _wait_physics(60)
	_check(airborne and _dropped == 0 and _invalid == 1 and _carry.get_carried() == half,
			"B3 interact while airborne carrying with nothing in reach is invalid (airborne %s): dropped %d, invalid %d, still carrying %s" % [airborne, _dropped, _invalid, _carry.is_carrying()])
	_check(_conservation_problem().is_empty(), "B3 conservation after an airborne drop attempt (%s)" % _conservation_problem())

	# B4: interact on the same frame as the jump press.
	_reset_counters()
	Input.action_press("jump")
	Input.action_press("interact")
	await _wait_physics(1)
	Input.action_release("interact")
	await _wait_physics(1)
	Input.action_release("jump")
	await _land()
	_check(_dropped == 0 and _invalid == 1 and _carry.get_carried() == half,
			"B4 jump + interact on the same frame, carrying: invalid (dropped %d, invalid %d)" % [_dropped, _invalid])
	_check(_conservation_problem().is_empty(), "B4 conservation after jump + interact on one frame")

	# B5: carrying, airborne next to the empty socket s3.
	await _teleport(AT_S3)
	_check(_carry.get_target() == s3 and not s3.is_filled(), "B5 setup: carrying, standing at the empty s3, which is highlighted")
	_reset_counters()
	before = _contents_text()
	presses = await _jump_pressing_near(s3.get_interaction_point())
	_check(presses > 0 and _invalid == presses and _placed == 0 and not s3.is_filled()
			and _carry.get_carried() == half and _contents_text() == before,
			"B5 interact while airborne and carrying next to an empty socket is invalid and changes nothing (presses %d, invalid %d, placed %d)" % [presses, _invalid, _placed])
	_check(_air_frames > 0 and _air_highlight_frames == 0,
			"B5 nothing is highlighted while airborne (%d of %d airborne frames had a highlight)" % [_air_highlight_frames, _air_frames])

	# B6: empty hands, airborne next to the filled socket s3.
	await _teleport(AT_S3)
	await _interact()
	_check(s3.get_pickup() == half and not _carry.is_carrying(), "B6 setup: the 1/2 Ω plugged into s3 from the floor")
	_check(_carry.get_target() == s3, "B6 setup: empty hands at the filled s3, which is highlighted")
	_reset_counters()
	before = _contents_text()
	presses = await _jump_pressing_near(s3.get_interaction_point())
	_check(presses > 0 and _invalid == presses and _removed == 0 and s3.get_pickup() == half
			and not _carry.is_carrying() and _contents_text() == before,
			"B6 interact while airborne next to a filled socket is invalid and changes nothing (presses %d, invalid %d, removed %d)" % [presses, _invalid, _removed])
	_check(_air_frames > 0 and _air_highlight_frames == 0,
			"B6 nothing is highlighted while airborne (%d of %d airborne frames had a highlight)" % [_air_highlight_frames, _air_frames])
	_check(_conservation_problem().is_empty() and _readout_problem().is_empty(),
			"B6 conservation and readout after a mid-air pull-out attempt")

	# B7: empty hands, airborne next to the loose 2 ohm at the feet.
	await _teleport(TWO_POS)
	_check(_carry.get_target() == two, "B7 setup: empty hands at the loose 2 Ω, which is highlighted")
	_reset_counters()
	before = _contents_text()
	presses = await _jump_pressing_near(two.get_interaction_point())
	_check(presses > 0 and _invalid == presses and _picked == 0 and two.is_loose()
			and not _carry.is_carrying() and _contents_text() == before,
			"B7 interact while airborne next to a loose resistor is invalid and changes nothing (presses %d, invalid %d, picked %d)" % [presses, _invalid, _picked])
	_check(_air_frames > 0 and _air_highlight_frames == 0,
			"B7 nothing is highlighted while airborne (%d of %d airborne frames had a highlight)" % [_air_highlight_frames, _air_frames])
	_check(_conservation_problem().is_empty(), "B7 conservation after a mid-air pick-up attempt")


## Makes a full jump from where Ohmie stands and lands again. While rising
## (so a press is surely seen in mid-air) and `point` is within reach, presses
## interact on alternate frames. Returns the number of presses. Also records
## _air_min_distance, _air_frames and _air_highlight_frames (airborne frames on
## which the carry had a target or any object showed its highlight).
func _jump_pressing_near(point: Vector2) -> int:
	var presses: int = 0
	var holding_interact: bool = false
	var left_floor: bool = false
	_air_min_distance = INF
	_air_frames = 0
	_air_highlight_frames = 0
	Input.action_press("jump")
	for i: int in MAX_AIR_FRAMES:
		await _wait_physics(1)
		var just_released: bool = holding_interact
		if holding_interact:
			Input.action_release("interact")
			holding_interact = false
		var distance: float = _body_centre().distance_to(point)
		if not _player.is_on_floor():
			left_floor = true
			_air_frames += 1
			_air_min_distance = minf(_air_min_distance, distance)
			if _carry.get_target() != null or _any_highlighted():
				_air_highlight_frames += 1
			if not just_released and _player.velocity.y < 0.0 and distance <= REACH:
				Input.action_press("interact")
				holding_interact = true
				presses += 1
		elif left_floor:
			break
	Input.action_release("interact")
	Input.action_release("jump")
	await _wait_physics(2)
	return presses


# --- C: where can a resistor be put down -----------------------------------------------

func _section_c_drop_spots() -> void:
	print("-- C: put-down spots")
	if not await _open_level(HALF_AND_HALF):
		return
	var half: PartPickup = _part("r_half")
	var two: PartPickup = _part("r_two")

	# C1: at the right end of the left ledge (one-way platform).
	await _teleport(HALF_POS)
	await _interact()
	Input.action_press("move_right")
	for i: int in MAX_WALK_FRAMES:
		await _wait_physics(1)
		if _player.position.x >= LEFT_LEDGE_RIGHT_X + 14.0 or not _player.is_on_floor():
			break
	Input.action_release("move_right")
	await _wait_physics(2)
	var on_ledge: bool = _player.is_on_floor() and absf(_player.position.y - LEFT_LEDGE_Y) <= POSITION_TOLERANCE
	_check(on_ledge, "C1 standing on the right end of the left ledge (%s)" % _player.position)
	await _interact()
	_check(half.is_loose(), "C1 the 1/2 Ω can be put down at the ledge's end (at %s)" % half.global_position)
	_check(_is_supported(half.global_position),
			"C1 a put-down resistor rests on a tile (put down at %s; ledge ends at x=%.0f, so it floats in mid-air)" % [half.global_position, LEFT_LEDGE_RIGHT_X])
	_check(half.global_position.x - FOOTPRINT_HALF_WIDTH >= LEFT_LEDGE_LEFT_X
			and half.global_position.x + FOOTPRINT_HALF_WIDTH <= LEFT_LEDGE_RIGHT_X
			and absf(half.global_position.y - LEFT_LEDGE_Y) <= POSITION_TOLERANCE
			and _footprint_supported(half.global_position),
			"C1 a put-down at the left ledge's end lands fully on the ledge (footprint x %.0f..%.0f, ledge x %.0f..%.0f, y %.0f)" % [half.global_position.x - FOOTPRINT_HALF_WIDTH, half.global_position.x + FOOTPRINT_HALF_WIDTH, LEFT_LEDGE_LEFT_X, LEFT_LEDGE_RIGHT_X, half.global_position.y])
	# The put-down slid up to 64 px back onto the ledge, which can be out of reach
	# of where Ohmie stands, so stand at it to pick it up.
	await _teleport(Vector2(half.global_position.x, LEFT_LEDGE_Y))
	await _interact()
	_check(_carry.get_carried() == half, "C1 it can be picked up again (standing at it)")

	# C2: on top of another loose resistor's spot, beside it, and as close as allowed.
	await _teleport(TWO_POS)
	_reset_counters()
	await _interact()
	_check(_dropped == 0 and _invalid == 1 and _carry.get_carried() == half and two.is_loose()
			and two.global_position == TWO_POS,
			"C2 putting down on top of the loose 2 Ω is refused: no spot within the 64 px slide is %.0f px clear of it, so nothing stacks" % MIN_SPACING)
	await _teleport(Vector2(TWO_POS.x + 50.0, FLOOR_Y))
	_reset_counters()
	await _interact()
	var slide_gap: float = absf(half.global_position.x - two.global_position.x)
	_check(_dropped == 1 and half.is_loose() and two.is_loose() and two.global_position == TWO_POS
			and slide_gap >= MIN_SPACING - 0.01,
			"C2 putting down 50 px from the loose 2 Ω slides aside to at least %.0f px from it (at %s, %.1f px)" % [MIN_SPACING, half.global_position, slide_gap])
	await _teleport(Vector2(half.global_position.x, FLOOR_Y))
	await _interact()
	_check(_carry.get_carried() == half, "C2 it can be picked up again beside the 2 Ω")
	var closest_x: float = -1.0
	for dx: int in range(40, 80):
		await _teleport(Vector2(TWO_POS.x + dx, FLOOR_Y))
		_reset_counters()
		await _interact()
		if _dropped == 1:
			closest_x = half.global_position.x
			break
	var overlap: float = 2.0 * ICON_HALF_WIDTH - absf(closest_x - TWO_POS.x)
	_info("C2 nearest allowed put-down beside the 2 Ω is at x=%.1f (%.1f px away): the two 96 px icons overlap by %.1f px" % [closest_x, closest_x - TWO_POS.x, overlap])
	_check(closest_x > 0.0 and absf(closest_x - TWO_POS.x) >= ICON_HALF_WIDTH,
			"C2 resistors are never put down covering more than half of another's icon")
	_check(closest_x > 0.0 and absf(closest_x - TWO_POS.x) >= MIN_SPACING - 0.01,
			"C2 a put-down beside another loose resistor does not land closer than %.0f px to it (%.1f px)" % [MIN_SPACING, absf(closest_x - TWO_POS.x)])
	# It may have slid out of reach of where Ohmie stood, so stand at it.
	await _teleport(Vector2(half.global_position.x, FLOOR_Y))
	await _interact()
	_check(_carry.get_carried() == half, "C2 it can be picked up again at its nearest allowed spot")

	# C3: right next to (in) the closed door. A put-down keeps clear of the door
	# (QA-06), and no spot within the 64 px slide is clear of it, so it is refused.
	await _teleport(Vector2(DOOR_X, FLOOR_Y))
	_reset_counters()
	await _interact()
	_check(_dropped == 0 and _invalid == 1 and _carry.get_carried() == half and not _room.is_complete(),
			"C3 putting a resistor down in the closed doorway is refused (the door stays uncovered) and does not complete the level")
	var door_index: int = _door.get_parent().get_index()
	var parts_index: int = half.get_parent().get_index()
	_info("C3 draw order: door container index %d, parts container index %d (part drawn %s the door)" % [door_index, parts_index, "in front of" if parts_index > door_index else "behind"])

	# C4: screen edges.
	Input.action_press("move_left")
	for i: int in MAX_WALK_FRAMES:
		await _wait_physics(1)
		if _player.position.x <= 18.5:
			break
	await _wait_physics(5)
	Input.action_release("move_left")
	_reset_counters()
	await _interact()
	_check(half.is_loose(), "C4 can put a resistor down at the left screen edge (x=%.1f)" % half.global_position.x)
	_check(half.global_position.x - ICON_HALF_WIDTH >= 0.0,
			"C4 a resistor put down at the left edge is fully on screen (icon spans x %.0f..%.0f)" % [half.global_position.x - ICON_HALF_WIDTH, half.global_position.x + ICON_HALF_WIDTH])
	await _interact()
	_check(_carry.get_carried() == half, "C4 it can be picked up again at the left edge")
	await _teleport(Vector2(1230, FLOOR_Y))
	Input.action_press("move_right")
	await _wait_physics(30)
	Input.action_release("move_right")
	# The right edge of w1_07 is beside the door, which a put-down keeps clear of.
	var edge_feet: Vector2 = _player.position
	_reset_counters()
	await _interact()
	_check(_dropped == 0 and _invalid == 1 and _carry.get_carried() == half,
			"C4 a put-down at the right screen edge beside the door is refused (at x=%.1f)" % edge_feet.x)
	# Without the door, the spot is pulled fully on screen.
	var no_parts: Array[Vector2] = []
	var open_floor: PartPlacement = PartPlacement.new(_player.get_world_2d().direct_space_state, no_parts)
	var edge_spot: Vector2 = open_floor.find_put_down(edge_feet, _carry.put_down_max_slide)
	_check(edge_spot != PartPlacement.NO_SPOT and edge_spot.x + ICON_HALF_WIDTH <= SCREEN_WIDTH,
			"C4 at the right edge with nothing blocking, the spot keeps the icon fully on screen (spot %s)" % edge_spot)

	# C5: dev_room, lip of the pit.
	if not await _open_level(DEV):
		return
	var r3: PartPickup = _part("r3")
	await _teleport(DEV_R3_HOME)
	await _interact()
	Input.action_press("move_right")
	for i: int in MAX_WALK_FRAMES:
		await _wait_physics(1)
		if _player.position.x >= DEV_PIT_LEFT_X + 14.0 or not _player.is_on_floor():
			break
	Input.action_release("move_right")
	await _wait_physics(2)
	_check(_player.is_on_floor(), "C5 standing on the lip of the pit (%s)" % _player.position)
	await _interact()
	_check(r3.is_loose() and _is_supported(r3.global_position),
			"C5 a resistor put down at the pit's lip rests on ground (at %s; the pit starts at x=%.0f)" % [r3.global_position, DEV_PIT_LEFT_X])
	_check(r3.is_loose() and r3.global_position.x + FOOTPRINT_HALF_WIDTH <= DEV_PIT_LEFT_X
			and absf(r3.global_position.y - FLOOR_Y) <= POSITION_TOLERANCE and _footprint_supported(r3.global_position),
			"C5 a put-down at the lip of the pit ends fully supported (footprint x %.0f..%.0f; the pit starts at x=%.0f)" % [r3.global_position.x - FOOTPRINT_HALF_WIDTH, r3.global_position.x + FOOTPRINT_HALF_WIDTH, DEV_PIT_LEFT_X])
	# It slid back from the lip, possibly out of reach, so stand at it.
	await _teleport(Vector2(r3.global_position.x, FLOOR_Y))
	await _interact()
	_check(_carry.get_carried() == r3, "C5 it can be picked up again (standing at it)")


# --- D: falling into the pit (dev_room) ------------------------------------------------

func _section_d_pit() -> void:
	print("-- D: pit falls (dev_room)")
	if not await _open_level(DEV):
		return
	var r1: PartPickup = _part("r1")
	var r2: PartPickup = _part("r2")
	var r3: PartPickup = _part("r3")

	# Plug r1 in first, so the circuit has something to keep.
	await _teleport(DEV_R1_HOME)
	await _interact()
	await _teleport(DEV_AT_LOWER_SOCKET)
	await _interact()
	var reading: String = _reading()
	_check(reading == "2 Ω", "D setup: r1 in the floor socket reads 2 Ω (got '%s')" % reading)

	# D1: carrying r3.
	await _teleport(DEV_R3_HOME)
	await _interact()
	_reset_counters()
	await _run_into_pit()
	await _wait_physics(60)
	_check(_fell == 1, "D1 a fall while carrying emits fell_out once (%d)" % _fell)
	_check(not _carry.is_carrying() and r3.is_loose() and r3.global_position.distance_to(DEV_R3_HOME) < 0.5,
			"D1 the carried r3 is back at its home (%s)" % r3.global_position)
	_check(_reading() == reading and _socket_holding(r1) != null,
			"D1 the circuit is untouched (readout '%s')" % _reading())
	_check(_at_spawn(), "D1 Ohmie is back at spawn on the floor (%s)" % _player.position)

	# D2: empty hands.
	_reset_counters()
	await _run_into_pit()
	await _wait_physics(60)
	_check(_fell == 1 and _at_spawn() and _conservation_problem().is_empty(),
			"D2 a fall with empty hands: fell_out once, back at spawn, nothing moved")

	# D3: five falls in a row.
	_reset_counters()
	for i: int in 5:
		await _run_into_pit()
	await _wait_physics(60)
	_check(_fell == 5 and _at_spawn() and _reading() == reading,
			"D3 five falls in a row: fell_out exactly 5 times (%d), circuit untouched, back at spawn" % _fell)

	# D4: a resistor returned home must not land on another loose resistor.
	# Put r2 down on r1's home spot (r1 is in the socket), then pull r1 and fall with it.
	await _teleport(DEV_R2_HOME)
	await _interact()
	await _teleport(DEV_R1_HOME)
	_reset_counters()
	await _interact()
	_check(_dropped == 1 and r2.global_position.distance_to(DEV_R1_HOME) < POSITION_TOLERANCE,
			"D4 setup: r2 put down on r1's home spot %s (r1 is plugged in)" % DEV_R1_HOME)
	await _teleport(DEV_AT_LOWER_SOCKET)
	await _interact()
	_check(_carry.get_carried() == r1, "D4 setup: r1 pulled out of the socket")
	await _run_into_pit()
	await _wait_physics(30)
	var gap: float = r1.global_position.distance_to(r2.global_position)
	_check(r1.is_loose() and r2.is_loose() and gap >= ICON_HALF_WIDTH,
			"D4 after the fall r1 goes home without landing on r2 (r1 %s, r2 %s, %.1f px apart)" % [r1.global_position, r2.global_position, gap])
	_check(r1.is_loose() and gap >= MIN_SPACING - 0.01 and r1.global_position.x >= ICON_HALF_WIDTH
			and r1.global_position.x <= SCREEN_WIDTH - ICON_HALF_WIDTH and _footprint_supported(r1.global_position),
			"D4 r1 lies beside its taken home: at least %.0f px from r2, on screen and fully supported (r1 %s)" % [MIN_SPACING, r1.global_position])
	_check(_conservation_problem().is_empty(), "D4 conservation after the fall (%s)" % _conservation_problem())


# --- E: after completion, doorway --------------------------------------------------------

func _section_e_completion() -> void:
	print("-- E: completion and the doorway")
	if not await _open_level(HALF_AND_HALF):
		return
	await _solve_half_and_half()
	_check(_door.is_open(), "E setup: w1_07 solved, door open")
	await _walk_into_door()
	_check(_room.is_complete() and _completed == 1, "E1 walking into the open door completes the level")
	await _wait_physics(SETTLE_FRAMES)
	var before: String = _state_text()
	var player_before: Vector2 = _player.position
	var hold_sets: Array[PackedStringArray] = [
		PackedStringArray(["move_left"]), PackedStringArray(["move_right", "jump"]),
		PackedStringArray(["interact"]), PackedStringArray(["move_down"]),
		PackedStringArray(["move_left", "move_right", "jump", "move_down", "interact"]),
	]
	for round_index: int in 6:
		for actions: PackedStringArray in hold_sets:
			for action: String in actions:
				Input.action_press(action)
			await _wait_physics(4)
			for action: String in actions:
				Input.action_release(action)
			await _wait_physics(2)
	await _wait_physics(SETTLE_FRAMES)
	_check(_state_text() == before and _player.position.distance_to(player_before) < 0.5 and _completed == 1,
			"E1 after completion, 4 s of every action except restart changes nothing (player %s -> %s)" % [player_before, _player.position])
	if _state_text() != before:
		print("      before: " + before)
		print("      after:  " + _state_text())

	# E2: walk into the open door carrying the decoy.
	if not await _open_level(HALF_AND_HALF):
		return
	await _solve_half_and_half()
	var two: PartPickup = _part("r_two")
	await _teleport(TWO_POS)
	await _interact()
	await _walk_into_door()
	_check(_room.is_complete() and _completed == 1 and _carry.get_carried() == two,
			"E2 entering the open door while carrying the 2 Ω decoy completes the level (GDD 2)")
	_check(_conservation_problem().is_empty(), "E2 conservation in the victory state (%s)" % _conservation_problem())

	# E3: stand in the closed doorway, then the circuit is solved (no socket is
	# reachable from the doorway in either level, so it is solved through the API).
	if not await _open_level(HALF_AND_HALF):
		return
	await _teleport(Vector2(DOOR_X, FLOOR_Y))
	await _wait_physics(30)
	_check(not _room.is_complete(), "E3 standing in the closed doorway does nothing")
	_api_fill({"s1": "r_half", "s2": "r_one_ledge", "s3": "r_one_floor"})
	await _wait_physics(3)
	_info("E3 the door opening around a player already standing in the doorway completes the level at once: %s" % _room.is_complete())


# --- G: restart ---------------------------------------------------------------------------

func _section_g_restart() -> void:
	print("-- G: restart")
	if not await _open_level(HALF_AND_HALF):
		return
	var initial: String = _state_text()

	# G1 mid-jump (running right; keys let go on the frame R is pressed, since
	# keys still held after a restart rightly keep acting on the new room).
	await _teleport(Vector2(OPEN_FLOOR_X, FLOOR_Y))
	Input.action_press("move_right")
	Input.action_press("jump")
	await _wait_physics(10)
	var airborne: bool = not _player.is_on_floor()
	var errors_before: int = _logger.count()
	_release_all()
	await _restart(1)
	_check(airborne, "G1 setup: Ohmie was in mid-air when restart was pressed")
	await _wait_physics(SETTLE_FRAMES + 20)
	_check(_room != null and _state_text() == initial and _logger.count() == errors_before,
			"G1 restart mid-jump gives the exact initial state, no errors")
	_print_state_diff(initial)

	# G2 mid-carry.
	await _teleport(ONE_FLOOR_POS)
	await _interact()
	errors_before = _logger.count()
	await _restart(1)
	await _wait_physics(SETTLE_FRAMES)
	_check(_room != null and _state_text() == initial and _logger.count() == errors_before,
			"G2 restart while carrying gives the exact initial state, no errors")
	_print_state_diff(initial)

	# G3 during the victory state.
	await _solve_half_and_half()
	await _walk_into_door()
	errors_before = _logger.count()
	await _restart(1)
	await _wait_physics(SETTLE_FRAMES)
	_check(_room != null and _state_text() == initial and _logger.count() == errors_before,
			"G3 restart in the victory state gives the exact initial state, no errors")
	_print_state_diff(initial)

	# G4 several restarts on consecutive frames, and two in one frame.
	await _teleport(ONE_FLOOR_POS)
	await _interact()
	errors_before = _logger.count()
	await _restart(6)
	await _wait_physics(SETTLE_FRAMES)
	var rooms: int = root.find_children("*", "Room", true, false).size()
	_check(_room != null and rooms == 1 and _state_text() == initial and _logger.count() == errors_before,
			"G4 six restart presses on consecutive frames: one room (%d), exact initial state, no errors (%d new)" % [rooms, _logger.count() - errors_before])
	_print_state_diff(initial)
	for line: String in _logger.lines_since(errors_before):
		print("      " + line)
	errors_before = _logger.count()
	_send_action_event(&"restart", true)
	_send_action_event(&"restart", false)
	_send_action_event(&"restart", true)
	_send_action_event(&"restart", false)
	await _wait_physics(4)
	_rebind()
	await _wait_physics(SETTLE_FRAMES)
	rooms = root.find_children("*", "Room", true, false).size()
	_check(_room != null and rooms == 1 and _state_text() == initial and _logger.count() == errors_before,
			"G4 two restart presses in one frame: one room (%d), exact initial state, no errors" % rooms)
	for line: String in _logger.lines_since(errors_before):
		print("      " + line)


# --- H: swap and replug -----------------------------------------------------------------

func _section_h_swap_and_replug() -> void:
	print("-- H: swap and replug")
	if not await _open_level(HALF_AND_HALF):
		return
	await _solve_half_and_half()
	var two: PartPickup = _part("r_two")
	var s3: CircuitSocket = _socket("s3")
	await _teleport(TWO_POS)
	await _interact()
	await _teleport(AT_S3)
	_reset_counters()
	var bad: int = 0
	var expected_texts: PackedStringArray = ["7/6 Ω", "1 Ω"]
	for i: int in 20:
		await _interact()
		var want: String = expected_texts[i % 2]
		if not _conservation_problem().is_empty() or not _readout_problem().is_empty() \
				or _reading() != want:
			bad += 1
	_check(bad == 0 and _swapped == 20 and _carry.get_carried() == two and s3.is_filled(),
			"H1 20 swaps at s3 (1 Ω <-> 2 Ω): readout alternates 7/6 Ω / 1 Ω and door follows (%d bad, %d swaps)" % [bad, _swapped])

	await _teleport(Vector2(OPEN_FLOOR_X, FLOOR_Y))
	await _interact()  # put the decoy down
	await _teleport(AT_S3)
	_reset_counters()
	bad = 0
	for i: int in 100:
		await _interact()
		var want: String = "3/2 Ω" if i % 2 == 0 else "1 Ω"
		if not _conservation_problem().is_empty() or not _readout_problem().is_empty() \
				or _reading() != want or _door.is_open() != (i % 2 == 1):
			bad += 1
	_check(bad == 0 and _removed == 50 and _placed == 50 and _opened == 50 and _closed == 50,
			"H2 pull out and replug s3 50 times: readout and door consistent every time (%d bad; removed %d placed %d opened %d closed %d)" % [bad, _removed, _placed, _opened, _closed])


# --- I: movement abuse ------------------------------------------------------------------

func _section_i_movement_abuse() -> void:
	print("-- I: movement abuse")
	if not await _open_level(HALF_AND_HALF):
		return
	var start: Vector2 = _player.position
	Input.action_press("move_left")
	Input.action_press("move_right")
	await _wait_physics(30)
	_check(absf(_player.position.x - start.x) < 0.5, "I1 holding left and right together does not move Ohmie")
	_release_all()

	_reset_counters()
	Input.action_press("jump")
	await _wait_physics(180)
	_check(_jumped == 1 and _player.is_on_floor(), "I2 holding jump for 3 s jumps exactly once (%d) and lands" % _jumped)
	Input.action_release("jump")

	Input.action_press("move_down")
	Input.action_press("move_right")
	var x0: float = _player.position.x
	await _wait_physics(30)
	var speed: float = (_player.position.x - x0) * 2.0
	_check(absf(speed - 240.0) < 12.0 and _player.is_on_floor(), "I3 holding down while walking on the floor: normal speed (%.0f px/s)" % speed)
	_release_all()

	# Hold down permanently, then try to stand on the S1 platform.
	await _teleport(Vector2(AT_S1.x, FLOOR_Y))
	Input.action_press("move_down")
	Input.action_press("jump")
	await _wait_physics(90)
	Input.action_release("jump")
	await _wait_physics(30)
	_info("I3 holding down while jumping up to the S1 platform: ends on y=%.0f (floor 640, platform 551)" % _player.position.y)
	await _teleport(AT_S1)
	await _wait_physics(30)
	_check(_player.position.y > S1_PLATFORM_Y + 20.0, "I3 holding down while standing on a one-way platform drops through it (y=%.0f)" % _player.position.y)
	_release_all()
	await _land()

	# Screen edges.
	await _teleport(Vector2(40, FLOOR_Y))
	var min_x: float = INF
	var max_x: float = -INF
	Input.action_press("move_left")
	for i: int in 3:
		Input.action_press("jump")
		for f: int in 50:
			await _wait_physics(1)
			min_x = minf(min_x, _player.position.x)
		Input.action_release("jump")
		await _wait_physics(2)
	Input.action_release("move_left")
	await _teleport(Vector2(1240, FLOOR_Y))
	Input.action_press("move_right")
	for i: int in 3:
		Input.action_press("jump")
		for f: int in 50:
			await _wait_physics(1)
			max_x = maxf(max_x, _player.position.x)
		Input.action_release("jump")
		await _wait_physics(2)
	Input.action_release("move_right")
	await _land()
	_check(min_x >= 17.9 and max_x <= 1262.1 and _player.is_on_floor(),
			"I4 jumping at the screen edges keeps Ohmie inside x 18..1262 (min %.1f, max %.1f) and he lands" % [min_x, max_x])

	# Top of the screen from the highest surface.
	await _teleport(ONE_LEDGE_POS)
	var min_y: float = INF
	Input.action_press("jump")
	for f: int in 60:
		await _wait_physics(1)
		min_y = minf(min_y, _player.position.y)
	Input.action_release("jump")
	await _land()
	_check(min_y - PLAYER_HEIGHT >= 0.0, "I5 from the right ledge Ohmie's head stays on screen (top y %.0f)" % (min_y - PLAYER_HEIGHT))


# --- J: readout and door for every assignment ---------------------------------------------

func _section_j_readout_sweep() -> void:
	print("-- J: readout sweep, all assignments")
	if not await _open_level(HALF_AND_HALF):
		return
	var room_parts: Array[PartPickup] = _room.get_parts()
	var sockets: Array[CircuitSocket] = _board.get_sockets()
	var assignments: Array[Dictionary] = []
	_enumerate(sockets.size(), 0, [], assignments, room_parts.size())
	var mismatches: PackedStringArray = []
	var open_count: int = 0
	for assignment: Dictionary in assignments:
		_api_clear()
		var values: Dictionary = {}
		for socket_index: int in assignment:
			var pickup: PartPickup = room_parts[assignment[socket_index] as int]
			pickup.take()
			sockets[socket_index].insert(pickup)
			values[sockets[socket_index].socket_id] = pickup.part.value
		var expected: String = _expected_half_and_half_reading(values)
		var is_match: bool = expected == "1 Ω"
		var shown: String = _reading()
		var colour: Color = _hud.get_row_value_color(1)
		var wire_colour: Color = _board.get_wires().get_core_color()
		var theme: RoomTheme = _room.get_room_theme()
		# An ohmmeter-only board never carries current: plain wires, teal on a match.
		var want_wire: Color = theme.wire_match if is_match else theme.wire_normal
		if _door.is_open():
			open_count += 1
		if shown != expected or _door.is_open() != is_match or (colour == Hud.COLOR_MATCH) != is_match \
				or wire_colour != want_wire or not _readout_problem().is_empty():
			mismatches.append("%s: shown '%s' expected '%s' door %s" % [values, shown, expected, _door.is_open()])
	_check(assignments.size() == 73, "J enumerated all 73 assignments of 4 resistors to 3 sockets (%d)" % assignments.size())
	_check(mismatches.is_empty(),
			"J readout text, meter text, readout colour, wire colour and door match an independent calculation and DcSolver for every assignment (%d mismatches)" % mismatches.size())
	for line: String in mismatches.slice(0, 5):
		print("      " + line)
	_info("J the door was open in %d of 73 assignments (two: 1/2 + (1 || 1) with either 1 Ω in s2)" % open_count)
	_api_clear()


# --- K: coyote time and jump buffer (GDD 5: 0.10 s each = 6 frames) ------------------

func _section_k_coyote_and_buffer() -> void:
	print("-- K: coyote time and jump buffer")
	if not await _open_level(HALF_AND_HALF):
		return
	for late: int in [2, 3, 10]:
		var rising: bool = await _jump_after_walking_off(late)
		var want: bool = late <= 3
		_check(rising == want, "K coyote: jump pressed %d frames after walking off the S1 platform %s (jumped: %s)" % [late, "jumps" if want else "does not jump", rising])
	var landing_frame: int = await _drop_and_count_to_landing(-1)
	for early: int in [3, 12]:
		await _drop_and_count_to_landing(landing_frame - early)
		var jumped_on_landing: bool = _jumped == 1
		var want: bool = early <= 4
		_check(jumped_on_landing == want, "K buffer: jump pressed %d frames before landing %s (jumped: %s)" % [early, "jumps on landing" if want else "is ignored", jumped_on_landing])


## Walks right off the S1 platform's right end and presses jump `late` frames
## after leaving it. True if Ohmie then rises.
func _jump_after_walking_off(late: int) -> bool:
	_release_all()
	await _teleport(Vector2(600, S1_PLATFORM_Y))
	Input.action_press("move_right")
	for i: int in 60:
		await _wait_physics(1)
		if not _player.is_on_floor():
			break
	Input.action_release("move_right")
	await _wait_physics(late - 1)
	_reset_counters()
	Input.action_press("jump")
	await _wait_physics(3)
	var rising: bool = _jumped == 1 and _player.velocity.y < 0.0
	Input.action_release("jump")
	await _land()
	await _wait_physics(5)
	return rising


## Drops through the S1 platform onto the floor, optionally pressing jump at
## frame `press_at` of the fall. Returns the frame on which Ohmie stood again.
func _drop_and_count_to_landing(press_at: int) -> int:
	_release_all()
	await _teleport(AT_S1)
	_reset_counters()
	Input.action_press("move_down")
	await _wait_physics(2)
	Input.action_release("move_down")
	var landed_at: int = -1
	for frame: int in 120:
		if frame == press_at:
			Input.action_press("jump")
		await _wait_physics(1)
		if frame > 3 and _player.is_on_floor() and landed_at < 0:
			landed_at = frame
		if _jumped > 0 or (landed_at >= 0 and frame > landed_at + 8):
			break
	Input.action_release("jump")
	await _land()
	await _wait_physics(30)
	return landed_at


func _enumerate(socket_count: int, index: int, used: Array, out: Array[Dictionary], pickup_count: int,
		current: Dictionary = {}) -> void:
	if index == socket_count:
		out.append(current.duplicate())
		return
	_enumerate(socket_count, index + 1, used, out, pickup_count, current)
	for p: int in pickup_count:
		if used.has(p):
			continue
		current[index] = p
		used.append(p)
		_enumerate(socket_count, index + 1, used, out, pickup_count, current)
		used.erase(p)
		current.erase(index)


## Independent ohmmeter reading for w1_07: s1 + (s2 || s3), an empty slot is open (OL).
func _expected_half_and_half_reading(values: Dictionary) -> String:
	if not values.has("s1"):
		return "OL"
	var branch: Rational = null
	for id: String in ["s2", "s3"]:
		if values.has(id):
			var v: Rational = values[id]
			branch = v if branch == null else branch.mul(v).div(branch.add(v))
	if branch == null:
		return "OL"
	return (values["s1"] as Rational).add(branch).to_text() + OHM


# --- scenario helpers --------------------------------------------------------------------

## Solves w1_07 with interact presses (teleporting between spots).
func _solve_half_and_half() -> void:
	await _teleport(HALF_POS)
	await _interact()
	await _teleport(AT_S1)
	await _interact()
	await _teleport(ONE_LEDGE_POS)
	await _interact()
	await _teleport(AT_S2)
	await _interact()
	await _teleport(ONE_FLOOR_POS)
	await _interact()
	await _teleport(AT_S3)
	await _interact()


func _walk_into_door() -> void:
	await _teleport(Vector2(OPEN_FLOOR_X, FLOOR_Y))
	Input.action_press("move_right")
	for i: int in MAX_WALK_FRAMES:
		await _wait_physics(1)
		if _room.is_complete():
			break
	Input.action_release("move_right")
	await _wait_physics(2)


func _run_into_pit() -> void:
	var before: int = _fell
	await _teleport(Vector2(900, FLOOR_Y))
	Input.action_press("move_right")
	for i: int in MAX_WALK_FRAMES:
		await _wait_physics(1)
		if _fell > before:
			break
	Input.action_release("move_right")
	await _wait_physics(10)


## Plugs resistors into sockets through the API: {"socket_id": "pickup_id"}.
func _api_fill(plan: Dictionary) -> void:
	for socket_id: String in plan:
		var pickup: PartPickup = _part(plan[socket_id])
		pickup.take()
		_socket(socket_id).insert(pickup)


## Empties every socket through the API and sends every resistor home.
func _api_clear() -> void:
	for socket: CircuitSocket in _board.get_sockets():
		var taken: PartPickup = socket.take_out()
		if taken != null:
			taken.place_loose(taken.home_position)


# --- state and invariants ----------------------------------------------------------------

## "" when every part is in exactly one state; otherwise what is wrong.
func _conservation_problem() -> String:
	var room_parts: Array[PartPickup] = _room.get_parts()
	if room_parts.size() != _part_count:
		return "part count %d, expected %d" % [room_parts.size(), _part_count]
	for pickup: PartPickup in room_parts:
		var states: int = 0
		if pickup.is_loose():
			states += 1
		if _carry.get_carried() == pickup:
			states += 1
		for socket: CircuitSocket in _board.get_sockets():
			if socket.get_pickup() == pickup:
				states += 1
		if states != 1:
			return "%s is in %d states" % [pickup.part_id, states]
		if pickup.visible != pickup.is_loose():
			return "%s visible=%s loose=%s" % [pickup.part_id, pickup.visible, pickup.is_loose()]
	var icon: Node2D = _carry.get_node(^"CarriedIcon") as Node2D
	if icon.visible != _carry.is_carrying():
		return "carried icon visible=%s carrying=%s" % [icon.visible, _carry.is_carrying()]
	return ""


## "" when the HUD, the board's ohmmeter and the door agree with DcSolver for
## the current slots.
func _readout_problem() -> String:
	var filled: Dictionary = {}
	for socket: CircuitSocket in _board.get_sockets():
		if socket.is_filled():
			filled[socket.socket_id] = socket.get_part()
	var solution: DcSolution = DcSolver.solve(_room.get_circuit().build_network(filled))
	var goal: LevelGoal = _room.get_goal()
	var want: String = goal.reading_text(0, solution)
	var is_match: bool = goal.is_met(solution)
	if _reading() != want:
		return "HUD '%s' but solver '%s'" % [_reading(), want]
	var meter_want: String = MeterText.reading(solution, goal.conditions[0].element_id)
	if _meter() != meter_want:
		return "meter '%s' but solver '%s'" % [_meter(), meter_want]
	if _door.is_open() != is_match:
		return "door open=%s but match=%s" % [_door.is_open(), is_match]
	return ""


## Presses interact `presses` times on alternate frames; returns frames that broke an invariant.
func _spam_interact(presses: int) -> int:
	var bad: int = 0
	for i: int in presses:
		Input.action_press("interact")
		await _wait_physics(1)
		if not _conservation_problem().is_empty() or not _readout_problem().is_empty():
			bad += 1
			print("      frame problem: %s %s" % [_conservation_problem(), _readout_problem()])
		Input.action_release("interact")
		await _wait_physics(1)
		if not _conservation_problem().is_empty() or not _readout_problem().is_empty():
			bad += 1
	await _wait_physics(2)
	return bad


## A text snapshot of everything restart must reset.
func _state_text() -> String:
	if _room == null:
		return "<no room>"
	var parts: PackedStringArray = []
	for pickup: PartPickup in _room.get_parts():
		parts.append("%s:%s@%s" % [pickup.part_id, "loose" if pickup.is_loose() else "-", pickup.global_position.round()])
	for socket: CircuitSocket in _board.get_sockets():
		parts.append("%s=%s" % [socket.socket_id, socket.get_pickup().part_id if socket.is_filled() else "empty"])
	parts.append("hud=%s" % _reading())
	parts.append("door=%s" % _door.is_open())
	parts.append("complete=%s" % _room.is_complete())
	parts.append("banner=%s" % _hud.is_level_complete_shown())
	parts.append("carrying=%s" % _carry.is_carrying())
	parts.append("target=%s" % _describe(_carry.get_target()))
	parts.append("player=%s floor=%s" % [_player.position.round(), _player.is_on_floor()])
	return " ".join(parts)


func _print_state_diff(expected: String) -> void:
	var now: String = _state_text()
	if now != expected:
		print("      expected: " + expected)
		print("      actual:   " + now)


func _is_supported(feet: Vector2) -> bool:
	var cell: Vector2i = _tiles.local_to_map(_tiles.to_local(feet))
	return _tiles.get_cell_source_id(cell) != -1


## True if tiles lie under the floor point and under both ends of the 80 px
## footprint (ends taken 0.5 px inside, so a footprint ending at a tile edge counts).
func _footprint_supported(feet: Vector2) -> bool:
	var inset: float = FOOTPRINT_HALF_WIDTH - 0.5
	for dx: float in [-inset, 0.0, inset]:
		if not _is_supported(Vector2(feet.x + dx, feet.y + 1.0)):
			return false
	return true


## Where every resistor is (loose spot, carried, or socket), for "nothing changed" checks.
func _contents_text() -> String:
	var parts: PackedStringArray = []
	for pickup: PartPickup in _room.get_parts():
		parts.append("%s:%s@%s" % [pickup.part_id, "loose" if pickup.is_loose() else "-", pickup.global_position.round()])
	for socket: CircuitSocket in _board.get_sockets():
		parts.append("%s=%s" % [socket.socket_id, socket.get_pickup().part_id if socket.is_filled() else "empty"])
	parts.append("carrying=%s" % (_carry.get_carried().part_id if _carry.is_carrying() else "none"))
	return " ".join(parts)


## True if any pickup shows its highlight frame or any socket its highlight texture.
func _any_highlighted() -> bool:
	for pickup: PartPickup in _room.get_parts():
		if (pickup.get_node(^"Highlight") as Sprite2D).visible:
			return true
	for socket: CircuitSocket in _board.get_sockets():
		if (socket.get_node(^"Frame") as Sprite2D).texture == socket.highlight_texture:
			return true
	return false


## The live reading on the plaque (both rooms here have one condition, on om1).
func _reading() -> String:
	return _hud.get_reading_text(0)


## The reading drawn in the goal's meter (om1) on the board.
func _meter() -> String:
	return _board.get_meter(_room.get_goal().conditions[0].element_id).get_reading()


func _at_spawn() -> bool:
	return _player.is_on_floor() and _player.position.distance_to(_room.level_data.spawn) <= POSITION_TOLERANCE


func _body_centre() -> Vector2:
	return _player.global_position + Vector2(0, -44)


func _socket_holding(pickup: PartPickup) -> CircuitSocket:
	for socket: CircuitSocket in _board.get_sockets():
		if socket.get_pickup() == pickup:
			return socket
	return null


func _describe(target: Interactable) -> String:
	if target == null:
		return "none"
	if target is PartPickup:
		return "pickup " + (target as PartPickup).part_id
	if target is CircuitSocket:
		return "socket " + (target as CircuitSocket).socket_id
	return str(target)


# --- L: same-level rule and the name tag (w1_05) ------------------------------------------

func _section_l_same_level() -> void:
	print("-- L: same-level rule and name tag (w1_05)")
	if not await _open_level(PARALLEL_PARKING):
		return
	var r2: PartPickup = _part("r2")
	var tag: TargetTag = _room.get_target_tag()
	await _teleport(W5_FLOOR_UNDER_R2)
	var distance: float = _body_centre().distance_to(r2.get_interaction_point())
	_check(_player.is_on_floor() and distance <= REACH and _carry.get_target() == null,
			"L1 on the floor beneath the low ledge the 2 Ω is in reach (%.1f px) but not a target: it is not at Ohmie's level (target %s)" % [distance, _describe(_carry.get_target())])
	_check(tag != null and not tag.visible, "L1 no name tag is shown without a target")
	_reset_counters()
	await _interact()
	_check(_picked == 0 and _invalid == 1 and r2.is_loose(),
			"L1 interact on the floor beneath it does not pick up the 2 Ω (picked %d, invalid %d)" % [_picked, _invalid])
	await _teleport(W5_R2_POS)
	_check(_player.is_on_floor() and absf(_player.position.y - W5_R2_POS.y) <= POSITION_TOLERANCE
			and _carry.get_target() == r2,
			"L2 standing on the ledge, the 2 Ω is the target (at %s, target %s)" % [_player.position, _describe(_carry.get_target())])
	_check(tag != null and tag.visible and tag.get_text() == "2 Ω",
			"L2 the name tag reads '2 Ω' over the highlighted part (got '%s')" % (tag.get_text() if tag != null else "no tag"))
	if tag != null:
		var rect: Rect2 = tag.get_global_rect()
		_check(rect.end.y <= r2.get_tag_anchor().y and rect.end.y <= W5_R2_POS.y - TargetTag.HEAD_CLEARANCE
				and rect.position.x >= 0.0 and rect.end.x <= SCREEN_WIDTH and rect.position.y >= 0.0,
				"L2 the tag floats above the part and clear of Ohmie's head, on screen (%s)" % rect)
	var carried_icon: Node2D = _carry.get_node(^"CarriedIcon") as Node2D
	var carried_z: int = _player.z_index + carried_icon.z_index if carried_icon.z_as_relative else carried_icon.z_index
	_check(_player.z_index > r2.z_index and _player.z_index > _board.get_sockets()[0].z_index
			and tag != null and carried_z > tag.z_index,
			"L2 Ohmie draws in front of loose parts and slots, the carried part on top of the tag (z %d > %d, %d; carried %d > tag %d)" % [
				_player.z_index, r2.z_index, _board.get_sockets()[0].z_index, carried_z, tag.z_index if tag != null else -1])
	_reset_counters()
	await _interact()
	_check(_carry.get_carried() == r2 and _picked == 1, "L2 interact on the ledge picks up the 2 Ω")
	_check(tag != null and not tag.visible, "L2 the tag goes away when the part is picked up and nothing else is in reach")


# --- room binding ----------------------------------------------------------------------

func _open_level(path: String) -> bool:
	_release_all()
	Room.level_override = path
	if current_scene != null:
		current_scene.queue_free()
	await _wait_physics(2)
	var main: Node = _packed.instantiate()
	root.add_child(main)
	current_scene = main
	await _wait_physics(1)
	if not _bind(main):
		_check(false, "room for %s loads" % path)
		return false
	await _wait_physics(SETTLE_FRAMES)
	return true


func _rebind() -> void:
	_room = null
	if current_scene == null or not _bind(current_scene):
		_check(false, "a room exists after restart")


func _bind(main: Node) -> bool:
	_room = main.get_node_or_null(ROOM_PATH) as Room
	if _room == null or _room.level_data == null or _room.get_player() == null or _room.get_carry() == null:
		_room = null
		return false
	_player = _room.get_player()
	_carry = _room.get_carry()
	_hud = _room.get_hud()
	_door = _room.get_door()
	_board = _room.get_board()
	_tiles = _room.get_node(^"Tiles") as TileMapLayer
	_part_count = _room.level_data.parts.size()
	_reset_counters()
	_carry.picked_up.connect(func(_r: PartPickup) -> void: _picked += 1)
	_carry.placed.connect(func(_r: PartPickup, _s: CircuitSocket) -> void: _placed += 1)
	_carry.removed.connect(func(_r: PartPickup, _s: CircuitSocket) -> void: _removed += 1)
	_carry.swapped.connect(func(_a: PartPickup, _b: PartPickup, _s: CircuitSocket) -> void: _swapped += 1)
	_carry.dropped.connect(func(_r: PartPickup) -> void: _dropped += 1)
	_carry.invalid_action.connect(func() -> void: _invalid += 1)
	_player.fell_out.connect(func() -> void: _fell += 1)
	_player.jumped.connect(func() -> void: _jumped += 1)
	_room.level_completed.connect(func() -> void: _completed += 1)
	_door.opened.connect(func() -> void: _opened += 1)
	_door.closed.connect(func() -> void: _closed += 1)
	return true


func _reset_counters() -> void:
	_picked = 0
	_placed = 0
	_removed = 0
	_swapped = 0
	_dropped = 0
	_invalid = 0
	_fell = 0
	_completed = 0
	_jumped = 0
	_opened = 0
	_closed = 0


## Presses restart `presses` times on consecutive frames (press, release, press...) and rebinds.
func _restart(presses: int) -> void:
	for i: int in presses:
		_send_action_event(&"restart", true)
		await _wait_physics(1)
		_send_action_event(&"restart", false)
		await _wait_physics(1)
	await _wait_physics(4)
	_rebind()


func _send_action_event(action: StringName, pressed: bool) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


# --- input helpers -----------------------------------------------------------------------

func _teleport(at: Vector2) -> void:
	_player.respawn(at)
	await _wait_physics(3)


func _interact() -> void:
	Input.action_press("interact")
	await _wait_physics(1)
	Input.action_release("interact")
	await _wait_physics(2)


func _land() -> void:
	for i: int in MAX_AIR_FRAMES:
		if _player.is_on_floor():
			break
		await _wait_physics(1)


func _part(id: String) -> PartPickup:
	for pickup: PartPickup in _room.get_parts():
		if pickup.part_id == id:
			return pickup
	return null


func _socket(id: String) -> CircuitSocket:
	for socket: CircuitSocket in _board.get_sockets():
		if socket.socket_id == id:
			return socket
	return null


func _wait_physics(frames: int) -> void:
	for i: int in frames:
		await physics_frame


func _release_all() -> void:
	for action: String in ACTIONS:
		Input.action_release(action)


func _info(text: String) -> void:
	print("INFO  " + text)


func _check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("PASS  " + description)
	else:
		_failed += 1
		print("FAIL  " + description)
