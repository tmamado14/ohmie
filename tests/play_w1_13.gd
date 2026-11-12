extends SceneTree
## Scripted headless playthrough of res://levels/w1_13.json ("Loop Hole": a
## ladder of three rungs between two buses: the top rung holds the fixed 3 ohm
## r_top and slot s_top (high, right), the middle rung the shared 2 ohm r_mid,
## the bottom rung slot s_bot (low, left) and the fixed 6 ohm r_bot; the
## voltmeter vm1 on a fourth rung across the buses reads the voltage on r_mid;
## both slots put + on the left bus, so two batteries aid; batteries 3, 6, 9 V
## and a 2 ohm resistor; goal: vm1 reads 4 V).
##
## The finale. The 9 V lies on a high shelf over the door that only the bounce
## pad reaches; the s_bot platform is an island between a live wire and a
## spike strip; a bot patrols the floor between the meter and the right-hand
## ledges; a spark orb rises and falls across the gap that the jump from the
## high right ledge to s_top must cross, so the 9 V is carried through it.
##
## First checks with the circuit API: the one solution (9 V top, 6 V bottom),
## the swapped pair (7/2 V), every single source with the other loop open or
## holding the resistor (never 4 V), and the other battery pairs. Then:
## - a zap section: the 6 V by the spawn carried left into the bot: one zap,
##   Ohmie back at the spawn, the 6 V back home, the circuit unchanged; then
##   `restart`;
## - a zap-free solve through the input map only (no teleporting), timing the
##   bot and the orb by predicting their motion and Ohmie's moves frame by
##   frame and waiting until the whole move keeps clear of every hurtbox: over
##   the bot, onto the island over the spikes, a hop off its left end onto the
##   pad and a bounce up to the 9 V; down, over the live wire onto the island,
##   off its right end over the spikes, over the bot, up the right ledges and
##   across the orb's gap into s_top (18/5 V); a timed drop past the bot for
##   the 6 V, back over the bot and onto the island into s_bot (4 V, door
##   open); then over the live wire to the door. The room's `zapped` signal
##   must not fire once.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --fixed-fps 60 --script res://tests/play_w1_13.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
const LEVEL_PATH: String = "res://levels/w1_13.json"
const ROOM_PATH: NodePath = ^"Room"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]
const TEST_NAME: String = "play_w1_13"

const TITLE: String = "Loop Hole"
const MISSION: String = "Put 4 V on the meter."
const PLAQUE_CAPTIONS: Array[String] = ["GOAL", "V"]
const PLAQUE_START_VALUES: Array[String] = ["4 V", "0 V"]
const PART_COUNT: int = 4
const SLOT_COUNT: int = 2
const METER_ID: String = "vm1"

## Layout facts of w1_13.json.
const SPAWN: Vector2 = Vector2(1216, 640)
const DOOR: Vector2 = Vector2(64, 640)
const FLOOR_Y: float = 640.0
const SHELF_Y: float = 391.0  # row 12, x 0..128 (the 9 V)
const S_BOT_PLATFORM_Y: float = 551.0  # row 17, x 320..416
const S_TOP_PLATFORM_Y: float = 359.0  # row 11, x 704..832
const RIGHT_LOW_Y: float = 551.0  # row 17, x 992..1120 (the 3 V)
const RIGHT_HIGH_Y: float = 455.0  # row 14, x 928..1024 (the 2 ohm)
const PAD_X: float = 176.0
const LIVE_WIRE_X: float = 288.0
const SPIKES_X: float = 464.0
const BOT_LEFT: float = 680.0
const BOT_RIGHT: float = 840.0
const BOT_SPEED: float = 60.0
const ORB_FROM: Vector2 = Vector2(888, 300)
const ORB_TO: Vector2 = Vector2(888, 440)
const ORB_SPEED: float = 70.0
const SIX_HOME: Vector2 = Vector2(1136, 640)
const NINE_X: float = 64.0
const S_BOT_X: float = 352.0
const S_TOP_X: float = 744.0
## Right of the bot (its hurtbox ends at x = 869).
const RIGHT_OF_BOT_X: float = 900.0
## Between the spikes (to x = 500) and the bot (from x = 651).
const MIDDLE_X: float = 600.0
## Takeoff from the middle floor for the jump left over the spikes onto the island.
const ONTO_S_BOT_X: float = 548.0
## On the island: the takeoff for the hop onto the pad, and for the jump off its right end.
const S_BOT_LEFT_X: float = 330.0
const S_BOT_RIGHT_X: float = 410.0
## Frames of move_left on the hop from S_BOT_LEFT_X: the feet meet the pad's cushion near x 178.
const ONTO_PAD_HOLD: int = 38
## Frames of move_left after the bounce: lands on the shelf near x 66.
const BOUNCE_STEER_FRAMES: int = 28
## Takeoff on the floor left of the live wire for the jump onto the island.
const FLOOR_TAKEOFF_X: float = 210.0
## Under the right ledges, for the jumps straight up.
const UNDER_RIGHT_X: float = 1010.0
## On the high right ledge, clear of the orb's column: the takeoff towards s_top.
const ORB_TAKEOFF_X: float = 950.0
## Frames of move_left on the hop off the island towards the door: lands near
## x 232, between the pad's catch zone and the live wire.
const TO_DOOR_HOLD: int = 27

