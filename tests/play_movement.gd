extends SceneTree
## Scripted headless movement test on res://levels/dev_room.json.
##
## Drives input through the input map, frame by frame, and checks that Ohmie
## lands at spawn, runs at the right speed, jumps to the right height, can jump
## onto and drop through a one-way platform, and respawns after falling in the pit.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --script res://tests/play_movement.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
const ROOM_PATH: NodePath = ^"Room"
const PLAYER_PATH: NodePath = ^"Room/Player"
const PHYSICS_FPS: float = 60.0

## Layout facts of dev_room.json.
const FLOOR_Y: float = 640.0
## Lower one-way platform: tiles in row 17 (top edge y = 544), columns 10..15.
## The collision surface is 7 px below the tile's top edge.
const LOWER_PLATFORM_Y: float = 551.0
const LOWER_PLATFORM_CENTRE_X: float = 416.0

const POSITION_TOLERANCE: float = 2.0
const RUN_SPEED: float = 240.0
const RUN_SPEED_TOLERANCE: float = 10.0
const APEX_MIN: float = 105.0
const APEX_MAX: float = 130.0
const SPEED_SAMPLE_FRAMES: int = 30
const SETTLE_FRAMES: int = 30
const MAX_WAIT_FRAMES: int = 180
const PIT_MAX_WAIT_FRAMES: int = 400

const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]

var _passed: int = 0
var _failed: int = 0
var _player: Player = null
var _spawn: Vector2 = Vector2.ZERO
var _jump_count: int = 0
var _land_count: int = 0
var _fell_out_count: int = 0
var _position_after_fell_out: Vector2 = Vector2.ZERO


func _initialize() -> void:
	_run()


func _run() -> void:
	var exit_code: int = await _run_checks()
	_release_all()
	print("")
	print("play_movement: %d passed, %d failed" % [_passed, _failed])
	quit(exit_code)


func _run_checks() -> int:
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_check(false, "main scene loads")
		return 1
	var main: Node = packed.instantiate()
	root.add_child(main)
	current_scene = main
	await _wait_physics(1)

	var room: Room = main.get_node_or_null(ROOM_PATH) as Room
	_player = main.get_node_or_null(PLAYER_PATH) as Player
	if room == null or room.level_data == null or _player == null:
		_check(false, "room, level data and player exist")
		return 1
	_spawn = room.level_data.spawn
	_player.jumped.connect(func() -> void: _jump_count += 1)
	_player.landed.connect(func() -> void: _land_count += 1)
	_player.fell_out.connect(_on_fell_out)

	await _check_lands_at_spawn()
	await _check_run_speed()
	await _check_jump_apex()
	await _check_one_way_platform()
	await _check_pit_respawn()
	return 0 if _failed == 0 else 1


func _check_lands_at_spawn() -> void:
	await _wait_physics(SETTLE_FRAMES)
	_check(_player.is_on_floor() and _player.position.distance_to(_spawn) <= POSITION_TOLERANCE,
		"lands on the floor at spawn (position %s, spawn %s, on floor %s)" % [_player.position, _spawn, _player.is_on_floor()])


func _check_run_speed() -> void:
	Input.action_press("move_right")
	await _wait_physics(2)
	var start_x: float = _player.position.x
	await _wait_physics(SPEED_SAMPLE_FRAMES)
	var end_x: float = _player.position.x
	Input.action_release("move_right")
	var speed: float = (end_x - start_x) * PHYSICS_FPS / SPEED_SAMPLE_FRAMES
	_check(absf(speed - RUN_SPEED) <= RUN_SPEED_TOLERANCE,
		"holding move_right runs right at about %d px/s (measured %.1f px/s)" % [int(RUN_SPEED), speed])


