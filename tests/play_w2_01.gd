extends SceneTree
## Scripted headless playthrough of res://levels/w2_01.json ("One Way Street",
## World 2 room 1, Copper Foundry, engineering numbers: a fixed 6 V battery, a
## 1 kΩ lamp lit from 3 to 6 mA with ammeter am1 in series, and two slots on
## parallel rungs between the same two buses: s_rev on the floor near the diode,
## facing against the battery, and s_fwd on a low shelf (one jump) facing with
## it. Parts: a 0.7 V diode and a 2 kΩ decoy resistor. Goal: lamp current 3–6 mA).
##
## Drives input through the input map only (no teleporting): carries the diode
## to the nearer slot s_rev (0 A, lamp dark, door shut, plain wires), moves it
## to s_fwd on the shelf (5.3 mA, lamp lit, match wires, door open), pulls it
## out (door shuts) and puts it down; tries the 2 kΩ resistor alone in s_fwd
## and in s_rev (2 mA, lamp dark, door shut each time); plugs the diode back
## into s_fwd beside the resistor (5.3 mA, door open) and walks through the
## door. Checks that no ERROR or WARNING is logged.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --fixed-fps 60 --script res://tests/play_w2_01.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
const LEVEL_PATH: String = "res://levels/w2_01.json"
const ROOM_PATH: NodePath = ^"Room"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]
const TITLE: String = "One Way Street"
const MISSION: String = "Light the lamp."
const LAMP_ID: String = "lamp1"
const AMMETER_ID: String = "am1"
const GOAL_TEXT: String = "3–6 mA"
const DIODE_TAG: String = "diode 0.7 V"
const DIODE_PLAQUE: String = "0.7 V"
const RESISTOR_TAG: String = "2 kΩ"
## Exact engine texts (QuantityText ENGINEERING).
const READING_OFF: String = "0 A"
const READING_DIODE: String = "5.3 mA"
const READING_RESISTOR: String = "2 mA"

## Layout facts of w2_01.json.
const SPAWN: Vector2 = Vector2(96, 640)
const FLOOR_Y: float = 640.0
const SHELF_Y: float = 551.0  # one-way platform in row 17, x 800-928
const DIODE_X: float = 224.0
const RESISTOR_X: float = 1056.0
const S_REV_X: float = 416.0  # floor slot
const S_FWD_X: float = 864.0  # shelf slot; jump straight up from the floor here
const OFF_SHELF_X: float = 960.0  # walk off the shelf's right end here
const PUT_DOWN_X: float = 680.0  # nothing within reach here
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
	print("play_w2_01: %d passed, %d failed" % [_passed, _failed])
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
	_check(_room.level_data.title == TITLE, "level title is '%s' (got '%s')" % [TITLE, _room.level_data.title])
	_check(_room.level_data.world == "copper_foundry"
			and _room.get_room_theme() == RoomTheme.load_for_world("copper_foundry"),
			"the room uses the Copper Foundry theme")
	_check(_hud.get_mission_text() == MISSION, "the mission sign shows '%s' (got '%s')" % [MISSION, _hud.get_mission_text()])
	_check(_hud.get_row_caption(0) == "GOAL" and _hud.get_row_value(0) == GOAL_TEXT,
			"the plaque shows GOAL %s (got '%s %s')" % [GOAL_TEXT, _hud.get_row_caption(0), _hud.get_row_value(0)])
	_check_state(READING_OFF, BoardLamp.State.OFF, "initial state")
	_check(not _door.is_open() and not _hud.is_mission_complete_shown(), "door starts closed, mission not done")
	_check(_room.get_board().get_wires().get_state() == CircuitWires.State.PLAIN, "wires start plain")
	_check(_room.get_parts().size() == 2 and _room.get_board().get_sockets().size() == 2,
			"two parts and two slots in the room")
	_check(_player.position.distance_to(SPAWN) <= POSITION_TOLERANCE and _player.is_on_floor(),
			"player starts on the floor at spawn (%s)" % _player.position)
	var diode: PartPickup = _part("d1")
	var resistor: PartPickup = _part("r1")
	if diode == null or resistor == null:
		_check(false, "parts d1 and r1 exist")
		return
	_check(diode.get_tag_text() == DIODE_TAG and diode.get_icon().get_label_text() == DIODE_PLAQUE,
			"the diode reads '%s' / '%s' (got '%s' / '%s')" % [DIODE_TAG, DIODE_PLAQUE, diode.get_tag_text(),
				diode.get_icon().get_label_text()])
	_check(resistor.get_tag_text() == RESISTOR_TAG and resistor.get_icon().get_label_text() == RESISTOR_TAG,
			"the resistor reads '%s' (tag '%s', plaque '%s')" % [RESISTOR_TAG, resistor.get_tag_text(),
				resistor.get_icon().get_label_text()])