const POSITION_TOLERANCE: float = 6.0
const SETTLE_FRAMES: int = 20
const MAX_WALK_FRAMES: int = 900
const MAX_AIR_FRAMES: int = 180
const MAX_ZAP_WAIT_FRAMES: int = 600
const RESTART_FRAMES: int = 4

# --- route prediction ------------------------------------------------------------------
## Ohmie's moves are predicted with the player's own integration (run 4 px a
## frame, jump 660 px/s, gravity 30 px/s per frame, one-way platforms caught
## only while falling, drop-through ignoring them for 15 frames, a pad's
## relaunch) and every hurtbox alongside it; a timed move starts only when the
## whole move, and a short stand after it, keeps SAFETY_MARGIN clear of all.
const RUN_STEP: float = 4.0
const JUMP_SPEED: float = 660.0
const GRAVITY_STEP: float = 30.0
const BOUNCE_SPEED: float = 913.0
const HALF_WIDTH: float = 18.0
const BODY_HEIGHT: float = 88.0
const DROP_FRAMES: int = 15
const SCREEN_RIGHT: float = 1280.0
const FALL_OUT_Y: float = 800.0
const SAFETY_MARGIN: float = 4.0
const STAND_CHECK_FRAMES: int = 45
const MAX_PLAN_FRAMES: int = 400
const MAX_TIMING_WAIT_FRAMES: int = 1200
## A timed move must have an unbroken run of safe start frames at least this long.
const MIN_WINDOW_FRAMES: int = 30
const MAX_CYCLE_FRAMES: int = 2400
## Run-up lengths (frames of running before the jump) a timed jump may choose from.
const RUN_UPS: Array[int] = [0, 6, 12, 18, 24, 30]

var _passed: int = 0
var _failed: int = 0

var _room: Room = null
var _player: Player = null
var _carry: PlayerCarry = null
var _hud: Hud = null
var _door: ExitDoor = null
var _respawn: PlayerRespawn = null
var _patrollers: Array[Patroller] = []
var _floaters: Array[Floater] = []
var _statics: Array[StaticHazard] = []
var _pads: Array[BouncePad] = []
var _completed_count: int = 0
var _zap_count: int = 0
var _respawn_count: int = 0
var _bounce_count: int = 0
var _frame: int = 0
## Surfaces Ohmie can stand on: {"y", "x0", "x1", "solid"}.
var _surfaces: Array[Dictionary] = []
## Floater centre seen on the previous frame: instance id -> [frame, position].
var _floater_seen: Dictionary = {}
## Frames waited before each timed move (for the report).
var _waits: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var exit_code: int = await _run_checks()
	_release_all()
	print("")
	print("%s: %d passed, %d failed" % [TEST_NAME, _passed, _failed])
	quit(exit_code)


func _run_checks() -> int:
	Room.level_override = LEVEL_PATH
	physics_frame.connect(func() -> void: _frame += 1)
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
	await _zap_while_carrying()
	if not await _restart():
		return 1
	_check(_zap_count == 0 and _room.get_parts().size() == PART_COUNT, "after restart the room is fresh")
	await _solve()
	_check(_zap_count == 0, "the solving run was never zapped (zapped %d)" % _zap_count)
	if _failed == 0:
		await _enter_door()
	print("timing waits: %s" % ", ".join(_waits))
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
	_check_homes()


## The room's objects: the pad, the live wire, the spikes, the bot and the
## spark orb, as the level file says.
func _check_objects() -> bool:
	var ok: bool = _pads.size() == 1 and _patrollers.size() == 1 and _floaters.size() == 1 and _statics.size() == 2
	_check(ok, "one pad, two static hazards, one patroller and one floater")
	if not ok:
		return false
	var bot: Patroller = _patrollers[0]
	var orb: Floater = _floaters[0]
	_check(_pads[0].global_position == Vector2(PAD_X, FLOOR_Y)
			and _statics[0].global_position == Vector2(LIVE_WIRE_X, FLOOR_Y)
			and _statics[1].global_position == Vector2(SPIKES_X, FLOOR_Y),
			"the pad, the live wire and the spikes stand at x=%d, %d, %d" % [int(PAD_X), int(LIVE_WIRE_X), int(SPIKES_X)])
	_check(bot.left == BOT_LEFT and bot.right == BOT_RIGHT and bot.speed == BOT_SPEED,
			"the bot walks %d..%d at %d px/s" % [int(BOT_LEFT), int(BOT_RIGHT), int(BOT_SPEED)])
	_check(orb.get_from() == ORB_FROM and orb.get_to() == ORB_TO and orb.speed == ORB_SPEED,
			"the spark orb drifts %s..%s at %d px/s" % [ORB_FROM, ORB_TO, int(ORB_SPEED)])
	return true


