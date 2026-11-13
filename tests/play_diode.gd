extends SceneTree
## Scripted headless playthrough of res://levels/dev_diode.json (a Copper
## Foundry development room in engineering numbers: a fixed 6 V battery, a
## 1 kΩ lamp lit from 3 to 6 mA with ammeter am1 in series, and two slots on
## parallel branches between the same nodes: s_fwd on the floor with its `from`
## on the battery-plus side, s_rev on a platform facing the other way. Parts: a
## 0.7 V diode and a 1 kΩ resistor. Goal: lamp current 5–6 mA).
##
## Drives input through the input map only (no teleporting): carries the diode
## to s_rev (0 A, lamp dark, door shut, plain wires, picture mirrored), moves it
## to s_fwd (5.3 mA, lamp lit, door open, match wires, picture not mirrored),
## pulls it out (door shuts), puts it down, plugs the resistor into s_fwd
## (3 mA, lamp lit, door shut), swaps the diode back in and walks through the
## door. Checks the diode's name tag and plaque text, and that no ERROR or
## WARNING is logged.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --fixed-fps 60 --script res://tests/play_diode.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
const LEVEL_PATH: String = "res://levels/dev_diode.json"
const ROOM_PATH: NodePath = ^"Room"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]
const LAMP_ID: String = "lamp1"
const AMMETER_ID: String = "am1"
const GOAL_TEXT: String = "5–6 mA"
const DIODE_TAG: String = "diode 0.7 V"
const DIODE_PLAQUE: String = "0.7 V"
const RESISTOR_TAG: String = "1 kΩ"
## Exact engine texts (QuantityText ENGINEERING).
const READING_OFF: String = "0 A"
const READING_DIODE: String = "5.3 mA"
const READING_RESISTOR: String = "3 mA"

## Layout facts of dev_diode.json.
const FLOOR_Y: float = 640.0
const STEP_Y: float = 551.0
const UPPER_Y: float = 487.0
const DIODE_X: float = 208.0
const RESISTOR_X: float = 1040.0
const SLOT_X: float = 640.0  # both slots are centred above this x
const STEP_JUMP_X: float = 368.0  # jump straight up onto the step platform here
const UPPER_JUMP_X: float = 440.0  # jump right onto the upper platform here
const OFF_UPPER_X: float = 800.0  # walk off the upper platform's right end here
const PUT_DOWN_X: float = 880.0  # nothing within reach here
const DOOR_X: float = 1180.0

const POSITION_TOLERANCE: float = 6.0
const SETTLE_FRAMES: int = 20
const MAX_WALK_FRAMES: int = 600
const MAX_AIR_FRAMES: int = 180


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

	func lines() -> PackedStringArray:
		_mutex.lock()
		var copy: PackedStringArray = _lines.duplicate()
		_mutex.unlock()
		return copy


var _passed: int = 0
var _failed: int = 0
var _logger: ErrorCounter = null

var _room: Room = null
var _player: Player = null
var _carry: PlayerCarry = null
var _hud: Hud = null
var _door: ExitDoor = null
var _completed_count: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_logger = ErrorCounter.new()
	OS.add_logger(_logger)
	var exit_code: int = await _run_checks()
	_release_all()
	var errors: PackedStringArray = _logger.lines()
	_check(errors.is_empty(), "no ERROR or WARNING was logged (%d logged)" % errors.size())
	for i: int in mini(errors.size(), 10):
		print("      " + errors[i])
	if not errors.is_empty():
		exit_code = 1
	OS.remove_logger(_logger)
	print("")
	print("play_diode: %d passed, %d failed" % [_passed, _failed])
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
	_check_start()
	await _play()
	Room.level_override = ""
	return 0 if _failed == 0 else 1


func _check_start() -> void:
	print("-- start")
	_check(_room.level_data.world == "copper_foundry"
			and _room.get_room_theme() == RoomTheme.load_for_world("copper_foundry"),
			"the room uses the Copper Foundry theme")
	_check(_hud.get_row_caption(0) == "GOAL" and _hud.get_row_value(0) == GOAL_TEXT,
			"the plaque shows GOAL %s (got '%s %s')" % [GOAL_TEXT, _hud.get_row_caption(0), _hud.get_row_value(0)])
	_check_state(READING_OFF, BoardLamp.State.OFF, "initial state")
	_check(not _door.is_open(), "door starts closed")
	var diode: PartPickup = _part("d1")
	var resistor: PartPickup = _part("r1")
	if diode == null or resistor == null:
		_check(false, "parts d1 and r1 exist")
		return
	_check(diode.get_tag_text() == DIODE_TAG, "the loose diode's name tag reads '%s' (got '%s')" % [
			DIODE_TAG, diode.get_tag_text()])
	_check(diode.get_icon().get_label_text() == DIODE_PLAQUE and not diode.get_icon().is_flipped(),
			"the loose diode's plaque reads '%s' and is not mirrored (got '%s')" % [
				DIODE_PLAQUE, diode.get_icon().get_label_text()])
	_check(resistor.get_tag_text() == RESISTOR_TAG and resistor.get_icon().get_label_text() == RESISTOR_TAG,
			"the 1k resistor reads '%s' (tag '%s', plaque '%s')" % [RESISTOR_TAG, resistor.get_tag_text(),
				resistor.get_icon().get_label_text()])


