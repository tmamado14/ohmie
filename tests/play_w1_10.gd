extends SceneTree
## Scripted headless playthrough of res://levels/w1_10.json ("Ohm Stretch": a
## ladder between two buses: the voltmeter vm1 on the top rung, slot p_top
## (high, left) and slot p_bot (middle, right) as the parallel pair, and the
## main line on the floor with slot src, the ammeter am1 and slot ser in
## series; batteries 6, 9, 12 V and resistors 1, 3, 4, 4, 6, 10 ohm; goal: am1
## reads 2 A and vm1 reads 4 V at once).
##
## First checks with the circuit API: the three solutions by value (12 V with
## 4 ohm and 3 || 6; 6 V with 1 ohm and 3 || 6 or 4 || 4), near misses, a
## battery in the pair, one pair slot left empty, and two batteries in the pair
## (SHORT). Then plays the room through the input map only (no teleporting):
## the 9 V by the spawn up into p_top (0 A, 9 V), the 12 V from the right
## ledge into p_bot (two batteries across the pair: SHORT, door shut), the
## 12 V pulled out and plugged into src, the 3 ohm swapped into p_top (0 A,
## 0 V), the 9 V put down, a 4 ohm into ser (12/7 A, 36/7 V: wrong), the 6 ohm
## from the high shelf into p_bot (2 A and 4 V, door open), then up to the door
## on the high shelf.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --fixed-fps 60 --script res://tests/play_w1_10.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
const LEVEL_PATH: String = "res://levels/w1_10.json"
const ROOM_PATH: NodePath = ^"Room"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]

const TITLE: String = "Ohm Stretch"
const MISSION: String = "Draw 2 A. Put 4 V on the meter."
const PLAQUE_CAPTIONS: Array[String] = ["I", "V"]
const PLAQUE_START_VALUES: Array[String] = ["0 A  →  2 A", "---  →  4 V"]
const PART_COUNT: int = 9
const SLOT_COUNT: int = 4

## Layout facts of w1_10.json.
const SPAWN: Vector2 = Vector2(48, 640)
const DOOR: Vector2 = Vector2(1216, 455)
const FLOOR_Y: float = 640.0
const LEFT_LEDGE_Y: float = 551.0  # row 17, x 0..160
const LEFT_STEP_Y: float = 519.0  # row 16, x 224..352
const P_TOP_PLATFORM_Y: float = 423.0  # row 13, x 256..352
const P_BOT_PLATFORM_Y: float = 519.0  # row 16, x 704..800
const RIGHT_LEDGE_Y: float = 551.0  # row 17, x 896..1120
const SHELF_Y: float = 455.0  # row 14, x 960..1280 (the door stands on it)
const NINE_X: float = 144.0
const THREE_X: float = 96.0
const TWELVE_X: float = 944.0
const FOUR_X: float = 1080.0
const SIX_X: float = 1000.0
const SRC_X: float = 304.0
const SER_X: float = 752.0
const P_TOP_X: float = 304.0
const P_BOT_X: float = 752.0
const UNDER_LEFT_LEDGE_X: float = 80.0
const TO_LEFT_STEP_JUMP_X: float = 150.0
const UNDER_P_TOP_X: float = 304.0
const TO_P_BOT_JUMP_X: float = 910.0
const OFF_P_BOT_X: float = 860.0
const UNDER_SHELF_X: float = 1040.0

const POSITION_TOLERANCE: float = 6.0
const SETTLE_FRAMES: int = 20
const MAX_WALK_FRAMES: int = 900
const MAX_AIR_FRAMES: int = 180

var _passed: int = 0
var _failed: int = 0

var _room: Room = null
var _player: Player = null
var _carry: PlayerCarry = null
var _hud: Hud = null
var _door: ExitDoor = null
var _completed_count: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var exit_code: int = await _run_checks()
	_release_all()
	print("")
	print("play_w1_10: %d passed, %d failed" % [_passed, _failed])
	quit(exit_code)


func _run_checks() -> int:
	Room.level_override = LEVEL_PATH
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_check(false, "main scene loads")
		return 1
	var main: Node = packed.instantiate()
	root.add_child(main)
	current_scene = main
	await _wait_physics(1)
	if not _bind_room(main):
		return 1
	await _wait_physics(SETTLE_FRAMES)

	_check_start_state()
	_check_circuit()
	await _solve()
	if _failed == 0:
		await _enter_door()
	Room.level_override = ""
	return 0 if _failed == 0 else 1