func _check_circuit() -> void:
	print("-- two sources (circuit API)")
	_api({"s_top": _b("6")}, ["12/5 V"], false, "6 V on top, bottom loop open")
	_api({"s_top": _b("9")}, ["18/5 V"], false, "9 V on top, bottom loop open")
	_api({"s_bot": _b("9")}, ["9/4 V"], false, "9 V at the bottom, top loop open")
	_api({"s_bot": _b("6")}, ["3/2 V"], false, "6 V at the bottom, top loop open")
	_api({"s_top": _b("9"), "s_bot": _r("2")}, ["72/23 V"], false, "9 V on top, 2 Ω at the bottom")
	_api({"s_top": _b("6"), "s_bot": _b("9")}, ["7/2 V"], false, "6 V top, 9 V bottom (swapped)")
	_api({"s_top": _b("9"), "s_bot": _b("3")}, ["7/2 V"], false, "9 V top, 3 V bottom")
	_api({"s_top": _b("6"), "s_bot": _b("3")}, ["5/2 V"], false, "6 V top, 3 V bottom")
	_api({"s_top": _b("9"), "s_bot": _b("6")}, ["4 V"], true, "9 V top, 6 V bottom")


## The 6 V by the spawn carried left into the bot.
func _zap_while_carrying() -> void:
	print("-- zapped by the bot while carrying")
	await _walk_to_x(SIX_HOME.x)
	await _pick("b6")
	var readings_before: String = _hud.get_reading_text(0)
	var meter_before: String = _room.get_board().get_meter(METER_ID).get_reading()
	var zaps_before: int = _zap_count
	var respawns_before: int = _respawn_count
	Input.action_press("move_left")
	for i: int in MAX_ZAP_WAIT_FRAMES:
		if _zap_count > zaps_before:
			break
		await _wait_physics(1)
	Input.action_release("move_left")
	_check(_zap_count == zaps_before + 1 and _player.position.x < BOT_RIGHT + 60.0,
			"walking left into the bot zaps (zapped %d at %s)" % [_zap_count - zaps_before, _player.position])
	for i: int in MAX_ZAP_WAIT_FRAMES:
		if _respawn_count > respawns_before:
			break
		await _wait_physics(1)
	await _wait_physics(2)
	var six: PartPickup = _part("b6")
	_check(_zap_count == zaps_before + 1, "exactly one zap (zapped %d)" % (_zap_count - zaps_before))
	_check(_player.position.distance_to(SPAWN) <= POSITION_TOLERANCE, "Ohmie is back at the spawn (%s)" % _player.position)
	_check(not _carry.is_carrying() and six.is_loose() and six.global_position.distance_to(SIX_HOME) < 0.5,
			"the 6 V is back home (%s)" % six.global_position)
	_check(not _socket("s_top").is_filled() and not _socket("s_bot").is_filled()
			and _hud.get_reading_text(0) == readings_before
			and _room.get_board().get_meter(METER_ID).get_reading() == meter_before,
			"the circuit is unchanged (both slots empty, meter '%s')" % meter_before)


func _solve() -> void:
	print("-- solve (no zaps)")
	# Left over the bot, onto the island, off its left end onto the pad, up to the 9 V.
	await _walk_to_x(RIGHT_OF_BOT_X)
	var walk_window: Dictionary = _timing_window([_predict_route([_seg("walk", -1, -1, MIDDLE_X)])])
	_check(int(walk_window["safe"]) == 0, "walking past the bot without a jump never works (%d of %d clear)"
			% [walk_window["safe"], walk_window["total"]])
	await _cross_left_over_bot()
	await _onto_island_from_right()
	await _walk_to_x(S_BOT_LEFT_X)
	await _bounce_to_shelf()
	await _walk_to_x(NINE_X)
	await _pick("b9")
	await _drop_through(FLOOR_Y, "drops through the shelf to the floor by the door")
	await _jump_and_land(0)
	_check_on(FLOOR_Y, "a jump in place under the shelf falls short of it (249 px up): lands on the floor again")

	# Carry the 9 V right: onto the island over the live wire, off over the spikes, over the bot.
	await _walk_to_x(FLOOR_TAKEOFF_X)
	await _timed_route([_seg("jump", 1)], "jump right over the live wire onto the island")
	_check_on(S_BOT_PLATFORM_Y, "lands on the island")
	await _walk_to_x(S_BOT_RIGHT_X)
	await _timed_route([_seg("jump", 1)], "jump right off the island over the spikes")
	_check_on(FLOOR_Y, "lands between the spikes and the bot")
	await _timed_route([_seg("jump", 1, -1, RIGHT_OF_BOT_X)], "running jump right over the bot (carrying the 9 V)",
			true, RUN_UPS)
	_check_on(FLOOR_Y, "lands right of the bot")

	# Up the right ledges and across the orb's gap into s_top.
	await _jump_from(UNDER_RIGHT_X, 0, RIGHT_LOW_Y, "jumps straight up onto the low right ledge")
	await _jump_and_land(0)
	_check_on(RIGHT_HIGH_Y, "jumps straight up onto the high right ledge")
	await _walk_to_x(ORB_TAKEOFF_X)
	await _timed_route([_seg("jump", -1)], "jump left across the orb's gap onto s_top (carrying the 9 V)", true)
	_check_on(S_TOP_PLATFORM_Y, "lands on the s_top platform")
	await _walk_to_x(S_TOP_X)
	await _plug("s_top")
	_expect(["18/5 V"], false, "9 V on top only", {METER_ID: "18/5 V"})

	# Down past the bot for the 6 V, back over the bot, onto the island into s_bot.
	await _timed_route([_seg("drop", 1, -1, RIGHT_OF_BOT_X)], "drop through s_top and run right past the bot", true)
	_check_on(FLOOR_Y, "lands on the floor right of the bot")
	await _walk_to_x(SIX_HOME.x)
	await _pick("b6")
	await _walk_to_x(RIGHT_OF_BOT_X)
	await _cross_left_over_bot()
	await _onto_island_from_right()
	await _walk_to_x(S_BOT_X)
	await _plug("s_bot")
	_expect(["4 V"], true, "9 V top, 6 V bottom", {METER_ID: "4 V"})

	# Off the island's left end, over the live wire, short of the pad.
	await _walk_to_x(S_BOT_LEFT_X)
	await _timed_route([_seg("jump", -1, TO_DOOR_HOLD)], "hop left off the island over the live wire")
	_check_on(FLOOR_Y, "lands between the pad and the live wire")
	_check(_bounce_count == 1, "the hop towards the door does not touch the pad (bounces %d)" % _bounce_count)


