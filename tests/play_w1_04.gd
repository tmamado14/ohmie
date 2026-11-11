extends SceneTree
## Scripted headless playthrough of res://levels/w1_04.json ("Chain Gang": a
## fixed 6 V battery, slot s1 on the floor and slot s2 on a raised platform in
## series, and the ammeter am1; resistors 1, 2, 3 and 4 ohm; goal: am1 reads
## 1 A, so the two slots must add up to 6 ohm: 2 + 4).
##
## First checks with the circuit API that series resistors add (no single
## resistor gives 1 A; 2 + 4 does, either way round; the near 3 and 1 do not).
## Then plays the room through the input map only (no teleporting): the
## tempting 3 ohm next to s1 into s1 (0 A, loop open), up to the platform and
## across to the high ledge for the 2 ohm, back down into s2 (6/5 A: wrong,
## door closed), off the platform's far end for the 4 ohm on the floor, back to
## s1 to swap out the 3 ohm (1 A, door open), then right into the door.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --fixed-fps 60 --script res://tests/play_w1_04.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
const LEVEL_PATH: String = "res://levels/w1_04.json"
const ROOM_PATH: NodePath = ^"Room"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]
const TITLE: String = "Chain Gang"
const MISSION: String = "Draw 1 A."
const METER_ID: String = "am1"

## Layout facts of w1_04.json.
const SPAWN: Vector2 = Vector2(96, 640)
const FLOOR_Y: float = 640.0
const S2_PLATFORM_Y: float = 551.0  # row 17, columns 19..28 (x 608..928)
const HIGH_LEDGE_Y: float = 487.0  # row 15, columns 30..33 (x 960..1088)
const THREE_X: float = 528.0  # 3 ohm on the floor beside s1
const TWO_X: float = 1024.0  # 2 ohm on the high ledge
const FOUR_X: float = 1056.0  # 4 ohm on the floor under the high ledge
const S1_X: float = 336.0  # s1 is used from the floor
const S2_X: float = 688.0  # s2 is used from the platform
const TO_S2_PLATFORM_JUMP_X: float = 640.0
const TO_HIGH_LEDGE_JUMP_X: float = 880.0
const DOOR_X: float = 1180.0

const POSITION_TOLERANCE: float = 6.0
const SETTLE_FRAMES: int = 20
const MAX_WALK_FRAMES: int = 600
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
	print("play_w1_04: %d passed, %d failed" % [_passed, _failed])
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
	_check_series()
	await _solve()
	Room.level_override = ""
	return 0 if _failed == 0 else 1


func _check_start_state() -> void:
	print("-- start")
	_check(_room.level_data.title == TITLE, "level title is '%s' (got '%s')" % [TITLE, _room.level_data.title])
	_check(_hud.get_mission_text() == MISSION, "the mission sign shows '%s' (got '%s')" % [MISSION, _hud.get_mission_text()])
	_check(_hud.get_row_caption(0) == "GOAL" and _hud.get_row_value(0) == "1 A" and _hud.get_row_caption(1) == "I",
			"the plaque shows GOAL 1 A and an I row (got '%s %s' / '%s')" % [_hud.get_row_caption(0),
				_hud.get_row_value(0), _hud.get_row_caption(1)])
	_check_reading("0 A", "initial reading")
	_check(not _hud.is_mission_complete_shown(), "the mission sign starts not done")
	_check(not _door.is_open(), "door starts closed")
	_check(_player.position.distance_to(SPAWN) <= POSITION_TOLERANCE and _player.is_on_floor(),
			"player starts on the floor at spawn (%s)" % _player.position)


## Series resistors add: only 2 + 4 = 6 ohm draws 1 A from 6 V.
func _check_series() -> void:
	print("-- series (circuit API)")
	var goal: LevelGoal = _room.get_goal()
	var cases: Array[Array] = [
		[{"s1": _resistor(4)}, "0 A", false, "4 Ω alone (s2 empty: open loop)"],
		[{"s1": _resistor(3), "s2": _resistor(1)}, "3/2 A", false, "3 Ω + 1 Ω, the two near parts"],
		[{"s1": _resistor(3), "s2": _resistor(4)}, "6/7 A", false, "3 Ω + 4 Ω"],
		[{"s1": _resistor(2), "s2": _resistor(4)}, "1 A", true, "2 Ω + 4 Ω"],
		[{"s1": _resistor(4), "s2": _resistor(2)}, "1 A", true, "4 Ω + 2 Ω"],
	]
	for entry: Array in cases:
		var solution: DcSolution = DcSolver.solve(_room.get_circuit().build_network(entry[0]))
		var shown: String = MeterText.reading(solution, METER_ID)
		_check(shown == entry[1] and goal.is_met(solution) == entry[2],
				"%s reads %s (got '%s'), goal %s" % [entry[3], entry[1], shown, "met" if entry[2] else "not met"])


