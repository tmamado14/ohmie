extends SceneTree
## Scripted headless playthrough of res://levels/level_02.json ("Ohm's Law": a
## 6 V battery across s1 in series with s2; goal 2 A, so 3 Ω; resistors 4, 2,
## 6 and 1 Ω).
##
## First checks the decoys with the circuit API: 4 + 2 gives 1 A and 1 + 6
## gives 6/7 A, neither meets the goal. Then solves the level start to finish
## through the input map only (no teleporting): the 2 Ω from the left ledge
## into s1 (0 A, door closed), the 1 Ω from the floor into s2 from the socket
## platform (2 A, mission done, door open), and walks into the door.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --fixed-fps 60 --script res://tests/play_level_02.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
const LEVEL_PATH: String = "res://levels/level_02.json"
const ROOM_PATH: NodePath = ^"Room"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]
const TITLE: String = "Ohm's Law"
const MISSION: String = "Ohm's law: I = V / R. Draw exactly 2 A from the 6 V battery."

## Layout facts of level_02.json.
const SPAWN: Vector2 = Vector2(96, 640)
const FLOOR_Y: float = 640.0
const LEFT_LEDGE_Y: float = 551.0  # row 17, columns 4..8
const SOCKET_PLATFORM_Y: float = 551.0  # row 17, columns 18..22
const TWO_X: float = 208.0  # 2 ohm on the left ledge
const ONE_X: float = 1020.0  # 1 ohm on the floor
const S1_X: float = 424.0  # s1 is used from the floor
const S2_X: float = 640.0  # s2 is used from the socket platform
const TO_SOCKET_PLATFORM_JUMP_X: float = 650.0
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
	print("play_level_02: %d passed, %d failed" % [_passed, _failed])
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
	_check_decoys()
	await _solve()
	return 0 if _failed == 0 else 1


func _check_start_state() -> void:
	print("-- start")
	_check(_room.level_data.title == TITLE, "level title is '%s' (got '%s')" % [TITLE, _room.level_data.title])
	_check(_hud.get_goal_text() == "2 A", "the plaque shows GOAL 2 A (got '%s')" % _hud.get_goal_text())
	_check(_hud.get_reading_caption() == "I", "the reading row is captioned I (got '%s')" % _hud.get_reading_caption())
	_check(_hud.get_equivalent_text() == "0 A", "initial reading is 0 A (got '%s')" % _hud.get_equivalent_text())
	_check(_hud.get_mission_text() == MISSION, "the mission sign shows '%s' (got '%s')" % [MISSION, _hud.get_mission_text()])
	_check(not _hud.is_mission_complete_shown(), "the mission sign starts not done")
	_check(not _door.is_open(), "door starts closed")
	_check(_player.position.distance_to(SPAWN) <= POSITION_TOLERANCE and _player.is_on_floor(),
			"player starts on the floor at spawn (%s)" % _player.position)


## Decoy combinations through the circuit API, judged by the level's goal.
func _check_decoys() -> void:
	print("-- decoys (circuit API)")
	_check_combination(Rational.new(4), Rational.new(2), "1 A")
	_check_combination(Rational.new(1), Rational.new(6), "6/7 A")


func _check_combination(s1: Rational, s2: Rational, expected: String) -> void:
	var filled: Dictionary = {"s1": s1, "s2": s2}
	var result: CircuitResult = CircuitSolver.solve(_room.get_circuit().build_graph(filled))
	var goal: LevelGoal = _room.get_goal()
	_check(goal.reading_label(result) == expected and not goal.is_met(result),
			"%s Ω + %s Ω reads %s and does not meet the goal (got '%s')" % [
				s1.to_text(), s2.to_text(), expected, goal.reading_label(result)])


func _solve() -> void:
	print("-- solve")
	var two: ResistorPickup = _pickup("r2")
	var one: ResistorPickup = _pickup("r4")
	if two == null or one == null:
		_check(false, "pickups r2 and r4 exist")
		return

	# Straight up onto the left ledge for the 2 ohm.
	await _walk_to_x(TWO_X)
	await _jump_and_land(0)
	_check(_on_surface(LEFT_LEDGE_Y), "jumps straight up onto the left ledge (%s)" % _player.position)
	await _interact()
	_check(_carry.get_carried() == two, "picks up the 2 Ω resistor")

	# Off the ledge's right end to the floor, plug into s1.
	await _walk_to_x(S1_X)
	_check(_on_surface(FLOOR_Y), "walks off the left ledge down to the floor (%s)" % _player.position)
	await _interact()
	_check(not _carry.is_carrying() and _socket("s1").get_resistor() == two, "plugs the 2 Ω into s1")
	_check(_hud.get_equivalent_text() == "0 A" and not _door.is_open(),
			"s1 alone: reading stays 0 A, door closed (got '%s')" % _hud.get_equivalent_text())

	# The 1 ohm on the floor, then up onto the socket platform and into s2.
	await _walk_to_x(ONE_X)
	_check(_on_surface(FLOOR_Y), "walks along the floor to the 1 Ω (%s)" % _player.position)
	await _interact()
	_check(_carry.get_carried() == one, "picks up the 1 Ω resistor")
	await _walk_to_x(TO_SOCKET_PLATFORM_JUMP_X)
	await _jump_and_land(0)
	_check(_on_surface(SOCKET_PLATFORM_Y), "jumps straight up onto the socket platform (%s)" % _player.position)
	await _walk_to_x(S2_X)
	await _interact()
	_check(not _carry.is_carrying() and _socket("s2").get_resistor() == one, "plugs the 1 Ω into s2")
	_check(_hud.get_equivalent_text() == "2 A" and _door.is_open(),
			"2 Ω + 1 Ω: reading 2 A and the door opens (got '%s')" % _hud.get_equivalent_text())
	_check(_room.get_goal().is_met(_room.get_board().get_last_result()), "the board's reading meets the goal")
	_check(_hud.is_mission_complete_shown(), "at 2 A the mission sign shows its done state")

	# Off the platform to the floor, then into the door.
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


func _pickup(id: String) -> ResistorPickup:
	for pickup: ResistorPickup in _room.get_pickups():
		if pickup.pickup_id == id:
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
