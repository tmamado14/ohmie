extends SceneTree
## Scripted headless playthrough of res://levels/w1_02.json ("Resistance Is
## Futile": one loop of slot s1, slot s2 and the ammeter am1; a 6 V battery and
## 3, 2 and 6 ohm resistors; goal: am1 reads 2 A).
##
## Solves the level start to finish through the input map only (no
## teleporting): the battery into s1 (still 0 A: the loop is open), the 3 ohm
## from the left ledge into s2 (2 A, mission complete, door open), swaps in the
## 2 ohm (3 A, door closed) and back, swaps a resistor into s1 so both slots
## hold resistors (0 A) and back, and walks into the door. The room that
## follows is read from the campaign at run time (Campaign.next_built_after):
## when there is one, the victory line offers it and a real `interact` event
## loads it; when w1_02 is the last built room, the line offers to play again
## and `interact` keeps the completed room.
## The plaque and the ammeter on the board agree at every step, and the battery
## sits in s1 with its plus end and + badge on the left (s1's `from` side).
##
## Then a SHORT: a board built in the test from LevelCircuit + DcSolver (a
## battery directly across an ammeter) reads SHORT through MeterText (the
## board's formatting) and GoalCondition; and a CircuitBoard whose slot gets a
## second, different battery in parallel shows SHORT on its meter, flashes its
## wires and emits `shorted` once.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --fixed-fps 60 --script res://tests/play_w1_02.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
const LEVEL_PATH: String = "res://levels/w1_02.json"
const SOCKET_SCENE: String = "res://scenes/socket.tscn"
const PICKUP_SCENE: String = "res://scenes/pickup.tscn"
const ROOM_PATH: NodePath = ^"Room"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]
const TITLE: String = "Resistance Is Futile"
const MISSION: String = "Draw 2 A."
const RELOAD_FRAMES: int = 6

## Layout facts of w1_02.json.
const SPAWN: Vector2 = Vector2(96, 640)
const FLOOR_Y: float = 640.0
const LEFT_LEDGE_Y: float = 551.0  # row 17, columns 4..8
const SOCKET_PLATFORM_Y: float = 551.0  # row 17, columns 18..22
const BATTERY_X: float = 208.0  # 6 V on the floor
const THREE_X: float = 208.0  # 3 ohm on the left ledge, straight above the battery
const TWO_X: float = 900.0  # 2 ohm on the floor
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
	print("play_w1_02: %d passed, %d failed" % [_passed, _failed])
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
	await _check_next_room()
	_check_short_formatting()
	await _check_short_on_a_board()
	return 0 if _failed == 0 else 1


func _check_start_state() -> void:
	print("-- start")
	_check(_room.level_data.title == TITLE, "level title is '%s' (got '%s')" % [TITLE, _room.level_data.title])
	_check(_hud.get_mission_text() == MISSION, "the mission sign shows '%s' (got '%s')" % [MISSION, _hud.get_mission_text()])
	_check(_hud.get_row_caption(0) == "GOAL" and _hud.get_row_value(0) == "2 A" and _hud.get_row_caption(1) == "I",
			"the plaque shows GOAL 2 A and an I row (got '%s %s' / '%s')" % [_hud.get_row_caption(0),
				_hud.get_row_value(0), _hud.get_row_caption(1)])
	_check_reading("0 A", "initial reading")
	_check(not _hud.is_mission_complete_shown(), "the mission sign starts not done")
	_check(not _door.is_open(), "door starts closed")
	_check(_room.get_board().get_wires().get_state() == CircuitWires.State.PLAIN, "wires start plain")
	_check(_player.position.distance_to(SPAWN) <= POSITION_TOLERANCE and _player.is_on_floor(),
			"player starts on the floor at spawn (%s)" % _player.position)


