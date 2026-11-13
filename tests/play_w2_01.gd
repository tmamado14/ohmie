extends SceneTree
## Scripted headless playthrough of res://levels/w2_01.json ("One Way Street",
## World 2 room 1, Copper Foundry, engineering numbers: one loop of a fixed 6 V
## battery (plus on its right), ammeter am1, a 1 kΩ lamp lit from 3 to 6 mA and
## one floor slot s1, whose battery-plus side is on the screen-right. Parts: a
## 0.7 V diode lying as drawn (stripe right, the wrong way for this loop) and a
## 2 kΩ decoy resistor by the door. Goal: lamp current 3–6 mA).
##
## Drives input through the input map only (no teleporting): plugs the diode in
## as found (0 A, lamp dark, door shut, plain wires), presses F at the slot with
## empty hands (5.3 mA, lamp lit, match wires, door open), F again (shut), F
## once more (open); pulls it out, turns it while carrying and plugs it back
## (dark), turns it again while carrying and plugs it back (lit); tries the
## resistor alone (2 mA, dark, door shut); swaps the diode back in and walks
## through the door. Checks the name tag's arrow, the hint line and that no
## ERROR or WARNING is logged.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --fixed-fps 60 --script res://tests/play_w2_01.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
const LEVEL_PATH: String = "res://levels/w2_01.json"
const ROOM_PATH: NodePath = ^"Room"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "flip", "restart"]
const TITLE: String = "One Way Street"
const MISSION: String = "Light the lamp."
const LAMP_ID: String = "lamp1"
const AMMETER_ID: String = "am1"
const GOAL_TEXT: String = "3–6 mA"
const TAG_RIGHT: String = "diode 0.7 V →"
const TAG_LEFT: String = "diode 0.7 V ←"
const DIODE_PLAQUE: String = "0.7 V"
const RESISTOR_TAG: String = "2 kΩ"
const FLIP_HINT: String = "F flip"
## Exact engine texts (QuantityText ENGINEERING).
const READING_OFF: String = "0 A"
const READING_DIODE: String = "5.3 mA"
const READING_RESISTOR: String = "2 mA"

## Layout facts of w2_01.json.
const SPAWN: Vector2 = Vector2(96, 640)
const FLOOR_Y: float = 640.0
const DIODE_X: float = 224.0
const RESISTOR_X: float = 1056.0
const SLOT_X: float = 640.0
const PUT_DOWN_X: float = 840.0  # nothing within reach here
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
var _flip_count: int = 0
var _last_flip_socket: CircuitSocket = null


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
	if not _check_start():
		return 1
	await _play()
	Room.level_override = ""
	return 0 if _failed == 0 else 1


func _check_start() -> bool:
	print("-- start")
	_check(_room.level_data.title == TITLE, "level title is '%s' (got '%s')" % [TITLE, _room.level_data.title])
	_check(_room.level_data.world == "copper_foundry"
			and _room.get_room_theme() == RoomTheme.load_for_world("copper_foundry"),
			"the room uses the Copper Foundry theme")
	_check(_hud.get_mission_text() == MISSION, "the mission sign shows '%s' (got '%s')" % [MISSION, _hud.get_mission_text()])
	_check(_hud.get_row_caption(0) == "GOAL" and _hud.get_row_value(0) == GOAL_TEXT,
			"the plaque shows GOAL %s (got '%s %s')" % [GOAL_TEXT, _hud.get_row_caption(0), _hud.get_row_value(0)])
	_check(_hud.get_hint_text().contains(FLIP_HINT), "the hint line contains '%s' (got '%s')" % [
			FLIP_HINT, _hud.get_hint_text()])
	_check_state(READING_OFF, BoardLamp.State.OFF, "initial state")
	_check(not _door.is_open() and not _hud.is_mission_complete_shown(), "door starts closed, mission not done")
	_check(_room.get_board().get_wires().get_state() == CircuitWires.State.PLAIN, "wires start plain")
	_check(_room.get_parts().size() == 2 and _room.get_board().get_sockets().size() == 1,
			"two parts and one slot in the room")
	_check(_player.position.distance_to(SPAWN) <= POSITION_TOLERANCE and _player.is_on_floor(),
			"player starts on the floor at spawn (%s)" % _player.position)
	var diode: PartPickup = _part("d1")
	var resistor: PartPickup = _part("r1")
	if diode == null or resistor == null or _socket("s1") == null:
		_check(false, "parts d1, r1 and slot s1 exist")
		return false
	_check_diode_look(diode, false, "the loose diode at the start")
	_check(diode.get_icon().get_label_text() == DIODE_PLAQUE, "the diode's plaque reads '%s' (got '%s')" % [
			DIODE_PLAQUE, diode.get_icon().get_label_text()])
	_check(resistor.get_tag_text() == RESISTOR_TAG and resistor.get_icon().get_label_text() == RESISTOR_TAG,
			"the resistor reads '%s' (tag '%s', plaque '%s')" % [RESISTOR_TAG, resistor.get_tag_text(),
				resistor.get_icon().get_label_text()])
	return true


