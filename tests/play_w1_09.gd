extends SceneTree
## Scripted headless playthrough of res://levels/w1_09.json ("Light Duty": one
## loop of slot s1 on a raised platform, slot s2 on the floor and lamp1, a
## 2 ohm lamp lit from 1 to 3/2 A; both slots face the same way round the loop,
## so a battery in either drives current forward through the lamp; batteries
## 6, 9, 12 V and resistors 2, 4, 6, 10 ohm; goal: the lamp current is between
## 1 and 3/2 A).
##
## First checks with the circuit API: lit, dark and blown combinations, two
## batteries together (always blown), a battery alone (open loop, dark). Then
## plays the room through the input map only (no teleporting): the 9 V by the
## spawn into s2 (open loop, dark), the 2 ohm from the low ledge up into s1
## (9/4 A, the lamp blows), the 10 ohm from the far floor swapped into s1
## (3/4 A, dark), the 2 ohm put down, the 4 ohm from the right ledge swapped
## into s1 (3/2 A, lit, door open), then right into the door.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --fixed-fps 60 --script res://tests/play_w1_09.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
const LEVEL_PATH: String = "res://levels/w1_09.json"
const ROOM_PATH: NodePath = ^"Room"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]

const TITLE: String = "Light Duty"
const MISSION: String = "Light the lamp. Don't blow it."
const PLAQUE_CAPTIONS: Array[String] = ["GOAL", "I"]
const PLAQUE_START_VALUES: Array[String] = ["1–3/2 A", "0 A"]
const PART_COUNT: int = 7
const SLOT_COUNT: int = 2
const LAMP_ID: String = "lamp1"

## Layout facts of w1_09.json.
const SPAWN: Vector2 = Vector2(96, 640)
const DOOR: Vector2 = Vector2(1210, 640)
const FLOOR_Y: float = 640.0
const LOW_LEDGE_Y: float = 551.0  # row 17, x 256..416
const S1_PLATFORM_Y: float = 455.0  # row 14, x 448..608
const RIGHT_LEDGE_Y: float = 551.0  # row 17, x 896..992
const NINE_X: float = 192.0
const TWO_X: float = 320.0
const TEN_X: float = 1072.0
const FOUR_X: float = 944.0
const S1_X: float = 528.0
const S2_X: float = 752.0
const UNDER_LOW_LEDGE_X: float = 336.0
const TO_S1_JUMP_X: float = 400.0
const PUT_DOWN_X: float = 400.0

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
	print("play_w1_09: %d passed, %d failed" % [_passed, _failed])
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
	print("-- lamp range (circuit API)")
	_api({"s2": _b("9")}, ["0 A"], false, "9 V alone (s1 empty, loop open)")
	_api({"s2": _b("9"), "s1": _r("2")}, ["9/4 A"], false, "9 V with 2 Ω (blown)")
	_api({"s2": _b("12"), "s1": _r("2")}, ["3 A"], false, "12 V with 2 Ω (blown)")
	_api({"s2": _b("12"), "s1": _r("4")}, ["2 A"], false, "12 V with 4 Ω (blown)")
	_api({"s2": _b("9"), "s1": _r("10")}, ["3/4 A"], false, "9 V with 10 Ω (dark)")
	_api({"s2": _b("6"), "s1": _r("6")}, ["3/4 A"], false, "6 V with 6 Ω (dark)")
	_api({"s2": _b("9"), "s1": _r("4")}, ["3/2 A"], true, "9 V with 4 Ω (lit at the limit)")
	_api({"s2": _b("9"), "s1": _r("6")}, ["9/8 A"], true, "9 V with 6 Ω (lit)")
	_api({"s1": _b("12"), "s2": _r("10")}, ["1 A"], true, "12 V in s1 with 10 Ω in s2 (lit, battery in the other slot)")
	_api({"s1": _b("6"), "s2": _b("9")}, ["15/2 A"], false, "6 V with 9 V (both batteries add: blown)")
	_check(BoardLamp.state_for(Rational.new(9, 4), Rational.new(1, 1), Rational.new(3, 2)) == BoardLamp.State.BLOWN
			and BoardLamp.state_for(Rational.new(3, 4), Rational.new(1, 1), Rational.new(3, 2)) == BoardLamp.State.OFF
			and BoardLamp.state_for(Rational.new(3, 2), Rational.new(1, 1), Rational.new(3, 2)) == BoardLamp.State.ON,
			"the lamp rating gives blown at 9/4 A, dark at 3/4 A and lit at 3/2 A")


func _solve() -> void:
	print("-- solve")
	# The 9 V by the spawn into s2 on the floor: the loop is open.
	await _walk_to_x(NINE_X)
	await _pick("b9")
	await _walk_to_x(S2_X)
	await _plug("s2")
	_expect(["0 A"], false, "9 V alone")
	_check_lamp(BoardLamp.State.OFF, "9 V alone")

	# The 2 ohm from the low ledge, up into s1: too much current.
	await _jump_from(UNDER_LOW_LEDGE_X, 0, LOW_LEDGE_Y, "jumps straight up onto the low ledge")
	await _walk_to_x(TWO_X)
	await _pick("r2")
	await _jump_from(TO_S1_JUMP_X, 1, S1_PLATFORM_Y, "jumps right onto the s1 platform")
	await _walk_to_x(S1_X)
	await _plug("s1")
	_expect(["9/4 A"], false, "9 V with 2 Ω")
	_check_lamp(BoardLamp.State.BLOWN, "9 V with 2 Ω")

	# The 10 ohm from the far floor: too little current.
	await _drop_through(FLOOR_Y, "drops through the s1 platform to the floor")
	await _walk_to_x(TEN_X)
	await _pick("r10")
	await _climb_to_s1()
	await _swap("s1", "r2")
	_expect(["3/4 A"], false, "9 V with 10 Ω")
	_check_lamp(BoardLamp.State.OFF, "9 V with 10 Ω")

	# Put the 2 ohm down, fetch the 4 ohm from the right ledge.
	await _drop_through(FLOOR_Y, "drops through the s1 platform to the floor again")
	await _walk_to_x(PUT_DOWN_X)
	await _put_down()
	await _jump_from(FOUR_X, 0, RIGHT_LEDGE_Y, "jumps straight up onto the right ledge")
	await _pick("r4")
	await _drop_through(FLOOR_Y, "drops through the right ledge to the floor")
	await _climb_to_s1()
	await _swap("s1", "r10")
	_expect(["3/2 A"], true, "9 V with 4 Ω")
	_check_lamp(BoardLamp.State.ON, "9 V with 4 Ω")


## From the floor: up onto the low ledge, right onto the s1 platform, to s1.
func _climb_to_s1() -> void:
	await _jump_from(UNDER_LOW_LEDGE_X, 0, LOW_LEDGE_Y, "jumps straight up onto the low ledge")
	await _jump_from(TO_S1_JUMP_X, 1, S1_PLATFORM_Y, "jumps right onto the s1 platform")
	await _walk_to_x(S1_X)


func _check_lamp(expected: BoardLamp.State, what: String) -> void:
	var lamp: BoardLamp = _room.get_board().get_lamp(LAMP_ID)
	var state: int = lamp.get_state() if lamp != null else -1
	_check(state == expected, "%s: the lamp is %s (got %s)" % [what, BoardLamp.State.keys()[expected],
			BoardLamp.State.keys()[state] if state >= 0 else "missing"])


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