## From RIGHT_OF_BOT_X: a running jump left over the bot to the middle floor.
func _cross_left_over_bot() -> void:
	await _timed_route([_seg("jump", -1, -1, MIDDLE_X)], "running jump left over the bot", true, RUN_UPS)
	_check_on(FLOOR_Y, "lands between the bot and the spikes")


## From the middle floor: a jump left over the spikes onto the island.
func _onto_island_from_right() -> void:
	await _walk_to_x(ONTO_S_BOT_X)
	await _timed_route([_seg("jump", -1)], "jump left over the spikes onto the island")
	_check_on(S_BOT_PLATFORM_Y, "lands on the island")


## From S_BOT_LEFT_X on the island: a hop left onto the pad, then steer left
## while bouncing to land on the shelf.
func _bounce_to_shelf() -> void:
	var bounces_before: int = _bounce_count
	var zaps_before: int = _zap_count
	Input.action_press("move_left")
	Input.action_press("jump")
	for i: int in MAX_AIR_FRAMES:
		await _wait_physics(1)
		if i + 1 >= ONTO_PAD_HOLD:
			Input.action_release("move_left")
		if _bounce_count > bounces_before:
			break
	Input.action_release("jump")
	Input.action_release("move_left")
	_check(_bounce_count == bounces_before + 1, "the hop off the island lands on the pad and bounces (bounced %d)"
			% (_bounce_count - bounces_before))
	Input.action_press("move_left")
	await _wait_physics(BOUNCE_STEER_FRAMES)
	Input.action_release("move_left")
	for i: int in MAX_AIR_FRAMES:
		await _wait_physics(1)
		if _player.is_on_floor():
			break
	await _wait_physics(2)
	_check_on(SHELF_Y, "the bounce carries Ohmie up onto the high shelf")
	_check(_bounce_count == bounces_before + 1 and _zap_count == zaps_before, "one bounce, no zap")


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
	_check(_zap_count == 0, "still never zapped at the door (zapped %d)" % _zap_count)


# --- timed moves ------------------------------------------------------------------------

## One move: `kind` "jump", "walk" or "drop"; `dir` -1, 0 or 1; `hold` frames
## of the direction key (-1: until `stop_x` is reached, or until landing when
## there is no stop_x); `stop_x` NAN for none. A jump may start with `run_up`
## frames of running before the jump key is pressed.
func _seg(kind: String, dir: int, hold: int = -1, stop_x: float = NAN, run_up: int = 0) -> Dictionary:
	return {"kind": kind, "dir": dir, "hold": hold, "stop_x": stop_x, "run_up": run_up}