func _solve() -> void:
	print("-- solve")
	var battery: PartPickup = _part("b6")
	var three: PartPickup = _part("r3")
	var two: PartPickup = _part("r2")
	if battery == null or three == null or two == null:
		_check(false, "parts b6, r3 and r2 exist")
		return
	var s1: CircuitSocket = _socket("s1")
	var s2: CircuitSocket = _socket("s2")

	# The battery on the floor, into s1 from the floor.
	await _walk_to_x(BATTERY_X)
	await _interact()
	_check(_carry.get_carried() == battery, "picks up the 6 V battery from the floor")
	await _walk_to_x(S1_X)
	await _interact()
	_check(not _carry.is_carrying() and s1.get_pickup() == battery, "plugs the battery into s1")
	_check_reading("0 A", "battery in s1, s2 empty (open loop)")
	_check(not _door.is_open(), "battery alone: door closed")
	var badges: PolarityBadges = s1.get_polarity_badges()
	_check(badges.is_shown() and not badges.is_plus_on_right() and not s1.get_icon().is_flipped(),
			"the battery in s1 is not mirrored and its + badge is on the left, at s1's 'from' node")
	_check(s1.get_icon().get_label_text() == "6 V", "the battery's plaque reads 6 V (got '%s')" % s1.get_icon().get_label_text())
	_check(not s2.get_polarity_badges().is_shown(), "the empty s2 shows no polarity badges")

	# Straight up onto the left ledge for the 3 ohm.
	await _walk_to_x(THREE_X)
	await _jump_and_land(0)
	_check(_on_surface(LEFT_LEDGE_Y), "jumps straight up onto the left ledge (%s)" % _player.position)
	await _interact()
	_check(_carry.get_carried() == three, "picks up the 3 Ω resistor")

	# Off the ledge's right end, up onto the socket platform, into s2.
	await _walk_to_x(TO_SOCKET_PLATFORM_JUMP_X)
	_check(_on_surface(FLOOR_Y), "walks off the left ledge and along the floor (%s)" % _player.position)
	await _jump_and_land(0)
	_check(_on_surface(SOCKET_PLATFORM_Y), "jumps straight up onto the socket platform (%s)" % _player.position)
	await _walk_to_x(S2_X)
	await _interact()
	_check(not _carry.is_carrying() and s2.get_pickup() == three, "plugs the 3 Ω into s2")
	_check_reading("2 A", "6 V across 3 Ω")
	_check(_door.is_open() and _room.get_board().is_goal_met(), "at 2 A the door opens")
	_check(_hud.is_mission_complete_shown() and _hud.is_condition_met_shown(0)
			and _hud.get_row_value_color(1) == Hud.COLOR_MATCH,
			"at 2 A the mission sign shows MISSION COMPLETE and the reading row is green")
	_check(_room.get_board().get_wires().get_state() == CircuitWires.State.MATCH, "wires show the match colour")

	# Fetch the 2 ohm and swap it in: 3 A, door closed. Swap back: 2 A.
	await _walk_to_x(TWO_X)
	_check(_on_surface(FLOOR_Y), "walks off the platform to the floor (%s)" % _player.position)
	await _interact()
	_check(_carry.get_carried() == two, "picks up the 2 Ω resistor")
	await _walk_to_x(TO_SOCKET_PLATFORM_JUMP_X)
	await _jump_and_land(0)
	await _walk_to_x(S2_X)
	_check(_on_surface(SOCKET_PLATFORM_Y), "back on the socket platform at s2 (%s)" % _player.position)
	await _interact()
	_check(s2.get_pickup() == two and _carry.get_carried() == three, "swaps the 2 Ω into s2, carrying the 3 Ω")
	_check_reading("3 A", "6 V across 2 Ω")
	_check(not _door.is_open() and not _hud.is_mission_complete_shown(), "at 3 A the door is closed again")
	_check(_room.get_board().get_wires().get_state() == CircuitWires.State.ENERGIZED,
			"wires show the energized colour")
	await _interact()
	_check(s2.get_pickup() == three and _carry.get_carried() == two, "swaps the 3 Ω back into s2")
	_check_reading("2 A", "restored")
	_check(_door.is_open(), "restored: door open")

	# Both slots with resistors and no battery: 0 A. Then the battery back.
	await _walk_to_x(S1_X)
	_check(_on_surface(FLOOR_Y), "walks off the platform to s1 on the floor (%s)" % _player.position)
	await _interact()
	_check(s1.get_pickup() == two and _carry.get_carried() == battery, "swaps the 2 Ω into s1, carrying the battery")
	_check_reading("0 A", "2 Ω and 3 Ω with no battery")
	_check(not _door.is_open(), "no battery: door closed")
	_check(not s1.get_polarity_badges().is_shown(), "a resistor in s1 shows no polarity badges")
	await _interact()
	_check(s1.get_pickup() == battery and _carry.get_carried() == two, "swaps the battery back into s1")
	_check_reading("2 A", "battery back")
	_check(_door.is_open(), "battery back: door open")

	# Into the door, still carrying the 2 ohm.
	Input.action_press("move_right")
	for i: int in MAX_WALK_FRAMES:
		await _wait_physics(1)
		if _room.is_complete():
			break
	_release_all()
	_check(_room.is_complete() and _completed_count == 1,
			"walking into the open door completes the level (player at %s, door x=%.0f)" % [_player.position, DOOR_X])
	_check(_hud.is_level_complete_shown(), "the level-complete banner is shown")


