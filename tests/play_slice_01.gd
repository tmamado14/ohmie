extends SceneTree
## Scripted headless playthrough of res://levels/slice_01.json ("Half and Half":
## s1 in series with s2 || s3; resistors 1/2, 1, 1 and a 2 decoy).
##
## First checks the decoy with the circuit API: 2 + (1 || 1) = 5/2, no match.
## Then solves the level start to finish through the input map only (no
## teleporting): 1/2 from the left ledge into s1 (still OPEN), 1 from the right
## ledge into s2 (3/2, door closed), the floor 1 into s3 (1, door open, mission
## sign done), pulls s3 out and plugs it back (sign reverts, then done again),
## and walks into the door.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --script res://tests/play_slice_01.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
const LEVEL_PATH: String = "res://levels/slice_01.json"
const ROOM_PATH: NodePath = ^"Room"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]
const TITLE: String = "Half and Half"
const MISSION: String = "Make exactly 1 Ω between A and B to unlock the door."

## Layout facts of slice_01.json.
const SPAWN: Vector2 = Vector2(96, 640)
const FLOOR_Y: float = 640.0
const LEFT_LEDGE_Y: float = 455.0  # row 14, columns 6..10
const S1_PLATFORM_Y: float = 551.0  # row 17, columns 13..18
const S2_PLATFORM_Y: float = 455.0  # row 14, columns 20..25
const RIGHT_LEDGE_Y: float = 359.0  # row 11, columns 28..32
const HALF_X: float = 272.0  # 1/2 ohm on the left ledge
const ONE_LEDGE_X: float = 976.0  # 1 ohm on the right ledge
const ONE_FLOOR_X: float = 1008.0  # 1 ohm on the floor
const S1_X: float = 512.0  # s1 is used from the S1 platform
const S2_X: float = 736.0  # s2 is used from the S2 platform
const S3_X: float = 736.0  # s3 is used from the floor
const TO_LEFT_LEDGE_JUMP_X: float = 440.0  # S1 platform -> left ledge
const TO_S2_JUMP_X: float = 590.0  # S1 platform -> S2 platform
const TO_RIGHT_LEDGE_JUMP_X: float = 815.0  # S2 platform -> right ledge
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
	print("play_slice_01: %d passed, %d failed" % [_passed, _failed])
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
	_check_decoy()
	await _solve()
	return 0 if _failed == 0 else 1


func _check_start_state() -> void:
	print("-- start")
	_check(_room.level_data.title == TITLE, "level title is '%s' (got '%s')" % [TITLE, _room.level_data.title])
	_check(_hud.get_equivalent_text() == "OPEN", "initial readout is OPEN (got '%s')" % _hud.get_equivalent_text())
	_check(not _door.is_open(), "door starts closed")
	_check(_room.get_goal() != null and _room.get_goal().mission == MISSION,
			"the level's mission is '%s'" % MISSION)
	_check(_hud.get_mission_text() == _room.get_goal().mission,
			"the mission sign shows the level's mission (got '%s')" % _hud.get_mission_text())
	_check(_hud.get_goal_text() == "1 Ω", "the plaque shows GOAL 1 Ω (got '%s')" % _hud.get_goal_text())
	_check(not _hud.is_mission_complete_shown(), "the mission sign starts not done")
	_check(_player.position.distance_to(SPAWN) <= POSITION_TOLERANCE and _player.is_on_floor(),
			"player starts on the floor at spawn (%s)" % _player.position)


## The 2 ohm decoy in s1 with both 1 ohm in s2 / s3 reads 5/2 and is no match.
func _check_decoy() -> void:
	print("-- decoy (circuit API)")
	var filled: Dictionary = {"s1": Rational.new(2), "s2": Rational.new(1), "s3": Rational.new(1)}
	var result: CircuitResult = CircuitSolver.solve(_room.get_circuit().build_graph(filled))
	_check(result.status == CircuitResult.Status.OK and result.value.equals(Rational.new(5, 2)),
			"2 + (1 || 1) = 5/2 (got '%s')" % result.to_text())
	_check(not result.matches(_room.get_target()), "the decoy combination does not match the 1 Ω target")


