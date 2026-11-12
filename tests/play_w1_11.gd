extends SceneTree
## Scripted headless playthrough of res://levels/w1_11.json ("Watt's Up": one
## loop of slot src on the floor, slot ser on a raised platform at the right
## and the fixed 3 ohm heater; batteries 6, 10, 12 V and resistors 1, 2, 3,
## 6 ohm; a pit at the far left with the 12 V beyond it; goal: the heater
## burns exactly 12 W, that is 2 A through 3 ohm).
##
## First checks with the circuit API: the two solutions by value (12 V with
## 3 ohm, 10 V with 2 ohm, in either slot), the tempting 6 V (it would give
## 12 W across the heater alone, but the series slot must hold something) and
## other near misses. Then plays the room through the input map only (no
## teleporting): the 6 V from the ledge by the spawn into src (0 W, open), the
## 1 ohm from the top of the inner staircase into ser (27/4 W), a jump over the
## pit for the 12 V, a deliberate fall into the pit while carrying it (Ohmie
## respawns, the 12 V goes home), the 12 V fetched again and swapped into src
## (27 W), the 6 V put down, the 3 ohm swapped into ser (12 W, door open),
## then right into the door.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --fixed-fps 60 --script res://tests/play_w1_11.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
const LEVEL_PATH: String = "res://levels/w1_11.json"
const ROOM_PATH: NodePath = ^"Room"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]

const TITLE: String = "Watt's Up"
const MISSION: String = "Burn 12 W in the heater."
const PLAQUE_CAPTIONS: Array[String] = ["GOAL", "P"]
const PLAQUE_START_VALUES: Array[String] = ["12 W", "0 W"]
const PART_COUNT: int = 7
const SLOT_COUNT: int = 2

## Layout facts of w1_11.json.
const SPAWN: Vector2 = Vector2(1150, 640)
const DOOR: Vector2 = Vector2(1224, 640)
const FLOOR_Y: float = 640.0
const INNER_LOW_Y: float = 551.0  # row 17, x 320..416
const INNER_MID_Y: float = 455.0  # row 14, x 416..544
const INNER_TOP_Y: float = 359.0  # row 11, x 320..512
const RIGHT_LEDGE_Y: float = 551.0  # row 17, x 736..832
const SER_PLATFORM_Y: float = 455.0  # row 14, x 832..960
const PIT_LEFT_X: float = 128.0  # pit columns 4..6, x 128..224
const PIT_RIGHT_X: float = 224.0
const SIX_X: float = 784.0
const ONE_X: float = 464.0
const TWELVE_X: float = 64.0
const THREE_X: float = 368.0
const SRC_X: float = 624.0
const SER_X: float = 912.0
const TO_INNER_MID_JUMP_X: float = 400.0
const TO_INNER_TOP_JUMP_X: float = 470.0
const TO_SER_JUMP_X: float = 800.0
const OVER_PIT_LEFT_JUMP_X: float = 240.0
const OVER_PIT_RIGHT_JUMP_X: float = 104.0
const PUT_DOWN_X: float = 700.0

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
	print("play_w1_11: %d passed, %d failed" % [_passed, _failed])
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
	print("-- power (circuit API)")
	_api({"src": _b("6")}, ["0 W"], false, "6 V alone (ser empty, loop open)")
	_api({"src": _b("6"), "ser": _r("1")}, ["27/4 W"], false, "6 V with 1 Ω")
	_api({"src": _b("6"), "ser": _r("3")}, ["3 W"], false, "6 V with 3 Ω")
	_api({"src": _b("12"), "ser": _r("1")}, ["27 W"], false, "12 V with 1 Ω")
	_api({"src": _b("12"), "ser": _r("6")}, ["16/3 W"], false, "12 V with 6 Ω")
	_api({"src": _b("6"), "ser": _b("10")}, ["256/3 W"], false, "6 V with 10 V (sources add, heater alone)")
	_api({"src": _b("12"), "ser": _r("3")}, ["12 W"], true, "12 V with 3 Ω")
	_api({"src": _b("10"), "ser": _r("2")}, ["12 W"], true, "10 V with 2 Ω")
	_api({"src": _r("3"), "ser": _b("12")}, ["12 W"], true, "3 Ω in src with 12 V in ser")


