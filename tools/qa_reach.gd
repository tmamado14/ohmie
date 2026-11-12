extends SceneTree
## QA reachability report for World 1 rooms 1-10 (not pass/fail).
##
## For every room, finds every standing surface from the tile rows (tops of
## solid ground at y = 32r, one-way platforms at y = 32r + 7), then puts Ohmie
## at every x (step STEP px) on each surface and records which interactable is
## the highlighted target:
##   empty hands: each loose part;
##   carrying (a part picked up first): each slot.
## Prints, per part and per slot, the surfaces and x ranges it can be used
## from, and flags:
##   UNREACHABLE  a part or slot no standing position can use;
##   OFF-SURFACE  a part or slot usable from a surface other than the one it
##                lies on / sits 44 px above (a possible platforming skip).
## Also prints each surface's rise above the surface below it.
##
## Usage:
##   godot --headless --path . --fixed-fps 60 --script res://tools/qa_reach.gd [-- --level=res://levels/w1_03.json]

const MAIN_SCENE: String = "res://scenes/main.tscn"
const ROOMS: PackedStringArray = [
	"res://levels/w1_01.json", "res://levels/w1_02.json", "res://levels/w1_03.json",
	"res://levels/w1_04.json", "res://levels/w1_05.json", "res://levels/w1_06.json",
	"res://levels/w1_07.json", "res://levels/w1_08.json", "res://levels/w1_09.json",
	"res://levels/w1_10.json",
]
const TILE: float = 32.0
const PLATFORM_SURFACE_OFFSET: float = 7.0
const SLOT_STAND_HEIGHT: float = 44.0
const STEP: float = 2.0
const OVERHANG: float = 18.0
const LAND_TOLERANCE: float = 3.0
const SOLID: String = "#B"

var _flags: PackedStringArray = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var rooms: PackedStringArray = ROOMS
	var only: String = Room.level_path_from_command_line()
	if not only.is_empty():
		rooms = PackedStringArray([only])
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	for path: String in rooms:
		await _report(packed, path)
	Room.level_override = ""
	print("")
	print("== Flags")
	if _flags.is_empty():
		print("  none")
	for line: String in _flags:
		print("  " + line)
	quit(0)


func _report(packed: PackedScene, path: String) -> void:
	Room.level_override = path
	var main: Node = packed.instantiate()
	root.add_child(main)
	current_scene = main
	await _wait(10)
	var room: Room = main.get_node_or_null(^"Room") as Room
	if room == null or room.level_data == null:
		print("could not load %s" % path)
		return
	var id: String = room.level_data.id
	print("")
	print("== %s \"%s\"" % [id, room.level_data.title])
	var surfaces: Array[Dictionary] = _surfaces(room.level_data.tile_rows)
	for s: Dictionary in surfaces:
		print("  surface y=%3.0f  x %4.0f..%4.0f  rise above the surface below: %s" % [
				s["y"], s["x0"], s["x1"], _rise_text(s, surfaces)])
	var player: Player = room.get_player()
	var carry: PlayerCarry = room.get_carry()

	# Empty hands: parts.
	var part_hits: Dictionary = await _sweep(player, carry, surfaces)
	# Carrying: slots. Pick up the first part by standing on it.
	var first: PartPickup = room.get_parts()[0]
	player.respawn(first.global_position)
	await _wait(3)
	Input.action_press("interact")
	await _wait(1)
	Input.action_release("interact")
	await _wait(3)
	var slot_hits: Dictionary = {}
	if carry.is_carrying():
		slot_hits = await _sweep(player, carry, surfaces)
	else:
		print("  (could not pick up %s to sweep the slots)" % first.part_id)

	for pickup: PartPickup in room.get_parts():
		_print_target(id, "part", pickup.part_id + " " + pickup.part.label(), pickup.global_position.y,
				part_hits.get(pickup.part_id, {}))
	for socket: CircuitSocket in room.get_board().get_sockets():
		_print_target(id, "slot", socket.socket_id, socket.global_position.y + SLOT_STAND_HEIGHT,
				slot_hits.get(socket.socket_id, {}))
	main.queue_free()
	current_scene = null
	await _wait(3)