func _solve() -> void:
	print("-- solve")
	var three: PartPickup = _part("r3")
	var two: PartPickup = _part("r2")
	var four: PartPickup = _part("r4")
	if three == null or two == null or four == null:
		_check(false, "parts r3, r2 and r4 exist")
		return
	var s1: CircuitSocket = _socket("s1")
	var s2: CircuitSocket = _socket("s2")

	# The tempting 3 ohm beside s1.
	await _walk_to_x(THREE_X)
	await _interact()
	_check(_carry.get_carried() == three, "picks up the 3 Ω resistor beside s1")
	await _walk_to_x(S1_X)
	await _interact()
	_check(not _carry.is_carrying() and s1.get_pickup() == three, "plugs the 3 Ω into s1")
	_check_reading("0 A", "3 Ω in s1, s2 empty (open loop)")
	_check(not _door.is_open(), "open loop: door closed")

	# Up onto the platform (the room's one 3-tile rise), across to the high ledge.
	await _walk_to_x(TO_S2_PLATFORM_JUMP_X)
	await _jump_and_land(0)
	_check(_on_surface(S2_PLATFORM_Y), "jumps straight up onto the s2 platform (%s)" % _player.position)
	await _walk_to_x(TO_HIGH_LEDGE_JUMP_X)
	await _jump_and_land(1)
	_check(_on_surface(HIGH_LEDGE_Y), "jumps right onto the high ledge (%s)" % _player.position)
	await _walk_to_x(TWO_X)
	await _interact()
	_check(_carry.get_carried() == two, "picks up the 2 Ω resistor on the high ledge")

	# Back down onto the platform, into s2.
	await _walk_to_x(S2_X)
	_check(_on_surface(S2_PLATFORM_Y), "walks off the high ledge back onto the s2 platform (%s)" % _player.position)
	await _interact()
	_check(not _carry.is_carrying() and s2.get_pickup() == two, "plugs the 2 Ω into s2")
	_check_reading("6/5 A", "3 Ω + 2 Ω")
	_check(not _door.is_open() and not _hud.is_mission_complete_shown(), "at 6/5 A the door stays closed")

	# Off the platform's far end for the 4 ohm, back to s1 to swap out the 3 ohm.
	await _walk_to_x(FOUR_X)
	_check(_on_surface(FLOOR_Y), "walks off the platform's right end to the floor (%s)" % _player.position)
	await _interact()
	_check(_carry.get_carried() == four, "picks up the 4 Ω resistor on the floor")
	await _walk_to_x(S1_X)
	_check(_on_surface(FLOOR_Y), "walks back under the platform to s1 (%s)" % _player.position)
	await _interact()
	_check(s1.get_pickup() == four and _carry.get_carried() == three, "swaps the 4 Ω into s1, carrying the 3 Ω")
	_check_reading("1 A", "4 Ω + 2 Ω")
	_check(_door.is_open() and _room.get_board().is_goal_met(), "at 1 A the door opens")
	_check(_hud.is_mission_complete_shown() and _hud.is_condition_met_shown(0)
			and _hud.get_row_value_color(1) == Hud.COLOR_MATCH,
			"at 1 A the mission sign shows its done state and the reading row is green")
	_check(_room.get_board().get_wires().get_state() == CircuitWires.State.MATCH, "wires show the match colour")

	# Right into the door, still carrying the 3 ohm.
	Input.action_press("move_right")
	for i: int in MAX_WALK_FRAMES:
		await _wait_physics(1)
		if _room.is_complete():
			break
	_release_all()
	_check(_room.is_complete() and _completed_count == 1,
			"walking into the open door completes the level (player at %s, door x=%.0f)" % [_player.position, DOOR_X])
	_check(_hud.is_level_complete_shown(), "the level-complete banner is shown")


# --- helpers ------------------------------------------------------------------------

## The plaque's reading and the ammeter on the board both read `expected`.
func _check_reading(expected: String, what: String) -> void:
	var shown: String = _hud.get_reading_text(0)
	var meter: String = _room.get_board().get_meter(METER_ID).get_reading()
	_check(shown == expected and meter == expected and _hud.get_row_value(1) == expected,
			"%s: the plaque and the ammeter read %s (plaque '%s', meter '%s')" % [what, expected, shown, meter])


func _resistor(ohms: int) -> Part:
	return Part.create(Part.Kind.RESISTOR, Rational.new(ohms, 1))


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
	if absf(_player.position.x - x) > POSITION_TOLERANCE:
		print("      (walk to x=%.0f ended at x=%.1f)" % [x, _player.position.x])


## Jumps (holding left for direction -1, right for 1, nothing for 0) and waits
## until the player has left the floor and landed again.
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
	await _wait_physics(2)


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