func _check_start_state() -> void:
	print("-- start")
	_check(_room.level_data.title == TITLE, "level title is '%s' (got '%s')" % [TITLE, _room.level_data.title])
	_check(_hud.get_mission_text() == MISSION, "the mission sign shows '%s' (got '%s')" % [MISSION, _hud.get_mission_text()])
	var captions: Array[String] = []
	var values: Array[String] = []
	for row: int in 2:
		captions.append(_hud.get_row_caption(row))
		values.append(_hud.get_row_value(row))
	_check(captions == PLAQUE_CAPTIONS and values == PLAQUE_START_VALUES,
			"the plaque rows read %s %s (got %s %s)" % [PLAQUE_CAPTIONS, PLAQUE_START_VALUES, captions, values])
	_check(not _hud.is_mission_complete_shown(), "the mission sign starts not done")
	_check(not _door.is_open(), "door starts closed")
	_check(_room.get_parts().size() == PART_COUNT and _room.get_board().get_sockets().size() == SLOT_COUNT,
			"%d parts and %d slots in the room" % [PART_COUNT, SLOT_COUNT])
	_check(_player.position.distance_to(SPAWN) <= POSITION_TOLERANCE and _player.is_on_floor(),
			"player starts on the floor at spawn (%s)" % _player.position)

func _check_circuit() -> void:
	print("-- two conditions (circuit API)")
	_api({"src": _b("12"), "ser": _r("4"), "p_top": _r("3"), "p_bot": _r("6")}, ["2 A", "4 V"], true,
			"12 V, 4 Ω, 3 Ω || 6 Ω")
	_api({"src": _b("6"), "ser": _r("1"), "p_top": _r("3"), "p_bot": _r("6")}, ["2 A", "4 V"], true,
			"6 V, 1 Ω, 3 Ω || 6 Ω")
	_api({"src": _b("6"), "ser": _r("1"), "p_top": _r("4"), "p_bot": _r("4")}, ["2 A", "4 V"], true,
			"6 V, 1 Ω, 4 Ω || 4 Ω")
	_api({"src": _r("4"), "ser": _b("12"), "p_top": _r("3"), "p_bot": _r("6")}, ["2 A", "4 V"], true,
			"battery and series resistor swapped (both slots face the same way round the loop)")
	_api({"src": _b("12"), "ser": _r("1"), "p_top": _r("3"), "p_bot": _r("6")}, ["4 A", "8 V"], false,
			"12 V, 1 Ω, 3 Ω || 6 Ω")
	_api({"src": _b("9"), "ser": _r("1"), "p_top": _r("3"), "p_bot": _r("6")}, ["3 A", "6 V"], false,
			"the 9 V decoy, 1 Ω, 3 Ω || 6 Ω")
	_api({"src": _b("12"), "ser": _r("4"), "p_top": _r("6")}, ["6/5 A", "36/5 V"], false,
			"12 V, 4 Ω, 6 Ω with the other pair slot empty")
	_api({"src": _b("12"), "ser": _r("4"), "p_top": _b("6")}, ["3/2 A", "6 V"], false,
			"a battery in the pair fixes the meter at its own voltage")
	_api({"p_top": _b("9"), "p_bot": _b("12")}, ["SHORT", "SHORT"], false, "9 V and 12 V side by side in the pair")


