extends SceneTree
## Scripted headless test of bounce pads, enemies and hazards on
## res://levels/dev_hazards.json ("Hazard Lab").
##
## Behaviour is driven through the input map. Ohmie is teleported only to set
## up a contact (into the spikes during the grace period, next to the jelly,
## onto the spark orb's platform). Checks:
## - a normal jump still peaks about 126 px; a bounce peaks 215..235 px above
##   the pad's cushion with jump held, released during the rise, not touched,
##   tapped during the rise, and while carrying a part;
## - walking through the pad at floor level does not bounce;
## - the high platform is out of reach of a normal jump and reached by a bounce;
## - the jelly stays within left..right, reverses at both ends and faces its
##   direction of travel;
## - walking into the spikes, the jelly and the spark orb each zaps exactly
##   once: `zapped` once, input ignored during the beat, back at spawn after
##   it, invulnerable for the grace period (and zapped again if still inside
##   a hazard when it ends);
## - a zap while carrying sends the part home and leaves the circuit alone;
## - the spikes and the jelly can be jumped over without contact;
## - a put-down on the pad or beside the spikes never leaves the part on
##   them, a put-down on the spikes is refused, and the part can be picked up
##   again;
## - `restart` puts every enemy back at its start.
## Prints measurements for level design (lines starting with "MEASURE").
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --fixed-fps 60 --script res://tests/play_hazards.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
const LEVEL_PATH: String = "res://levels/dev_hazards.json"
const ROOM_PATH: NodePath = ^"Room"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]
const PHYSICS_FPS: float = 60.0
const RUN_SPEED: float = 240.0
const TILE: float = 32.0
## Ohmie's collider width.
const PLAYER_WIDTH: float = 36.0

## Layout facts of dev_hazards.json.
const SPAWN: Vector2 = Vector2(96, 640)
const FLOOR_Y: float = 640.0
const HIGH_PLATFORM_Y: float = 455.0
const HIGH_PLATFORM_LEFT: float = 416.0
const LOW_PLATFORM_Y: float = 551.0
const BATTERY_HOME: Vector2 = Vector2(528, 455)
const SPIKES_X: float = 240.0
const PAD_X: float = 400.0
const JELLY_START: float = 760.0
const JELLY_LEFT: float = 640.0
const JELLY_RIGHT: float = 880.0
const ORB_FROM: Vector2 = Vector2(1008, 400)
const ORB_TO: Vector2 = Vector2(1008, 530)
const UNDER_HIGH_PLATFORM_X: float = 528.0
## Takeoff for a running jump centred on the spikes (apex about 88 px later).
const SPIKES_TAKEOFF_X: float = 152.0
## Beside the spikes, clear of their hurtbox (it ends at x = 276).
const BESIDE_SPIKES_X: float = 312.0
## Left of the jelly's range, clear of its hurtbox at the left end.
const BEFORE_JELLY_X: float = 560.0
## Past the jelly's range (its hurtbox reaches x = 902 at the right end).
const PAST_JELLY_X: float = 930.0
const ORB_PLATFORM_START: Vector2 = Vector2(950, 551)

## Height above the floor of the top of each hurtbox (from the scenes).
const HURT_TOPS: Dictionary = {"spikes": 44.0, "jelly": 45.0, "bot": 43.0, "live_wire": 42.0}
## Width of each hurtbox.
const HURT_WIDTHS: Dictionary = {"spikes": 72.0, "jelly": 40.0, "bot": 46.0, "live_wire": 52.0}
## A part's footprint (PartPlacement).
const FOOTPRINT_HALF: float = 40.0
const FOOTPRINT_HEIGHT: float = 64.0

const JUMP_APEX_MIN: float = 120.0
const JUMP_APEX_MAX: float = 130.0
const BOUNCE_APEX_MIN: float = 215.0
const BOUNCE_APEX_MAX: float = 235.0
const POSITION_TOLERANCE: float = 3.0
const SETTLE_FRAMES: int = 20
const MAX_WALK_FRAMES: int = 600
const MAX_AIR_FRAMES: int = 240
const MAX_ZAP_WAIT_FRAMES: int = 600
## Frames to hold inputs during the hit beat (shorter than the beat).
const BEAT_PROBE_FRAMES: int = 20
const RESTART_FRAMES: int = 4