## After completion, with the following room taken from the campaign: the
## victory line offers it and `interact` (sent as an input event, as a key
## press would be) loads it; or, when this is the last built room, the line
## offers to play again and `interact` keeps the completed room.
func _check_next_room() -> void:
	print("-- next room")
	var campaign: Campaign = Campaign.load_from_file(Campaign.DEFAULT_PATH)
	var next_file: String = campaign.next_built_after(LEVEL_PATH) if campaign != null else ""
	var next_data: LevelData = LevelData.load_from_file(next_file) if not next_file.is_empty() else null
	var expected_line: String = Hud.VICTORY_NEXT_ROOM if next_data != null else Hud.VICTORY_PLAY_AGAIN
	_check(_hud.get_victory_line() == expected_line,
			"the victory line reads '%s' (got '%s')" % [expected_line, _hud.get_victory_line()])
	_send_action_event(&"interact", true)
	await _wait_physics(1)
	_send_action_event(&"interact", false)
	await _wait_physics(RELOAD_FRAMES)
	var room: Room = current_scene.get_node_or_null(ROOM_PATH) as Room if current_scene != null else null
	if next_data != null:
		_check(room != null and room.level_data != null and room.level_data.title == next_data.title,
				"pressing interact loads the next room, %s '%s' (got '%s')" % [next_file, next_data.title,
					room.level_data.title if room != null and room.level_data != null else "no room"])
	else:
		_check(room == _room and room.is_complete(), "last built room: pressing interact keeps the completed room")
	Room.level_override = ""


## A battery directly across an ammeter, built from level data and solved.
func _check_short_formatting() -> void:
	print("-- short (LevelCircuit + DcSolver)")
	var circuit: LevelCircuit = LevelCircuit.from_dictionary({
		"nodes": {"p": [0, 0], "q": [224, 0]},
		"edges": [
			{"id": "b1", "type": "battery", "from": "p", "to": "q", "value": "6"},
			{"id": "am1", "type": "ammeter", "from": "p", "to": "q"},
		],
	}, "short test")
	var solution: DcSolution = DcSolver.solve(circuit.build_base_network())
	_check(solution.status == DcSolution.Status.SHORT, "a battery across an ammeter is a SHORT (%s)" % solution.status_text())
	_check(MeterText.reading(solution, "am1") == "SHORT",
			"the board's meter text reads SHORT (got '%s')" % MeterText.reading(solution, "am1"))
	var conditions: Array[GoalCondition] = [GoalCondition.from_dictionary({"of": "am1", "quantity": "current", "equals": "2"})]
	var goal: LevelGoal = LevelGoal.create(MISSION, conditions)
	_check(goal.reading_text(0, solution) == "SHORT" and not goal.is_met(solution),
			"the plaque text reads SHORT and the goal is not met (got '%s')" % goal.reading_text(0, solution))