func _solve() -> void:
	print("-- solve")
	var meters: Dictionary = {"am1": "", "vm1": ""}

	# The 9 V by the spawn, up the left side into p_top.
	await _walk_to_x(NINE_X)
	await _pick("b9")
	await _climb_to_p_top()
	await _plug("p_top")
	meters["am1"] = "0 A"
	meters["vm1"] = "9 V"
	_expect(["0 A", "9 V"], false, "9 V across the pair, main line open", meters)

	# The 12 V from the right ledge into p_bot: two batteries across the pair.
	await _drop_through(LEFT_STEP_Y, "drops through to the left step")
	await _drop_through(FLOOR_Y, "drops through to the floor")
	await _jump_from(TWELVE_X, 0, RIGHT_LEDGE_Y, "jumps straight up onto the right ledge")
	await _pick("b12")
	await _jump_from(TO_P_BOT_JUMP_X, -1, P_BOT_PLATFORM_Y, "jumps left onto the p_bot platform")
	await _walk_to_x(P_BOT_X)
	await _plug("p_bot")
	meters["am1"] = "SHORT"
	meters["vm1"] = "SHORT"
	_expect(["SHORT", "SHORT"], false, "9 V and 12 V in the pair", meters)
	_check(_room.get_board().get_last_solution().status == DcSolution.Status.SHORT, "the board's circuit is SHORT")

	# The 12 V moves to the source slot.
	await _pull("p_bot", "b12")
	_expect(["0 A", "9 V"], false, "12 V pulled out again", meters_of("0 A", "9 V"))
	await _drop_through(FLOOR_Y, "drops through the p_bot platform to the floor")
	await _walk_to_x(SRC_X)
	await _plug("src")
	_expect(["0 A", "9 V"], false, "12 V in src, ser empty", meters_of("0 A", "9 V"))

	# The 3 ohm from the left ledge into p_top; the 9 V comes out and is put down.
	await _jump_from(UNDER_LEFT_LEDGE_X, 0, LEFT_LEDGE_Y, "jumps straight up onto the left ledge")
	await _walk_to_x(THREE_X)
	await _pick("r3")
	await _jump_from(TO_LEFT_STEP_JUMP_X, 1, LEFT_STEP_Y, "jumps right onto the left step")
	await _jump_from(UNDER_P_TOP_X, 0, P_TOP_PLATFORM_Y, "jumps straight up onto the p_top platform")
	await _walk_to_x(P_TOP_X)
	await _swap("p_top", "b9")
	_expect(["0 A", "0 V"], false, "3 Ω in p_top, ser empty", meters_of("0 A", "0 V"))
	await _drop_through(LEFT_STEP_Y, "drops through to the left step")
	await _put_down()

	# A 4 ohm from the right floor into ser.
	await _drop_through(FLOOR_Y, "drops through to the floor")
	await _walk_to_x(FOUR_X)
	await _pick("r4b")
	await _walk_to_x(SER_X)
	await _plug("ser")
	_expect(["12/7 A", "36/7 V"], false, "12 V, 4 Ω, 3 Ω alone in the pair", meters_of("12/7 A", "36/7 V"))

	# The 6 ohm from the high shelf into p_bot.
	await _jump_from(SIX_X, 0, RIGHT_LEDGE_Y, "jumps straight up onto the right ledge")
	await _jump_from(SIX_X, 0, SHELF_Y, "jumps straight up onto the high shelf")
	await _walk_to_x(SIX_X)
	await _pick("r6")
	await _drop_through(RIGHT_LEDGE_Y, "drops through the shelf to the right ledge")
	await _jump_from(TO_P_BOT_JUMP_X, -1, P_BOT_PLATFORM_Y, "jumps left onto the p_bot platform")
	await _walk_to_x(P_BOT_X)
	await _plug("p_bot")
	_expect(["2 A", "4 V"], true, "12 V, 4 Ω, 3 Ω || 6 Ω", meters_of("2 A", "4 V"))
	_check(_hud.get_row_value(0) == "2 A  →  2 A" and _hud.get_row_value(1) == "4 V  →  4 V",
			"both plaque rows show reading and target (got '%s' / '%s')" % [_hud.get_row_value(0), _hud.get_row_value(1)])

	# Off the p_bot platform, up the right ledge and onto the door's shelf.
	await _walk_to_x(OFF_P_BOT_X)
	_check_on(FLOOR_Y, "walks off the p_bot platform to the floor")
	await _jump_from(UNDER_SHELF_X, 0, RIGHT_LEDGE_Y, "jumps straight up onto the right ledge")
	await _jump_from(UNDER_SHELF_X, 0, SHELF_Y, "jumps straight up onto the door's shelf")


## From the floor: up the left ledge and the left step to the p_top platform.
func _climb_to_p_top() -> void:
	await _jump_from(UNDER_LEFT_LEDGE_X, 0, LEFT_LEDGE_Y, "jumps straight up onto the left ledge")
	await _jump_from(TO_LEFT_STEP_JUMP_X, 1, LEFT_STEP_Y, "jumps right onto the left step")
	await _jump_from(UNDER_P_TOP_X, 0, P_TOP_PLATFORM_Y, "jumps straight up onto the p_top platform")
	await _walk_to_x(P_TOP_X)


func meters_of(current: String, voltage: String) -> Dictionary:
	return {"am1": current, "vm1": voltage}