func _solve() -> void:
	print("-- solve")
	var half: ResistorPickup = _pickup("r_half")
	var one_ledge: ResistorPickup = _pickup("r_one_ledge")
	var one_floor: ResistorPickup = _pickup("r_one_floor")
	if half == null or one_ledge == null or one_floor == null:
		_check(false, "pickups r_half, r_one_ledge and r_one_floor exist")
		return

	# Up onto the S1 platform, then across to the left ledge for the 1/2 ohm.
	await _walk_to_x(S1_X)
	await _jump_and_land(0)
	_check(_on_surface(S1_PLATFORM_Y), "jumps straight up onto the S1 platform (%s)" % _player.position)
	await _walk_to_x(TO_LEFT_LEDGE_JUMP_X)
	await _jump_and_land(-1)
	_check(_on_surface(LEFT_LEDGE_Y), "jumps left onto the left ledge (%s)" % _player.position)
	await _walk_to_x(HALF_X)
	await _interact()
	_check(_carry.get_carried() == half, "picks up the 1/2 Ω resistor")

	# Off the ledge's right end back onto the S1 platform, plug into s1.
	await _walk_to_x(S1_X)
	_check(_on_surface(S1_PLATFORM_Y), "walks off the left ledge back onto the S1 platform (%s)" % _player.position)
	await _interact()
	_check(not _carry.is_carrying() and _socket("s1").get_resistor() == half,
			"plugs the 1/2 Ω into s1")
	_check(_hud.get_equivalent_text() == "OPEN" and not _door.is_open(),
			"s1 alone: readout stays OPEN, door closed (got '%s')" % _hud.get_equivalent_text())

	# Across to the S2 platform and up to the right ledge for a 1 ohm.
	await _walk_to_x(TO_S2_JUMP_X)
	await _jump_and_land(1)
	_check(_on_surface(S2_PLATFORM_Y), "jumps right onto the S2 platform (%s)" % _player.position)
	await _walk_to_x(TO_RIGHT_LEDGE_JUMP_X)
	await _jump_and_land(1)
	_check(_on_surface(RIGHT_LEDGE_Y), "jumps right onto the right ledge (%s)" % _player.position)
	await _walk_to_x(ONE_LEDGE_X)
	await _interact()
	_check(_carry.get_carried() == one_ledge, "picks up the 1 Ω resistor on the right ledge")

	# Off the ledge's left end back onto the S2 platform, plug into s2.
	await _walk_to_x(S2_X)
	_check(_on_surface(S2_PLATFORM_Y), "walks off the right ledge back onto the S2 platform (%s)" % _player.position)
	await _interact()
	_check(not _carry.is_carrying() and _socket("s2").get_resistor() == one_ledge,
			"plugs the 1 Ω into s2")
	_check(_hud.get_equivalent_text() == "3/2 Ω" and not _door.is_open(),
			"s1 + s2: readout 3/2 Ω, door closed (got '%s')" % _hud.get_equivalent_text())

	# Off the S2 platform's right end to the floor, fetch the floor 1 ohm, plug into s3.
	await _walk_to_x(ONE_FLOOR_X)
	_check(_on_surface(FLOOR_Y), "walks off the S2 platform down to the floor (%s)" % _player.position)
	await _interact()
	_check(_carry.get_carried() == one_floor, "picks up the 1 Ω resistor on the floor")
	await _walk_to_x(S3_X)
	await _interact()
	_check(not _carry.is_carrying() and _socket("s3").get_resistor() == one_floor,
			"plugs the 1 Ω into s3")
	_check(_hud.get_equivalent_text() == "1 Ω" and _door.is_open(),
			"1/2 + (1 || 1): readout 1 Ω and the door opens (got '%s')" % _hud.get_equivalent_text())
	_check(_room.get_board().get_last_result().matches(_room.get_target()), "board reports a match")
	_check(_hud.is_mission_complete_shown(), "at 1 Ω the mission sign shows its done state")

	# Pull the s3 resistor out: the sign reverts. Plug it back: done again.
	await _interact()
	_check(_carry.get_carried() == one_floor and not _socket("s3").is_filled(),
			"pulls the 1 Ω back out of s3")
	_check(not _hud.is_mission_complete_shown() and not _door.is_open(),
			"pulled out: mission sign no longer done, door closed (readout '%s')" % _hud.get_equivalent_text())
	await _interact()
	_check(_socket("s3").get_resistor() == one_floor and _hud.is_mission_complete_shown() and _door.is_open(),
			"plugged back: mission sign done again, door open (readout '%s')" % _hud.get_equivalent_text())

	# Walk into the door.
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