## A fixed 6 V battery, a 3 ohm resistor and an ammeter in one loop, with a
## slot in parallel with the battery. A 9 V battery in the slot conflicts with
## the fixed one: SHORT.
func _check_short_on_a_board() -> void:
	print("-- short (CircuitBoard)")
	var circuit: LevelCircuit = LevelCircuit.from_dictionary({
		"nodes": {"p": [0, 200], "q": [224, 200], "r": [224, 0], "s": [0, 0], "t": [0, 400], "u": [224, 400]},
		"edges": [
			{"id": "b1", "type": "battery", "from": "s", "to": "r", "value": "6"},
			{"id": "w1", "type": "wire", "from": "r", "to": "q"},
			{"id": "r1", "type": "resistor", "from": "q", "to": "p", "value": "3"},
			{"id": "am1", "type": "ammeter", "from": "s", "to": "p"},
			{"id": "w2", "type": "wire", "from": "s", "to": "t"},
			{"id": "s1", "type": "slot", "from": "t", "to": "u"},
			{"id": "w3", "type": "wire", "from": "u", "to": "r"},
		],
	}, "board short test")
	var conditions: Array[GoalCondition] = [GoalCondition.from_dictionary({"of": "am1", "quantity": "current", "equals": "2"})]
	var board: CircuitBoard = CircuitBoard.new()
	board.socket_scene = load(SOCKET_SCENE) as PackedScene
	root.add_child(board)
	var shorts: Array[int] = [0]
	board.shorted.connect(func() -> void: shorts[0] += 1)
	board.build(circuit, LevelGoal.create(MISSION, conditions))
	var meter: BoardMeter = board.get_meter("am1")
	_check(meter.get_reading() == "2 A" and board.is_goal_met() and shorts[0] == 0,
			"the board starts at 2 A with the goal met (meter '%s')" % meter.get_reading())
	var pickup: PartPickup = (load(PICKUP_SCENE) as PackedScene).instantiate() as PartPickup
	root.add_child(pickup)
	pickup.setup("b9", Part.create(Part.Kind.BATTERY, Rational.new(9)), Vector2.ZERO)
	pickup.take()
	board.get_sockets()[0].insert(pickup)
	_check(meter.get_reading() == "SHORT" and not board.is_goal_met(),
			"a 9 V battery in parallel with the 6 V one: the ammeter reads SHORT, goal not met (meter '%s')" % meter.get_reading())
	_check(board.get_wires().get_state() == CircuitWires.State.SHORT and shorts[0] == 1,
			"the wires show the short state and `shorted` was emitted once (%d)" % shorts[0])
	await _wait_physics(20)
	var flashed: bool = false
	for i: int in 40:
		await process_frame
		if board.get_wires().get_core_color() != CircuitWires.SHORT_COLOR:
			flashed = true
			break
	_check(flashed, "the short's wire colour flashes")
	board.get_sockets()[0].take_out()
	_check(meter.get_reading() == "2 A" and board.is_goal_met() and shorts[0] == 1,
			"taking the battery out ends the short (meter '%s', shorted %d)" % [meter.get_reading(), shorts[0]])
	board.queue_free()
	pickup.queue_free()
	await _wait_physics(2)


# --- helpers ------------------------------------------------------------------------

## The plaque's reading and the ammeter on the board both read `expected`.
func _check_reading(expected: String, what: String) -> void:
	var shown: String = _hud.get_reading_text(0)
	var meter: String = _room.get_board().get_meter("am1").get_reading()
	_check(shown == expected and meter == expected and _hud.get_row_value(1) == expected,
			"%s: the plaque and the ammeter read %s (plaque '%s', meter '%s')" % [what, expected, shown, meter])


func _send_action_event(action: StringName, pressed: bool) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


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
