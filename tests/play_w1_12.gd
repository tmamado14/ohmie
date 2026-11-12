extends SceneTree
## Scripted headless playthrough of res://levels/w1_12.json ("A Bridge Too
## Far": a fixed 6 V battery feeds a Wheatstone bridge; slot s_top (high) and
## the fixed 2 ohm arm_a form the top path, slot s_bot (low) and the fixed
## 4 ohm arm_b the bottom path; am_bridge joins the two middle points and
## am_supply reads the supply current; resistors 1/2, 1, 2, 3, 4 ohm; goal:
## am_bridge reads 0 A and am_supply reads 3 A).
##
## First checks with the circuit API: the one solution (1 ohm top, 2 ohm
## bottom), the balanced near misses (2 with 4: 9/4 A; 1/2 with 1: 18/5 A),
## the swapped pair (3 A but the bridge carries -1 A) and the empty board (no
## current anywhere, which zeroes the bridge but not the supply). Then plays
## the room through the input map only (no teleporting): the 2 ohm from the
## left shelf into s_top (3/5 A across the bridge), the 1 ohm from the right
## ledge into s_bot (3 A flowing, bridge -1 A: wrong), the 1 ohm pulled and
## swapped into s_top (6/7 A, 18/7 A), the 2 ohm into s_bot (0 A and 3 A,
## door open), then right into the door.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --fixed-fps 60 --script res://tests/play_w1_12.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
const LEVEL_PATH: String = "res://levels/w1_12.json"
const ROOM_PATH: NodePath = ^"Room"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]

const TITLE: String = "A Bridge Too Far"
const MISSION: String = "Zero the bridge. Keep 3 A flowing."
const PLAQUE_CAPTIONS: Array[String] = ["I", "I"]
const PLAQUE_START_VALUES: Array[String] = ["0 A  →  0 A", "0 A  →  3 A"]
const PART_COUNT: int = 5
const SLOT_COUNT: int = 2

## Layout facts of w1_12.json.
const SPAWN: Vector2 = Vector2(64, 640)
const DOOR: Vector2 = Vector2(1216, 640)
const FLOOR_Y: float = 640.0
const S_BOT_PLATFORM_Y: float = 551.0  # row 17, x 192..288
const LEFT_SHELF_Y: float = 455.0  # row 14, x 0..96
const S_TOP_PLATFORM_Y: float = 359.0  # row 11, x 192..320
const RIGHT_LEDGE_Y: float = 551.0  # row 17, x 928..1056
const TWO_X: float = 48.0
const ONE_X: float = 992.0
const S_TOP_X: float = 272.0
const S_BOT_X: float = 240.0
const TO_LEFT_SHELF_JUMP_X: float = 200.0
const TO_S_TOP_JUMP_X: float = 80.0

const POSITION_TOLERANCE: float = 6.0
const SETTLE_FRAMES: int = 20
const MAX_WALK_FRAMES: int = 900
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
	print("play_w1_12: %d passed, %d failed" % [_passed, _failed])
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
	_check_circuit()
	await _solve()
	if _failed == 0:
		await _enter_door()
	Room.level_override = ""
	return 0 if _failed == 0 else 1


func _check_start_state() -> void:
	print("-- start")
	_check(_room.level_data.title == TITLE, "level title is '%s' (got '%s')" % [TITLE, _room.level_data.title])
	_check(_hud.get_mission_text() == MISSION, "the mission sign shows '%s' (got '%s')" % [MISSION, _hud.get_mission_text()])
	var captions: Array[String] = []
	var values: Array[String] = []
	for row: int in 2:
		captions.append(_hud.get_row_caption(row))
		values.append(_hud.get_row_value(row))
	_check(captions == PLAQUE_CAPTIONS and values == PLAQUE_START_VALUES,
			"the plaque rows read %s %s (got %s %s)" % [PLAQUE_CAPTIONS, PLAQUE_START_VALUES, captions, values])
	_check(not _hud.is_mission_complete_shown(), "the mission sign starts not done")
	_check(not _door.is_open(), "door starts closed")
	_check(_room.get_parts().size() == PART_COUNT and _room.get_board().get_sockets().size() == SLOT_COUNT,
			"%d parts and %d slots in the room" % [PART_COUNT, SLOT_COUNT])
	_check(_player.position.distance_to(SPAWN) <= POSITION_TOLERANCE and _player.is_on_floor(),
			"player starts on the floor at spawn (%s)" % _player.position)

