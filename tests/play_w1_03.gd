extends SceneTree
## Scripted headless playthrough of res://levels/w1_03.json ("Ohm Sweet Ohm":
## one loop of slot s1 (floor), slot s2 (low platform) and the ammeter am1;
## 3 V and 9 V batteries, 1, 3 and 6 ohm resistors; goal: am1 reads 3 A).
##
## First checks the circuit with the API: both answers (3 V with 1 ohm, 9 V
## with 3 ohm) read +3 A whichever slot holds the battery, and the 6 ohm decoy
## never gives 3 A. Then plays the room from the right-hand spawn through the
## input map only (no teleporting): the tempting 9 V by the spawn into s1 (0 A,
## loop open), the 1 ohm from the far left up onto the platform into s2 (9 A:
## the wrong pair, door closed), the 3 V from the floor swapped into s1 (3 A,
## door open, carrying the 9 V), then left into the door.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --fixed-fps 60 --script res://tests/play_w1_03.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
const LEVEL_PATH: String = "res://levels/w1_03.json"
const ROOM_PATH: NodePath = ^"Room"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]
const TITLE: String = "Ohm Sweet Ohm"
const MISSION: String = "Draw 3 A."
const METER_ID: String = "am1"

## Layout facts of w1_03.json.
const SPAWN: Vector2 = Vector2(1200, 640)
const FLOOR_Y: float = 640.0
const S2_PLATFORM_Y: float = 583.0  # row 18, columns 13..18 (x 416..608)
const NINE_V_X: float = 1104.0  # 9 V on the floor by the spawn
const ONE_X: float = 216.0  # 1 ohm on the floor, far left
const THREE_V_X: float = 352.0  # 3 V on the floor under the high ledge
const S1_X: float = 752.0  # s1 is used from the floor
const S2_X: float = 528.0  # s2 is used from the low platform
const TO_S2_PLATFORM_JUMP_X: float = 450.0
const HIGH_LEDGE_Y: float = 519.0  # row 16, columns 7..11 (x 224..384)
const THREE_OHM_X: float = 304.0  # 3 ohm on the high ledge
const TO_HIGH_LEDGE_JUMP_X: float = 430.0  # s2 platform -> high ledge
const OFF_HIGH_LEDGE_X: float = 180.0  # past the high ledge's left end
const DOOR_X: float = 100.0

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
	print("play_w1_03: %d passed, %d failed" % [_passed, _failed])
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
	_check_answers()
	await _solve()
	Room.level_override = ""
	return 0 if _failed == 0 else 1


func _check_start_state() -> void:
	print("-- start")
	_check(_room.level_data.title == TITLE, "level title is '%s' (got '%s')" % [TITLE, _room.level_data.title])
	_check(_hud.get_mission_text() == MISSION, "the mission sign shows '%s' (got '%s')" % [MISSION, _hud.get_mission_text()])
	_check(_hud.get_row_caption(0) == "GOAL" and _hud.get_row_value(0) == "3 A" and _hud.get_row_caption(1) == "I",
			"the plaque shows GOAL 3 A and an I row (got '%s %s' / '%s')" % [_hud.get_row_caption(0),
				_hud.get_row_value(0), _hud.get_row_caption(1)])
	_check_reading("0 A", "initial reading")
	_check(not _hud.is_mission_complete_shown(), "the mission sign starts not done")
	_check(not _door.is_open(), "door starts closed")
	_check(_player.position.distance_to(SPAWN) <= POSITION_TOLERANCE and _player.is_on_floor(),
			"player starts on the floor at spawn (%s)" % _player.position)


## Both answers, with the battery in either slot, read +3 A; the decoy never fits.
func _check_answers() -> void:
	print("-- answers (circuit API)")
	var goal: LevelGoal = _room.get_goal()
	var cases: Array[Array] = [
		[_battery(3), _resistor(1), "3 A", true, "3 V in s1, 1 Ω in s2"],
		[_resistor(1), _battery(3), "3 A", true, "1 Ω in s1, 3 V in s2"],
		[_battery(9), _resistor(3), "3 A", true, "9 V in s1, 3 Ω in s2"],
		[_resistor(3), _battery(9), "3 A", true, "3 Ω in s1, 9 V in s2"],
		[_battery(9), _resistor(6), "3/2 A", false, "9 V with the 6 Ω decoy"],
		[_battery(3), _resistor(6), "1/2 A", false, "3 V with the 6 Ω decoy"],
	]
	for entry: Array in cases:
		var solution: DcSolution = DcSolver.solve(_room.get_circuit().build_network({"s1": entry[0], "s2": entry[1]}))
		var shown: String = MeterText.reading(solution, METER_ID)
		_check(shown == entry[2] and goal.is_met(solution) == entry[3],
				"%s reads %s (got '%s'), goal %s" % [entry[4], entry[2], shown, "met" if entry[3] else "not met"])


