extends SceneTree
## Scripted headless playthrough of res://levels/w1_05.json ("Parallel
## Parking": a fixed 6 V battery feeding two parallel branches; the top branch
## is the ammeter am_top in series with slot s_top on a high platform, the
## bottom branch is the ammeter am_bot in series with slot s_bot on the floor;
## resistors 2, 3 and 6 ohm; goal: am_top reads 3 A AND am_bot reads 2 A, so
## 2 ohm on top and 3 ohm below).
##
## First checks with the circuit API that each branch gets the full 6 V and
## draws 6/R on its own (the swapped pair reads 2 A on top and 3 A below; the
## 6 ohm decoy always reads 1 A). Then plays the room from the right-hand spawn
## through the input map only (no teleporting): the tempting 3 ohm by the spawn
## up over the side platform into s_top (2 A on top), down and left to hop onto
## the low ledge for the 2 ohm, back into s_bot (2 A on top, 3 A below: the
## swapped arrangement, door shut), the 2 ohm pulled out and carried up to swap
## with the 3 ohm in s_top (3 A on top: only the top row green), the 3 ohm
## carried down into s_bot (both rows green, door open), then left into the door.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --fixed-fps 60 --script res://tests/play_w1_05.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
const LEVEL_PATH: String = "res://levels/w1_05.json"
const ROOM_PATH: NodePath = ^"Room"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]
const TITLE: String = "Parallel Parking"
const MISSION: String = "3 A on top. 2 A below."
const TOP_METER_ID: String = "am_top"
const BOTTOM_METER_ID: String = "am_bot"
const TOP_TARGET: String = "3 A"
const BOTTOM_TARGET: String = "2 A"
## Between the reading and the target on a two-condition plaque row (Hud.ARROW).
const ARROW: String = "  →  "

## Layout facts of w1_05.json.
const SPAWN: Vector2 = Vector2(1200, 640)
const FLOOR_Y: float = 640.0
const SIDE_PLATFORM_Y: float = 551.0  # row 17, columns 28..31 (x 896..1024)
const S_TOP_PLATFORM_Y: float = 487.0  # row 15, columns 21..25 (x 672..832)
const LOW_LEDGE_Y: float = 583.0  # row 18, columns 7..11 (x 224..384)
const THREE_X: float = 976.0  # 3 ohm on the floor under the side platform
const TWO_X: float = 288.0  # 2 ohm on the low ledge
const S_BOT_X: float = 752.0  # s_bot is used from the floor
const S_TOP_X: float = 752.0  # s_top is used from the high platform, straight above s_bot
const OFF_S_TOP_PLATFORM_X: float = 640.0  # left of the high platform's left end (x 672)
const TO_SIDE_PLATFORM_JUMP_X: float = 960.0
const TO_S_TOP_PLATFORM_JUMP_X: float = 910.0
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
	print("play_w1_05: %d passed, %d failed" % [_passed, _failed])
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
	_check_board_layout()
	_check_parallel()
	await _solve()
	Room.level_override = ""
	return 0 if _failed == 0 else 1


