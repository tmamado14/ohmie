extends SceneTree
## Scripted headless playthrough of res://levels/dev_room.json (two parallel
## sockets, resistors 2, 2 and a 4 decoy).
##
## Drives input through the input map only (no teleporting). Part 1 checks the
## interaction edge cases: interact with nothing near, drop and pick up again,
## no pick-up while carrying, swap at a socket, and a fall into the pit
## returning the carried resistor home with the circuit untouched. Then it
## restarts the room with the `restart` action. Part 2 solves the level: plug
## in 2 and 2, pull one out and put it back, and walk into the open door.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --script res://tests/play_slice.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
## This test is written for dev_room.json, whatever level main.tscn defaults to.
const LEVEL_PATH: String = "res://levels/dev_room.json"
const ROOM_PATH: NodePath = ^"Room"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]

## Layout facts of dev_room.json.
const SPAWN: Vector2 = Vector2(96, 640)
const FLOOR_Y: float = 640.0
const LOWER_PLATFORM_Y: float = 551.0
const UPPER_PLATFORM_Y: float = 455.0
const R1_HOME: Vector2 = Vector2(200, 640)  # 2 ohm on the floor
const R2_HOME: Vector2 = Vector2(384, 551)  # 2 ohm on the lower platform
const R3_HOME: Vector2 = Vector2(880, 640)  # 4 ohm decoy on the floor
const DROP_X: float = 300.0  # nothing within reach here
const SOCKET_X: float = 640.0  # both sockets are centred above this x
const UPPER_JUMP_X: float = 470.0  # jump from the lower to the upper platform here
const PIT_RUN_UP_X: float = 900.0
const DOOR_JUMP_X: float = 930.0  # jump over the pit towards the door here

const POSITION_TOLERANCE: float = 6.0
const SETTLE_FRAMES: int = 20
const MAX_WALK_FRAMES: int = 600
const MAX_AIR_FRAMES: int = 180
const RESTART_FRAMES: int = 10

var _passed: int = 0
var _failed: int = 0

var _room: Room = null
var _player: Player = null
var _carry: PlayerCarry = null
var _hud: Hud = null
var _door: ExitDoor = null

var _invalid_count: int = 0
var _picked_count: int = 0
var _placed_count: int = 0
var _removed_count: int = 0
var _swapped_count: int = 0
var _dropped_count: int = 0
var _fell_out_count: int = 0
var _completed_count: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var exit_code: int = await _run_checks()
	_release_all()
	print("")
	print("play_slice: %d passed, %d failed" % [_passed, _failed])
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

	await _part_one_edge_cases()
	await _restart_room()
	if _room == null:
		return 1
	await _part_two_solve()
	return 0 if _failed == 0 else 1


# --- part 1: edge cases ----------------------------------------------------------