func _check_circuit() -> void:
	print("-- bridge (circuit API)")
	_api({}, ["0 A", "0 A"], false, "both slots empty (no current anywhere)")
	_api({"s_top": _r("2")}, ["3/5 A", "9/5 A"], false, "2 Ω in s_top only")
	_api({"s_bot": _r("2")}, ["-6/5 A", "9/5 A"], false, "2 Ω in s_bot only")
	_api({"s_top": _r("2"), "s_bot": _r("1")}, ["-1 A", "3 A"], false, "2 Ω top, 1 Ω bottom (3 A, bridge not zero)")
	_api({"s_top": _r("2"), "s_bot": _r("4")}, ["0 A", "9/4 A"], false, "2 Ω top, 4 Ω bottom (balanced, too little current)")
	_api({"s_top": _r("1/2"), "s_bot": _r("1")}, ["0 A", "18/5 A"], false, "1/2 Ω top, 1 Ω bottom (balanced, too much current)")
	_api({"s_top": _r("1"), "s_bot": _r("3")}, ["6/25 A", "72/25 A"], false, "1 Ω top, 3 Ω bottom")
	_api({"s_top": _r("1"), "s_bot": _r("2")}, ["0 A", "3 A"], true, "1 Ω top, 2 Ω bottom")


func _solve() -> void:
	print("-- solve")
	var meters: Dictionary = {"am_bridge": "", "am_supply": ""}
	# The 2 ohm from the left shelf into s_top.
	await _jump_from(S_BOT_X, 0, S_BOT_PLATFORM_Y, "jumps straight up onto the s_bot platform")
	await _climb_to_shelf_and_pick("r2")
	await _jump_from(TO_S_TOP_JUMP_X, 1, S_TOP_PLATFORM_Y, "jumps right onto the s_top platform")
	await _walk_to_x(S_TOP_X)
	await _plug("s_top")
	meters = {"am_bridge": "3/5 A", "am_supply": "9/5 A"}
	_expect(["3/5 A", "9/5 A"], false, "2 Ω in s_top only", meters)

	# The 1 ohm from the right ledge into s_bot: 3 A, but the bridge is not zero.
	await _drop_through(S_BOT_PLATFORM_Y, "drops through to the s_bot platform")
	await _drop_through(FLOOR_Y, "drops through to the floor")
	await _jump_from(ONE_X, 0, RIGHT_LEDGE_Y, "jumps straight up onto the right ledge")
	await _pick("r1")
	await _drop_through(FLOOR_Y, "drops through the right ledge to the floor")
	await _jump_from(S_BOT_X, 0, S_BOT_PLATFORM_Y, "jumps straight up onto the s_bot platform")
	await _walk_to_x(S_BOT_X)
	await _plug("s_bot")
	meters = {"am_bridge": "-1 A", "am_supply": "3 A"}
	_expect(["-1 A", "3 A"], false, "2 Ω top, 1 Ω bottom", meters)
	_check(_hud.is_condition_met_shown(1) and not _hud.is_condition_met_shown(0),
			"the supply row is green, the bridge row is not")

	# Swap them round: the 1 ohm up into s_top, the 2 ohm down into s_bot.
	await _pull("s_bot", "r1")
	await _jump_from(TO_LEFT_SHELF_JUMP_X, -1, LEFT_SHELF_Y, "jumps left onto the left shelf")
	await _jump_from(TO_S_TOP_JUMP_X, 1, S_TOP_PLATFORM_Y, "jumps right onto the s_top platform")
	await _walk_to_x(S_TOP_X)
	await _swap("s_top", "r2")
	meters = {"am_bridge": "6/7 A", "am_supply": "18/7 A"}
	_expect(["6/7 A", "18/7 A"], false, "1 Ω in s_top only", meters)
	await _drop_through(S_BOT_PLATFORM_Y, "drops through to the s_bot platform")
	await _walk_to_x(S_BOT_X)
	await _plug("s_bot")
	meters = {"am_bridge": "0 A", "am_supply": "3 A"}
	_expect(["0 A", "3 A"], true, "1 Ω top, 2 Ω bottom", meters)


## From the s_bot platform: left onto the shelf and pick up `id` there.
func _climb_to_shelf_and_pick(id: String) -> void:
	await _jump_from(TO_LEFT_SHELF_JUMP_X, -1, LEFT_SHELF_Y, "jumps left onto the left shelf")
	await _walk_to_x(TWO_X)
	await _pick(id)


func _enter_door() -> void:
	print("-- door")
	var action: String = "move_right" if DOOR.x > _player.position.x else "move_left"
	Input.action_press(action)
	for i: int in MAX_WALK_FRAMES:
		await _wait_physics(1)
		if _room.is_complete():
			break
	_release_all()
	_check(_room.is_complete() and _completed_count == 1,
			"walking into the open door completes the level (player at %s, door at %s)" % [_player.position, DOOR])
	_check(_hud.is_level_complete_shown(), "the level-complete banner is shown")


# --- helpers ------------------------------------------------------------------------

