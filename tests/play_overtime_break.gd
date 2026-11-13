extends SceneTree
## Adversarial QA test for the overtime rooms w1_11 ("Watt's Up"), w1_12 ("A
## Bridge Too Far") and w1_13 ("Loop Hole"): bounce pads, enemies, hazards.
##
## Drives Ohmie through the input map. To reach a test position quickly it
## moves Ohmie with Player.respawn(at) ("teleport") to a spot where he can
## legally stand; every interaction and every move that is measured still goes
## through the actions and the real physics. Sections that only measure where
## a move lands, or which target a standing spot reaches, switch the hazards
## (and in section A the pads) off with process_mode; every hazard verdict is
## then computed from each hazard's exact motion over its whole cycle, so it
## covers every enemy phase.
##
## Sections, per room:
##   A  put-down sweep: carrying a part, interact at every standing spot of
##      every surface; each accepted put-down must be pick-up-able again from
##      its own level, and from a spot with a fair hazard window (at least
##      MIN_WINDOW_FRAMES consecutive start frames for a STAND_FRAMES stand);
##      no part ever lies on a static hazard.
##   B  return home with the home crowded: each part in turn is plugged in,
##      another part is put down on its home, the part is pulled out and Ohmie
##      is zapped; the part must come back on its home surface, clear of the
##      other loose parts (GDD 2) and pick-up-able.
##   C  standing areas: the spawn (the first second after a respawn), the
##      door and the bounce pads' columns must never meet a hazard at any
##      phase; every part home and every slot must have a standing spot no
##      hazard ever touches.
##   E  graph of safe zones (each surface minus the x ranges any hazard's
##      sweep can touch), measured with real physics: jumps (several hold
##      lengths, and jump-then-keep-running), runs, walk-offs, drop-throughs,
##      bounces with steering after the bounce, and a second move chained at
##      once when a move ends inside a hazard's sweep; every zone must be
##      reachable from every other with a fair window (widest-path
##      bottleneck). Drop-through / walk-off traps onto static hazards and the
##      bounce landings that can meet a hazard are printed as INFO.
##   T  each pad's landing map (steer left/right for h frames after a bounce),
##      and the tightest designed moves (w1_11 the bounce to the shelf, w1_12
##      up past the jelly, w1_13 across the orb's gap): how many takeoff/hold
##      combinations work and with what window.
## Known failing checks (real bugs, see the QA report): section B "came back
## clear of the other loose parts" (a returning part is stacked on the part
## that crowds its home) and "came back on its home surface".
## Then section D, edge cases with the hazards live:
##   D1 interact at a pickup on the frames around a jelly's zap (w1_11);
##   D2 interact at a slot on the same frame as a zap (w1_13);
##   D3 restart during the zap freeze (w1_13);
##   D4 interact spam through a zap and the respawn (w1_11);
##   D5 pit fall while carrying, with interact spam (w1_11);
##   D6 zapped with the door open, then the door, then a hazard after the win (w1_13);
##   D7 bounce while carrying, interact spam in the air (w1_11, w1_13).
##
## A check that exposes a real bug FAILS and stays failing until it is fixed.
## INFO lines are measurements, not pass/fail. Engine ERROR / WARNING lines are
## counted by a Logger and must stay at zero.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --fixed-fps 60 --script res://tests/play_overtime_break.gd [-- --only=w1_12]


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

	func count() -> int:
		_mutex.lock()
		var n: int = _lines.size()
		_mutex.unlock()
		return n

	func lines_since(start: int) -> PackedStringArray:
		_mutex.lock()
		var out: PackedStringArray = _lines.slice(start)
		_mutex.unlock()
		return out


const MAIN_SCENE: String = "res://scenes/main.tscn"
const ROOM_PATH: NodePath = ^"Room"
const ROOM_FILES: PackedStringArray = ["res://levels/w1_11.json", "res://levels/w1_12.json", "res://levels/w1_13.json"]
const W11: String = "res://levels/w1_11.json"
const W12: String = "res://levels/w1_12.json"
const W13: String = "res://levels/w1_13.json"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]

## The part carried in each room's put-down sweep.
const SWEEP_PART: Dictionary = {"w1_11": "r6", "w1_12": "r2", "w1_13": "b6"}

const TILE: float = 32.0
const PLATFORM_OFFSET: float = 7.0
const HALF_WIDTH: float = 18.0
const BODY_HEIGHT: float = 88.0
const SCREEN_MIN_STAND_X: float = 18.0
const SCREEN_MAX_STAND_X: float = 1262.0
const SETTLE_FRAMES: int = 20
## A fair timed move: this many consecutive start frames per enemy cycle.
const MIN_WINDOW_FRAMES: int = 30
## How long a pickup or plug-in stand lasts (arrive, press, turn round).
const STAND_FRAMES: int = 20
## Standing frames recorded before every measured move (the takeoff stand).
const PREFIX_STAND_FRAMES: int = 10
## Returned by the window functions when no hazard ever touches the path.
const FREE: int = 9999
const SWEEP_STEP: float = 8.0
const PICK_STEP: float = 4.0
const PICK_SPAN: float = 64.0
const TAKEOFF_STEP: float = 16.0
const MAX_MOVE_FRAMES: int = 240
const HOLDS: Array[int] = [6, 12, 18, 24, 999]
## Second moves chained at once after a move that ends inside a hazard's sweep.
const FOLLOW_UPS: Array[Dictionary] = [
	{"kind": "jump", "dir": -1, "hold": 999}, {"kind": "jump", "dir": 1, "hold": 999},
	{"kind": "jump", "dir": -1, "hold": 12}, {"kind": "jump", "dir": 1, "hold": 12},
	{"kind": "jump", "dir": 0, "hold": 0}, {"kind": "run", "dir": -1, "hold": 30},
	{"kind": "run", "dir": 1, "hold": 30}, {"kind": "drop", "dir": 0, "hold": 999},
]
const STEER_HOLDS: Array[int] = [8, 16, 24, 32, 48, 999]
## After a respawn Ohmie must be safe this long without input.
const RESPAWN_SAFE_FRAMES: int = 60
const FREEZE_WAIT_FRAMES: int = 40
const MAX_ZAP_WAIT_FRAMES: int = 900

var _passed: int = 0
var _failed: int = 0
var _logger: ErrorCounter = null
var _packed: PackedScene = null
var _only: String = ""