## Waits, standing, until the predicted route keeps clear of every hurtbox,
## then performs it. `run_ups` lists the run-up lengths (frames of running
## before the first jump) Ohmie may choose from, as a player picks a takeoff
## point. Before waiting, measures over one full enemy cycle on how many start
## frames some run-up would be safe and the longest unbroken safe window; when
## `threatened`, checks that an enemy really can spoil the move and that the
## window is still at least MIN_WINDOW_FRAMES long.
func _timed_route(segments: Array[Dictionary], what: String, threatened: bool = false,
		run_ups: Array[int] = [0]) -> void:
	var options: Array[Array] = []
	var paths: Array[PackedVector2Array] = []
	for run_up: int in run_ups:
		var option: Array[Dictionary] = []
		for seg: Dictionary in segments:
			option.append(seg.duplicate())
		option[0]["run_up"] = run_up
		var path: PackedVector2Array = _predict_route(option)
		if not path.is_empty():
			options.append(option)
			paths.append(path)
	_check(not paths.is_empty(), "%s: the predicted move stays in the room" % what)
	var longest_path: int = 0
	for path: PackedVector2Array in paths:
		longest_path = maxi(longest_path, path.size())
	var waited: int = 0
	var chosen: int = -1
	var measured: bool = false
	for i: int in MAX_TIMING_WAIT_FRAMES:
		_sample_floaters()
		if _floaters_ready() and not paths.is_empty():
			if not measured:
				measured = true
				var fixed: Dictionary = _timing_window([paths[0]])
				var window: Dictionary = _timing_window(paths)
				print(("      %s: over a %d-frame cycle, safe to start on %d frames from where he stands"
						+ " (longest window %.2f s); choosing a run-up, on %d frames (longest window %d frames = %.2f s)")
						% [what, window["total"], fixed["safe"], float(fixed["longest"]) / 60.0, window["safe"],
							window["longest"], float(window["longest"]) / 60.0])
				if threatened:
					_check(int(fixed["safe"]) < int(fixed["total"]) and int(window["longest"]) >= MIN_WINDOW_FRAMES,
							"%s: the enemy can spoil a jump from here, and a clear window of %d frames (>= %d) comes every cycle"
							% [what, window["longest"], MIN_WINDOW_FRAMES])
			var hazards: Array = _predict_hazards(longest_path + 2)
			for p: int in paths.size():
				if _route_clear(paths[p], hazards, 0):
					chosen = p
					break
			if chosen >= 0:
				break
		await _wait_physics(1)
		waited += 1
	_check(chosen >= 0, "%s: a safe moment comes (waited %d frames)" % [what, waited])
	if chosen < 0:
		return
	var run_up_used: int = options[chosen][0]["run_up"]
	_waits.append("%s %d%s" % [what, waited, " (run-up %d)" % run_up_used if run_up_used > 0 else ""])
	var zaps_before: int = _zap_count
	for i: int in options[chosen].size():
		if i > 0:
			await _wait_physics(1)
		await _perform(options[chosen][i])
	await _wait_physics(2)
	_check(_zap_count == zaps_before, "%s: no zap (at %s)" % [what, _player.position])


func _perform(seg: Dictionary) -> void:
	var kind: String = seg["kind"]
	var dir: int = seg["dir"]
	var hold: int = seg["hold"]
	var stop_x: float = seg["stop_x"]
	var run_up: int = seg["run_up"]
	var dir_action: String = "move_left" if dir < 0 else "move_right"
	var held: bool = dir != 0
	if held:
		Input.action_press(dir_action)
	if kind == "jump" and run_up == 0:
		Input.action_press("jump")
	elif kind == "drop":
		Input.action_press("move_down")
	var left_floor: bool = false
	for k: int in range(1, MAX_PLAN_FRAMES):
		await _wait_physics(1)
		if kind == "jump" and k == run_up:
			Input.action_press("jump")
		var on_floor: bool = _player.is_on_floor()
		if not on_floor:
			left_floor = true
			if kind == "drop":
				Input.action_release("move_down")
		if held and _should_release(k, hold, stop_x, dir, _player.position.x, on_floor, left_floor):
			Input.action_release(dir_action)
			held = false
		if on_floor and not held and (left_floor or kind == "walk"):
			break
	_release_all()


## The rule both _perform and _predict_route use to let go of the direction key
## before frame `k`, given the state after frame k - 1.
func _should_release(k: int, hold: int, stop_x: float, dir: int, x: float, on_floor: bool, left_floor: bool) -> bool:
	if hold >= 0 and k >= hold:
		return true
	if not is_nan(stop_x) and ((dir > 0 and x >= stop_x) or (dir < 0 and x <= stop_x)):
		return true
	return hold < 0 and is_nan(stop_x) and on_floor and left_floor


## True when Ohmie, standing where he is for `delay` frames and then following
## `path`, keeps clear of every predicted hurtbox (each frame is checked
## against the hazards of that frame and the next, for ordering slack).
func _route_clear(path: PackedVector2Array, hazards: Array, delay: int) -> bool:
	var here: Vector2 = _player.position
	for k: int in delay + path.size():
		var feet: Vector2 = here if k < delay else path[k - delay]
		var body: Rect2 = Rect2(feet.x - HALF_WIDTH, feet.y - BODY_HEIGHT, HALF_WIDTH * 2.0, BODY_HEIGHT) \
				.grow(SAFETY_MARGIN)
		for shapes: Array in [hazards[k], hazards[k + 1]]:
			for shape: Dictionary in shapes:
				if _shape_hits(shape, body):
					return false
	return true