func _solve() -> void:
	print("-- solve")
	# The 6 V from the ledge by the spawn into src.
	await _jump_from(SIX_X, 0, RIGHT_LEDGE_Y, "jumps straight up onto the ledge by the spawn")
	await _pick("b6")
	await _drop_through(FLOOR_Y, "drops through the ledge to the floor")
	await _walk_to_x(SRC_X)
	await _plug("src")
	_expect(["0 W"], false, "6 V alone")

	# The 1 ohm from the top of the inner staircase into ser.
	await _jump_from(THREE_X, 0, INNER_LOW_Y, "jumps straight up onto the low inner step")
	await _jump_from(TO_INNER_MID_JUMP_X, 1, INNER_MID_Y, "jumps right onto the middle inner step")
	await _jump_from(TO_INNER_TOP_JUMP_X, 0, INNER_TOP_Y, "jumps straight up onto the top inner step")
	await _walk_to_x(ONE_X)
	await _pick("r1")
	await _drop_through(INNER_MID_Y, "drops through to the middle inner step")
	await _drop_through(FLOOR_Y, "drops through to the floor")
	await _climb_to_ser()
	await _plug("ser")
	_expect(["27/4 W"], false, "6 V with 1 Ω")

	# Over the pit for the 12 V; a fall into the pit sends it home.
	await _drop_through(FLOOR_Y, "drops through the ser platform to the floor")
	await _jump_from(OVER_PIT_LEFT_JUMP_X, -1, FLOOR_Y, "jumps left over the pit")
	_check(_player.position.x < PIT_LEFT_X, "lands left of the pit (x=%.0f)" % _player.position.x)
	await _walk_to_x(TWELVE_X)
	await _pick("b12")
	var twelve: PartPickup = _part("b12")
	await _walk_to_x((PIT_LEFT_X + PIT_RIGHT_X) / 2.0)
	for i: int in MAX_AIR_FRAMES:
		if _player.position.distance_to(SPAWN) <= POSITION_TOLERANCE:
			break
		await _wait_physics(1)
	await _wait_physics(SETTLE_FRAMES)
	_check(_player.position.distance_to(SPAWN) <= POSITION_TOLERANCE and _player.is_on_floor(),
			"walking into the pit respawns Ohmie at the spawn (%s)" % _player.position)
	_check(not _carry.is_carrying() and twelve.is_loose() and twelve.global_position.distance_to(Vector2(TWELVE_X, FLOOR_Y)) < 2.0,
			"the 12 V went back home beyond the pit (%s)" % twelve.global_position)
	_expect(["27/4 W"], false, "the circuit is untouched by the fall")

	# Again, this time back over the pit.
	await _jump_from(OVER_PIT_LEFT_JUMP_X, -1, FLOOR_Y, "jumps left over the pit again")
	await _walk_to_x(TWELVE_X)
	await _pick("b12")
	await _jump_from(OVER_PIT_RIGHT_JUMP_X, 1, FLOOR_Y, "jumps right back over the pit")
	_check(_player.position.x > PIT_RIGHT_X, "lands right of the pit (x=%.0f)" % _player.position.x)
	await _walk_to_x(SRC_X)
	await _swap("src", "b6")
	_expect(["27 W"], false, "12 V with 1 Ω")

	# Put the 6 V down, fetch the 3 ohm from the low inner step.
	await _walk_to_x(PUT_DOWN_X)
	await _put_down()
	await _jump_from(THREE_X, 0, INNER_LOW_Y, "jumps straight up onto the low inner step")
	await _walk_to_x(THREE_X)
	await _pick("r3")
	await _drop_through(FLOOR_Y, "drops through the low inner step to the floor")
	await _climb_to_ser()
	await _swap("ser", "r1")
	_expect(["12 W"], true, "12 V with 3 Ω")


## From the floor: up the ledge by the spawn and right onto the ser platform.
func _climb_to_ser() -> void:
	await _jump_from(SIX_X, 0, RIGHT_LEDGE_Y, "jumps straight up onto the ledge by the spawn")
	await _jump_from(TO_SER_JUMP_X, 1, SER_PLATFORM_Y, "jumps right onto the ser platform")
	await _walk_to_x(SER_X)


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