func _play() -> void:
	var diode: PartPickup = _part("d1")
	var resistor: PartPickup = _part("r1")
	var s1: CircuitSocket = _socket("s1")

	print("-- natural first try: plug the diode in as found")
	await _walk_to_x(DIODE_X)
	_check(_on_surface(FLOOR_Y), "walks along the flat floor to the diode (%s)" % _player.position)
	await _interact()
	_check(_carry.get_carried() == diode, "picks up the diode")
	await _walk_to_x(SLOT_X)
	await _interact()
	_check(s1.get_pickup() == diode and not _carry.is_carrying(), "plugs the diode into s1")
	_check(not diode.part.flipped and not s1.get_icon().is_flipped() and s1.get_tag_text() == TAG_RIGHT,
			"s1 keeps the diode as found: stripe right, tag '%s' (got '%s')" % [TAG_RIGHT, s1.get_tag_text()])
	_check_wrong_way("diode stripe right in s1")

	print("-- F at the slot with empty hands")
	var flips: int = _flip_count
	await _flip()
	_check(_flip_count == flips + 1 and _last_flip_socket == s1 and s1.get_pickup() == diode
			and not _carry.is_carrying(), "F with empty hands turns the diode in s1")
	_check(diode.part.flipped and s1.get_icon().is_flipped() and s1.get_tag_text() == TAG_LEFT,
			"s1's diode is now stripe left, tag '%s' (got '%s')" % [TAG_LEFT, s1.get_tag_text()])
	_check_right_way("diode stripe left in s1")
	await _flip()
	_check(not diode.part.flipped and s1.get_tag_text() == TAG_RIGHT, "F again turns it back to stripe right")
	_check_wrong_way("turned back")
	await _flip()
	_check(diode.part.flipped and s1.get_tag_text() == TAG_LEFT, "F once more turns it stripe left")
	_check_right_way("turned once more")

	print("-- turn it while carrying")
	await _interact()
	_check(_carry.get_carried() == diode and not s1.is_filled() and diode.part.flipped,
			"pulls the diode out; it keeps its direction (stripe left)")
	_check_state(READING_OFF, BoardLamp.State.OFF, "slot empty")
	_check(not _door.is_open(), "slot empty: the door shuts")
	await _flip()
	_check(not diode.part.flipped and not _carry.get_carried_icon().is_flipped(), "F while carrying turns it stripe right")
	await _interact()
	_check(s1.get_pickup() == diode and s1.get_tag_text() == TAG_RIGHT, "plugs it back in stripe right")
	_check_wrong_way("plugged back stripe right")
	await _interact()
	await _flip()
	_check(_carry.get_carried() == diode and diode.part.flipped and _carry.get_carried_icon().is_flipped(),
			"pulls it out and turns it stripe left while carrying")
	await _interact()
	_check(s1.get_pickup() == diode and s1.get_tag_text() == TAG_LEFT, "plugs it back in stripe left")
	_check_right_way("plugged back stripe left")

	print("-- the decoy resistor alone")
	await _interact()
	_check(_carry.get_carried() == diode, "pulls the diode out")
	await _walk_to_x(PUT_DOWN_X)
	await _interact()
	_check(not _carry.is_carrying() and diode.is_loose() and diode.part.flipped,
			"puts the diode down; it stays stripe left")
	await _walk_to_x(RESISTOR_X)
	await _interact()
	_check(_carry.get_carried() == resistor, "picks up the resistor")
	await _walk_to_x(SLOT_X)
	await _interact()
	_check(s1.get_pickup() == resistor, "plugs the resistor into s1")
	_check_state(READING_RESISTOR, BoardLamp.State.OFF, "2 kΩ alone")
	_check(not _door.is_open() and not _room.get_board().is_goal_met(), "2 kΩ alone: door shut")

	print("-- swap the diode back in and leave")
	await _walk_to_x(diode.global_position.x)
	await _interact()
	_check(_carry.get_carried() == diode, "picks the diode up again")
	await _walk_to_x(SLOT_X)
	await _interact()
	_check(s1.get_pickup() == diode and _carry.get_carried() == resistor, "swaps the diode in for the resistor")
	_check_right_way("diode swapped in")
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

func _check_wrong_way(what: String) -> void:
	_check_state(READING_OFF, BoardLamp.State.OFF, what)
	_check(not _door.is_open() and not _room.get_board().is_goal_met()
			and _room.get_board().get_wires().get_state() == CircuitWires.State.PLAIN,
			"%s: door shut, wires plain" % what)


func _check_right_way(what: String) -> void:
	_check_state(READING_DIODE, BoardLamp.State.ON, what)
	_check(_door.is_open() and _room.get_board().is_goal_met() and _hud.is_mission_complete_shown()
			and _room.get_board().get_wires().get_state() == CircuitWires.State.MATCH,
			"%s: the goal holds, the door opens, wires match" % what)


## The diode's direction, picture mirroring and name tag agree with `flipped`.
func _check_diode_look(diode: PartPickup, flipped: bool, what: String) -> void:
	var tag: String = TAG_LEFT if flipped else TAG_RIGHT
	_check(diode.part.flipped == flipped and diode.get_icon().is_flipped() == flipped and diode.get_tag_text() == tag,
			"%s: %s, tag '%s' (got flipped %s, mirrored %s, '%s')" % [what,
				"flipped" if flipped else "not flipped", tag,
				diode.part.flipped, diode.get_icon().is_flipped(), diode.get_tag_text()])


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
	_carry.part_flipped.connect(_on_part_flipped)
	return true


func _on_part_flipped(_turned: PartPickup, socket: CircuitSocket) -> void:
	_flip_count += 1
	_last_flip_socket = socket


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


func _interact() -> void:
	await _press("interact")


func _flip() -> void:
	await _press("flip")


func _press(action: String) -> void:
	Input.action_press(action)
	await _wait_physics(1)
	Input.action_release(action)
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