## Over one full cycle of the room's moving hazards: on how many start frames
## at least one of `paths` would be clear, and the longest run of consecutive
## such start frames.
func _timing_window(paths: Array[PackedVector2Array]) -> Dictionary:
	var total: int = _cycle_frames()
	var longest_path: int = 0
	for path: PackedVector2Array in paths:
		longest_path = maxi(longest_path, path.size())
	var hazards: Array = _predict_hazards(total + longest_path + 2)
	var safe: int = 0
	var run: int = 0
	var longest: int = 0
	var first_run: int = -1
	for delay: int in total:
		var clear: bool = false
		for path: PackedVector2Array in paths:
			if _route_clear_from(path, hazards, delay):
				clear = true
				break
		if clear:
			safe += 1
			run += 1
			longest = maxi(longest, run)
		else:
			if first_run < 0:
				first_run = run
			run = 0
	if first_run > 0 and run > 0:
		longest = maxi(longest, run + first_run)  # the window wraps round the cycle
	return {"safe": safe, "total": total, "longest": longest}


## Like _route_clear, but the move starts `delay` frames from now and the time
## spent waiting is not checked (only the move itself).
func _route_clear_from(path: PackedVector2Array, hazards: Array, delay: int) -> bool:
	for k: int in path.size():
		var feet: Vector2 = path[k]
		var body: Rect2 = Rect2(feet.x - HALF_WIDTH, feet.y - BODY_HEIGHT, HALF_WIDTH * 2.0, BODY_HEIGHT) \
				.grow(SAFETY_MARGIN)
		for shapes: Array in [hazards[delay + k], hazards[delay + k + 1]]:
			for shape: Dictionary in shapes:
				if _shape_hits(shape, body):
					return false
	return true


## Frames after which every moving hazard is back where it started.
func _cycle_frames() -> int:
	var cycle: int = 1
	for hazard: Hazard in _room.get_objects().get_hazards():
		var frames: int = 0
		var patroller: Patroller = hazard as Patroller
		var floater: Floater = hazard as Floater
		if patroller != null:
			frames = roundi(2.0 * (patroller.right - patroller.left) / patroller.speed * 60.0)
		elif floater != null:
			frames = roundi(2.0 * floater.get_from().distance_to(floater.get_to()) / floater.speed * 60.0)
		if frames > 0:
			cycle = cycle * frames / _gcd(cycle, frames)
	return mini(cycle, MAX_CYCLE_FRAMES)


func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t: int = a % b
		a = b
		b = t
	return a


## Ohmie's feet after each future physics frame for `segments` (one idle frame
## between segments), or an empty array if he would fall out of the room.
func _predict_route(segments: Array[Dictionary]) -> PackedVector2Array:
	var path: PackedVector2Array = PackedVector2Array()
	var x: float = _player.position.x
	var y: float = _player.position.y
	var vy: float = _player.velocity.y
	var on_floor: bool = _player.is_on_floor()
	for s: int in segments.size():
		if s > 0:
			path.append(Vector2(x, y))
		var seg: Dictionary = segments[s]
		var kind: String = seg["kind"]
		var dir: int = seg["dir"]
		var held: bool = dir != 0
		var left_floor: bool = false
		var drop_left: int = 0
		for k: int in MAX_PLAN_FRAMES:
			if k > 0 and held and _should_release(k, seg["hold"], seg["stop_x"], dir, x, on_floor, left_floor):
				held = false
			if k > 0 and on_floor and not held and (left_floor or kind == "walk"):
				break
			# One physics frame.
			if kind == "jump" and k == int(seg["run_up"]) and on_floor:
				vy = -JUMP_SPEED
				on_floor = false
			elif not on_floor:
				vy += GRAVITY_STEP
			if kind == "drop" and k == 0 and on_floor:
				drop_left = DROP_FRAMES
				on_floor = false
				vy = 0.0
			if held:
				x = clampf(x + dir * RUN_STEP, HALF_WIDTH, SCREEN_RIGHT - HALF_WIDTH)
			var new_y: float = y + vy / 60.0
			var landed: bool = false
			if vy > 0.0:
				for pad: BouncePad in _room.get_objects().get_pads():
					var cushion: float = pad.get_surface_y()
					if y <= cushion + 1.0 and new_y >= cushion and absf(x - pad.global_position.x) <= pad.catch_half_width:
						new_y = cushion
						vy = -BOUNCE_SPEED
						landed = true
						break
			if vy > 0.0 and not landed:
				var best: float = INF
				for surface: Dictionary in _surfaces:
					var sy: float = surface["y"]
					if (surface["solid"] or drop_left <= 0) and y <= sy + 0.01 and new_y >= sy and sy < best \
							and x + HALF_WIDTH > surface["x0"] and x - HALF_WIDTH < surface["x1"]:
						best = sy
				if best < INF:
					new_y = best
					vy = 0.0
					on_floor = true
			y = new_y
			if on_floor and not _supported(x, y):
				on_floor = false
			if not on_floor:
				left_floor = true
			drop_left = maxi(drop_left - 1, 0)
			if y > FALL_OUT_Y:
				return PackedVector2Array()
			path.append(Vector2(x, y))
	for k: int in STAND_CHECK_FRAMES:
		path.append(Vector2(x, y))
	return path


