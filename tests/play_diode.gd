extends SceneTree
## Scripted headless playthrough of res://levels/dev_diode.json (a Copper
## Foundry development room in engineering numbers: a fixed 6 V battery, a
## 1 kΩ lamp lit from 3 to 6 mA with ammeter am1 in series, and two slots on
## parallel branches between the same two nodes; both conduct from the
## screen-left (battery-plus) side to the right: s_fwd on the floor (from lb on
## the left), s_rev on a platform (from ra on the right). Parts: a 0.7 V diode,
## not flipped, and a 1 kΩ resistor. Goal: lamp current 5–6 mA).
##
## The player turns a diode with `flip` (F); nothing turns it by itself (GDD
## 11, "Direction"). Not flipped (stripe right) conducts left to right.
## Drives input through the input map only: flips the loose diode on the
## ground, flips it while carried, presses F in the air (nothing), plugs it into
## each slot the wrong way round (0 A, lamp dark, door shut), flips it in place
## (5.3 mA, door open) and back, pulls it out and puts it down (direction
## kept), presses F with the resistor carried, with the resistor in a slot and
## with nothing in reach (invalid each time), sends the carried flipped diode
## home through the room's respawn path (PlayerRespawn.respawn_now, the pit-fall
## path: the room has no pit or hazard), restarts (the level's direction
## returns) and solves the room. Checks the pictures' mirroring, the name tag's
## arrow, the engine's anode node, the hint line (with "F flip" here, without
## it in w1_01) and that no ERROR or WARNING is logged.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --fixed-fps 60 --script res://tests/play_diode.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
const LEVEL_PATH: String = "res://levels/dev_diode.json"
const NO_DIODE_LEVEL_PATH: String = "res://levels/w1_01.json"
const ROOM_PATH: NodePath = ^"Room"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "flip", "restart"]
const LAMP_ID: String = "lamp1"
const AMMETER_ID: String = "am1"
const GOAL_TEXT: String = "5–6 mA"
const TAG_RIGHT: String = "diode 0.7 V →"
const TAG_LEFT: String = "diode 0.7 V ←"
const DIODE_PLAQUE: String = "0.7 V"
const RESISTOR_TAG: String = "1 kΩ"
## Exact engine texts (QuantityText ENGINEERING).
const READING_OFF: String = "0 A"
const READING_DIODE: String = "5.3 mA"
const READING_RESISTOR: String = "3 mA"
const HINT_ENTRIES: PackedStringArray = [
	"A/D move", "Space jump (hold for higher)", "S drop down", "E use", "F flip", "R restart"]

## Layout facts of dev_diode.json.
const FLOOR_Y: float = 640.0
const STEP_Y: float = 551.0
const UPPER_Y: float = 487.0
const DIODE_HOME: Vector2 = Vector2(208, 640)
const RESISTOR_X: float = 1040.0
const SLOT_X: float = 640.0  # both slots are centred above this x
const STEP_JUMP_X: float = 368.0  # jump straight up onto the step platform here
const UPPER_JUMP_X: float = 440.0  # jump right onto the upper platform here
const OFF_UPPER_X: float = 800.0  # walk off the upper platform's right end here
const PUT_DOWN_X: float = 880.0  # nothing within reach here
const NOTHING_X: float = 1120.0  # nothing within reach here once the resistor is gone
const DOOR_X: float = 1180.0
## Each slot's nodes: the screen-left node is the anode of a diode not flipped.
const S_FWD_LEFT: String = "lb"
const S_FWD_RIGHT: String = "rb"
const S_REV_LEFT: String = "la"
const S_REV_RIGHT: String = "ra"

const POSITION_TOLERANCE: float = 6.0
const SETTLE_FRAMES: int = 20
const RESTART_FRAMES: int = 10
const AIR_FLIP_DELAY: int = 6
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
var _invalid_count: int = 0
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
	if not _check_start():
		return 1
	await _flip_loose_and_carried()
	await _slot(_socket("s_rev"), S_REV_LEFT, S_REV_RIGHT, true)
	await _walk_to_x(OFF_UPPER_X)
	_check(_on_surface(FLOOR_Y), "walks off the platform to the floor (%s)" % _player.position)
	await _slot(_socket("s_fwd"), S_FWD_LEFT, S_FWD_RIGHT, false)
	await _put_down()
	await _invalid_flips()
	await _home_after_respawn()
	await _restart_room()
	if _room == null:
		return 1
	await _solve_after_restart()
	await _hint_without_diodes()
	Room.level_override = ""
	return 0 if _failed == 0 else 1