func _solve() -> void:
	print("-- solve")
	var nine: PartPickup = _part("b9")
	var one: PartPickup = _part("r1")
	var three_v: PartPickup = _part("b3")
	if nine == null or one == null or three_v == null:
		_check(false, "parts b9, r1 and b3 exist")
		return
	var s1: CircuitSocket = _socket("s1")
	var s2: CircuitSocket = _socket("s2")

	# The tempting 9 V by the spawn, into s1 on the floor.
	await _walk_to_x(NINE_V_X)
	await _interact()
	_check(_carry.get_carried() == nine, "picks up the 9 V battery by the spawn")
	await _walk_to_x(S1_X)
	await _interact()
	_check(not _carry.is_carrying() and s1.get_pickup() == nine, "plugs the 9 V into s1")
	_check_reading("0 A", "9 V in s1, s2 empty (open loop)")
	var badges: PolarityBadges = s1.get_polarity_badges()
	_check(badges.is_shown() and not badges.is_plus_on_right(), "the 9 V's + badge is on the left, at s1's 'from' node")

	# Under the platform to the far left for the 1 ohm, then up into s2.
	await _walk_to_x(ONE_X)
	_check(_on_surface(FLOOR_Y), "walks under the platform to the far left (%s)" % _player.position)
	await _interact()
	_check(_carry.get_carried() == one, "picks up the 1 Ω resistor")
	await _walk_to_x(TO_S2_PLATFORM_JUMP_X)
	await _jump_and_land(0)
	_check(_on_surface(S2_PLATFORM_Y), "jumps straight up onto the s2 platform (%s)" % _player.position)
	await _walk_to_x(S2_X)
	await _interact()
	_check(not _carry.is_carrying() and s2.get_pickup() == one, "plugs the 1 Ω into s2")
	_check_reading("9 A", "9 V across 1 Ω")
	_check(not _door.is_open() and not _hud.is_mission_complete_shown(), "at 9 A the door stays closed")
	_check(_room.get_board().get_wires().get_state() == CircuitWires.State.ENERGIZED, "wires show the energized colour")

	# The other answer's 3 ohm is up on the high ledge: hop up, check it is in
	# reach, leave it, and drop off the ledge's far end to the floor.
	await _walk_to_x(TO_HIGH_LEDGE_JUMP_X)
	await _jump_and_land(-1)
	_check(_on_surface(HIGH_LEDGE_Y), "jumps left from the s2 platform onto the high ledge (%s)" % _player.position)
	await _walk_to_x(THREE_OHM_X)
	_check(_carry.get_target() == _part("r3"), "the 3 Ω on the high ledge is in reach")
	await _walk_to_x(OFF_HIGH_LEDGE_X)
	_check(_on_surface(FLOOR_Y), "walks off the high ledge's left end to the floor (%s)" % _player.position)

	# The 3 V on the floor, back under the platform to s1: swap out the 9 V.
	await _walk_to_x(THREE_V_X)
	_check(_on_surface(FLOOR_Y), "walks along the floor to the 3 V (%s)" % _player.position)
	await _interact()
	_check(_carry.get_carried() == three_v, "picks up the 3 V battery")
	await _walk_to_x(S1_X)
	await _interact()
	_check(s1.get_pickup() == three_v and _carry.get_carried() == nine, "swaps the 3 V into s1, carrying the 9 V")
	_check_reading("3 A", "3 V across 1 Ω")
	_check(_door.is_open() and _room.get_board().is_goal_met(), "at 3 A the door opens")
	_check(_hud.is_mission_complete_shown() and _hud.is_condition_met_shown(0)
			and _hud.get_row_value_color(1) == Hud.COLOR_MATCH,
			"at 3 A the mission sign shows its done state and the reading row is green")
	_check(_room.get_board().get_wires().get_state() == CircuitWires.State.MATCH, "wires show the match colour")
	_check(s1.get_icon().get_label_text() == "3 V", "s1 shows the 3 V battery (got '%s')" % s1.get_icon().get_label_text())

	# Left into the door, still carrying the 9 V.
	Input.action_press("move_left")
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


func _battery(volts: int) -> Part:
	return Part.create(Part.Kind.BATTERY, Rational.new(volts, 1))


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