func _part_one_edge_cases() -> void:
	print("-- part 1: interaction edge cases")
	_check(_hud.get_equivalent_text() == "OPEN", "initial readout is OPEN (got '%s')" % _hud.get_equivalent_text())
	_check(not _door.is_open(), "door starts closed")
	_check(_player.position.distance_to(SPAWN) <= POSITION_TOLERANCE, "player starts at spawn (%s)" % _player.position)

	var invalid_before: int = _invalid_count
	await _interact()
	_check(_invalid_count == invalid_before + 1 and not _carry.is_carrying()
			and _hud.get_equivalent_text() == "OPEN" and _all_pickups_at_home(),
			"interact with empty hands and nothing near: invalid action only, nothing changes")

	var r1: ResistorPickup = _pickup("r1")
	var r3: ResistorPickup = _pickup("r3")
	await _walk_to_x(R1_HOME.x)
	await _interact()
	_check(_carry.get_carried() == r1 and not r1.is_loose() and _picked_count == 1,
			"picks up the 2 ohm resistor r1")

	await _walk_to_x(DROP_X)
	var drop_x: float = _player.position.x
	await _interact()
	_check(not _carry.is_carrying() and r1.is_loose() and _dropped_count == 1
			and r1.global_position.distance_to(Vector2(drop_x, FLOOR_Y)) <= POSITION_TOLERANCE,
			"carrying with nothing near puts r1 down at the feet (at %s)" % r1.global_position)
	await _interact()
	_check(_carry.get_carried() == r1 and _picked_count == 2, "the dropped r1 can be picked up again")

	await _walk_to_x(R3_HOME.x)
	invalid_before = _invalid_count
	_check(_carry.get_target() != r3, "while carrying, the loose 4 ohm r3 is not highlighted")
	await _interact()
	_check(_carry.get_carried() == r1 and r3.is_loose() and _invalid_count == invalid_before + 1,
			"interact while carrying next to a loose resistor does not pick it up (invalid action)")

	await _walk_to_x(SOCKET_X)
	await _interact()
	_check(_placed_count == 1 and not _carry.is_carrying() and _hud.get_equivalent_text() == "2 Ω",
			"r1 plugged into the floor socket reads 2 Ω (got '%s')" % _hud.get_equivalent_text())

	await _walk_to_x(R3_HOME.x)
	await _interact()
	_check(_carry.get_carried() == r3, "picks up r3 with empty hands")
	await _walk_to_x(SOCKET_X)
	await _interact()
	_check(_swapped_count == 1 and _carry.get_carried() == r1 and _hud.get_equivalent_text() == "4 Ω"
			and not _door.is_open(),
			"carrying r3 at the filled socket swaps: socket reads 4 Ω, r1 now carried (got '%s')" % _hud.get_equivalent_text())

	var fell_before: int = _fell_out_count
	await _walk_to_x(PIT_RUN_UP_X)
	Input.action_press("move_right")
	for i: int in MAX_WALK_FRAMES:
		await _wait_physics(1)
		if _fell_out_count > fell_before:
			break
	Input.action_release("move_right")
	await _wait_physics(SETTLE_FRAMES)
	_check(_fell_out_count == fell_before + 1, "walks into the pit while carrying r1")
	_check(not _carry.is_carrying() and r1.is_loose()
			and r1.global_position.distance_to(R1_HOME) <= 0.5,
			"after the fall r1 is back at its home %s (at %s)" % [R1_HOME, r1.global_position])
	_check(_hud.get_equivalent_text() == "4 Ω" and not r3.is_loose(),
			"the fall leaves the circuit untouched (readout '%s')" % _hud.get_equivalent_text())
	_check(_player.position.distance_to(SPAWN) <= POSITION_TOLERANCE and _player.is_on_floor(),
			"player respawned at spawn (%s)" % _player.position)


# --- part 2: solve the level --------------------------------------------------------