func _check_jump_apex() -> void:
	await _wait_physics(5)
	var floor_y: float = _player.position.y
	var jumps_before: int = _jump_count
	var lands_before: int = _land_count
	Input.action_press("jump")
	var min_y: float = floor_y
	var left_floor: bool = false
	for i: int in MAX_WAIT_FRAMES:
		await _wait_physics(1)
		min_y = minf(min_y, _player.position.y)
		if not _player.is_on_floor():
			left_floor = true
		elif left_floor:
			break
	Input.action_release("jump")
	var apex: float = floor_y - min_y
	_check(left_floor and apex >= APEX_MIN and apex <= APEX_MAX,
		"jump from the floor peaks %.0f..%.0f px above it (measured %.1f px)" % [APEX_MIN, APEX_MAX, apex])
	_check(_jump_count == jumps_before + 1 and _land_count == lands_before + 1 and _player.is_on_floor(),
		"jump emits jumped and landed once each and ends on the floor (jumped %d, landed %d)" % [_jump_count - jumps_before, _land_count - lands_before])


func _check_one_way_platform() -> void:
	# Walk under the middle of the lower platform.
	Input.action_press("move_right")
	for i: int in MAX_WAIT_FRAMES:
		await _wait_physics(1)
		if _player.position.x >= LOWER_PLATFORM_CENTRE_X:
			break
	Input.action_release("move_right")
	await _wait_physics(3)
	_check(_player.is_on_floor() and absf(_player.position.y - FLOOR_Y) <= POSITION_TOLERANCE,
		"walks on the floor under the lower platform (position %s)" % _player.position)

	# Jump straight up through it and land on top.
	Input.action_press("jump")
	var left_floor: bool = false
	for i: int in MAX_WAIT_FRAMES:
		await _wait_physics(1)
		if not _player.is_on_floor():
			left_floor = true
		elif left_floor:
			break
	Input.action_release("jump")
	_check(left_floor and _player.is_on_floor() and absf(_player.position.y - LOWER_PLATFORM_Y) <= POSITION_TOLERANCE,
		"jumps up through the lower one-way platform and lands on it (position %s)" % _player.position)

	await _wait_physics(SETTLE_FRAMES)
	_check(_player.is_on_floor() and absf(_player.position.y - LOWER_PLATFORM_Y) <= POSITION_TOLERANCE,
		"stands on the lower platform (position %s)" % _player.position)

	# Hold move_down to drop back to the floor.
	Input.action_press("move_down")
	var reached_floor: bool = false
	for i: int in MAX_WAIT_FRAMES:
		await _wait_physics(1)
		if _player.is_on_floor() and _player.position.y > LOWER_PLATFORM_Y + POSITION_TOLERANCE:
			reached_floor = true
			break
	Input.action_release("move_down")
	await _wait_physics(3)
	_check(reached_floor and _player.is_on_floor() and absf(_player.position.y - FLOOR_Y) <= POSITION_TOLERANCE,
		"drops through the platform with move_down onto the floor (position %s)" % _player.position)


func _check_pit_respawn() -> void:
	var fell_before: int = _fell_out_count
	Input.action_press("move_right")
	for i: int in PIT_MAX_WAIT_FRAMES:
		await _wait_physics(1)
		if _fell_out_count > fell_before:
			break
	Input.action_release("move_right")
	_check(_fell_out_count == fell_before + 1, "walking into the pit emits fell_out once (count %d)" % (_fell_out_count - fell_before))
	_check(_position_after_fell_out.distance_to(_spawn) <= POSITION_TOLERANCE,
		"fell_out respawns at spawn (position right after %s)" % _position_after_fell_out)
	await _wait_physics(SETTLE_FRAMES)
	_check(_player.is_on_floor() and _player.position.distance_to(_spawn) <= POSITION_TOLERANCE and _fell_out_count == fell_before + 1,
		"after respawn stands on the floor at spawn (position %s)" % _player.position)


func _on_fell_out() -> void:
	# The room's handler is connected first, so the respawn has already happened.
	_fell_out_count += 1
	_position_after_fell_out = _player.position


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