var _passed: int = 0
var _failed: int = 0

var _room: Room = null
var _player: Player = null
var _carry: PlayerCarry = null
var _respawn: PlayerRespawn = null
var _pad: BouncePad = null
var _jelly: Patroller = null
var _orb: Floater = null
var _spikes: StaticHazard = null

var _zap_count: int = 0
var _bounce_count: int = 0
var _respawn_count: int = 0
var _frame: int = 0
var _zap_frame: int = 0
var _respawn_frame: int = 0
var _bounce_frame: int = 0
var _bounce_surface_y: float = 0.0

## Normal jump heights above the floor, one per frame from takeoff to landing.
var _jump_heights: Array[float] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var exit_code: int = await _run_checks()
	_release_all()
	print("")
	print("play_hazards: %d passed, %d failed" % [_passed, _failed])
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
	_check_start_positions()
	await _wait_physics(SETTLE_FRAMES)

	_check_start_state()
	await _check_normal_jump()
	await _check_spikes_zap()
	await _check_jump_over_spikes()
	await _check_high_platform_out_of_jump_reach()
	await _check_bounces()
	await _check_bounce_to_high_platform()
	await _check_bounce_while_carrying()
	await _check_put_down_on_pad()
	await _check_put_down_beside_spikes()
	await _check_zap_while_carrying()
	await _check_jump_over_jelly()
	await _check_floater_zap()
	await _check_patrol()
	await _check_restart()
	Room.level_override = ""
	return 0 if _failed == 0 else 1


# --- checks --------------------------------------------------------------------------

## Right after the room is built (enemies have moved for at most two frames).
func _check_start_positions() -> void:
	print("-- objects")
	_check(_pad.position == Vector2(PAD_X, FLOOR_Y) and _spikes.position == Vector2(SPIKES_X, FLOOR_Y)
			and absf(_jelly.position.y - FLOOR_Y) < 0.01 and absf(_jelly.position.x - JELLY_START) <= 2.5
			and _orb.position.distance_to(ORB_FROM) <= 3.0,
			"objects stand on their level positions (pad %s, spikes %s, jelly %s, orb %s)" % [_pad.position,
				_spikes.position, _jelly.position, _orb.position])


func _check_start_state() -> void:
	print("-- start")
	_check(_room.get_objects().get_pads().size() == 1 and _room.get_objects().get_hazards().size() == 3,
			"the room builds one bounce pad and three hazards")
	_check(_jelly.left == JELLY_LEFT and _jelly.right == JELLY_RIGHT and _jelly.speed == 60.0,
			"the jelly walks %d..%d at 60 px/s" % [int(JELLY_LEFT), int(JELLY_RIGHT)])
	var objects: Node2D = _room.get_objects()
	var parts: Node2D = _room.get_node(^"Parts") as Node2D
	_check(objects.get_index() > _room.get_board().get_index() and objects.get_index() < parts.get_index()
			and objects.get_index() < _player.get_index() and objects.z_index == 0,
			"objects draw after the board and before the parts and Ohmie")
	_check(_player.position.distance_to(SPAWN) <= POSITION_TOLERANCE and _player.is_on_floor(),
			"Ohmie starts on the floor at spawn (%s)" % _player.position)


func _check_normal_jump() -> void:
	print("-- normal jump")
	var apex: float = await _jump_in_place()
	_check(apex >= JUMP_APEX_MIN and apex <= JUMP_APEX_MAX,
			"a normal jump still peaks %.0f..%.0f px above the floor (measured %.1f px)" % [JUMP_APEX_MIN,
				JUMP_APEX_MAX, apex])
	print("MEASURE normal jump apex %.1f px (%.2f tiles), airtime %d frames" % [apex, apex / TILE,
			_jump_heights.size()])
	for kind: String in ["spikes", "jelly", "bot", "live_wire"]:
		var top: float = HURT_TOPS[kind]
		var frames_above: int = 0
		for height: float in _jump_heights:
			if height > top:
				frames_above += 1
		var span: float = RUN_SPEED * frames_above / PHYSICS_FPS
		var widest: float = span - PLAYER_WIDTH
		print("MEASURE running jump over %s: feet above its %.0f px hurtbox top for %d frames = %.0f px of run;"
				% [kind, top, frames_above, span]
				+ " clears a hurtbox up to %.0f px wide (this one is %.0f px: margin %.0f px in total)"
				% [widest, HURT_WIDTHS[kind], widest - float(HURT_WIDTHS[kind])])