## The plaque shows `readings` (one per goal condition), every board meter in
## `meters` (id -> text) shows its text, and the door and the mission sign are
## open exactly when `met`.
func _expect(readings: Array[String], met: bool, what: String, meters: Dictionary = {}) -> void:
	var ok: bool = true
	var got: Array[String] = []
	for i: int in readings.size():
		got.append(_hud.get_reading_text(i))
		if got[i] != readings[i]:
			ok = false
	for id: String in meters.keys():
		var meter: BoardMeter = _room.get_board().get_meter(id)
		var text: String = meter.get_reading() if meter != null else "missing"
		got.append("%s %s" % [id, text])
		if text != String(meters[id]):
			ok = false
	_check(ok, "%s: reads %s %s (got %s)" % [what, readings, meters.values() if not meters.is_empty() else "", got])
	_check(_door.is_open() == met and _room.get_board().is_goal_met() == met and _hud.is_mission_complete_shown() == met,
			"%s: door %s" % [what, "open" if met else "closed"])
	if met:
		var all_green: bool = true
		for i: int in readings.size():
			all_green = all_green and _hud.is_condition_met_shown(i)
		_check(all_green and _room.get_board().get_wires().get_state() == CircuitWires.State.MATCH,
				"%s: every plaque row is green and the wires show the match colour" % what)


## Solves `fill` (slot id -> Part) with the circuit API and checks the goal's
## reading texts and whether the goal is met.
func _api(fill: Dictionary, readings: Array[String], met: bool, what: String) -> void:
	var solution: DcSolution = DcSolver.solve(_room.get_circuit().build_network(fill))
	var goal: LevelGoal = _room.get_goal()
	var got: Array[String] = []
	for i: int in goal.condition_count():
		got.append(goal.reading_text(i, solution))
	_check(got == readings and goal.is_met(solution) == met,
			"%s reads %s, goal %s (got %s, %s)" % [what, readings, "met" if met else "not met", got,
				"met" if goal.is_met(solution) else "not met"])


func _r(ohms: String) -> Part:
	return Part.create(Part.Kind.RESISTOR, Rational.parse(ohms))


func _b(volts: String) -> Part:
	return Part.create(Part.Kind.BATTERY, Rational.parse(volts))


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


## Checks that Ohmie stands on the surface at `surface_y`.
func _check_on(surface_y: float, what: String) -> void:
	_check(_on_surface(surface_y), "%s (at %s, surface y=%.0f)" % [what, _player.position, surface_y])


## Picks up `id` where Ohmie stands and checks it is carried.
func _pick(id: String) -> void:
	await _interact()
	_check(_carry.get_carried() == _part(id), "picks up %s (carrying %s)" % [id,
			_carry.get_carried().part_id if _carry.is_carrying() else "nothing"])


## Plugs the carried part into empty slot `slot_id` where Ohmie stands.
func _plug(slot_id: String) -> void:
	var held: PartPickup = _carry.get_carried()
	await _interact()
	_check(held != null and not _carry.is_carrying() and _socket(slot_id).get_pickup() == held,
			"plugs %s into %s" % [held.part_id if held != null else "nothing", slot_id])


## Swaps the carried part into filled slot `slot_id`; checks Ohmie now carries `out_id`.
func _swap(slot_id: String, out_id: String) -> void:
	var held: PartPickup = _carry.get_carried()
	await _interact()
	_check(held != null and _socket(slot_id).get_pickup() == held and _carry.get_carried() == _part(out_id),
			"swaps %s into %s and takes out %s" % [held.part_id if held != null else "nothing", slot_id, out_id])


## Pulls the part out of slot `slot_id`; checks Ohmie now carries `out_id`.
func _pull(slot_id: String, out_id: String) -> void:
	await _interact()
	_check(not _socket(slot_id).is_filled() and _carry.get_carried() == _part(out_id),
			"pulls %s out of %s" % [out_id, slot_id])


## Puts the carried part down at Ohmie's feet (nothing in reach).
func _put_down() -> void:
	var held: PartPickup = _carry.get_carried()
	await _interact()
	_check(held != null and not _carry.is_carrying() and held.is_loose(),
			"puts %s down (at %s)" % [held.part_id if held != null else "nothing", held.global_position if held != null else Vector2.ZERO])


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
	await _wait_physics(2)
	if absf(_player.position.x - x) > POSITION_TOLERANCE:
		print("      (walk to x=%.0f ended at x=%.1f)" % [x, _player.position.x])


## Jumps (holding left for direction -1, right for 1, nothing for 0) with a full
## jump hold and waits until the player has left the floor and landed again.
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
	await _wait_physics(3)


## Walks to `x`, jumps in `direction` and checks the landing surface.
func _jump_from(x: float, direction: int, surface_y: float, what: String) -> void:
	await _walk_to_x(x)
	await _jump_and_land(direction)
	_check_on(surface_y, what)


## Holds move_down to drop through the one-way platform Ohmie stands on and
## waits for the landing below.
func _drop_through(surface_y: float, what: String) -> void:
	var start_y: float = _player.position.y
	Input.action_press("move_down")
	var left_floor: bool = false
	for i: int in MAX_AIR_FRAMES:
		await _wait_physics(1)
		if not _player.is_on_floor():
			left_floor = true
			Input.action_release("move_down")
		elif left_floor and _player.position.y > start_y + POSITION_TOLERANCE:
			break
	Input.action_release("move_down")
	await _wait_physics(3)
	_check_on(surface_y, what)


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