func _check_start_state() -> void:
	print("-- start")
	_check(_room.level_data.title == TITLE, "level title is '%s' (got '%s')" % [TITLE, _room.level_data.title])
	_check(_hud.get_mission_text() == MISSION, "the mission sign shows '%s' (got '%s')" % [MISSION, _hud.get_mission_text()])
	_check(_hud.get_condition_count() == 2 and _hud.get_target_text(0) == TOP_TARGET
			and _hud.get_target_text(1) == BOTTOM_TARGET,
			"the goal has two conditions, %s first and %s second (got %d: '%s', '%s')" % [TOP_TARGET, BOTTOM_TARGET,
				_hud.get_condition_count(), _hud.get_target_text(0), _hud.get_target_text(1)])
	_check(_hud.get_row_caption(0) == "I top" and _hud.get_row_caption(1) == "I below",
			"the plaque rows are captioned 'I top' and 'I below' (got '%s' / '%s')" % [_hud.get_row_caption(0), _hud.get_row_caption(1)])
	for row: int in 2:
		var caption: Label = _hud.get_node(NodePath("Readout/Row%dCaption" % row)) as Label
		var font_size: int = caption.get_theme_font_size(&"font_size")
		var text_width: float = caption.get_theme_font(&"font").get_string_size(caption.text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var value: Label = _hud.get_node(NodePath("Readout/Row%dValue" % row)) as Label
		_check(text_width <= caption.size.x and caption.position.x + caption.size.x <= value.position.x,
				"plaque row %d caption fits its column (text %.1f px, column %.1f px, font %d)" % [row, text_width,
					caption.size.x, font_size])
	_check_readings("0 A", "0 A", "initial reading")
	_check(not _hud.is_mission_complete_shown(), "the mission sign starts not done")
	_check(not _door.is_open(), "door starts closed")
	_check(_player.position.distance_to(SPAWN) <= POSITION_TOLERANCE and _player.is_on_floor(),
			"player starts on the floor at spawn (%s)" % _player.position)


## "Top" and "below" match the screen: the top meter and slot are above the bottom ones.
func _check_board_layout() -> void:
	print("-- board layout")
	var board: CircuitBoard = _room.get_board()
	var top_meter: BoardMeter = board.get_meter(TOP_METER_ID)
	var bottom_meter: BoardMeter = board.get_meter(BOTTOM_METER_ID)
	var s_top: CircuitSocket = _socket("s_top")
	var s_bot: CircuitSocket = _socket("s_bot")
	if top_meter == null or bottom_meter == null or s_top == null or s_bot == null:
		_check(false, "meters am_top, am_bot and slots s_top, s_bot exist")
		return
	_check(top_meter.global_position.y < bottom_meter.global_position.y,
			"am_top is drawn above am_bot (y %.0f < %.0f)" % [top_meter.global_position.y, bottom_meter.global_position.y])
	_check(s_top.global_position.y < s_bot.global_position.y,
			"s_top is drawn above s_bot (y %.0f < %.0f)" % [s_top.global_position.y, s_bot.global_position.y])


## Each branch gets the full 6 V and draws 6/R: only 2 ohm on top with 3 ohm below.
func _check_parallel() -> void:
	print("-- parallel branches (circuit API)")
	var goal: LevelGoal = _room.get_goal()
	var cases: Array[Array] = [
		[{}, "0 A", "0 A", false, "both slots empty"],
		[{"s_top": _resistor(2)}, "3 A", "0 A", false, "2 Ω on top alone"],
		[{"s_bot": _resistor(3)}, "0 A", "2 A", false, "3 Ω below alone"],
		[{"s_top": _resistor(3), "s_bot": _resistor(2)}, "2 A", "3 A", false, "3 Ω on top, 2 Ω below (swapped)"],
		[{"s_top": _resistor(6), "s_bot": _resistor(3)}, "1 A", "2 A", false, "6 Ω decoy on top, 3 Ω below"],
		[{"s_top": _resistor(2), "s_bot": _resistor(6)}, "3 A", "1 A", false, "2 Ω on top, 6 Ω decoy below"],
		[{"s_top": _resistor(6), "s_bot": _resistor(2)}, "1 A", "3 A", false, "6 Ω on top, 2 Ω below"],
		[{"s_top": _resistor(2), "s_bot": _resistor(3)}, "3 A", "2 A", true, "2 Ω on top, 3 Ω below"],
	]
	for entry: Array in cases:
		var solution: DcSolution = DcSolver.solve(_room.get_circuit().build_network(entry[0]))
		var top: String = MeterText.reading(solution, TOP_METER_ID)
		var bottom: String = MeterText.reading(solution, BOTTOM_METER_ID)
		_check(top == entry[1] and bottom == entry[2] and goal.is_met(solution) == entry[3],
				"%s reads %s on top and %s below (got '%s' / '%s'), goal %s" % [entry[4], entry[1], entry[2],
					top, bottom, "met" if entry[3] else "not met"])


func _solve() -> void:
	print("-- solve")
	var three: PartPickup = _part("r3")
	var two: PartPickup = _part("r2")
	if three == null or two == null:
		_check(false, "parts r3 and r2 exist")
		return
	var s_top: CircuitSocket = _socket("s_top")
	var s_bot: CircuitSocket = _socket("s_bot")

	# The tempting 3 ohm by the spawn, up over the side platform into s_top.
	await _walk_to_x(THREE_X)
	await _interact()
	_check(_carry.get_carried() == three, "picks up the 3 Ω resistor by the spawn")
	await _climb_to_s_top()
	await _interact()
	_check(not _carry.is_carrying() and s_top.get_pickup() == three, "plugs the 3 Ω into s_top")
	_check_readings("2 A", "0 A", "3 Ω on top, nothing below")
	_check(not _door.is_open(), "at 2 A / 0 A the door stays closed")

	# Down and left, a hop onto the low ledge for the 2 ohm, back into s_bot.
	await _walk_to_x(TWO_X)
	_check(_on_surface(FLOOR_Y), "walks off the high platform and along the floor (%s)" % _player.position)
	await _jump_and_land(0)
	_check(_on_surface(LOW_LEDGE_Y), "jumps straight up onto the low ledge (%s)" % _player.position)
	await _interact()
	_check(_carry.get_carried() == two, "picks up the 2 Ω resistor")
	await _walk_to_x(S_BOT_X)
	_check(_on_surface(FLOOR_Y), "walks off the low ledge back to s_bot (%s)" % _player.position)
	await _interact()
	_check(not _carry.is_carrying() and s_bot.get_pickup() == two, "plugs the 2 Ω into s_bot")
	_check_readings("2 A", "3 A", "swapped: 3 Ω on top, 2 Ω below")
	_check(not _door.is_open() and not _hud.is_mission_complete_shown(),
			"swapped (2 A on top, 3 A below): the door stays closed")

	# Fix it: pull the 2 ohm out of s_bot and carry it up to swap with the 3 ohm.
	await _interact()
	_check(_carry.get_carried() == two and s_bot.get_pickup() == null, "pulls the 2 Ω out of s_bot")
	_check_readings("2 A", "0 A", "3 Ω on top, s_bot empty again")
	await _climb_to_s_top()
	await _interact()
	_check(s_top.get_pickup() == two and _carry.get_carried() == three, "swaps the 2 Ω into s_top, carrying the 3 Ω")
	_check_readings("3 A", "0 A", "2 Ω on top, nothing below")
	_check(not _door.is_open() and not _hud.is_mission_complete_shown(), "only the top condition met: door closed")

	# Off the high platform's left end and back to s_bot with the 3 ohm.
	await _walk_to_x(OFF_S_TOP_PLATFORM_X)
	_check(_on_surface(FLOOR_Y), "walks off the high platform's left end to the floor (%s)" % _player.position)
	await _walk_to_x(S_BOT_X)
	await _interact()
	_check(not _carry.is_carrying() and s_bot.get_pickup() == three, "plugs the 3 Ω into s_bot")
	_check_readings("3 A", "2 A", "2 Ω on top, 3 Ω below")
	_check(_door.is_open() and _room.get_board().is_goal_met(), "at 3 A on top and 2 A below the door opens")
	_check(_hud.is_mission_complete_shown(), "the mission sign shows its done state")
	_check(_room.get_board().get_wires().get_state() == CircuitWires.State.MATCH, "wires show the match colour")

	# Left into the door, empty-handed.
	Input.action_press("move_left")
	for i: int in MAX_WALK_FRAMES:
		await _wait_physics(1)
		if _room.is_complete():
			break
	_release_all()
	_check(_room.is_complete() and _completed_count == 1,
			"walking into the open door completes the level (player at %s, door x=%.0f)" % [_player.position, DOOR_X])
	_check(_hud.is_level_complete_shown(), "the level-complete banner is shown")


## From the floor: under the side platform, straight up onto it (the room's one
## 3-tile rise), left onto the high platform, and along it to s_top.
func _climb_to_s_top() -> void:
	await _walk_to_x(TO_SIDE_PLATFORM_JUMP_X)
	await _jump_and_land(0)
	_check(_on_surface(SIDE_PLATFORM_Y), "jumps straight up onto the side platform (%s)" % _player.position)
	await _walk_to_x(TO_S_TOP_PLATFORM_JUMP_X)
	await _jump_and_land(-1)
	_check(_on_surface(S_TOP_PLATFORM_Y), "jumps left onto the s_top platform (%s)" % _player.position)
	await _walk_to_x(S_TOP_X)


# --- helpers ------------------------------------------------------------------------

## Both meters on the board, the plaque readings and the plaque rows show
## `top` / `bottom`; each row is green exactly when its condition is met.
func _check_readings(top: String, bottom: String, what: String) -> void:
	var board: CircuitBoard = _room.get_board()
	var top_meter: String = board.get_meter(TOP_METER_ID).get_reading()
	var bottom_meter: String = board.get_meter(BOTTOM_METER_ID).get_reading()
	_check(top_meter == top and bottom_meter == bottom
			and _hud.get_reading_text(0) == top and _hud.get_reading_text(1) == bottom,
			"%s: am_top reads %s and am_bot reads %s (meters '%s' / '%s', plaque '%s' / '%s')" % [what, top, bottom,
				top_meter, bottom_meter, _hud.get_reading_text(0), _hud.get_reading_text(1)])
	var row0: String = top + ARROW + TOP_TARGET
	var row1: String = bottom + ARROW + BOTTOM_TARGET
	_check(_hud.get_row_value(0) == row0 and _hud.get_row_value(1) == row1,
			"%s: the plaque rows read '%s' and '%s' (got '%s' / '%s')" % [what, row0, row1,
				_hud.get_row_value(0), _hud.get_row_value(1)])
	var top_met: bool = top == TOP_TARGET
	var bottom_met: bool = bottom == BOTTOM_TARGET
	_check(_hud.is_condition_met_shown(0) == top_met and _hud.is_condition_met_shown(1) == bottom_met
			and (_hud.get_row_value_color(0) == Hud.COLOR_MATCH) == top_met
			and (_hud.get_row_value_color(1) == Hud.COLOR_MATCH) == bottom_met,
			"%s: the top row is %s and the bottom row is %s" % [what, "green" if top_met else "not green",
				"green" if bottom_met else "not green"])


func _resistor(ohms: int) -> Part:
	return Part.create(Part.Kind.RESISTOR, Rational.new(ohms, 1))


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