func _check_spikes_zap() -> void:
	print("-- walking into the spikes")
	var zaps_before: int = _zap_count
	Input.action_press("move_right")
	await _wait_for_zap(zaps_before)
	_check(_zap_count == zaps_before + 1, "walking into the spikes zaps (zapped %d)" % (_zap_count - zaps_before))
	await _check_zap_beat("spikes", zaps_before)

	print("-- invulnerable after a respawn")
	_check(_respawn.is_invulnerable(), "Ohmie is invulnerable right after the respawn")
	var grace_zaps: int = _zap_count
	_player.global_position = Vector2(SPIKES_X, FLOOR_Y)  # set up a contact
	var grace_frames: int = 0
	while _respawn.is_invulnerable() and grace_frames < MAX_ZAP_WAIT_FRAMES:
		await _wait_physics(1)
		grace_frames += 1
		if _zap_count != grace_zaps:
			break
	_check(_zap_count == grace_zaps and grace_frames > 20,
			"standing in the spikes during the grace period does not zap (%d frames, zapped %d)" % [grace_frames,
				_zap_count - grace_zaps])
	await _wait_for_zap(grace_zaps)
	_check(_zap_count == grace_zaps + 1 and _frame - _respawn_frame >= 35,
			"still inside the spikes when the grace period ends: zapped again (%d frames after the respawn)"
			% (_frame - _respawn_frame))
	await _wait_for_respawn()
	await _wait_until_vulnerable()


func _check_jump_over_spikes() -> void:
	print("-- jumping over the spikes")
	var zaps_before: int = _zap_count
	await _run_and_jump(SPIKES_TAKEOFF_X)
	_check(_zap_count == zaps_before and _player.position.x > SPIKES_X + 55.0 and _player.is_on_floor(),
			"a running jump clears the spikes without contact (landed at x=%.0f, zapped %d)" % [_player.position.x,
				_zap_count - zaps_before])


func _check_high_platform_out_of_jump_reach() -> void:
	print("-- the high platform")
	var bounces_before: int = _bounce_count
	await _walk_to_x(UNDER_HIGH_PLATFORM_X)
	_check(_bounce_count == bounces_before,
			"walking through the pad at floor level does not bounce (bounced %d)" % (_bounce_count - bounces_before))
	var apex: float = await _jump_in_place()
	_check(_player.is_on_floor() and absf(_player.position.y - FLOOR_Y) <= POSITION_TOLERANCE,
			"a normal jump under the high platform (apex %.0f px) lands back on the floor (y=%.0f)" % [apex,
				_player.position.y])