func _check_start() -> bool:
	print("-- start")
	_check(_room.level_data.world == "copper_foundry"
			and _room.get_room_theme() == RoomTheme.load_for_world("copper_foundry"),
			"the room uses the Copper Foundry theme")
	_check(_hud.get_row_caption(0) == "GOAL" and _hud.get_row_value(0) == GOAL_TEXT,
			"the plaque shows GOAL %s (got '%s %s')" % [GOAL_TEXT, _hud.get_row_caption(0), _hud.get_row_value(0)])
	_check_state(READING_OFF, BoardLamp.State.OFF, "initial state")
	_check(not _door.is_open(), "door starts closed")
	var expected_hint: String = MenuStyle.hint_text(HINT_ENTRIES)
	_check(_hud.get_hint_text() == expected_hint, "the hint line reads '%s' (got '%s')" % [
			expected_hint, _hud.get_hint_text()])
	var diode: PartPickup = _part("d1")
	var resistor: PartPickup = _part("r1")
	if diode == null or resistor == null or _socket("s_fwd") == null or _socket("s_rev") == null:
		_check(false, "parts d1, r1 and slots s_fwd, s_rev exist")
		return false
	_check_diode_look(diode, false, "the loose diode at the start")
	_check(diode.get_icon().get_label_text() == DIODE_PLAQUE, "the diode's plaque reads '%s' (got '%s')" % [
			DIODE_PLAQUE, diode.get_icon().get_label_text()])
	_check(resistor.get_tag_text() == RESISTOR_TAG and resistor.get_icon().get_label_text() == RESISTOR_TAG,
			"the 1k resistor reads '%s' (tag '%s', plaque '%s')" % [RESISTOR_TAG, resistor.get_tag_text(),
				resistor.get_icon().get_label_text()])
	return true


func _flip_loose_and_carried() -> void:
	var diode: PartPickup = _part("d1")
	print("-- flip on the ground")
	await _walk_to_x(DIODE_HOME.x)
	_check(_carry.get_target() == diode, "the loose diode is highlighted")
	var flips: int = _flip_count
	await _flip()
	_check(_flip_count == flips + 1 and not _carry.is_carrying() and diode.is_loose()
			and diode.global_position.is_equal_approx(DIODE_HOME), "F at the loose diode turns it where it lies")
	_check_diode_look(diode, true, "the loose diode after F")
	_check(diode.get_icon().get_label_text() == DIODE_PLAQUE, "the plaque text is not mirrored")
	await _flip()
	_check_diode_look(diode, false, "the loose diode after F again")

	print("-- carried")
	await _interact()
	_check(_carry.get_carried() == diode, "picks up the diode")
	_check(not diode.part.flipped and not _carry.get_carried_icon().is_flipped(),
			"picking it up keeps its direction: the carried picture is not mirrored")
	await _flip()
	_check(diode.part.flipped and _carry.get_carried_icon().is_flipped() and _carry.get_carried() == diode,
			"F while carrying turns it: the carried picture is mirrored at once")
	await _flip()
	_check(not diode.part.flipped and not _carry.get_carried_icon().is_flipped(), "F again turns it back")
	await _flip()
	_check(diode.part.flipped, "turned stripe-left (the wrong way for both slots)")

	print("-- in the air")
	var invalid: int = _invalid_count
	flips = _flip_count
	var was_in_air: bool = await _flip_in_air()
	_check(was_in_air and _flip_count == flips and _invalid_count == invalid + 1 and diode.part.flipped
			and _carry.get_carried_icon().is_flipped(), "F in the air is invalid and changes nothing")
	_check(_on_surface(FLOOR_Y), "lands on the floor again (%s)" % _player.position)