func _part_two_solve() -> void:
	print("-- part 2: solve")
	_check(_hud.get_equivalent_text() == "OPEN" and not _door.is_open() and _all_pickups_at_home()
			and not _room.is_complete(),
			"after restart: readout OPEN, door closed, resistors at home")

	await _walk_to_x(R1_HOME.x)
	await _interact()
	_check(_carry.get_carried() == _pickup("r1"), "picks up the first 2 ohm resistor")
	await _walk_to_x(SOCKET_X)
	await _interact()
	_check(_hud.get_equivalent_text() == "2 Ω" and not _door.is_open(),
			"plugged into the floor socket: readout 2 Ω, door closed (got '%s')" % _hud.get_equivalent_text())

	# The second 2 ohm lies on the lower platform: stand under it and jump up.
	await _walk_to_x(R2_HOME.x)
	await _jump_and_land()
	_check(absf(_player.position.y - LOWER_PLATFORM_Y) <= POSITION_TOLERANCE,
			"jumps onto the lower platform (y %.1f)" % _player.position.y)
	await _interact()
	_check(_carry.get_carried() == _pickup("r2"), "picks up the second 2 ohm resistor")

	# Run and jump across to the upper platform under the top socket.
	await _walk_to_x(UPPER_JUMP_X)
	Input.action_press("move_right")
	await _jump_and_land()
	Input.action_release("move_right")
	_check(absf(_player.position.y - UPPER_PLATFORM_Y) <= POSITION_TOLERANCE,
			"jumps up to the upper platform (position %s)" % _player.position)
	await _walk_to_x(SOCKET_X)
	await _interact()
	_check(_hud.get_equivalent_text() == "1 Ω" and _door.is_open(),
			"both 2 Ω in parallel: readout 1 Ω and the door opens (got '%s')" % _hud.get_equivalent_text())
	_check(_room.get_board().get_last_result().matches(Rational.new(1)), "board reports a match")

	await _interact()
	_check(_removed_count == 1 and _carry.is_carrying() and not _door.is_open()
			and _hud.get_equivalent_text() == "2 Ω",
			"pulling one out closes the door again (readout '%s')" % _hud.get_equivalent_text())
	await _interact()
	_check(not _carry.is_carrying() and _door.is_open() and _hud.get_equivalent_text() == "1 Ω",
			"putting it back opens the door again")

	# Walk off the platform, jump the pit and run into the door.
	await _walk_to_x(DOOR_JUMP_X)
	Input.action_press("move_right")
	Input.action_press("jump")
	for i: int in MAX_WALK_FRAMES:
		await _wait_physics(1)
		if _room.is_complete():
			break
	_release_all()
	_check(_room.is_complete() and _completed_count == 1, "walking into the open door completes the level")
	_check(_hud.is_level_complete_shown(), "the level-complete banner is shown")

	await _wait_physics(SETTLE_FRAMES)
	var x_before: float = _player.position.x
	Input.action_press("move_left")
	await _wait_physics(SETTLE_FRAMES)
	Input.action_release("move_left")
	_check(absf(_player.position.x - x_before) < 0.5, "player input is disabled after completion")

	await _restart_room()
	_check(_room != null and not _room.is_complete() and _hud.get_equivalent_text() == "OPEN",
			"restart still works after completion")


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
	_carry.invalid_action.connect(func() -> void: _invalid_count += 1)
	_carry.picked_up.connect(func(_r: ResistorPickup) -> void: _picked_count += 1)
	_carry.placed.connect(func(_r: ResistorPickup, _s: CircuitSocket) -> void: _placed_count += 1)
	_carry.removed.connect(func(_r: ResistorPickup, _s: CircuitSocket) -> void: _removed_count += 1)
	_carry.swapped.connect(func(_a: ResistorPickup, _b: ResistorPickup, _s: CircuitSocket) -> void: _swapped_count += 1)
	_carry.dropped.connect(func(_r: ResistorPickup) -> void: _dropped_count += 1)
	_player.fell_out.connect(func() -> void: _fell_out_count += 1)
	_room.level_completed.connect(func() -> void: _completed_count += 1)
	return true


func _restart_room() -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = &"restart"
	event.pressed = true
	Input.parse_input_event(event)
	await _wait_physics(2)
	var release: InputEventAction = InputEventAction.new()
	release.action = &"restart"
	release.pressed = false
	Input.parse_input_event(release)
	await _wait_physics(RESTART_FRAMES)
	_reset_counters()
	var old_room: Room = _room
	_room = null
	if current_scene == null or not _bind_room(current_scene) or _room == old_room:
		_check(false, "restart reloads the room")
		_room = null
		return
	await _wait_physics(SETTLE_FRAMES)


func _reset_counters() -> void:
	_invalid_count = 0
	_picked_count = 0
	_placed_count = 0
	_removed_count = 0
	_swapped_count = 0
	_dropped_count = 0
	_fell_out_count = 0
	_completed_count = 0


func _pickup(id: String) -> ResistorPickup:
	for pickup: ResistorPickup in _room.get_pickups():
		if pickup.pickup_id == id:
			return pickup
	return null


func _all_pickups_at_home() -> bool:
	for pickup: ResistorPickup in _room.get_pickups():
		if not pickup.is_loose() or pickup.global_position.distance_to(pickup.home_position) > 0.5:
			return false
	return true


## Holds left or right until the player's x reaches `x`, then lets go.
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
	# Let a fall from a ledge finish before the next step.
	for i: int in MAX_AIR_FRAMES:
		if _player.is_on_floor():
			break
		await _wait_physics(1)
	if absf(_player.position.x - x) > POSITION_TOLERANCE:
		print("      (walk to x=%.0f ended at x=%.1f)" % [x, _player.position.x])


## Presses jump and waits until the player has left the floor and landed again.
func _jump_and_land() -> void:
	Input.action_press("jump")
	var left_floor: bool = false
	for i: int in MAX_AIR_FRAMES:
		await _wait_physics(1)
		if not _player.is_on_floor():
			left_floor = true
		elif left_floor:
			break
	Input.action_release("jump")
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