func _check_bounces() -> void:
	print("-- bouncing")
	await _walk_to_x(PAD_X)
	var bounces_before: int = _bounce_count
	Input.action_press("jump")
	await _wait_for_bounce(bounces_before)
	_check(_bounce_count == bounces_before + 1 and absf(_bounce_surface_y - _pad.get_surface_y()) < 0.01,
			"jumping onto the pad bounces (bounced %d)" % (_bounce_count - bounces_before))

	var held: Dictionary = await _measure_bounce(Callable())
	_check_apex(held, "with jump held")
	var released: Dictionary = await _measure_bounce(func(frame: int) -> void:
		if frame == 6:
			Input.action_release("jump"))
	_check_apex(released, "with jump released while rising (no cut)")
	var untouched: Dictionary = await _measure_bounce(Callable())
	_check_apex(untouched, "with no input (standing on the pad keeps bouncing)")
	var tapped: Dictionary = await _measure_bounce(func(frame: int) -> void:
		if frame == 4:
			Input.action_press("jump")
		elif frame == 6:
			Input.action_release("jump"))
	_check_apex(tapped, "with jump tapped while rising (no extra jump)")
	_check(not _player.is_bouncing() or _player.velocity.y < 0.0, "the bounce flag clears once falling")

	var heights: Array[float] = untouched["heights"]
	var frames: int = heights.size()
	var apex: float = untouched["apex"]
	print("MEASURE bounce apex %.1f px above the cushion (%.2f tiles); the cushion is %.0f px above the floor,"
			% [apex, apex / TILE, _pad.surface_height]
			+ " so the apex is %.1f px (%.2f tiles) above the floor" % [apex + _pad.surface_height,
				(apex + _pad.surface_height) / TILE])
	print("MEASURE bounce airtime back to cushion height %d frames = %.0f px of horizontal run at 240 px/s"
			% [frames, RUN_SPEED * frames / PHYSICS_FPS])
	for platform_above_floor: float in [FLOOR_Y - HIGH_PLATFORM_Y, 6.0 * TILE + _pad.surface_height]:
		var above_cushion: float = platform_above_floor - _pad.surface_height
		var land_frame: int = _descending_frame(heights, above_cushion)
		print("MEASURE bounce to a platform surface %.0f px above the floor (%.0f px above the cushion):"
				% [platform_above_floor, above_cushion]
				+ " up to %.0f px of horizontal run before landing on it (%d frames)" % [
					RUN_SPEED * land_frame / PHYSICS_FPS, land_frame])


func _check_bounce_to_high_platform() -> void:
	print("-- bouncing up to the high platform")
	var bounces_before: int = _bounce_count
	await _wait_for_bounce(bounces_before)
	Input.action_press("move_right")
	await _wait_physics(24)
	Input.action_release("move_right")
	await _wait_until_on_floor()
	_check(_player.is_on_floor() and absf(_player.position.y - HIGH_PLATFORM_Y) <= POSITION_TOLERANCE,
			"a bounce with move_right reaches the high platform (position %s)" % _player.position)


func _check_bounce_while_carrying() -> void:
	print("-- bouncing while carrying")
	await _walk_to_x(BATTERY_HOME.x)
	await _interact()
	_check(_carry.get_carried() == _part(), "picks up the battery on the high platform")
	# Walk off the platform's left end, then let go so Ohmie drops onto the pad.
	var bounces_before: int = _bounce_count
	Input.action_press("move_left")
	for i: int in MAX_WALK_FRAMES:
		await _wait_physics(1)
		if not _player.is_on_floor():
			break
	Input.action_release("move_left")
	await _wait_for_bounce(bounces_before)
	_check(_bounce_count == bounces_before + 1, "dropping off the platform onto the pad bounces")
	var carrying: Dictionary = await _measure_bounce(Callable())
	_check_apex(carrying, "while carrying a part")
	_check(_carry.is_carrying(), "still carrying after bouncing")
	# Step off the pad sideways.
	await _wait_for_bounce(_bounce_count)
	Input.action_press("move_left")
	await _wait_physics(12)
	Input.action_release("move_left")
	await _wait_until_on_floor()
	_check(absf(_player.position.y - FLOOR_Y) <= POSITION_TOLERANCE and absf(_player.position.x - PAD_X) > _pad.catch_half_width,
			"drifting sideways leaves the pad and lands on the floor (position %s)" % _player.position)


func _check_put_down_on_pad() -> void:
	print("-- putting a part down on the pad")
	var bounces_before: int = _bounce_count
	await _walk_to_x(PAD_X)
	_check(_bounce_count == bounces_before, "standing in the pad at floor level does not bounce")
	await _interact()
	var part: PartPickup = _part()
	_check(not _carry.is_carrying() and part.is_loose(), "the put-down at the pad lays the part down (slid)")
	_check(not _on_blocker(part.global_position) and absf(part.global_position.y - FLOOR_Y) < 0.01,
			"the part does not overlap the pad or the spikes (at %s)" % part.global_position)
	await _walk_to_x(part.global_position.x)
	await _interact()
	_check(_carry.get_carried() == part, "the part can be picked up again")