## Plugs the carried (flipped, wrong-way) diode into `socket`, flips it in
## place (conducts), flips it back and pulls it out. `left` and `right` are
## the slot's screen-left and screen-right nodes. `upper`: the slot is used
## from the upper platform.
func _slot(socket: CircuitSocket, left: String, right: String, upper: bool) -> void:
	var diode: PartPickup = _part("d1")
	var slot_name: String = socket.socket_id
	print("-- %s" % slot_name)
	if upper:
		await _walk_to_x(STEP_JUMP_X)
		await _jump_and_land(0)
		_check(_on_surface(STEP_Y), "jumps onto the step platform (%s)" % _player.position)
		await _walk_to_x(UPPER_JUMP_X)
		await _jump_and_land(1)
		_check(_on_surface(UPPER_Y), "jumps onto the upper platform (%s)" % _player.position)
	await _walk_to_x(SLOT_X)
	await _interact()
	_check(socket.get_pickup() == diode and not _carry.is_carrying(), "plugs the diode into %s" % slot_name)
	_check(diode.part.flipped and socket.get_icon().is_flipped() and socket.get_tag_text() == TAG_LEFT,
			"%s: plugged in stripe-left, the slot does not turn it (mirrored, tag '%s')" % [
				slot_name, socket.get_tag_text()])
	_check(_engine_anode(socket) == right, "%s: the engine's anode is the right node '%s' (got '%s')" % [
			slot_name, right, _engine_anode(socket)])
	_check_state(READING_OFF, BoardLamp.State.OFF, "%s wrong way round" % slot_name)
	_check(not _door.is_open() and not _room.get_board().is_goal_met(), "%s wrong way round: door shut" % slot_name)
	_check(_room.get_board().get_wires().get_state() == CircuitWires.State.PLAIN, "%s wrong way: plain wires" % slot_name)
	_check(not socket.get_polarity_badges().is_shown(), "no battery badges for a diode")

	var flips: int = _flip_count
	await _flip()
	_check(_flip_count == flips + 1 and _last_flip_socket == socket and socket.get_pickup() == diode
			and not _carry.is_carrying(), "%s: F with empty hands turns the diode in the slot" % slot_name)
	_check(not diode.part.flipped and not socket.get_icon().is_flipped() and socket.get_tag_text() == TAG_RIGHT
			and socket.get_icon().get_label_text() == DIODE_PLAQUE,
			"%s: the picture is not mirrored, the tag reads '%s' (got '%s')" % [slot_name, TAG_RIGHT, socket.get_tag_text()])
	_check(_engine_anode(socket) == left, "%s: the engine's anode is now the left node '%s' (got '%s')" % [
			slot_name, left, _engine_anode(socket)])
	_check_state(READING_DIODE, BoardLamp.State.ON, "%s turned the right way" % slot_name)
	_check(_door.is_open() and _room.get_board().is_goal_met() and _hud.is_mission_complete_shown(),
			"%s turned: the goal holds and the door opens" % slot_name)
	_check(_room.get_board().get_wires().get_state() == CircuitWires.State.MATCH, "%s turned: match wires" % slot_name)
	await _flip()
	_check(diode.part.flipped and socket.get_icon().is_flipped() and _engine_anode(socket) == right,
			"%s: F again turns it back" % slot_name)
	_check_state(READING_OFF, BoardLamp.State.OFF, "%s turned back" % slot_name)
	_check(not _door.is_open(), "%s turned back: the door shuts" % slot_name)

	await _interact()
	_check(_carry.get_carried() == diode and not socket.is_filled(), "pulls the diode out of %s" % slot_name)
	_check(diode.part.flipped and _carry.get_carried_icon().is_flipped(),
			"pulled out of %s: it keeps its direction (stripe left)" % slot_name)


func _put_down() -> void:
	var diode: PartPickup = _part("d1")
	print("-- put down")
	await _walk_to_x(PUT_DOWN_X)
	await _interact()
	_check(not _carry.is_carrying() and diode.is_loose(), "puts the diode down")
	_check_diode_look(diode, true, "the diode after the put-down")


func _invalid_flips() -> void:
	var resistor: PartPickup = _part("r1")
	var s_fwd: CircuitSocket = _socket("s_fwd")
	print("-- F where nothing can turn")
	await _walk_to_x(RESISTOR_X)
	await _interact()
	_check(_carry.get_carried() == resistor, "picks up the resistor")
	var flips: int = _flip_count
	var invalid: int = _invalid_count
	await _flip()
	_check(_flip_count == flips and _invalid_count == invalid + 1 and _carry.get_carried() == resistor
			and not resistor.part.flipped and not _carry.get_carried_icon().is_flipped(),
			"F while carrying the resistor is invalid and changes nothing")
	await _walk_to_x(SLOT_X)
	await _interact()
	_check(s_fwd.get_pickup() == resistor, "plugs the resistor into s_fwd")
	_check_state(READING_RESISTOR, BoardLamp.State.ON, "1 kΩ in s_fwd")
	_check(_carry.get_target() == s_fwd, "s_fwd (holding the resistor) is highlighted")
	await _flip()
	_check(_flip_count == flips and _invalid_count == invalid + 2 and s_fwd.get_pickup() == resistor
			and not s_fwd.get_icon().is_flipped(), "F at a slot holding a resistor is invalid")
	_check_state(READING_RESISTOR, BoardLamp.State.ON, "after F at the resistor")
	await _walk_to_x(NOTHING_X)
	_check(_carry.get_target() == null, "nothing is in reach at x %.0f" % NOTHING_X)
	await _flip()
	_check(_flip_count == flips and _invalid_count == invalid + 3, "F with empty hands and nothing in reach is invalid")