func _enter_door() -> void:
	print("-- door")
	var action: String = "move_right" if DOOR.x > _player.position.x else "move_left"
	Input.action_press(action)
	for i: int in MAX_WALK_FRAMES:
		await _wait_physics(1)
		if _room.is_complete():
			break
	_release_all()
	_check(_room.is_complete() and _completed_count == 1,
			"walking into the open door completes the level (player at %s, door at %s)" % [_player.position, DOOR])
	_check(_hud.is_level_complete_shown(), "the level-complete banner is shown")


# --- helpers ------------------------------------------------------------------------

## The plaque shows `readings` (one per goal condition), every board meter in
## `meters` (id -> text) shows its text, and the door and the mission sign are
## open exactly when `met`.
func _expect(readings: Array[String], met: bool, what: String, meters: Dictionary = {}) -> void:
	var ok: bool = true
	var got: Array[String] = []
	for i: int in readings.size():
		got.append(_hud.get_reading_text(i))
		if got[i] != readings[i]:
			ok = false
	for id: String in meters.keys():
		var meter: BoardMeter = _room.get_board().get_meter(id)
		var text: String = meter.get_reading() if meter != null else "missing"
		got.append("%s %s" % [id, text])
		if text != String(meters[id]):
			ok = false
	_check(ok, "%s: reads %s %s (got %s)" % [what, readings, meters.values() if not meters.is_empty() else "", got])
	_check(_door.is_open() == met and _room.get_board().is_goal_met() == met and _hud.is_mission_complete_shown() == met,
			"%s: door %s" % [what, "open" if met else "closed"])
	if met:
		var all_green: bool = true
		for i: int in readings.size():
			all_green = all_green and _hud.is_condition_met_shown(i)
		_check(all_green and _room.get_board().get_wires().get_state() == CircuitWires.State.MATCH,
				"%s: every plaque row is green and the wires show the match colour" % what)


## Solves `fill` (slot id -> Part) with the circuit API and checks the goal's
## reading texts and whether the goal is met.
func _api(fill: Dictionary, readings: Array[String], met: bool, what: String) -> void:
	var solution: DcSolution = DcSolver.solve(_room.get_circuit().build_network(fill))
	var goal: LevelGoal = _room.get_goal()
	var got: Array[String] = []
	for i: int in goal.condition_count():
		got.append(goal.reading_text(i, solution))
	_check(got == readings and goal.is_met(solution) == met,
			"%s reads %s, goal %s (got %s, %s)" % [what, readings, "met" if met else "not met", got,
				"met" if goal.is_met(solution) else "not met"])


func _r(ohms: String) -> Part:
	return Part.create(Part.Kind.RESISTOR, Rational.parse(ohms))


func _b(volts: String) -> Part:
	return Part.create(Part.Kind.BATTERY, Rational.parse(volts))


func _bind_room(main: Node) -> bool:
	_room = main.get_node_or_null(ROOM_PATH) as Room
	if _room == null or _room.level_data == null or _room.get_player() == null or _room.get_carry() == null:
		_check(false, "room, level data, player and carry exist")
		_room = null
		return false
	_player = _room.get_player()
	_carry = _room.get_carry()
	_hud = _room.get_hud()
	_door = _room.get_door()
	_room.level_completed.connect(func() -> void: _completed_count += 1)
	return true


func _part(id: String) -> PartPickup:
	for pickup: PartPickup in _room.get_parts():
		if pickup.part_id == id:
			return pickup
	return null


func _socket(id: String) -> CircuitSocket:
	for socket: CircuitSocket in _room.get_board().get_sockets():
		if socket.socket_id == id:
			return socket
	return null


func _on_surface(surface_y: float) -> bool:
	return _player.is_on_floor() and absf(_player.position.y - surface_y) <= POSITION_TOLERANCE


## Checks that Ohmie stands on the surface at `surface_y`.
func _check_on(surface_y: float, what: String) -> void:
	_check(_on_surface(surface_y), "%s (at %s, surface y=%.0f)" % [what, _player.position, surface_y])


## Picks up `id` where Ohmie stands and checks it is carried.
func _pick(id: String) -> void:
	await _interact()
	_check(_carry.get_carried() == _part(id), "picks up %s (carrying %s)" % [id,
			_carry.get_carried().part_id if _carry.is_carrying() else "nothing"])