func _check_put_down_beside_spikes() -> void:
	print("-- putting a part down beside the spikes")
	await _walk_to_x(BESIDE_SPIKES_X)
	var zaps_before: int = _zap_count
	await _interact()
	var part: PartPickup = _part()
	_check(_zap_count == zaps_before and not _carry.is_carrying() and part.is_loose(),
			"the put-down beside the spikes lays the part down")
	_check(not _on_blocker(part.global_position),
			"the part slid clear of the spikes (at %s)" % part.global_position)
	await _walk_to_x(part.global_position.x)
	await _interact()
	_check(_carry.get_carried() == part, "the part can be picked up again")
	var no_parts: Array[Vector2] = []
	var placement: PartPlacement = PartPlacement.new(_player.get_world_2d().direct_space_state, no_parts,
			_blocker_rects())
	_check(placement.find_put_down(Vector2(SPIKES_X, FLOOR_Y), _carry.put_down_max_slide) == PartPlacement.NO_SPOT,
			"a put-down on the middle of the spikes is refused")
	var on_pad: Vector2 = placement.find_put_down(Vector2(PAD_X, FLOOR_Y), _carry.put_down_max_slide)
	_check(on_pad != PartPlacement.NO_SPOT and not _on_blocker(on_pad),
			"a put-down on the middle of the pad slides clear of it (to %s)" % on_pad)


func _check_zap_while_carrying() -> void:
	print("-- zapped by the jelly while carrying")
	var socket: CircuitSocket = _room.get_board().get_sockets()[0]
	var reading_before: String = _room.get_hud().get_reading_text(0)
	_player.global_position = Vector2(BEFORE_JELLY_X, FLOOR_Y)  # set up a contact
	await _wait_physics(2)
	var zaps_before: int = _zap_count
	Input.action_press("move_right")
	await _wait_for_zap(zaps_before)
	_check(_zap_count == zaps_before + 1, "walking into the jelly zaps (zapped %d)" % (_zap_count - zaps_before))
	await _check_zap_beat("jelly", zaps_before)
	var part: PartPickup = _part()
	_check(not _carry.is_carrying() and part.is_loose() and part.global_position.distance_to(BATTERY_HOME) < 0.01,
			"the carried part is back at its home (%s)" % part.global_position)
	_check(not socket.is_filled() and _room.get_hud().get_reading_text(0) == reading_before,
			"the circuit is unchanged (slot empty, reading '%s')" % _room.get_hud().get_reading_text(0))
	await _wait_until_vulnerable()


func _check_jump_over_jelly() -> void:
	print("-- jumping over the jelly")
	await _run_and_jump(SPIKES_TAKEOFF_X)
	await _walk_to_x(BEFORE_JELLY_X)
	var zaps_before: int = _zap_count
	# Take off when the jelly, walking left, will be under Ohmie at his apex.
	var apex_frames: int = _apex_frame()
	for i: int in MAX_ZAP_WAIT_FRAMES:
		var meet_x: float = _player.position.x + RUN_SPEED * apex_frames / PHYSICS_FPS
		var jelly_then: float = _jelly.position.x - _jelly.speed * apex_frames / PHYSICS_FPS
		if _jelly.get_direction() < 0.0 and jelly_then >= JELLY_LEFT and absf(jelly_then - meet_x) <= 4.0:
			break
		await _wait_physics(1)
	Input.action_press("move_right")
	Input.action_press("jump")
	await _wait_until_landed()
	Input.action_release("jump")
	await _walk_to_x(PAST_JELLY_X)
	_check(_zap_count == zaps_before and _player.position.x >= PAST_JELLY_X - POSITION_TOLERANCE,
			"a running jump over the jelly and a run past it make no contact (zapped %d, x=%.0f)" % [
				_zap_count - zaps_before, _player.position.x])