func _supported(x: float, y: float) -> bool:
	for surface: Dictionary in _surfaces:
		if absf(float(surface["y"]) - y) < 0.5 and x + HALF_WIDTH > surface["x0"] and x - HALF_WIDTH < surface["x1"]:
			return true
	return false


## Predicted hurtbox shapes: element k is the list of shapes after k + 1
## physics frames from now.
func _predict_hazards(frames: int) -> Array:
	var tracks: Array[Dictionary] = []
	for hazard: Hazard in _room.get_objects().get_hazards():
		tracks.append(_track_for(hazard))
	var out: Array = []
	for k: int in frames:
		var shapes: Array[Dictionary] = []
		for track: Dictionary in tracks:
			_advance_track(track)
			shapes.append(_track_shape(track))
		out.append(shapes)
	return out


func _track_for(hazard: Hazard) -> Dictionary:
	var hurtbox: Hurtbox = hazard.get_hurtbox()
	var shape: Shape2D = (hurtbox.get_child(0) as CollisionShape2D).shape
	var track: Dictionary = {"offset": hurtbox.position}
	if shape is RectangleShape2D:
		track["size"] = (shape as RectangleShape2D).size
	else:
		track["radius"] = (shape as CircleShape2D).radius
	var patroller: Patroller = hazard as Patroller
	var floater: Floater = hazard as Floater
	if patroller != null:
		track["type"] = "patroller"
		track["pos"] = patroller.global_position
		track["dir"] = patroller.get_direction()
		track["left"] = patroller.left
		track["right"] = patroller.right
		track["step"] = patroller.speed / 60.0
		track["faces_right"] = patroller.art_faces_right
		track["base_x"] = hurtbox.position.x * _patroller_sign(patroller.get_direction(), patroller.art_faces_right)
	elif floater != null:
		track["type"] = "floater"
		track["from"] = floater.get_from()
		track["to"] = floater.get_to()
		track["leg"] = floater.get_from().distance_to(floater.get_to()) / floater.speed
		track["phase"] = _floater_phase(floater)
		track["faces_right"] = floater.art_faces_right
		track["base_x"] = hurtbox.position.x * _floater_sign(track)
		track["pos"] = floater.global_position
	else:
		track["type"] = "static"
		track["pos"] = hazard.global_position
	return track


func _advance_track(track: Dictionary) -> void:
	match String(track["type"]):
		"patroller":
			var pos: Vector2 = track["pos"]
			var dir: float = track["dir"]
			var x: float = pos.x + dir * float(track["step"])
			if x >= float(track["right"]):
				x = track["right"]
				dir = -1.0
			elif x <= float(track["left"]):
				x = track["left"]
				dir = 1.0
			track["pos"] = Vector2(x, pos.y)
			track["dir"] = dir
		"floater":
			var phase: float = fmod(float(track["phase"]) + (1.0 / 60.0) / float(track["leg"]), 2.0)
			track["phase"] = phase
			var along: float = phase if phase < 1.0 else 2.0 - phase
			var from: Vector2 = track["from"]
			track["pos"] = from.lerp(track["to"], 0.5 - 0.5 * cos(PI * along))


func _track_shape(track: Dictionary) -> Dictionary:
	var offset: Vector2 = track["offset"]
	match String(track["type"]):
		"patroller":
			offset.x = float(track["base_x"]) * _patroller_sign(track["dir"], track["faces_right"])
		"floater":
			offset.x = float(track["base_x"]) * _floater_sign(track)
	var centre: Vector2 = Vector2(track["pos"]) + offset
	if track.has("size"):
		var size: Vector2 = track["size"]
		return {"rect": Rect2(centre - size / 2.0, size)}
	return {"centre": centre, "radius": track["radius"]}


func _shape_hits(shape: Dictionary, body: Rect2) -> bool:
	if shape.has("rect"):
		return (shape["rect"] as Rect2).intersects(body)
	var centre: Vector2 = shape["centre"]
	var nearest: Vector2 = Vector2(clampf(centre.x, body.position.x, body.end.x), clampf(centre.y, body.position.y, body.end.y))
	return nearest.distance_to(centre) < float(shape["radius"])


func _patroller_sign(dir: float, faces_right: bool) -> float:
	return 1.0 if (dir > 0.0) == faces_right else -1.0


func _floater_sign(track: Dictionary) -> float:
	var dx: float = Vector2(track["to"]).x - Vector2(track["from"]).x
	if float(track["phase"]) >= 1.0:
		dx = -dx
	if dx == 0.0:
		return 1.0
	return 1.0 if (dx > 0.0) == bool(track["faces_right"]) else -1.0


## Records every floater's centre once per frame.
func _sample_floaters() -> void:
	for hazard: Hazard in _room.get_objects().get_hazards():
		var floater: Floater = hazard as Floater
		if floater == null:
			continue
		var id: int = floater.get_instance_id()
		var seen: Array = _floater_seen.get(id, [-1, Vector2.ZERO, -1, Vector2.ZERO])
		if int(seen[0]) != _frame:
			_floater_seen[id] = [_frame, floater.global_position, seen[0], seen[1]]