func _play() -> void:
	var diode: PartPickup = _part("d1")
	var resistor: PartPickup = _part("r1")
	var s_fwd: CircuitSocket = _socket("s_fwd")
	var s_rev: CircuitSocket = _socket("s_rev")
	if diode == null or resistor == null or s_fwd == null or s_rev == null:
		_check(false, "parts d1, r1 and slots s_fwd, s_rev exist")
		return

	print("-- diode in s_rev")
	await _walk_to_x(DIODE_X)
	await _interact()
	_check(_carry.get_carried() == diode, "picks up the diode")
	await _walk_to_x(STEP_JUMP_X)
	await _jump_and_land(0)
	_check(_on_surface(STEP_Y), "jumps onto the step platform (%s)" % _player.position)
	await _walk_to_x(UPPER_JUMP_X)
	await _jump_and_land(1)
	_check(_on_surface(UPPER_Y), "jumps onto the upper platform (%s)" % _player.position)
	await _walk_to_x(SLOT_X)
	await _interact()
	_check(s_rev.get_pickup() == diode and not _carry.is_carrying(), "plugs the diode into s_rev")
	_check_state(READING_OFF, BoardLamp.State.OFF, "reversed diode")
	_check(not _door.is_open() and not _room.get_board().is_goal_met(), "reversed diode: door shut")
	_check(_room.get_board().get_wires().get_state() == CircuitWires.State.PLAIN,
			"reversed diode: the wires show the plain state")
	_check(s_rev.get_icon().is_flipped() and s_rev.get_icon().get_label_text() == DIODE_PLAQUE,
			"s_rev's from node is on the right: the picture is mirrored, the plaque still reads '%s'" % DIODE_PLAQUE)
	_check(s_rev.get_tag_text() == DIODE_TAG, "s_rev's name tag reads '%s' (got '%s')" % [DIODE_TAG, s_rev.get_tag_text()])
	_check(not s_rev.get_polarity_badges().is_shown(), "no battery badges for a diode")

	print("-- diode in s_fwd")
	await _interact()
	_check(_carry.get_carried() == diode and not s_rev.is_filled(), "pulls the diode out of s_rev")
	_check(not diode.get_icon().is_flipped(), "a carried diode is not mirrored")
	await _walk_to_x(OFF_UPPER_X)
	_check(_on_surface(FLOOR_Y), "walks off the platform to the floor (%s)" % _player.position)
	await _walk_to_x(SLOT_X)
	await _interact()
	_check(s_fwd.get_pickup() == diode, "plugs the diode into s_fwd")
	_check_state(READING_DIODE, BoardLamp.State.ON, "forward diode")
	_check(_door.is_open() and _room.get_board().is_goal_met() and _hud.is_mission_complete_shown(),
			"forward diode: the goal holds and the door opens")
	_check(_room.get_board().get_wires().get_state() == CircuitWires.State.MATCH, "the wires show the match state")
	_check(not s_fwd.get_icon().is_flipped() and s_fwd.get_icon().get_label_text() == DIODE_PLAQUE,
			"s_fwd's from node is on the left: the picture is not mirrored")

	print("-- pull out, resistor in s_fwd")
	await _interact()
	_check(_carry.get_carried() == diode and not s_fwd.is_filled(), "pulls the diode out of s_fwd")
	_check_state(READING_OFF, BoardLamp.State.OFF, "both slots empty")
	_check(not _door.is_open(), "pulled out: the door shuts")
	await _walk_to_x(PUT_DOWN_X)
	await _interact()
	_check(not _carry.is_carrying() and diode.is_loose(), "puts the diode down")
	await _walk_to_x(RESISTOR_X)
	await _interact()
	_check(_carry.get_carried() == resistor, "picks up the resistor")
	await _walk_to_x(SLOT_X)
	await _interact()
	_check(s_fwd.get_pickup() == resistor, "plugs the resistor into s_fwd")
	_check_state(READING_RESISTOR, BoardLamp.State.ON, "1 kΩ in s_fwd")
	_check(not _door.is_open(), "1 kΩ in s_fwd: the lamp is lit but the door stays shut")

	print("-- swap the diode back in and leave")
	await _walk_to_x(diode.global_position.x)
	await _interact()
	_check(_carry.get_carried() == diode, "picks the diode up again")
	await _walk_to_x(SLOT_X)
	await _interact()
	_check(s_fwd.get_pickup() == diode and _carry.get_carried() == resistor, "swaps the diode in for the resistor")
	_check_state(READING_DIODE, BoardLamp.State.ON, "diode swapped in")
	_check(_door.is_open(), "the door is open again")
	Input.action_press("move_right")
	for i: int in MAX_WALK_FRAMES:
		await _wait_physics(1)
		if _room.is_complete():
			break
	_release_all()
	_check(_room.is_complete() and _completed_count == 1,
			"walking into the open door completes the level (player at %s, door x=%.0f)" % [_player.position, DOOR_X])


# --- helpers ------------------------------------------------------------------------

## The ammeter and the plaque read `reading` and the lamp is in `lamp_state`.
func _check_state(reading: String, lamp_state: BoardLamp.State, what: String) -> void:
	var meter: BoardMeter = _room.get_board().get_meter(AMMETER_ID)
	var meter_text: String = meter.get_reading() if meter != null else "missing"
	var lamp: BoardLamp = _room.get_board().get_lamp(LAMP_ID)
	var state: int = lamp.get_state() if lamp != null else -1
	_check(meter_text == reading and _hud.get_reading_text(0) == reading and _hud.get_row_value(1) == reading
			and state == lamp_state,
			"%s: ammeter and plaque read %s, lamp %s (meter '%s', plaque '%s', lamp %s)" % [what, reading,
				BoardLamp.State.keys()[lamp_state], meter_text, _hud.get_reading_text(0),
				BoardLamp.State.keys()[state] if state >= 0 else "missing"])


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


## Jumps (holding the key) moving `direction` (-1, 0, 1) and waits to land.
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