func _check_floater_zap() -> void:
	print("-- walking into the spark orb")
	_player.global_position = ORB_PLATFORM_START  # set up a contact
	await _wait_physics(2)
	_check(_player.is_on_floor() and absf(_player.position.y - LOW_PLATFORM_Y) <= POSITION_TOLERANCE,
			"Ohmie stands on the orb's platform")
	var zaps_before: int = _zap_count
	# Walk towards the orb's path and stand there until it comes down.
	Input.action_press("move_right")
	for i: int in MAX_WALK_FRAMES:
		if _zap_count > zaps_before or _player.position.x >= ORB_FROM.x:
			break
		await _wait_physics(1)
	Input.action_release("move_right")
	await _wait_for_zap(zaps_before)
	_check(_zap_count == zaps_before + 1, "the spark orb zaps Ohmie on its platform (zapped %d)" % (_zap_count - zaps_before))
	await _check_zap_beat("spark orb", zaps_before)
	await _wait_until_vulnerable()


func _check_patrol() -> void:
	print("-- the jelly's patrol")
	var min_x: float = INF
	var max_x: float = -INF
	var last_direction: float = _jelly.get_direction()
	var reversals: Array[float] = []
	var reversal_frames: Array[int] = []
	var facing_ok: bool = true
	var frames: int = int(2.0 * 2.0 * (JELLY_RIGHT - JELLY_LEFT) / _jelly.speed * PHYSICS_FPS) + 30
	var last_x: float = _jelly.position.x
	for i: int in frames:
		await _wait_physics(1)
		var x: float = _jelly.position.x
		min_x = minf(min_x, x)
		max_x = maxf(max_x, x)
		if _jelly.get_direction() != last_direction:
			reversals.append(x)
			reversal_frames.append(i)
			last_direction = _jelly.get_direction()
		elif x != last_x and (x > last_x) != _jelly.is_facing_right():
			facing_ok = false
		last_x = x
	_check(min_x >= JELLY_LEFT - 0.01 and max_x <= JELLY_RIGHT + 0.01,
			"the jelly stays within %d..%d (saw %.1f..%.1f)" % [int(JELLY_LEFT), int(JELLY_RIGHT), min_x, max_x])
	var at_left: bool = false
	var at_right: bool = false
	for x: float in reversals:
		at_left = at_left or absf(x - JELLY_LEFT) < 0.01
		at_right = at_right or absf(x - JELLY_RIGHT) < 0.01
	_check(at_left and at_right and reversals.size() >= 3,
			"the jelly reverses at both ends (%d reversals at %s)" % [reversals.size(), str(reversals)])
	_check(facing_ok, "the jelly always faces its direction of travel")
	if reversal_frames.size() >= 2:
		var pass_frames: int = reversal_frames[1] - reversal_frames[0]
		print("MEASURE a patroller at 60 px/s takes %d frames (%.2f s) per pass over %.0f px; so %.2f s over 240 px"
				% [pass_frames, pass_frames / PHYSICS_FPS, JELLY_RIGHT - JELLY_LEFT,
					pass_frames / PHYSICS_FPS * 240.0 / (JELLY_RIGHT - JELLY_LEFT)])


func _check_restart() -> void:
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
		return
	var elapsed: float = (RESTART_FRAMES + 2) / PHYSICS_FPS
	_check(absf(_jelly.position.x - JELLY_START) <= _jelly.speed * elapsed + 0.5 and _jelly.get_direction() > 0.0,
			"after restart the jelly is back at its start, walking right (x=%.1f)" % _jelly.position.x)
	_check(_orb.position.distance_to(ORB_FROM) <= _orb.speed * elapsed + 0.5,
			"after restart the spark orb is back at its start (%s)" % _orb.position)
	_check(_part().global_position == BATTERY_HOME and _player.position.distance_to(SPAWN) <= 40.0,
			"after restart the part and Ohmie are back at their starts")


# --- zap helpers --------------------------------------------------------------------