## True when every floater was also seen on the frame before this one.
func _floaters_ready() -> bool:
	for id: int in _floater_seen.keys():
		var seen: Array = _floater_seen[id]
		if int(seen[0]) != _frame or int(seen[2]) != _frame - 1:
			return false
	return true


## The floater's phase (0..2) from where it is and which way it moved.
func _floater_phase(floater: Floater) -> float:
	var from: Vector2 = floater.get_from()
	var to: Vector2 = floater.get_to()
	var leg: Vector2 = to - from
	var pos: Vector2 = floater.global_position
	var s: float = clampf((pos - from).dot(leg) / leg.length_squared(), 0.0, 1.0)
	var along: float = acos(clampf(1.0 - 2.0 * s, -1.0, 1.0)) / PI
	var seen: Array = _floater_seen.get(floater.get_instance_id(), [])
	var moving_out: bool = s < 0.5
	if seen.size() == 4 and int(seen[2]) == _frame - 1:
		var moved: Vector2 = pos - Vector2(seen[3])
		if moved.length() > 0.001:
			moving_out = moved.dot(leg) > 0.0
	return along if moving_out else 2.0 - along


func _build_surfaces() -> void:
	_surfaces.clear()
	var rows: PackedStringArray = _room.level_data.tile_rows
	for r: int in rows.size():
		var row: String = rows[r]
		var c: int = 0
		while c < row.length():
			var ch: String = row[c]
			var solid_top: bool = ch == "#" and (r == 0 or rows[r - 1][c] != "#")
			if ch == "=" or solid_top:
				var start: int = c
				while c < row.length() and row[c] == ch and (ch == "=" or r == 0 or rows[r - 1][c] != "#"):
					c += 1
				_surfaces.append({"y": 32.0 * r + (7.0 if ch == "=" else 0.0), "x0": 32.0 * start, "x1": 32.0 * c,
						"solid": ch == "#"})
			else:
				c += 1


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
	_respawn = _room.get_respawn()
	_completed_count = 0
	_zap_count = 0
	_respawn_count = 0
	_bounce_count = 0
	_floater_seen.clear()
	_room.level_completed.connect(func() -> void: _completed_count += 1)
	_room.zapped.connect(func() -> void: _zap_count += 1)
	_respawn.respawned.connect(func() -> void: _respawn_count += 1)
	_patrollers.clear()
	_floaters.clear()
	_statics.clear()
	for hazard: Hazard in _room.get_objects().get_hazards():
		if hazard is Patroller:
			_patrollers.append(hazard as Patroller)
		elif hazard is Floater:
			_floaters.append(hazard as Floater)
		elif hazard is StaticHazard:
			_statics.append(hazard as StaticHazard)
	_pads = _room.get_objects().get_pads()
	for pad: BouncePad in _pads:
		pad.bounced.connect(func(_body: Node2D, _surface_y: float, _speed: float) -> void: _bounce_count += 1)
	_build_surfaces()
	return _check_objects()


## Presses restart and binds the reloaded room.
func _restart() -> bool:
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
	if current_scene == null or not _bind_room(current_scene) or _room == old_room:
		_check(false, "restart reloads the room")
		return false
	await _wait_physics(SETTLE_FRAMES)
	var any_filled: bool = false
	for socket: CircuitSocket in _room.get_board().get_sockets():
		any_filled = any_filled or socket.is_filled()
	_check(_player.position.distance_to(SPAWN) <= POSITION_TOLERANCE and not any_filled,
			"restart puts Ohmie at the spawn with empty slots")
	return true


## Every part's home is a spot the part may lie on (on screen, supported,
## clear of the other parts, pads, hazards, slots, board parts and the door),
## so a zap sends a carried part exactly home.
func _check_homes() -> void:
	var rects: Array[Rect2] = []
	for node: Node in get_nodes_in_group(PartBlocker.GROUP):
		var blocker: PartBlocker = node as PartBlocker
		if blocker != null:
			rects.append(blocker.get_global_rect())
	var bad: Array[String] = []
	for pickup: PartPickup in _room.get_parts():
		var others: Array[Vector2] = []
		for other: PartPickup in _room.get_parts():
			if other != pickup:
				others.append(other.home_position)
		var placement: PartPlacement = PartPlacement.new(_player.get_world_2d().direct_space_state, others, rects)
		if placement.valid_spot_at(pickup.home_position) == PartPlacement.NO_SPOT:
			bad.append(pickup.part_id)
	_check(bad.is_empty(), "every part's home is a valid resting spot, so a zap returns it exactly (bad: %s)" % str(bad))


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


## Pulls the part out of slot `slot_id`; checks Ohmie now carries `out_id`.
func _pull(slot_id: String, out_id: String) -> void:
	await _interact()
	_check(not _socket(slot_id).is_filled() and _carry.get_carried() == _part(out_id),
			"pulls %s out of %s" % [out_id, slot_id])


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