func _home_after_respawn() -> void:
	var diode: PartPickup = _part("d1")
	print("-- sent home while carried")
	await _walk_to_x(diode.global_position.x)
	await _interact()
	_check(_carry.get_carried() == diode and diode.part.flipped, "picks up the flipped diode")
	# dev_diode has no pit or hazard: use the room's own respawn path (what a
	# pit fall calls, and what a zap ends with).
	_room.get_respawn().respawn_now()
	await _wait_physics(SETTLE_FRAMES)
	_check(not _carry.is_carrying() and diode.is_loose()
			and diode.global_position.distance_to(DIODE_HOME) <= POSITION_TOLERANCE,
			"the respawn sends the carried diode home (%s)" % diode.global_position)
	_check_diode_look(diode, true, "the diode sent home")
	_check(not _room.level_data.parts[0].part.flipped, "the level data's own diode is never turned")


func _solve_after_restart() -> void:
	var diode: PartPickup = _part("d1")
	var s_fwd: CircuitSocket = _socket("s_fwd")
	print("-- after restart")
	_check(diode != null and diode.is_loose() and diode.global_position.distance_to(DIODE_HOME) <= POSITION_TOLERANCE,
			"restart puts the diode back home")
	if diode == null or s_fwd == null:
		return
	_check_diode_look(diode, false, "the diode after restart (the level's direction)")
	await _walk_to_x(DIODE_HOME.x)
	await _interact()
	await _walk_to_x(SLOT_X)
	await _interact()
	_check(s_fwd.get_pickup() == diode and _engine_anode(s_fwd) == S_FWD_LEFT,
			"the diode as drawn goes into s_fwd with its anode on the left")
	_check_state(READING_DIODE, BoardLamp.State.ON, "diode as drawn in s_fwd")
	_check(_door.is_open(), "the door is open")
	Input.action_press("move_right")
	for i: int in MAX_WALK_FRAMES:
		await _wait_physics(1)
		if _room.is_complete():
			break
	_release_all()
	_check(_room.is_complete() and _completed_count == 1,
			"walking into the open door completes the level (player at %s, door x=%.0f)" % [_player.position, DOOR_X])


func _hint_without_diodes() -> void:
	print("-- a room without diodes")
	Room.level_override = NO_DIODE_LEVEL_PATH
	reload_current_scene()
	await _wait_physics(RESTART_FRAMES)
	var room: Room = current_scene.get_node_or_null(ROOM_PATH) as Room if current_scene != null else null
	if room == null or room.get_hud() == null:
		_check(false, "w1_01 loads")
		return
	var hint: String = room.get_hud().get_hint_text()
	_check(not hint.contains(Hud.FLIP_HINT) and hint.contains(Hud.USE_HINT),
			"w1_01's hint line has no '%s' (got '%s')" % [Hud.FLIP_HINT, hint])


# --- helpers ------------------------------------------------------------------------

## The diode's direction, picture mirroring and name tag agree with `flipped`.
func _check_diode_look(diode: PartPickup, flipped: bool, what: String) -> void:
	var tag: String = TAG_LEFT if flipped else TAG_RIGHT
	_check(diode.part.flipped == flipped and diode.get_icon().is_flipped() == flipped and diode.get_tag_text() == tag,
			"%s: %s, picture %s, tag '%s' (got flipped %s, mirrored %s, '%s')" % [what,
				"flipped" if flipped else "not flipped", "mirrored" if flipped else "as drawn", tag,
				diode.part.flipped, diode.get_icon().is_flipped(), diode.get_tag_text()])


## The anode node the board's network gives the diode in `socket`: the same
## LevelCircuit.build_network call the board makes.
func _engine_anode(socket: CircuitSocket) -> String:
	var network: DcNetwork = _room.get_circuit().build_network({socket.socket_id: socket.get_part()})
	if network.get_kind(socket.socket_id) != DcNetwork.Kind.DIODE:
		return "not a diode"
	return network.get_node_a(socket.socket_id)


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
	_carry.invalid_action.connect(_on_invalid_action)
	return true


func _on_part_flipped(_turned: PartPickup, socket: CircuitSocket) -> void:
	_flip_count += 1
	_last_flip_socket = socket


func _on_invalid_action() -> void:
	_invalid_count += 1


func _restart_room() -> void:
	print("-- restart")
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
	var old_room: Room = _room
	_room = null
	_completed_count = 0
	if current_scene == null or not _bind_room(current_scene) or _room == old_room:
		_check(false, "restart reloads the room")
		_room = null
		return
	await _wait_physics(SETTLE_FRAMES)


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


## Jumps straight up and presses `flip` while airborne; waits to land. Returns
## whether Ohmie was in the air when the key went down.
func _flip_in_air() -> bool:
	Input.action_press("jump")
	for i: int in MAX_AIR_FRAMES:
		await _wait_physics(1)
		if not _player.is_on_floor():
			break
	await _wait_physics(AIR_FLIP_DELAY)
	var in_air: bool = not _player.is_on_floor()
	await _flip()
	Input.action_release("jump")
	for i: int in MAX_AIR_FRAMES:
		if _player.is_on_floor():
			break
		await _wait_physics(1)
	await _wait_physics(2)
	return in_air


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