## After a zap has just been counted: holds inputs during the beat (nothing
## moves, no second zap), then checks the respawn at the spawn and the grace.
func _check_zap_beat(what: String, zaps_before: int) -> void:
	var frozen_at: Vector2 = _player.position
	Input.action_press("move_right")
	Input.action_press("jump")
	await _wait_physics(BEAT_PROBE_FRAMES)
	_check(_player.position == frozen_at and _player.is_frozen() and _respawn.is_zapping(),
			"%s: input is ignored during the hit beat (still at %s)" % [what, _player.position])
	_release_all()
	await _wait_for_respawn()
	var beat_frames: int = _respawn_frame - _zap_frame
	_check(_zap_count == zaps_before + 1, "%s: zapped exactly once (zapped %d)" % [what, _zap_count - zaps_before])
	_check(beat_frames >= 25 and beat_frames <= 30,
			"%s: the beat lasts about 0.45 s (%d frames)" % [what, beat_frames])
	_check(_player.position.distance_to(SPAWN) <= POSITION_TOLERANCE and not _player.is_frozen(),
			"%s: back at spawn after the beat (%s)" % [what, _player.position])
	_check(_respawn.is_invulnerable(), "%s: invulnerable after the respawn" % what)


func _wait_for_zap(zaps_before: int) -> void:
	for i: int in MAX_ZAP_WAIT_FRAMES:
		if _zap_count > zaps_before:
			break
		await _wait_physics(1)


func _wait_for_respawn() -> void:
	var before: int = _respawn_count
	for i: int in MAX_ZAP_WAIT_FRAMES:
		if _respawn_count > before:
			break
		await _wait_physics(1)


func _wait_until_vulnerable() -> void:
	for i: int in MAX_ZAP_WAIT_FRAMES:
		if not _respawn.is_invulnerable():
			break
		await _wait_physics(1)
	await _wait_physics(2)


# --- movement helpers ---------------------------------------------------------------

## Jumps straight up with jump held; returns the apex above the takeoff
## height and fills _jump_heights.
func _jump_in_place() -> float:
	await _wait_until_on_floor()
	var floor_y: float = _player.position.y
	_jump_heights.clear()
	Input.action_press("jump")
	var left_floor: bool = false
	for i: int in MAX_AIR_FRAMES:
		await _wait_physics(1)
		if not _player.is_on_floor():
			left_floor = true
			_jump_heights.append(floor_y - _player.position.y)
		elif left_floor:
			break
	Input.action_release("jump")
	await _wait_physics(2)
	var apex: float = 0.0
	for height: float in _jump_heights:
		apex = maxf(apex, height)
	return apex


## From a standstill, runs right and jumps with jump held once x reaches
## `takeoff_x`; lets go of everything once landed.
func _run_and_jump(takeoff_x: float) -> void:
	await _wait_until_on_floor()
	Input.action_press("move_right")
	for i: int in MAX_WALK_FRAMES:
		if _player.position.x >= takeoff_x:
			break
		await _wait_physics(1)
	Input.action_press("jump")
	await _wait_until_landed()
	_release_all()
	await _wait_physics(2)


## Waits until Ohmie leaves the floor and lands again.
func _wait_until_landed() -> void:
	var left_floor: bool = false
	for i: int in MAX_AIR_FRAMES:
		await _wait_physics(1)
		if not _player.is_on_floor():
			left_floor = true
		elif left_floor:
			break


func _wait_until_on_floor() -> void:
	for i: int in MAX_AIR_FRAMES:
		if _player.is_on_floor():
			break
		await _wait_physics(1)


func _wait_for_bounce(bounces_before: int) -> void:
	for i: int in MAX_AIR_FRAMES:
		if _bounce_count > bounces_before:
			break
		await _wait_physics(1)


## Follows one bounce from the launch that just happened until the next one:
## returns {"apex": px above the cushion, "heights": per-frame heights above
## the cushion}. `each_frame(frame)` may press or release inputs.
func _measure_bounce(each_frame: Callable) -> Dictionary:
	var start: int = _bounce_count
	var surface: float = _bounce_surface_y
	var heights: Array[float] = []
	for i: int in MAX_AIR_FRAMES:
		if each_frame.is_valid():
			each_frame.call(i)
		await _wait_physics(1)
		if _bounce_count > start:
			break
		heights.append(surface - _player.position.y)
	var apex: float = 0.0
	for height: float in heights:
		apex = maxf(apex, height)
	return {"apex": apex, "heights": heights}