## {target id: {surface y: [x, ...]}} for every standing position.
func _sweep(player: Player, carry: PlayerCarry, surfaces: Array[Dictionary]) -> Dictionary:
	var hits: Dictionary = {}
	for s: Dictionary in surfaces:
		var y: float = s["y"]
		var x: float = (s["x0"] as float) - OVERHANG
		while x <= (s["x1"] as float) + OVERHANG:
			if x >= 18.0 and x <= 1262.0:
				player.respawn(Vector2(x, y))
				await _wait(2)
				if player.is_on_floor() and absf(player.position.y - y) <= LAND_TOLERANCE:
					var target: Interactable = carry.get_target()
					var tid: String = ""
					if target is PartPickup:
						tid = (target as PartPickup).part_id
					elif target is CircuitSocket:
						tid = (target as CircuitSocket).socket_id
					if not tid.is_empty():
						if not hits.has(tid):
							hits[tid] = {}
						var by_surface: Dictionary = hits[tid]
						if not by_surface.has(y):
							by_surface[y] = []
						(by_surface[y] as Array).append(player.position.x)
			x += STEP
	return hits


func _print_target(room_id: String, kind: String, name: String, intended_y: float, by_surface: Dictionary) -> void:
	if by_surface.is_empty():
		print("  %s %-14s UNREACHABLE" % [kind, name])
		_flags.append("%s: %s %s is UNREACHABLE from any standing position" % [room_id, kind, name])
		return
	var parts: PackedStringArray = []
	for y: Variant in by_surface.keys():
		var xs: Array = by_surface[y]
		var lo: float = INF
		var hi: float = -INF
		for v: Variant in xs:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
		var mark: String = ""
		if absf(float(y) - intended_y) > LAND_TOLERANCE:
			mark = " OFF-SURFACE"
			_flags.append("%s: %s %s (meant for surface y=%.0f) is usable from surface y=%.0f, x %.0f..%.0f" % [
					room_id, kind, name, intended_y, float(y), lo, hi])
		parts.append("y=%.0f x %.0f..%.0f (%.0f px)%s" % [float(y), lo, hi, hi - lo, mark])
	print("  %s %-14s %s" % [kind, name, "; ".join(parts)])


## Standing surfaces: contiguous runs of tops in one row.
func _surfaces(rows: PackedStringArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: int in rows.size():
		var run_start: int = -1
		var run_y: float = 0.0
		for c: int in rows[r].length() + 1:
			var y: float = -1.0
			if c < rows[r].length():
				var ch: String = rows[r][c]
				var above: String = rows[r - 1][c] if r > 0 else "."
				if SOLID.contains(ch) and not SOLID.contains(above):
					y = r * TILE
				elif ch == "=":
					y = r * TILE + PLATFORM_SURFACE_OFFSET
			if run_start >= 0 and (y < 0.0 or y != run_y):
				out.append({"y": run_y, "x0": run_start * TILE, "x1": c * TILE})
				run_start = -1
			if y >= 0.0 and run_start < 0:
				run_start = c
				run_y = y
	return out


## The smallest rise from any lower surface overlapping this one in x.
func _rise_text(s: Dictionary, surfaces: Array[Dictionary]) -> String:
	var best: float = INF
	for other: Dictionary in surfaces:
		if (other["y"] as float) <= (s["y"] as float):
			continue
		var overlap: bool = (other["x0"] as float) < (s["x1"] as float) + 4 * TILE \
				and (other["x1"] as float) > (s["x0"] as float) - 4 * TILE
		if overlap:
			best = minf(best, (other["y"] as float) - (s["y"] as float))
	return "-" if best == INF else "%.0f px" % best


func _wait(frames: int) -> void:
	for i: int in frames:
		await physics_frame