## Plugs the carried part into empty slot `slot_id` where Ohmie stands.
func _plug(slot_id: String) -> void:
	var held: PartPickup = _carry.get_carried()
	await _interact()
	_check(held != null and not _carry.is_carrying() and _socket(slot_id).get_pickup() == held,
			"plugs %s into %s" % [held.part_id if held != null else "nothing", slot_id])


## Swaps the carried part into filled slot `slot_id`; checks Ohmie now carries `out_id`.
func _swap(slot_id: String, out_id: String) -> void:
	var held: PartPickup = _carry.get_carried()
	await _interact()
	_check(held != null and _socket(slot_id).get_pickup() == held and _carry.get_carried() == _part(out_id),
			"swaps %s into %s and takes out %s" % [held.part_id if held != null else "nothing", slot_id, out_id])


## Pulls the part out of slot `slot_id`; checks Ohmie now carries `out_id`.
func _pull(slot_id: String, out_id: String) -> void:
	await _interact()
	_check(not _socket(slot_id).is_filled() and _carry.get_carried() == _part(out_id),
			"pulls %s out of %s" % [out_id, slot_id])


## Puts the carried part down at Ohmie's feet (nothing in reach).
func _put_down() -> void:
	var held: PartPickup = _carry.get_carried()
	await _interact()
	_check(held != null and not _carry.is_carrying() and held.is_loose(),
			"puts %s down (at %s)" % [held.part_id if held != null else "nothing", held.global_position if held != null else Vector2.ZERO])


## Holds left or right until the player's x reaches `x`, then lets go and waits
## for a fall from a ledge to finish.
func _walk_to_x(x: float) -> void:
	var action: String = "move_right" if x > _player.position.x else "move_left"
	var going_right: bool = action == "move_right"
	Input.action_press(action)
	for i: int in MAX_WALK_FRAMES:
		await _wait_physics(1)
		if (going_right and _player.position.x >= x) or (not going_right and _player.position.x <= x):
			break
	Input.action_release(action)
	await _wait_physics(2)
	for i: int in MAX_AIR_FRAMES:
		if _player.is_on_floor():
			break
		await _wait_physics(1)
	await _wait_physics(2)
	if absf(_player.position.x - x) > POSITION_TOLERANCE:
		print("      (walk to x=%.0f ended at x=%.1f)" % [x, _player.position.x])


## Jumps (holding left for direction -1, right for 1, nothing for 0) with a full
## jump hold and waits until the player has left the floor and landed again.
func _jump_and_land(direction: int) -> void:
	var move_action: String = ""
	if direction < 0:
		move_action = "move_left"
	elif direction > 0:
		move_action = "move_right"
	if not move_action.is_empty():
		Input.action_press(move_action)
	Input.action_press("jump")
	var left_floor: bool = false
	for i: int in MAX_AIR_FRAMES:
		await _wait_physics(1)
		if not _player.is_on_floor():
			left_floor = true
		elif left_floor:
			break
	Input.action_release("jump")
	if not move_action.is_empty():
		Input.action_release(move_action)
	await _wait_physics(3)


## Walks to `x`, jumps in `direction` and checks the landing surface.
func _jump_from(x: float, direction: int, surface_y: float, what: String) -> void:
	await _walk_to_x(x)
	await _jump_and_land(direction)
	_check_on(surface_y, what)


## Holds move_down to drop through the one-way platform Ohmie stands on and
## waits for the landing below.
func _drop_through(surface_y: float, what: String) -> void:
	var start_y: float = _player.position.y
	Input.action_press("move_down")
	var left_floor: bool = false
	for i: int in MAX_AIR_FRAMES:
		await _wait_physics(1)
		if not _player.is_on_floor():
			left_floor = true
			Input.action_release("move_down")
		elif left_floor and _player.position.y > start_y + POSITION_TOLERANCE:
			break
	Input.action_release("move_down")
	await _wait_physics(3)
	_check_on(surface_y, what)


func _interact() -> void:
	Input.action_press("interact")
	await _wait_physics(1)
	Input.action_release("interact")
	await _wait_physics(2)


func _wait_physics(frames: int) -> void:
	for i: int in frames:
		await physics_frame


func _release_all() -> void:
	for action: String in ACTIONS:
		Input.action_release(action)


func _check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("PASS  " + description)
	else:
		_failed += 1
		print("FAIL  " + description)