func _check_apex(result: Dictionary, how: String) -> void:
	var apex: float = result["apex"]
	_check(apex >= BOUNCE_APEX_MIN and apex <= BOUNCE_APEX_MAX,
			"bounce apex %s is %.0f..%.0f px above the cushion (measured %.1f px)" % [how, BOUNCE_APEX_MIN,
				BOUNCE_APEX_MAX, apex])


## First frame index after the apex at which height <= `height`.
func _descending_frame(heights: Array[float], height: float) -> int:
	var apex_index: int = 0
	for i: int in heights.size():
		if heights[i] > heights[apex_index]:
			apex_index = i
	for i: int in range(apex_index, heights.size()):
		if heights[i] <= height:
			return i + 1
	return heights.size()


## Frames from takeoff to the highest point of a normal jump.
func _apex_frame() -> int:
	var apex_index: int = 0
	for i: int in _jump_heights.size():
		if _jump_heights[i] > _jump_heights[apex_index]:
			apex_index = i
	return apex_index + 1


func _walk_to_x(x: float) -> void:
	await _wait_until_on_floor()
	var action: String = "move_right" if x > _player.position.x else "move_left"
	var going_right: bool = action == "move_right"
	Input.action_press(action)
	for i: int in MAX_WALK_FRAMES:
		await _wait_physics(1)
		if (going_right and _player.position.x >= x) or (not going_right and _player.position.x <= x):
			break
	Input.action_release(action)
	await _wait_physics(2)
	await _wait_until_on_floor()


func _interact() -> void:
	Input.action_press("interact")
	await _wait_physics(1)
	Input.action_release("interact")
	await _wait_physics(2)


# --- room helpers -------------------------------------------------------------------

func _bind_room(main: Node) -> bool:
	_room = main.get_node_or_null(ROOM_PATH) as Room
	if _room == null or _room.level_data == null or _room.get_player() == null or _room.get_carry() == null:
		_check(false, "room, level data, player and carry exist")
		_room = null
		return false
	_player = _room.get_player()
	_carry = _room.get_carry()
	_respawn = _room.get_respawn()
	_pad = null
	_jelly = null
	_orb = null
	_spikes = null
	for pad: BouncePad in _room.get_objects().get_pads():
		_pad = pad
	for hazard: Hazard in _room.get_objects().get_hazards():
		if hazard is Patroller:
			_jelly = hazard as Patroller
		elif hazard is Floater:
			_orb = hazard as Floater
		elif hazard is StaticHazard:
			_spikes = hazard as StaticHazard
	if _pad == null or _jelly == null or _orb == null or _spikes == null:
		_check(false, "the pad, the jelly, the orb and the spikes exist")
		return false
	_room.zapped.connect(func() -> void:
		_zap_count += 1
		_zap_frame = _frame)
	_respawn.respawned.connect(func() -> void:
		_respawn_count += 1
		_respawn_frame = _frame)
	_pad.bounced.connect(func(_body: Node2D, surface_y: float, _speed: float) -> void:
		_bounce_count += 1
		_bounce_frame = _frame
		_bounce_surface_y = surface_y)
	return true


func _part() -> PartPickup:
	return _room.get_parts()[0]


func _blocker_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for node: Node in get_nodes_in_group(PartBlocker.GROUP):
		var blocker: PartBlocker = node as PartBlocker
		if blocker != null:
			rects.append(blocker.get_global_rect())
	return rects


## True when a part lying at `spot` would overlap a pad or a static hazard.
func _on_blocker(spot: Vector2) -> bool:
	var footprint: Rect2 = Rect2(spot.x - FOOTPRINT_HALF, spot.y - FOOTPRINT_HEIGHT, FOOTPRINT_HALF * 2.0,
			FOOTPRINT_HEIGHT)
	for rect: Rect2 in _blocker_rects():
		if footprint.intersects(rect):
			return true
	return false


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