var _room: Room = null
var _player: Player = null
var _carry: PlayerCarry = null
var _respawn: PlayerRespawn = null
var _zaps: int = 0
var _respawns: int = 0
var _invalids: int = 0
var _bounces: int = 0
var _completions: int = 0
var _drops: int = 0
var _pickups: int = 0
## Physics frames since the run started, and when the last pickup and zap happened.
var _frame: int = 0
var _pick_frame: int = -1
var _zap_frame: int = -1
## Standing surfaces: {"y", "x0", "x1", "solid", "name"}.
var _surfaces: Array[Dictionary] = []
## One per hazard: {"name", "kind", "shapes": Array (one shape per frame of its cycle), "envelope": Rect2}.
var _tracks: Array[Dictionary] = []
## Safe standing zones (section E's graph nodes): {"surface", "y", "x0", "x1", "solid", "name"}.
var _zones: Array[Dictionary] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	_logger = ErrorCounter.new()
	OS.add_logger(_logger)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr("--only=".length())
	_packed = load(MAIN_SCENE) as PackedScene
	physics_frame.connect(func() -> void: _frame += 1)
	var errors_before: int = _logger.count()
	for file: String in ROOM_FILES:
		if not _only.is_empty() and not file.contains(_only):
			continue
		await _room_sections(file)
	if _only.is_empty() or _only == "D":
		await _edge_cases()
	var errors: PackedStringArray = _logger.lines_since(errors_before)
	for line: String in errors:
		print("      logged: " + line)
	_check(errors.is_empty(), "no ERROR or WARNING logged during the run (%d)" % errors.size())
	_release_all()
	Room.level_override = ""
	print("")
	print("play_overtime_break: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


# --- per-room sections -------------------------------------------------------------------

func _room_sections(file: String) -> void:
	if not await _load(file):
		return
	var id: String = _room.level_data.id
	print("")
	print("==== %s \"%s\"" % [id, _room.level_data.title])
	for s: Dictionary in _surfaces:
		print("INFO  %s surface %s" % [id, s["name"]])
	for t: Dictionary in _tracks:
		print("INFO  %s hazard %s (%s): cycle %d frames, sweeps %s" % [id, t["name"], t["kind"],
				(t["shapes"] as Array).size(), t["envelope"]])
	await _section_c_standing(id)
	await _load(file)
	await _section_a_put_down(id)
	await _section_b_return_home(file, id)
	await _load(file)
	await _section_e_graph(id)
	await _section_t_tight(file, id)


## C: standing areas against every hazard at every phase.
func _section_c_standing(id: String) -> void:
	print("-- %s C: standing areas" % id)
	_set_hazards_active(false)
	_set_pads_active(false)
	var spawn: Vector2 = _room.level_data.spawn
	var spawn_path: PackedVector2Array = _stand_path(spawn, RESPAWN_SAFE_FRAMES)
	_check(_window(spawn_path) == FREE,
			"%s: no hazard reaches a body standing at the spawn %s at any phase (window %s)"
			% [id, spawn, _window_text(_window(spawn_path))])
	var door: Vector2 = _room.get_door().global_position
	var door_bad: Array[String] = []
	var x: float = door.x - 40.0
	while x <= door.x + 40.0:
		var w: int = _window(_stand_path(Vector2(x, door.y), STAND_FRAMES))
		if w != FREE:
			door_bad.append("x=%.0f window %s" % [x, _window_text(w)])
		x += 8.0
	_check(door_bad.is_empty(), "%s: no hazard reaches the door's doorway at any phase %s" % [id, door_bad])
	for pad: BouncePad in _room.get_objects().get_pads():
		var column: PackedVector2Array = PackedVector2Array()
		var y: float = pad.global_position.y
		while y >= pad.get_surface_y() - 230.0:
			column.append(Vector2(pad.global_position.x, y))
			y -= 4.0
		var bad: Array[String] = []
		for p: Vector2 in column:
			var w: int = _window(PackedVector2Array([p]))
			if w != FREE:
				bad.append("feet %s" % p)
		_check(bad.is_empty(), "%s: no hazard reaches a straight bounce on the pad at x=%.0f at any phase %s"
				% [id, pad.global_position.x, bad.slice(0, 4)])
	# Parts: where they can be picked up from, and the hazard exposure there.
	for pickup: PartPickup in _room.get_parts():
		var spots: Array[float] = await _use_positions(pickup, pickup.global_position.y, pickup.global_position.x)
		var summary: Dictionary = _exposure(spots, pickup.global_position.y)
		print("INFO  %s part %s home %s: picked up from x %s; %s" % [id, pickup.part_id, pickup.global_position,
				_ranges_text(spots), summary["text"]])
		_check(not spots.is_empty() and int(summary["best"]) == FREE,
				"%s: part %s can be picked up from a spot no hazard ever touches (best window %s)"
				% [id, pickup.part_id, _window_text(int(summary["best"]))])
	# Slots: carrying a part.
	var first: PartPickup = _room.get_parts()[0]
	await _take(first)
	for socket: CircuitSocket in _room.get_board().get_sockets():
		var spots: Array[float] = await _use_positions(socket, socket.get_standing_y(), socket.global_position.x)
		var summary: Dictionary = _exposure(spots, socket.get_standing_y())
		print("INFO  %s slot %s: used from y=%.0f x %s; %s" % [id, socket.socket_id, socket.get_standing_y(),
				_ranges_text(spots), summary["text"]])
		_check(not spots.is_empty() and int(summary["best"]) == FREE,
				"%s: slot %s can be used (carrying) from a spot no hazard ever touches (best window %s)"
				% [id, socket.socket_id, _window_text(int(summary["best"]))])
	_set_hazards_active(true)
	_set_pads_active(true)


## A: put the carried part down at every standing spot, then pick it up again.
func _section_a_put_down(id: String) -> void:
	print("-- %s A: put-down sweep" % id)
	_set_hazards_active(false)
	_set_pads_active(false)
	var part: PartPickup = _part(String(SWEEP_PART[id]))
	if not await _take(part):
		_check(false, "%s: could take %s for the put-down sweep" % [id, part.part_id])
		return
	var tried: int = 0
	var refused: int = 0
	var spots: Dictionary = {}
	var unpickable: Array[String] = []
	var unfair: Array[String] = []
	var on_static: Array[String] = []
	var in_patrol: Array[String] = []
	var lost: Array[String] = []
	for s: Dictionary in _surfaces:
		var y: float = s["y"]
		var x: float = float(s["x0"]) - 16.0
		while x <= float(s["x1"]) + 16.0:
			var sx: float = clampf(x, SCREEN_MIN_STAND_X, SCREEN_MAX_STAND_X)
			x += SWEEP_STEP
			if not _carry.is_carrying():
				break
			if not await _stand(sx, y):
				continue
			if _carry.get_target() != null:
				continue  # interact would plug into a slot, not put down
			tried += 1
			await _interact()
			if _carry.is_carrying():
				refused += 1
				continue
			var spot: Vector2 = part.global_position
			var key: String = "%.0f,%.0f" % [spot.x, spot.y]
			var where: String = "stood x=%.0f y=%.0f -> part at (%s)" % [sx, y, key]
			if _on_static_hazard(spot):
				on_static.append(where)
			if _in_patrol(spot):
				in_patrol.append(key)
			if spots.has(key):
				# Already evaluated: pick it up again from the stored best spot.
				var best_x: float = spots[key]
				if not (await _stand(best_x, spot.y)) or _carry.get_target() != part:
					lost.append(where)
					break
				await _interact()
				continue
			var positions: Array[float] = await _use_positions(part, spot.y, spot.x)
			if positions.is_empty():
				unpickable.append(where)
				lost.append(where)
				break
			var summary: Dictionary = _exposure(positions, spot.y)
			if int(summary["best"]) < MIN_WINDOW_FRAMES:
				unfair.append("%s best window %s" % [where, _window_text(int(summary["best"]))])
			spots[key] = float(summary["best_x"])
			await _stand(float(summary["best_x"]), spot.y)
			await _interact()
			if not _carry.is_carrying():
				lost.append(where + " (pickup failed)")
				break
	print("INFO  %s: %d put-downs tried, %d refused, %d distinct resting spots; %d spots lie in an enemy's patrol: %s"
			% [id, tried, refused, spots.size(), _unique(in_patrol).size(), _unique(in_patrol)])
	_check(lost.is_empty(), "%s: the part could always be picked up again after a put-down %s" % [id, lost])
	_check(unpickable.is_empty(), "%s: every put-down spot can be picked up from its own level %s" % [id, unpickable])
	_check(unfair.is_empty(), "%s: every put-down spot has a pickup spot with a fair window (>= %d frames) %s"
			% [id, MIN_WINDOW_FRAMES, unfair])
	_check(on_static.is_empty(), "%s: no put-down lies on a static hazard %s" % [id, on_static])
	_set_hazards_active(true)
	_set_pads_active(true)


## B: the home of each part is crowded by another part when it is sent home.
func _section_b_return_home(file: String, id: String) -> void:
	print("-- %s B: return home with the home crowded" % id)
	for pickup_index: int in _room.get_parts().size():
		if not await _load(file):
			return
		_set_hazards_active(false)
		_set_pads_active(false)
		var parts: Array[PartPickup] = _room.get_parts()
		var part: PartPickup = parts[pickup_index]
		var home: Vector2 = part.home_position
		var socket: CircuitSocket = _room.get_board().get_sockets()[0]
		# Plug the part in.
		await _take(part)
		await _stand(socket.global_position.x, socket.get_standing_y())
		await _interact()
		if socket.get_pickup() != part:
			_check(false, "%s B %s: plugged into %s" % [id, part.part_id, socket.socket_id])
			continue
		# Put the nearest other part down on its home.
		var other: PartPickup = null
		for candidate: PartPickup in parts:
			if candidate != part and (other == null
					or candidate.home_position.distance_to(home) < other.home_position.distance_to(home)):
				other = candidate
		await _take(other)
		await _stand(home.x, home.y)
		await _interact()
		if _carry.is_carrying() or not _too_close(other.global_position, home):
			print("INFO  %s B %s: %s could not be put down on the home %s (refused or slid to %s); skipped"
					% [id, part.part_id, other.part_id, home, other.global_position])
			if _carry.is_carrying():
				await _stand(other.home_position.x, other.home_position.y)
				await _interact()
			continue
		# Pull the part out and get zapped.
		await _stand(socket.global_position.x, socket.get_standing_y())
		await _interact()
		if _carry.get_carried() != part:
			_check(false, "%s B %s: pulled out of %s" % [id, part.part_id, socket.socket_id])
			continue
		_respawn.zap()
		await _wait(FREEZE_WAIT_FRAMES)
		var back: Vector2 = part.global_position
		var crowded: Array[String] = []
		for p: PartPickup in _room.get_parts():
			if p != part and p.is_loose() and _too_close(p.global_position, back):
				crowded.append("%s at %s" % [p.part_id, p.global_position])
		var home_surface: Dictionary = _surface_at(home)
		var same_surface: bool = not home_surface.is_empty() and _surface_at(back) == home_surface
		var positions: Array[float] = await _use_positions(part, back.y, back.x)
		if positions.is_empty() and not crowded.is_empty():
			# Stacked on another part, which wins the tie: lift that one off first, then try.
			for p: PartPickup in _room.get_parts():
				if p != part and p.is_loose() and _too_close(p.global_position, back):
					var under: Array[float] = await _use_positions(p, back.y, back.x)
					if not under.is_empty():
						await _stand(under[under.size() / 2], back.y)
						await _interact()
						var lifted: bool = _carry.get_carried() == p
						if lifted:
							# Into a slot, so it is out of the way and not near the stack.
							var spare: CircuitSocket = _room.get_board().get_sockets()[1]
							await _stand(spare.global_position.x, spare.get_standing_y())
							await _interact()
						print("INFO  %s B %s: stacked with %s, which wins the tie there; lifted %s off first (%s)"
								% [id, part.part_id, p.part_id, p.part_id, "ok" if lifted else "could not"])
						positions = await _use_positions(part, back.y, back.x)
					break
		var summary: Dictionary = _exposure(positions, back.y)
		print("INFO  %s B %s (home %s, %s put down at %s): came back at %s; pickup %s"
				% [id, part.part_id, home, other.part_id, other.global_position, back, summary["text"]])
		_check(part.is_loose() and not _carry.is_carrying(), "%s B %s: loose again after the zap" % [id, part.part_id])
		_check(crowded.is_empty(), "%s B %s: came back clear of the other loose parts (overlaps %s at %s)"
				% [id, part.part_id, crowded, back])
		_check(same_surface, "%s B %s: came back on its home surface %s (at %s, surface %s)"
				% [id, part.part_id, home_surface.get("name", "?"), back, _surface_at(back).get("name", "none")])
		_check(not positions.is_empty() and int(summary["best"]) >= MIN_WINDOW_FRAMES,
				"%s B %s: can be picked up where it came back with a fair window (best %s)"
				% [id, part.part_id, _window_text(int(summary["best"]))])


## E: the surface graph with real physics.
func _section_e_graph(id: String) -> void:
	print("-- %s E: surface graph" % id)
	_set_hazards_active(false)
	_set_pads_active(true)
	_build_zones()
	for z: Dictionary in _zones:
		print("INFO  %s zone %s" % [id, z["name"]])
	var n: int = _zones.size()
	## best[i][j] = {"w": window, "how": text}
	var best: Array = []
	for i: int in n:
		var row: Array = []
		for j: int in n:
			row.append({"w": -1, "how": ""})
		best.append(row)
	var traps: Array[String] = []
	var bounce_lines: Array[String] = []
	var moves: int = 0
	for i: int in n:
		var z: Dictionary = _zones[i]
		var y: float = z["y"]
		var takeoffs: Array[float] = []
		var x: float = z["x0"]
		while x < float(z["x1"]):
			takeoffs.append(x)
			x += TAKEOFF_STEP
		takeoffs.append(float(z["x1"]))
		for tx: float in takeoffs:
			var specs: Array[Dictionary] = []
			for dir: int in [-1, 0, 1]:
				if dir == 0:
					specs.append({"kind": "jump", "dir": 0, "hold": 0, "after": 0})
				else:
					for h: int in HOLDS:
						specs.append({"kind": "jump", "dir": dir, "hold": h, "after": 0})
					for a: int in [20, 40]:
						specs.append({"kind": "jump", "dir": dir, "hold": 999, "after": a})
					specs.append({"kind": "walk", "dir": dir, "hold": 999, "after": 0})
					for h: int in [30, 60, 90]:
						specs.append({"kind": "run", "dir": dir, "hold": h, "after": 0})
			if not bool(z["solid"]):
				for dir: int in [-1, 0, 1]:
					specs.append({"kind": "drop", "dir": dir, "hold": 999, "after": 0})
			for spec: Dictionary in specs:
				if not await _stand(tx, y):
					break
				var r: Dictionary = await _move(spec["kind"], spec["dir"], spec["hold"], 2, 0, PREFIX_STAND_FRAMES,
						spec["after"])
				moves += 1
				var how: String = "%s dir %d hold %d%s from x=%.0f" % [spec["kind"], spec["dir"], spec["hold"],
						" then run %d" % spec["after"] if int(spec["after"]) > 0 else "", tx]
				if int(r["bounces"]) > 0:
					# Steer after the first bounce instead of whatever the move did.
					for d2: int in [-1, 0, 1]:
						var holds2: Array[int] = [0]
						if d2 != 0:
							holds2 = STEER_HOLDS
						for h2: int in holds2:
							if not await _stand(tx, y):
								break
							var rb: Dictionary = await _move(spec["kind"], spec["dir"], spec["hold"], d2, h2)
							moves += 1
							var bhow: String = "%s, then steer %d for %d after the bounce" % [how, d2, h2]
							_record_edge(best, i, rb, bhow, traps, bounce_lines)
					continue
				_record_edge(best, i, r, how, traps, bounce_lines)
				var end_pos: Vector2 = r["pos"]
				if bool(r["landed"]) and not bool(r["fell"]) and _zone_index_at(end_pos) < 0 \
						and _surface_index_at(end_pos) >= 0:
					# Landed inside a hazard's sweep: chain an immediate second move.
					var on_platform: bool = not bool(_surface_at(end_pos).get("solid", true))
					for follow: Dictionary in FOLLOW_UPS:
						if String(follow["kind"]) == "drop" and not on_platform:
							continue
						if not await _stand(tx, y):
							break
						var first: Dictionary = await _move(spec["kind"], spec["dir"], spec["hold"], 2, 0,
								PREFIX_STAND_FRAMES, spec["after"])
						if not bool(first["landed"]) or Vector2(first["pos"]).distance_to(end_pos) > 1.0:
							continue
						var second: Dictionary = await _move(follow["kind"], follow["dir"], follow["hold"], 2, 0, 0)
						moves += 2
						var both: PackedVector2Array = first["path"]
						both.append_array(second["path"])
						var chained: Dictionary = {"path": both, "landed": second["landed"], "pos": second["pos"],
								"bounces": int(first["bounces"]) + int(second["bounces"]), "fell": second["fell"]}
						_record_edge(best, i, chained, "%s, then at once %s dir %d hold %d" % [how, follow["kind"],
								follow["dir"], follow["hold"]], traps, bounce_lines)
	print("INFO  %s: %d measured moves" % [id, moves])
	# Widest path (maximise the smallest window along the way).
	var wide: Array = []
	for i: int in n:
		var row: Array[int] = []
		for j: int in n:
			row.append(FREE if i == j else int(best[i][j]["w"]))
		wide.append(row)
	for k: int in n:
		for i: int in n:
			for j: int in n:
				var via: int = mini(int(wide[i][k]), int(wide[k][j]))
				if via > int(wide[i][j]):
					wide[i][j] = via
	for i: int in n:
		var direct: PackedStringArray = []
		for j: int in n:
			if j != i and int(best[i][j]["w"]) >= 0:
				direct.append("%s %s (%s)" % [_zones[j]["name"], _window_text(int(best[i][j]["w"])), best[i][j]["how"]])
		print("INFO  %s from %s directly to: %s" % [id, _zones[i]["name"], "; ".join(direct)])
	var unreachable: Array[String] = []
	var unfair: Array[String] = []
	var tightest: int = FREE
	var tightest_pair: String = ""
	for i: int in n:
		for j: int in n:
			if i == j:
				continue
			var w: int = wide[i][j]
			if w < 0:
				unreachable.append("%s -> %s" % [_zones[i]["name"], _zones[j]["name"]])
			elif w < MIN_WINDOW_FRAMES:
				unfair.append("%s -> %s (%s)" % [_zones[i]["name"], _zones[j]["name"], _window_text(w)])
			if w >= 0 and w < tightest:
				tightest = w
				tightest_pair = "%s -> %s" % [_zones[i]["name"], _zones[j]["name"]]
	print("INFO  %s: tightest best route between two safe zones: %s, window %s" % [id, tightest_pair, _window_text(tightest)])
	var matrix: PackedStringArray = []
	for i: int in n:
		var cells: PackedStringArray = []
		for j: int in n:
			cells.append("-" if i == j else _window_text(int(wide[i][j])))
		matrix.append("%d:[%s]" % [i, ", ".join(cells)])
	print("INFO  %s widest-path windows (row = from zone index): %s" % [id, " ".join(matrix)])
	_check(unreachable.is_empty(), "%s: every safe zone can be reached from every other %s" % [id, unreachable])
	_check(unfair.is_empty(), "%s: every safe zone can be reached from every other with a fair window (>= %d frames) %s"
			% [id, MIN_WINDOW_FRAMES, unfair])
	for line: String in _unique(traps):
		print("INFO  %s trap: %s" % [id, line])
	var risky: int = 0
	for line: String in bounce_lines:
		if not line.ends_with("window free"):
			risky += 1
			print("INFO  %s bounce: %s" % [id, line])
	print("INFO  %s: %d bounce landings measured, %d of them can meet a hazard (listed above)" % [id, bounce_lines.size(), risky])
	_set_hazards_active(true)


func _record_edge(best: Array, from_index: int, r: Dictionary, how: String, traps: Array[String],
		bounce_lines: Array[String]) -> void:
	var path: PackedVector2Array = r["path"]
	var w: int = _window(path)
	if not bool(r["landed"]):
		if bool(r["fell"]):
			traps.append("%s falls out of the room" % how)
		return
	var statics: Array[String] = _static_hits(path)
	var kind: String = how.get_slice(" ", 0)
	var landing: Vector2 = r["pos"]
	if not statics.is_empty() and (kind == "drop" or kind == "walk"):
		traps.append("%s lands at %s via %s" % [how, landing.round(), statics])
	var to_index: int = _zone_index_at(landing)
	if int(r["bounces"]) > 0 and how.contains("steer"):
		bounce_lines.append("%s -> lands %s on %s, window %s%s" % [how, landing.round(),
				_zones[to_index]["name"] if to_index >= 0 else "a hazard's sweep", _window_text(w),
				" STATIC " + str(statics) if not statics.is_empty() else ""])
	if to_index < 0:
		return
	if to_index == from_index:
		return
	if w > int(best[from_index][to_index]["w"]):
		best[from_index][to_index] = {"w": w, "how": how}


## T: the tightest designed moves, input tolerance.
func _section_t_tight(file: String, id: String) -> void:
	print("-- %s T: input tolerance of the tightest moves" % id)
	await _load(file)
	_set_hazards_active(false)
	_set_pads_active(true)
	await _pad_map(id)
	match id:
		"w1_11":
			# From left of the pad: hop onto it holding right `h` frames, then steer right `s` frames after the bounce.
			var ok: Array[String] = []
			var total: int = 0
			for start_x: float in [270.0, 280.0, 290.0, 300.0]:
				for h: int in [6, 9, 12, 15, 18]:
					for steer: int in [8, 12, 16, 20, 24, 28, 32, 40]:
						if not await _stand(start_x, 640.0):
							continue
						total += 1
						var r: Dictionary = await _move("jump", 1, h, 1, steer)
						if bool(r["landed"]) and absf(Vector2(r["pos"]).y - 391.0) < 1.0:
							ok.append("x%.0f/h%d/s%d w%s" % [start_x, h, steer, _window_text(_window(r["path"]))])
			print("INFO  w1_11 bounce to the shelf: %d of %d (takeoff, hop hold, steer) combinations land on the shelf: %s"
					% [ok.size(), total, ok])
			_check(ok.size() * 4 >= total, "w1_11: at least a quarter of plausible bounce inputs reach the shelf (%d of %d)"
					% [ok.size(), total])
		"w1_12":
			# From the s_bot platform: jump right holding `h` frames, land on the jelly's platform,
			# wait `wait` frames, then jump left (held) onto the s_top platform.
			var ok: Array[String] = []
			var landed_on_jelly: int = 0
			var total: int = 0
			var best_w: int = -1
			for start_x: float in [256.0, 264.0, 272.0, 280.0, 288.0, 296.0, 304.0]:
				for h: int in [6, 8, 10, 12, 14, 16, 18, 20, 24, 30]:
					for wait: int in [0, 6, 12]:
						if not await _stand(start_x, 551.0):
							continue
						total += 1
						var r1: Dictionary = await _move("jump", 1, h, 2, 0)
						if not bool(r1["landed"]) or absf(Vector2(r1["pos"]).y - 455.0) > 1.0:
							continue
						if wait == 0:
							landed_on_jelly += 1
						var path: PackedVector2Array = r1["path"]
						for k: int in wait:
							await _wait(1)
							path.append(_player.position)
						var r2: Dictionary = await _move("jump", -1, 999, 2, 0, 0)
						path.append_array(r2["path"])
						if bool(r2["landed"]) and absf(Vector2(r2["pos"]).y - 359.0) < 1.0:
							var w: int = _window(path)
							best_w = maxi(best_w, w)
							if w >= MIN_WINDOW_FRAMES:
								ok.append("x%.0f/h%d/wait%d w%s" % [start_x, h, wait, _window_text(w)])
			print(("INFO  w1_12 up past the jelly: of %d (takeoff, hold, wait) tries, %d hold/takeoff pairs land on the jelly's"
					+ " platform; %d whole moves reach s_top with a window >= %d: %s; best window %s")
					% [total, landed_on_jelly, ok.size(), MIN_WINDOW_FRAMES, ok, _window_text(best_w)])
			_check(best_w >= MIN_WINDOW_FRAMES, "w1_12: the climb past the jelly to s_top has a fair window (best %s)"
					% _window_text(best_w))
		"w1_13":
			var ok: Array[String] = []
			var reach: int = 0
			var total: int = 0
			var best_w: int = -1
			var x: float = 912.0
			while x <= 1000.0:
				for h: int in [12, 18, 24, 30, 999]:
					if not await _stand(x, 455.0):
						continue
					total += 1
					var r: Dictionary = await _move("jump", -1, h, 2, 0)
					if bool(r["landed"]) and absf(Vector2(r["pos"]).y - 359.0) < 1.0:
						reach += 1
						var w: int = _window(r["path"])
						best_w = maxi(best_w, w)
						if w >= MIN_WINDOW_FRAMES:
							ok.append("x%.0f/h%d w%s" % [x, h, _window_text(w)])
				x += 4.0
			print(("INFO  w1_13 across the orb's gap: %d of %d (takeoff, hold) tries reach s_top's platform; %d with a window"
					+ " >= %d: %s; best window %s") % [reach, total, ok.size(), MIN_WINDOW_FRAMES, ok, _window_text(best_w)])
			_check(best_w >= MIN_WINDOW_FRAMES, "w1_13: the jump across the orb's gap has a fair window (best %s)"
					% _window_text(best_w))
	_set_hazards_active(true)


## Each pad's landing map: hop onto the pad from 46 px to its left (right held
## 12 frames), then from the first bounce steer left or right for h frames.
func _pad_map(id: String) -> void:
	for pad: BouncePad in _room.get_objects().get_pads():
		var px: float = pad.global_position.x
		if not await _stand(px - 46.0, 640.0):
			continue
		var still: Dictionary = await _move("jump", 1, 12, 0, 0)
		print("INFO  %s pad x=%.0f: no steering after the bounce -> %s" % [id, px,
				"keeps bouncing on the pad (%d bounces in %d frames)" % [still["bounces"], MAX_MOVE_FRAMES]
				if not bool(still["landed"]) else "lands %s" % Vector2(still["pos"]).round()])
		for dir: int in [-1, 1]:
			var cells: PackedStringArray = []
			for h: int in [4, 8, 12, 16, 20, 24, 28, 32, 40, 48, 56, 64, 999]:
				if not await _stand(px - 46.0, 640.0):
					continue
				var r: Dictionary = await _move("jump", 1, 12, dir, h)
				if bool(r["fell"]):
					cells.append("%d: falls out" % h)
					continue
				if not bool(r["landed"]):
					cells.append("%d: keeps bouncing" % h)
					continue
				var landing: Vector2 = r["pos"]
				var statics: Array[String] = _static_hits(r["path"])
				var zone: int = _zone_index_at(landing)
				cells.append("%d: (%.0f,%.0f) %s%s" % [h, landing.x, landing.y,
						"safe zone" if zone >= 0 else "IN A HAZARD SWEEP",
						" HITS " + ",".join(statics) if not statics.is_empty() else ""])
			print("INFO  %s pad x=%.0f steer %s for h frames: %s" % [id, px, "left" if dir < 0 else "right", "; ".join(cells)])


# --- D: edge cases with the hazards live --------------------------------------------------

func _edge_cases() -> void:
	print("")
	print("==== D: edge cases with the hazards live")
	await _d1_pickup_on_zap_frame()
	await _d2_slot_on_zap_frame()
	await _d3_restart_during_freeze()
	await _d4_spam_through_zap()
	await _d5_pit_fall_carrying()
	await _d6_door_open_zap_and_win()
	await _d7_bounce_interact(W11)
	await _d7_bounce_interact(W13)


## Sets up w1_11 with the 6 ohm lying at x 470 in the jelly's path and Ohmie
## standing over it while the jelly walks left towards him. Returns false on failure.
func _d1_setup() -> bool:
	if not await _load(W11):
		return false
	_set_hazards_active(false)
	await _take(_part("r6"))
	await _stand(470.0, 640.0)
	await _interact()
	await _stand(700.0, 640.0)
	_set_hazards_active(true)
	var jelly: Patroller = _patrollers()[0]
	for i: int in MAX_ZAP_WAIT_FRAMES:
		if jelly.get_direction() < 0.0 and jelly.position.x <= 560.0:
			break
		await _wait(1)
	await _stand(470.0, 640.0)
	return _part("r6").is_loose() and _carry.get_target() == _part("r6")


func _d1_pickup_on_zap_frame() -> void:
	print("-- D1 (w1_11): interact at a pickup on the frames around the jelly's zap")
	if not await _d1_setup():
		_check(false, "D1: setup (6 ohm in the jelly's path, Ohmie over it)")
		return
	var zap_frame: int = -1
	for i: int in MAX_ZAP_WAIT_FRAMES:
		await _wait(1)
		if _zaps > 0:
			zap_frame = i + 1
			break
	_check(zap_frame > 0, "D1: the jelly zaps Ohmie standing over the part (after %d frames)" % zap_frame)
	if zap_frame < 0:
		return
	var picked_offsets: Array[int] = []
	var missed_offsets: Array[int] = []
	for offset: int in [-4, -3, -2, -1, 0, 1, 2]:
		if not await _d1_setup():
			_check(false, "D1 offset %d: setup" % offset)
			continue
		var start: int = _frame
		_pick_frame = -1
		_zap_frame = -1
		await _wait(maxi(zap_frame + offset - 1, 0))
		Input.action_press("interact")
		await _wait(1)
		Input.action_release("interact")
		await _wait(FREEZE_WAIT_FRAMES + 2)
		var r6: PartPickup = _part("r6")
		var where: Vector2 = r6.global_position
		var picked: bool = _pick_frame >= 0
		_check(_zaps == 1 and _respawns == 1, "D1 offset %d: exactly one zap and one respawn (%d, %d)" % [offset, _zaps, _respawns])
		_check(_conserved(), "D1 offset %d: every part is in exactly one place" % offset)
		_check(not _carry.is_carrying() and r6.is_loose(), "D1 offset %d: not carrying, the 6 ohm is loose" % offset)
		if picked:
			picked_offsets.append(offset)
			_check(_pick_frame < _zap_frame and where.distance_to(r6.home_position) < 0.5,
					"D1 offset %d: picked up on frame %d, before the zap on frame %d, so it went home (at %s)"
					% [offset, _pick_frame - start, _zap_frame - start, where])
		else:
			missed_offsets.append(offset)
			_check(where.distance_to(Vector2(470, 640)) < 0.5,
					"D1 offset %d: the press came on or after the zap (frame %d) and did nothing; the part still lies at x 470 (at %s)"
					% [offset, _zap_frame - start, where])
	_check(not picked_offsets.is_empty() and not missed_offsets.is_empty() and picked_offsets.max() < missed_offsets.min(),
			"D1: presses up to a boundary pick up, later ones are ignored (picked %s, ignored %s)" % [picked_offsets, missed_offsets])


func _d2_slot_on_zap_frame() -> void:
	print("-- D2 (w1_13): interact at a slot on the same frame as a zap")
	if not await _load(W13):
		return
	_set_hazards_active(false)
	await _take(_part("b6"))
	await _stand(352.0, 551.0)
	var target_ok: bool = _carry.get_target() is CircuitSocket
	Input.action_press("interact")
	_respawn.zap()
	await _wait(1)
	Input.action_release("interact")
	await _wait(FREEZE_WAIT_FRAMES)
	var s_bot: CircuitSocket = _socket("s_bot")
	_check(target_ok and not s_bot.is_filled() and _part("b6").global_position.distance_to(_part("b6").home_position) < 0.5,
			"D2: the zap wins: s_bot stays empty and the 6 V goes home (s_bot %s, 6 V at %s)"
			% ["filled" if s_bot.is_filled() else "empty", _part("b6").global_position])
	_check(_conserved() and not _room.get_door().is_open(), "D2: parts conserved, door shut")
	_set_hazards_active(true)


func _d3_restart_during_freeze() -> void:
	print("-- D3 (w1_13): restart during the zap freeze")
	if not await _load(W13):
		return
	await _stand(760.0, 640.0)
	for i: int in MAX_ZAP_WAIT_FRAMES:
		if _zaps > 0:
			break
		await _wait(1)
	_check(_zaps == 1 and _respawn.is_zapping(), "D3: the bot zaps Ohmie on its floor")
	await _wait(8)
	var old_room: Room = _room
	var press: InputEventAction = InputEventAction.new()
	press.action = &"restart"
	press.pressed = true
	Input.parse_input_event(press)
	await _wait(2)
	var release: InputEventAction = InputEventAction.new()
	release.action = &"restart"
	release.pressed = false
	Input.parse_input_event(release)
	await _wait(4)
	if current_scene == null or not _bind(current_scene) or _room == old_room:
		_check(false, "D3: restart during the freeze reloads the room")
		return
	await _wait(RESPAWN_SAFE_FRAMES)
	_check(not _player.is_frozen() and not _respawn.is_zapping() and _zaps == 0,
			"D3: the reloaded room is not frozen and nothing zapped Ohmie")
	_check(_player.position.distance_to(_room.level_data.spawn) < 2.0, "D3: Ohmie stands at the spawn (%s)" % _player.position)
	var x0: float = _player.position.x
	Input.action_press("move_left")
	await _wait(10)
	Input.action_release("move_left")
	_check(_player.position.x < x0 - 30.0, "D3: Ohmie answers the keys after the restart (moved %.0f px)" % (x0 - _player.position.x))


func _d4_spam_through_zap() -> void:
	print("-- D4 (w1_11): interact spam through a zap and the respawn")
	if not await _load(W11):
		return
	_set_hazards_active(false)
	await _take(_part("b6"))
	var jelly: Patroller = _patrollers()[0]
	await _stand(jelly.position.x, 640.0)
	_set_hazards_active(true)
	var invalid_before: int = _invalids
	var bad: Array[String] = []
	for i: int in 150:
		if i % 2 == 0:
			Input.action_press("interact")
		else:
			Input.action_release("interact")
		await _wait(1)
		if not _conserved():
			bad.append("frame %d" % i)
	Input.action_release("interact")
	await _wait(2)
	var all_home: bool = true
	for p: PartPickup in _room.get_parts():
		all_home = all_home and p.is_loose() and p.global_position.distance_to(p.home_position) < 0.5
	_check(_zaps == 1, "D4: one zap (%d)" % _zaps)
	_check(bad.is_empty(), "D4: parts conserved on every frame of the spam %s" % [bad.slice(0, 5)])
	_check(all_home and not _carry.is_carrying(), "D4: the 6 V went home and nothing was picked up or put down by the spam")
	_check(_player.position.distance_to(_room.level_data.spawn) < 2.0, "D4: Ohmie is at the spawn")
	print("INFO  D4: %d invalid-action sounds during 75 presses" % (_invalids - invalid_before))


func _d5_pit_fall_carrying() -> void:
	print("-- D5 (w1_11): pit fall while carrying, with interact spam")
	if not await _load(W11):
		return
	_set_hazards_active(false)
	var r3: PartPickup = _part("r3")
	await _take(r3)
	await _stand(64.0, 640.0)
	_set_hazards_active(true)
	var src: CircuitSocket = _socket("src")
	Input.action_press("move_right")
	var put_down_at: Vector2 = Vector2.INF
	for i: int in 200:
		if i % 4 == 0:
			Input.action_press("interact")
		elif i % 4 == 1:
			Input.action_release("interact")
		await _wait(1)
		if not _carry.is_carrying() and put_down_at == Vector2.INF and _respawns == 0:
			put_down_at = r3.global_position
		if _respawns > 0:
			break
	_release_all()
	await _wait(3)
	if put_down_at != Vector2.INF:
		print("INFO  D5: the spam put the 3 ohm down at %s before the pit (a grounded press with nothing in reach)" % put_down_at)
	_check(_respawns == 1 and _zaps == 0, "D5: walking into the pit respawns Ohmie once, without a zap (%d, %d)" % [_respawns, _zaps])
	_check(not _carry.is_carrying() and r3.is_loose()
			and (r3.global_position.distance_to(r3.home_position) < 0.5 or put_down_at != Vector2.INF),
			"D5: the 3 ohm is home again (or where the spam put it down) (%s)" % r3.global_position)
	_check(r3.global_position.y < 700.0 and _conserved() and not src.is_filled(), "D5: no part lies in the pit; board untouched")


func _d6_door_open_zap_and_win() -> void:
	print("-- D6 (w1_13): zapped with the door open, the door, then a hazard after the win")
	if not await _load(W13):
		return
	_set_hazards_active(false)
	await _take(_part("b9"))
	await _stand(744.0, 359.0)
	await _interact()
	await _take(_part("b6"))
	await _stand(352.0, 551.0)
	await _interact()
	_check(_room.get_door().is_open(), "D6: 9 V in s_top and 6 V in s_bot open the door")
	await _stand(760.0, 640.0)
	_set_hazards_active(true)
	for i: int in MAX_ZAP_WAIT_FRAMES:
		if _respawns > 0:
			break
		await _wait(1)
	await _wait(3)
	_check(_zaps == 1 and _room.get_door().is_open() and _socket("s_top").get_pickup() == _part("b9")
			and _socket("s_bot").get_pickup() == _part("b6"), "D6: after the zap the door is still open and the slots unchanged")
	await _wait(RESPAWN_SAFE_FRAMES)
	await _stand(130.0, 640.0)
	Input.action_press("move_left")
	for i: int in 120:
		await _wait(1)
		if _room.is_complete():
			break
	Input.action_release("move_left")
	_check(_room.is_complete() and _completions == 1, "D6: walking left into the open door completes the room")
	var zaps_before: int = _zaps
	var bot: Patroller = _patrollers()[0]
	_player.respawn(Vector2(bot.position.x, 640.0))
	await _wait(RESPAWN_SAFE_FRAMES)
	_check(_zaps == zaps_before and _room.is_complete() and _completions == 1,
			"D6: after the win the bot cannot zap Ohmie (zaps %d)" % (_zaps - zaps_before))


func _d7_bounce_interact(file: String) -> void:
	if not await _load(file):
		return
	var id: String = _room.level_data.id
	print("-- D7 (%s): bounce while carrying, interact spam in the air" % id)
	var pad: BouncePad = _room.get_objects().get_pads()[0]
	_set_hazards_active(false)
	var held: PartPickup = _room.get_parts()[0]
	await _take(held)
	await _stand(pad.global_position.x - 46.0, 640.0)
	_set_hazards_active(true)
	Input.action_press("move_right")
	Input.action_press("jump")
	var bounced_at: int = -1
	var presses_in_air: int = 0
	var invalid_before: int = _invalids
	var dropped: bool = false
	var interact_down: bool = false
	for i: int in 160:
		if i == 12:
			Input.action_release("move_right")
		if interact_down:
			Input.action_release("interact")
			interact_down = false
		elif i % 3 == 0 and i > 2:
			Input.action_press("interact")
			interact_down = true
			if not _player.is_on_floor():
				presses_in_air += 1
		await _wait(1)
		if _bounces > 0 and bounced_at < 0:
			bounced_at = i
		if _carry.get_carried() != held:
			dropped = true
	_release_all()
	await _wait(2)
	_check(bounced_at >= 0 and _bounces >= 2, "D7 %s: the hop lands on the pad and Ohmie keeps bouncing (%d bounces)" % [id, _bounces])
	_check(not dropped and _carry.get_carried() == held, "D7 %s: the part stayed in Ohmie's hands through %d presses in the air"
			% [id, presses_in_air])
	_check(_invalids - invalid_before >= presses_in_air - 2,
			"D7 %s: presses in the air are refused (%d invalid of %d)" % [id, _invalids - invalid_before, presses_in_air])
	_check(_zaps == 0, "D7 %s: bouncing in place on the pad is never zapped" % id)


# --- moves and measurement ---------------------------------------------------------------

## Performs a move from where Ohmie stands, recording his feet each physics
## frame (after `prefix` standing frames) until he stands again after leaving
## the floor. `kind` "jump" (key held throughout), "walk" or "drop"; `dir`
## -1/0/1 held for `hold` frames (999: until landing). `steer_dir` 2 means no
## steering; otherwise from the first bounce the direction becomes `steer_dir`
## for `steer_hold` frames (999: until landing).
## Returns {"path", "landed", "pos", "bounces", "fell"}.
func _move(kind: String, dir: int, hold: int, steer_dir: int, steer_hold: int,
		prefix: int = PREFIX_STAND_FRAMES, after: int = 0) -> Dictionary:
	var path: PackedVector2Array = PackedVector2Array()
	for i: int in prefix:
		path.append(_player.position)
	var dir_action: String = "move_left" if dir < 0 else "move_right"
	var held: bool = dir != 0
	if held:
		Input.action_press(dir_action)
	if kind == "jump":
		Input.action_press("jump")
	elif kind == "drop":
		Input.action_press("move_down")
	var bounces_before: int = _bounces
	var respawns_before: int = _respawns
	var left_floor: bool = false
	var steering: bool = false
	var steer_action: String = "move_left" if steer_dir < 0 else "move_right"
	var steer_frames: int = 0
	var landed: bool = false
	var fell: bool = false
	## Frames left of the run after landing (-1: not started).
	var post: int = -1
	for k: int in range(1, MAX_MOVE_FRAMES + 1):
		await _wait(1)
		if _respawns != respawns_before:
			fell = true
			break
		path.append(_player.position)
		if kind == "drop" and k >= 2:
			Input.action_release("move_down")
		var on_floor: bool = _player.is_on_floor()
		if not on_floor:
			left_floor = true
		if steer_dir != 2 and not steering and _bounces > bounces_before:
			steering = true
			Input.action_release("move_left")
			Input.action_release("move_right")
			held = false
			if steer_dir != 0:
				Input.action_press(steer_action)
		if steering:
			steer_frames += 1
			if steer_hold != 999 and steer_frames >= steer_hold:
				Input.action_release("move_left")
				Input.action_release("move_right")
		elif held and hold != 999 and k >= hold:
			Input.action_release(dir_action)
			held = false
		if kind == "run":
			if on_floor and not held:
				landed = true
				break
		elif on_floor and left_floor:
			if after > 0 and post < 0:
				post = after
			if post > 0:
				post -= 1
				if post == 0:
					Input.action_release(dir_action)
					held = false
			else:
				landed = true
				break
		if not left_floor and k >= 60 and kind != "run":
			break
	_release_all()
	return {"path": path, "landed": landed, "pos": _player.position, "bounces": _bounces - bounces_before, "fell": fell}


## Feet positions for standing still at `at` for `frames` frames.
func _stand_path(at: Vector2, frames: int) -> PackedVector2Array:
	var path: PackedVector2Array = PackedVector2Array()
	for i: int in frames:
		path.append(at)
	return path


## The smallest, over the hazards that can touch `path`, of the longest run
## of consecutive start frames (per cycle) at which following `path` stays
## clear of that hazard. FREE when no hazard can ever touch it; 0 when a
## static hazard does.
func _window(path: PackedVector2Array) -> int:
	var result: int = FREE
	if path.is_empty():
		return result
	var bounds: Rect2 = _body(path[0])
	for p: Vector2 in path:
		bounds = bounds.merge(_body(p))
	for track: Dictionary in _tracks:
		if not (track["envelope"] as Rect2).intersects(bounds):
			continue
		result = mini(result, _track_window(track, path))
	return result


func _track_window(track: Dictionary, path: PackedVector2Array) -> int:
	var shapes: Array = track["shapes"]
	var n: int = shapes.size()
	var envelope: Rect2 = track["envelope"]
	var relevant: Array[int] = []
	for k: int in path.size():
		if envelope.intersects(_body(path[k])):
			relevant.append(k)
	if relevant.is_empty():
		return FREE
	var safe: Array[bool] = []
	var any_unsafe: bool = false
	for o: int in n:
		var ok: bool = true
		for k: int in relevant:
			if _hits(shapes[(o + k) % n], _body(path[k])):
				ok = false
				break
		safe.append(ok)
		any_unsafe = any_unsafe or not ok
	if not any_unsafe:
		return FREE
	var longest: int = 0
	var run: int = 0
	for o: int in 2 * n:
		if safe[o % n]:
			run += 1
			longest = maxi(longest, mini(run, n))
		else:
			run = 0
	return longest


## Names of static hazards `path` touches.
func _static_hits(path: PackedVector2Array) -> Array[String]:
	var out: Array[String] = []
	for track: Dictionary in _tracks:
		if track["kind"] != "static":
			continue
		for p: Vector2 in path:
			if _hits((track["shapes"] as Array)[0], _body(p)):
				out.append(String(track["name"]))
				break
	return out


## For standing x positions on surface y: the best (largest) stand window and
## where, plus a text summary.
func _exposure(xs: Array[float], y: float) -> Dictionary:
	var best: int = -1
	var best_x: float = NAN
	var touched: Array[String] = []
	for x: float in xs:
		var w: int = _window(_stand_path(Vector2(x, y), STAND_FRAMES))
		if w != FREE:
			touched.append("%.0f:%s" % [x, _window_text(w)])
		if w > best:
			best = w
			best_x = x
	var text: String = "no hazard ever reaches those spots" if touched.is_empty() \
			else "hazard reaches %d of %d spots (x:window %s)" % [touched.size(), xs.size(), _compress(touched)]
	return {"best": best, "best_x": best_x, "text": text}


func _body(feet: Vector2) -> Rect2:
	return Rect2(feet.x - HALF_WIDTH, feet.y - BODY_HEIGHT, HALF_WIDTH * 2.0, BODY_HEIGHT)


func _hits(shape: Dictionary, body: Rect2) -> bool:
	if shape.has("rect"):
		return (shape["rect"] as Rect2).intersects(body)
	var centre: Vector2 = shape["c"]
	var nearest: Vector2 = Vector2(clampf(centre.x, body.position.x, body.end.x), clampf(centre.y, body.position.y, body.end.y))
	return nearest.distance_to(centre) < float(shape["r"])


## True when a part lying at `spot` (its 80 x 64 footprint) overlaps a static hazard's hurtbox.
func _on_static_hazard(spot: Vector2) -> bool:
	var footprint: Rect2 = Rect2(spot.x - 40.0, spot.y - 64.0, 80.0, 64.0)
	for track: Dictionary in _tracks:
		if track["kind"] == "static" and _hits((track["shapes"] as Array)[0], footprint):
			return true
	return false


## True when a part lying at `spot` overlaps the area a patroller sweeps.
func _in_patrol(spot: Vector2) -> bool:
	var footprint: Rect2 = Rect2(spot.x - 40.0, spot.y - 64.0, 80.0, 64.0)
	for track: Dictionary in _tracks:
		if track["kind"] == "patroller" and (track["envelope"] as Rect2).intersects(footprint):
			return true
	return false


func _build_tracks() -> void:
	_tracks.clear()
	for hazard: Hazard in _room.get_objects().get_hazards():
		var hurtbox: Hurtbox = hazard.get_hurtbox()
		var collision: CollisionShape2D = hurtbox.get_child(0) as CollisionShape2D
		var shape: Shape2D = collision.shape
		var local: Vector2 = hurtbox.position + collision.position
		var shapes: Array = []
		var kind: String = "static"
		var patroller: Patroller = hazard as Patroller
		var floater: Floater = hazard as Floater
		if patroller != null:
			kind = "patroller"
			var now_sign: float = 1.0 if (patroller.get_direction() > 0.0) == patroller.art_faces_right else -1.0
			var base_x: float = hurtbox.position.x * now_sign
			var step: float = patroller.speed / 60.0
			var x: float = patroller.left
			var dir: float = 1.0
			var frames: int = roundi(2.0 * (patroller.right - patroller.left) / step)
			for k: int in frames:
				x += dir * step
				if x >= patroller.right:
					x = patroller.right
					dir = -1.0
				elif x <= patroller.left:
					x = patroller.left
					dir = 1.0
				var facing: float = 1.0 if (dir > 0.0) == patroller.art_faces_right else -1.0
				var centre: Vector2 = Vector2(x, patroller.global_position.y) + Vector2(base_x * facing, local.y)
				shapes.append(_shape_at(shape, centre))
		elif floater != null:
			kind = "floater"
			var from: Vector2 = floater.get_from()
			var to: Vector2 = floater.get_to()
			var leg: float = from.distance_to(to) / floater.speed
			var frames: int = roundi(2.0 * leg * 60.0)
			var phase: float = 0.0
			for k: int in frames:
				phase = fmod(phase + (1.0 / 60.0) / leg, 2.0)
				var along: float = phase if phase < 1.0 else 2.0 - phase
				var pos: Vector2 = from.lerp(to, 0.5 - 0.5 * cos(PI * along))
				var dx: float = to.x - from.x
				if phase >= 1.0:
					dx = -dx
				var facing: float = 1.0
				if dx != 0.0:
					facing = 1.0 if (dx > 0.0) == floater.art_faces_right else -1.0
				shapes.append(_shape_at(shape, pos + Vector2(hurtbox.position.x * facing, local.y)))
		else:
			shapes.append(_shape_at(shape, hazard.global_position + local))
		var envelope: Rect2 = _shape_rect(shapes[0])
		for s: Dictionary in shapes:
			envelope = envelope.merge(_shape_rect(s))
		_tracks.append({"name": String(hazard.name), "kind": kind, "shapes": shapes, "envelope": envelope})


func _shape_at(shape: Shape2D, centre: Vector2) -> Dictionary:
	var rect: RectangleShape2D = shape as RectangleShape2D
	if rect != null:
		return {"rect": Rect2(centre - rect.size / 2.0, rect.size)}
	var circle: CircleShape2D = shape as CircleShape2D
	return {"c": centre, "r": circle.radius if circle != null else 0.0}


func _shape_rect(shape: Dictionary) -> Rect2:
	if shape.has("rect"):
		return shape["rect"]
	var r: float = shape["r"]
	return Rect2(Vector2(shape["c"]) - Vector2(r, r), Vector2(r, r) * 2.0)


func _build_surfaces() -> void:
	_surfaces.clear()
	var rows: PackedStringArray = _room.level_data.tile_rows
	for r: int in rows.size():
		var run_start: int = -1
		var run_y: float = 0.0
		var run_solid: bool = false
		for c: int in rows[r].length() + 1:
			var y: float = -1.0
			var solid: bool = false
			if c < rows[r].length():
				var ch: String = rows[r][c]
				var above: String = rows[r - 1][c] if r > 0 else "."
				if "#B".contains(ch) and not "#B".contains(above):
					y = r * TILE
					solid = true
				elif ch == "=":
					y = r * TILE + PLATFORM_OFFSET
			if run_start >= 0 and (y < 0.0 or y != run_y or solid != run_solid):
				_surfaces.append({"y": run_y, "x0": run_start * TILE, "x1": c * TILE, "solid": run_solid,
						"name": "%s y%.0f x%d-%d" % ["floor" if run_solid else "platform", run_y, run_start * 32, c * 32]})
				run_start = -1
			if y >= 0.0 and run_start < 0:
				run_start = c
				run_y = y
				run_solid = solid


## Safe zones: each surface's standing feet range minus the x ranges where some
## hazard's sweep can touch a standing body. These are the graph's nodes.
func _build_zones() -> void:
	_zones.clear()
	for si: int in _surfaces.size():
		var s: Dictionary = _surfaces[si]
		var y: float = s["y"]
		var lo: float = maxf(float(s["x0"]) - HALF_WIDTH + 2.0, SCREEN_MIN_STAND_X)
		var hi: float = minf(float(s["x1"]) + HALF_WIDTH - 2.0, SCREEN_MAX_STAND_X)
		var segments: Array[Vector2] = [Vector2(lo, hi)]
		for cut: Vector2 in _danger_cuts(y):
			var next: Array[Vector2] = []
			for seg: Vector2 in segments:
				if cut.y <= seg.x or cut.x >= seg.y:
					next.append(seg)
					continue
				if cut.x > seg.x:
					next.append(Vector2(seg.x, cut.x))
				if cut.y < seg.y:
					next.append(Vector2(cut.y, seg.y))
			segments = next
		for seg: Vector2 in segments:
			if seg.y - seg.x < 4.0:
				continue
			_zones.append({"surface": si, "y": y, "x0": seg.x, "x1": seg.y, "solid": s["solid"],
					"name": "%s y%.0f feet x%.0f-%.0f" % ["floor" if bool(s["solid"]) else "platform", y, seg.x, seg.y]})


## Feet x intervals on a surface at `y` where some hazard's sweep can touch a standing body.
func _danger_cuts(y: float) -> Array[Vector2]:
	var cuts: Array[Vector2] = []
	for track: Dictionary in _tracks:
		var env: Rect2 = track["envelope"]
		if env.position.y < y and env.end.y > y - BODY_HEIGHT:
			cuts.append(Vector2(env.position.x - HALF_WIDTH, env.end.x + HALF_WIDTH))
	return cuts


func _zone_index_at(feet: Vector2) -> int:
	for cut: Vector2 in _danger_cuts(feet.y):
		if feet.x > cut.x and feet.x < cut.y:
			return -1
	for i: int in _zones.size():
		var z: Dictionary = _zones[i]
		if absf(float(z["y"]) - feet.y) < 1.0 and feet.x >= float(z["x0"]) - 3.0 and feet.x <= float(z["x1"]) + 3.0:
			return i
	return -1


## The surface (from _surfaces) Ohmie's feet at `feet` stand on, or {}.
func _surface_at(feet: Vector2) -> Dictionary:
	var i: int = _surface_index_at(feet)
	return _surfaces[i] if i >= 0 else {}


func _surface_index_at(feet: Vector2) -> int:
	for i: int in _surfaces.size():
		var s: Dictionary = _surfaces[i]
		if absf(float(s["y"]) - feet.y) < 1.0 and feet.x + HALF_WIDTH > float(s["x0"]) and feet.x - HALF_WIDTH < float(s["x1"]):
			return i
	return -1


# --- room helpers --------------------------------------------------------------------------

func _load(file: String) -> bool:
	_release_all()
	Room.level_override = file
	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
		await _wait(2)
	var main: Node = _packed.instantiate()
	root.add_child(main)
	current_scene = main
	await _wait(SETTLE_FRAMES)
	return _bind(main)


func _bind(main: Node) -> bool:
	_room = main.get_node_or_null(ROOM_PATH) as Room
	if _room == null or _room.level_data == null or _room.get_player() == null:
		_check(false, "room, level data and player exist")
		return false
	_player = _room.get_player()
	_carry = _room.get_carry()
	_respawn = _room.get_respawn()
	_zaps = 0
	_respawns = 0
	_invalids = 0
	_bounces = 0
	_completions = 0
	_drops = 0
	_pickups = 0
	_room.zapped.connect(func() -> void:
		_zaps += 1
		_zap_frame = _frame)
	_room.level_completed.connect(func() -> void: _completions += 1)
	_respawn.respawned.connect(func() -> void: _respawns += 1)
	_carry.invalid_action.connect(func() -> void: _invalids += 1)
	_carry.dropped.connect(func(_p: PartPickup) -> void: _drops += 1)
	_carry.picked_up.connect(func(_p: PartPickup) -> void:
		_pickups += 1
		_pick_frame = _frame)
	for pad: BouncePad in _room.get_objects().get_pads():
		pad.bounced.connect(func(_b: Node2D, _y: float, _s: float) -> void: _bounces += 1)
	_build_surfaces()
	_build_tracks()
	return true


func _set_hazards_active(active: bool) -> void:
	for hazard: Hazard in _room.get_objects().get_hazards():
		hazard.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


func _set_pads_active(active: bool) -> void:
	for pad: BouncePad in _room.get_objects().get_pads():
		pad.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


func _patrollers() -> Array[Patroller]:
	var out: Array[Patroller] = []
	for hazard: Hazard in _room.get_objects().get_hazards():
		if hazard is Patroller:
			out.append(hazard as Patroller)
	return out


## Puts Ohmie's feet at (x, y) and returns whether he stands there on a surface.
func _stand(x: float, y: float) -> bool:
	_player.respawn(Vector2(clampf(x, SCREEN_MIN_STAND_X, SCREEN_MAX_STAND_X), y))
	await _wait(2)
	return _player.is_on_floor() and absf(_player.position.y - y) <= 1.0


## Stands on `part` where it lies and picks it up. Returns whether it is carried.
func _take(part: PartPickup) -> bool:
	if _carry.get_carried() == part:
		return true
	await _stand(part.global_position.x, part.global_position.y)
	await _interact()
	return _carry.get_carried() == part


## Standing x positions on surface `y` within PICK_SPAN of `cx` from which
## `target` is the highlighted target (with the hands as they are).
func _use_positions(target: Interactable, y: float, cx: float) -> Array[float]:
	var out: Array[float] = []
	var x: float = cx - PICK_SPAN
	while x <= cx + PICK_SPAN:
		var sx: float = clampf(x, SCREEN_MIN_STAND_X, SCREEN_MAX_STAND_X)
		x += PICK_STEP
		if out.has(sx):
			continue
		if await _stand(sx, y) and _carry.get_target() == target:
			out.append(sx)
	return out


func _too_close(a: Vector2, b: Vector2) -> bool:
	return absf(a.x - b.x) < PartPlacement.MIN_SPACING and absf(a.y - b.y) < PartPlacement.FOOTPRINT_HEIGHT


## Every part is exactly one of loose, carried or plugged in, and loose <=> visible.
func _conserved() -> bool:
	for p: PartPickup in _room.get_parts():
		var states: int = 0
		if p.is_loose():
			states += 1
		if _carry.get_carried() == p:
			states += 1
		for socket: CircuitSocket in _room.get_board().get_sockets():
			if socket.get_pickup() == p:
				states += 1
		if states != 1 or p.is_loose() != p.visible:
			return false
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


func _interact() -> void:
	Input.action_press("interact")
	await _wait(1)
	Input.action_release("interact")
	await _wait(1)


func _wait(frames: int) -> void:
	for i: int in frames:
		await physics_frame


func _release_all() -> void:
	for action: String in ACTIONS:
		Input.action_release(action)


# --- text ----------------------------------------------------------------------------------

func _window_text(w: int) -> String:
	if w == FREE:
		return "free"
	if w < 0:
		return "none"
	return "%d f" % w


func _ranges_text(xs: Array[float]) -> String:
	if xs.is_empty():
		return "(none)"
	var parts: PackedStringArray = []
	var start: float = xs[0]
	var last: float = xs[0]
	for i: int in range(1, xs.size()):
		if xs[i] - last > PICK_STEP + 0.5:
			parts.append("%.0f..%.0f" % [start, last])
			start = xs[i]
		last = xs[i]
	parts.append("%.0f..%.0f" % [start, last])
	return ", ".join(parts)


func _compress(items: Array[String]) -> String:
	if items.size() <= 8:
		return str(items)
	return "%s ... %s" % [str(items.slice(0, 4)), str(items.slice(items.size() - 3))]


func _unique(items: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for item: String in items:
		if not out.has(item):
			out.append(item)
	return out


func _check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("PASS  " + description)
	else:
		_failed += 1
		print("FAIL  " + description)