func _play() -> void:
	var diode: PartPickup = _part("d1")
	var resistor: PartPickup = _part("r1")
	var s_fwd: CircuitSocket = _socket("s_fwd")
	var s_rev: CircuitSocket = _socket("s_rev")
	if diode == null or resistor == null or s_fwd == null or s_rev == null:
		_check(false, "parts d1, r1 and slots s_fwd, s_rev exist")
		return

	print("-- natural first try: diode into the nearer slot s_rev")
	await _walk_to_x(DIODE_X)
	_check(_on_surface(FLOOR_Y), "walks along the flat floor to the diode (%s)" % _player.position)
	await _interact()
	_check(_carry.get_carried() == diode, "picks up the diode")
	await _walk_to_x(S_REV_X)
	await _interact()
	_check(s_rev.get_pickup() == diode and not _carry.is_carrying(), "plugs the diode into s_rev")
	_check_state(READING_OFF, BoardLamp.State.OFF, "reversed diode")
	_check(not _door.is_open() and not _room.get_board().is_goal_met(), "reversed diode: door shut")
	_check(_room.get_board().get_wires().get_state() == CircuitWires.State.PLAIN, "reversed diode: wires plain")
	_check(s_rev.get_icon().is_flipped() and s_rev.get_tag_text() == DIODE_TAG,
			"s_rev's from node is on the right: the diode picture is mirrored")

	print("-- diode into s_fwd on the shelf")
	await _interact()
	_check(_carry.get_carried() == diode and not s_rev.is_filled(), "pulls the diode out of s_rev")
	await _climb_to_shelf()
	await _interact()
	_check(s_fwd.get_pickup() == diode, "plugs the diode into s_fwd")
	_check_state(READING_DIODE, BoardLamp.State.ON, "forward diode")
	_check(_door.is_open() and _room.get_board().is_goal_met() and _hud.is_mission_complete_shown(),
			"forward diode: the goal holds and the door opens")
	_check(_room.get_board().get_wires().get_state() == CircuitWires.State.MATCH, "forward diode: wires match")
	_check(not s_fwd.get_icon().is_flipped(), "s_fwd's from node is on the left: the picture is not mirrored")

	print("-- the decoy resistor alone in each slot")
	await _interact()
	_check(_carry.get_carried() == diode and not s_fwd.is_filled(), "pulls the diode out of s_fwd")
	_check_state(READING_OFF, BoardLamp.State.OFF, "both slots empty")
	_check(not _door.is_open(), "pulled out: the door shuts")
	await _walk_to_x(OFF_SHELF_X)
	_check(_on_surface(FLOOR_Y), "walks off the shelf to the floor (%s)" % _player.position)
	await _walk_to_x(PUT_DOWN_X)
	await _interact()
	_check(not _carry.is_carrying() and diode.is_loose(), "puts the diode down")
	await _walk_to_x(RESISTOR_X)
	await _interact()
	_check(_carry.get_carried() == resistor, "picks up the resistor")
	await _climb_to_shelf()
	await _interact()
	_check(s_fwd.get_pickup() == resistor, "plugs the resistor into s_fwd")
	_check_state(READING_RESISTOR, BoardLamp.State.OFF, "2 kΩ in s_fwd")
	_check(not _door.is_open() and not _room.get_board().is_goal_met(), "2 kΩ in s_fwd: door shut")
	await _interact()
	_check(_carry.get_carried() == resistor and not s_fwd.is_filled(), "pulls the resistor out of s_fwd")
	await _walk_to_x(OFF_SHELF_X)
	await _walk_to_x(S_REV_X)
	await _interact()
	_check(s_rev.get_pickup() == resistor, "plugs the resistor into s_rev")
	_check_state(READING_RESISTOR, BoardLamp.State.OFF, "2 kΩ in s_rev")
	_check(not _door.is_open() and not _room.get_board().is_goal_met(), "2 kΩ in s_rev: door shut")

	print("-- diode forward beside the resistor, then leave")
	await _walk_to_x(diode.global_position.x)
	await _interact()
	_check(_carry.get_carried() == diode, "picks the diode up again")
	await _climb_to_shelf()
	await _interact()
	_check(s_fwd.get_pickup() == diode and s_rev.get_pickup() == resistor, "plugs the diode into s_fwd")
	_check_state(READING_DIODE, BoardLamp.State.ON, "forward diode beside 2 kΩ")
	_check(_door.is_open(), "the door is open again")
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

## Walks under the shelf and jumps straight up onto it (an 89 px rise).
func _climb_to_shelf() -> void:
	await _walk_to_x(S_FWD_X)
	await _jump_and_land(0)
	_check(_on_surface(SHELF_Y), "one jump lands on the shelf (%s)" % _player.position)


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
