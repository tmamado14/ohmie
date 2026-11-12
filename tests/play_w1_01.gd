extends SceneTree
## Scripted headless playthrough of res://levels/w1_01.json ("Closing Time":
## one loop of slot s1 and lamp1, a 3 ohm lamp lit from 1 to 3 A; one 6 V
## battery on a flat floor; goal: the lamp current is between 1 and 3 A).
##
## Solves the level start to finish through the input map only (no
## teleporting): walks right to the battery, picks it up, plugs it into s1
## (2 A, lamp lit, door open, + badge on the left at s1's `from` node), pulls
## it out again (the wrong arrangement this room has: an open loop, 0 A, lamp
## dark, door shut), plugs it back and walks into the door. The plaque and the
## lamp agree at every step. Then puts range targets (1–3/2 A) on the plaque,
## alone and on two-condition rows, and checks that every value fits.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --fixed-fps 60 --script res://tests/play_w1_01.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
const LEVEL_PATH: String = "res://levels/w1_01.json"
const ROOM_PATH: NodePath = ^"Room"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]
const TITLE: String = "Closing Time"
const MISSION: String = "Light the lamp."
const GOAL_TEXT: String = "1–3 A"
const LAMP_ID: String = "lamp1"

## Layout facts of w1_01.json.
const SPAWN: Vector2 = Vector2(96, 640)
const FLOOR_Y: float = 640.0
const BATTERY_X: float = 336.0
const S1_X: float = 640.0
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
	print("play_w1_01: %d passed, %d failed" % [_passed, _failed])
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
	await _solve()
	await _check_range_targets_fit()
	Room.level_override = ""
	return 0 if _failed == 0 else 1


## Range targets never overflow the plaque: on one-condition and two-condition
## rows ("3/2 A  →  1–3/2 A") every value is no wider than its slot and ends at
## the plaque's right text edge. Done last, as it replaces the room's goal rows.
func _check_range_targets_fit() -> void:
	print("-- range targets on the plaque")
	var cases: Array[Array] = [
		[PackedStringArray(["I"]), PackedStringArray(["1–3/2 A"]), PackedStringArray(["3/2 A"])],
		[PackedStringArray(["I", "V"]), PackedStringArray(["1–3/2 A", "1/3–5/2 V"]), PackedStringArray(["13/12 A", "13/12 V"])],
	]
	for c: Array in cases:
		_hud.set_goal_rows(c[0], c[1])
		var met: Array[bool] = [false, false]
		_hud.show_readings(c[2], met, false)
		await process_frame
		for row: int in 2:
			var label: Label = _hud.get_node(NodePath("Readout/Row%dValue" % row)) as Label
			var font_size: int = label.get_theme_font_size(&"font_size")
			var text_width: float = label.get_theme_font(&"font").get_string_size(label.text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var right: float = label.position.x + label.size.x
			_check(text_width <= label.size.x and right <= Hud.VALUE_RIGHT + 0.5,
					"plaque row %d '%s' fits (%.0f px text in %.0f px, right edge %.0f of %.0f, font %d)" % [
						row, label.text, text_width, label.size.x, right, Hud.VALUE_RIGHT, font_size])


func _check_start_state() -> void:
	print("-- start")
	_check(_room.level_data.title == TITLE, "level title is '%s' (got '%s')" % [TITLE, _room.level_data.title])
	_check(_hud.get_mission_text() == MISSION, "the mission sign shows '%s' (got '%s')" % [MISSION, _hud.get_mission_text()])
	_check(_hud.get_row_caption(0) == "GOAL" and _hud.get_row_value(0) == GOAL_TEXT and _hud.get_row_caption(1) == "I",
			"the plaque shows GOAL %s and an I row (got '%s %s' / '%s')" % [GOAL_TEXT, _hud.get_row_caption(0),
				_hud.get_row_value(0), _hud.get_row_caption(1)])
	_check_state("0 A", BoardLamp.State.OFF, "initial state")
	_check(not _hud.is_mission_complete_shown(), "the mission sign starts not done")
	_check(not _door.is_open(), "door starts closed")
	_check(_room.get_board().get_wires().get_state() == CircuitWires.State.PLAIN, "wires start plain")
	_check(_room.get_parts().size() == 1 and _room.get_board().get_sockets().size() == 1,
			"one part and one slot in the room")
	_check(_player.position.distance_to(SPAWN) <= POSITION_TOLERANCE and _player.is_on_floor(),
			"player starts on the floor at spawn (%s)" % _player.position)


func _solve() -> void:
	print("-- solve")
	var battery: PartPickup = _part("b6")
	if battery == null:
		_check(false, "part b6 exists")
		return
	var s1: CircuitSocket = _socket("s1")

	await _walk_to_x(BATTERY_X)
	_check(_on_surface(FLOOR_Y), "walks along the flat floor to the battery (%s)" % _player.position)
	await _interact()
	_check(_carry.get_carried() == battery, "picks up the 6 V battery")

	await _walk_to_x(S1_X)
	await _interact()
	_check(not _carry.is_carrying() and s1.get_pickup() == battery, "plugs the battery into s1")
	_check_state("2 A", BoardLamp.State.ON, "6 V across the 3 Ω lamp")
	_check(_door.is_open() and _room.get_board().is_goal_met(), "the lamp is lit and the door opens")
	_check(_hud.is_mission_complete_shown() and _hud.is_condition_met_shown(0)
			and _hud.get_row_value_color(1) == Hud.COLOR_MATCH,
			"the mission sign shows its done state and the reading row is green")
	_check(_room.get_board().get_wires().get_state() == CircuitWires.State.MATCH, "wires show the match colour")
	var badges: PolarityBadges = s1.get_polarity_badges()
	_check(badges.is_shown() and not badges.is_plus_on_right() and not s1.get_icon().is_flipped(),
			"the battery's + badge is on the left, at s1's 'from' node")

	# The only wrong arrangement this room has: the loop open again.
	await _interact()
	_check(_carry.get_carried() == battery and not s1.is_filled(), "pulls the battery back out of s1")
	_check_state("0 A", BoardLamp.State.OFF, "open loop")
	_check(not _door.is_open() and not _hud.is_mission_complete_shown(), "open loop: lamp dark, door closed")
	await _interact()
	_check(s1.get_pickup() == battery, "plugs the battery back in")
	_check_state("2 A", BoardLamp.State.ON, "loop closed again")
	_check(_door.is_open(), "loop closed again: door open")

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

## The plaque reads `reading` and the lamp is in `lamp_state`.
func _check_state(reading: String, lamp_state: BoardLamp.State, what: String) -> void:
	var shown: String = _hud.get_reading_text(0)
	var lamp: BoardLamp = _room.get_board().get_lamp(LAMP_ID)
	var state: int = lamp.get_state() if lamp != null else -1
	_check(shown == reading and _hud.get_row_value(1) == reading and state == lamp_state,
			"%s: the plaque reads %s and the lamp is %s (plaque '%s', lamp %s)" % [what, reading,
				BoardLamp.State.keys()[lamp_state], shown, BoardLamp.State.keys()[state] if state >= 0 else "missing"])


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
