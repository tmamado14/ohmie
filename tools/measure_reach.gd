extends SceneTree
## QA measurement tool for w1_07 ("Half and Half"): how comfortable are the
## jumps and the interaction ranges? Prints a report; exits 0 unless the room
## fails to load. Not a pass/fail test.
##
## 1. Jump apex from flat floor with jump held for 1, 3, 6, 12 frames and fully.
## 2. Each jump on the intended route (floor -> S1 platform, S1 -> left ledge,
##    S1 -> S2 platform, S2 -> right ledge) with each of those hold times, from
##    the takeoff point the playthrough test uses, plus the shortest hold that works.
## 3. The range of takeoff x for each route jump (full hold) that lands on target.
## 4. The standing x range on each surface from which each part (empty hands)
##    and each slot (carrying) is the highlighted interact target.
##
## Moves Ohmie with Player.respawn() between samples; jumps and moves use the
## input map. Usage:
##   godot --headless --path . --fixed-fps 60 --script res://tools/measure_reach.gd

const MAIN_SCENE: String = "res://scenes/main.tscn"
const LEVEL: String = "res://levels/w1_07.json"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]
const FULL_HOLD: int = -1
const HOLDS: Array[int] = [1, 3, 6, 12, FULL_HOLD]
const FLOOR_Y: float = 640.0
const OPEN_FLOOR_X: float = 1100.0
const LAND_TOLERANCE: float = 3.0
const MAX_AIR_FRAMES: int = 180

## name, takeoff (feet), direction (-1, 0, 1), landing surface y, sweep x from, sweep x to
const ROUTE: Array[Dictionary] = [
	{"name": "floor -> S1 platform (89 px, straight up)", "from": Vector2(512, 640), "dir": 0, "to_y": 551.0, "sweep": Vector2(380, 660)},
	{"name": "S1 platform -> left ledge (96 px, left)", "from": Vector2(440, 551), "dir": -1, "to_y": 455.0, "sweep": Vector2(398, 627)},
	{"name": "S1 platform -> S2 platform (96 px, right)", "from": Vector2(590, 551), "dir": 1, "to_y": 455.0, "sweep": Vector2(398, 627)},
	{"name": "S2 platform -> right ledge (96 px, right)", "from": Vector2(815, 455), "dir": 1, "to_y": 359.0, "sweep": Vector2(622, 851)},
]

## kind, id, surface y, sweep x from, sweep x to
const TARGETS: Array[Dictionary] = [
	{"kind": "pickup", "id": "r_two", "y": 640.0, "sweep": Vector2(180, 380)},
	{"kind": "pickup", "id": "r_half", "y": 455.0, "sweep": Vector2(170, 372)},
	{"kind": "pickup", "id": "r_one_floor", "y": 640.0, "sweep": Vector2(900, 1120)},
	{"kind": "pickup", "id": "r_one_ledge", "y": 359.0, "sweep": Vector2(876, 1076)},
	{"kind": "slot", "id": "s1", "y": 551.0, "sweep": Vector2(398, 627)},
	{"kind": "slot", "id": "s2", "y": 455.0, "sweep": Vector2(622, 851)},
	{"kind": "slot", "id": "s3", "y": 640.0, "sweep": Vector2(600, 880)},
]

var _room: Room = null
var _player: Player = null
var _carry: PlayerCarry = null


func _initialize() -> void:
	_run()


func _run() -> void:
	Room.level_override = LEVEL
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _wait(20)
	_room = main.get_node_or_null(^"Room") as Room
	if _room == null or _room.get_player() == null:
		push_error("measure_reach: room did not load")
		quit(1)
		return
	_player = _room.get_player()
	_carry = _room.get_carry()

	print("== 1. Apex above flat floor by jump hold time (GDD 5: about 121 px)")
	for hold: int in HOLDS:
		var result: Dictionary = await _jump(Vector2(OPEN_FLOOR_X, FLOOR_Y), 0, hold)
		print("  hold %-5s apex %6.1f px" % [_hold_name(hold), FLOOR_Y - (result["min_y"] as float)])

	print("== 2. Route jumps from the playthrough's takeoff points")
	for jump: Dictionary in ROUTE:
		var line: String = "  %-44s" % jump["name"]
		for hold: int in HOLDS:
			var ok: bool = await _route_jump_lands(jump, jump["from"], hold)
			line += "  %s:%s" % [_hold_name(hold), "ok" if ok else "FAIL"]
		var shortest: int = -1
		for hold: int in range(1, 40):
			if await _route_jump_lands(jump, jump["from"], hold):
				shortest = hold
				break
		var full: Dictionary = await _jump(jump["from"], jump["dir"], FULL_HOLD)
		var clearance: float = (jump["to_y"] as float) - (full["min_y"] as float)
		print(line)
		print("  %-44s  shortest working hold %d frames; feet peak %.1f px above the landing surface" % ["", shortest, clearance])

	print("== 3. Takeoff x window per route jump (full hold, step 2 px)")
	for jump: Dictionary in ROUTE:
		var sweep: Vector2 = jump["sweep"]
		var hits: Array[float] = []
		var x: float = sweep.x
		while x <= sweep.y:
			if await _route_jump_lands(jump, Vector2(x, (jump["from"] as Vector2).y), FULL_HOLD):
				hits.append(x)
			x += 2.0
		print("  %-44s  %s" % [jump["name"], _ranges(hits, 2.0)])

	print("== 4. Standing x range where each object is the interact target (reach 56 px)")
	await _teleport(Vector2(272, FLOOR_Y))
	for target: Dictionary in TARGETS:
		if target["kind"] == "slot" and not _carry.is_carrying():
			await _teleport(Vector2(272, FLOOR_Y))  # r_two
			await _interact()
		if target["kind"] == "pickup" and _carry.is_carrying():
			await _teleport(Vector2(OPEN_FLOOR_X, FLOOR_Y))
			await _interact()
		var sweep: Vector2 = target["sweep"]
		var hits: Array[float] = []
		for xi: int in range(int(sweep.x), int(sweep.y) + 1):
			_player.respawn(Vector2(xi, target["y"]))
			await _wait(2)
			if _player.is_on_floor() and absf(_player.position.y - (target["y"] as float)) <= LAND_TOLERANCE \
					and _target_id() == target["id"]:
				hits.append(float(xi))
		print("  %-6s %-12s on y=%3.0f  %s" % [target["kind"], target["id"], target["y"], _ranges(hits, 1.0)])
	_release_all()
	quit(0)


func _route_jump_lands(jump: Dictionary, from: Vector2, hold: int) -> bool:
	var result: Dictionary = await _jump(from, jump["dir"], hold)
	return result["landed"] and absf((result["land_y"] as float) - (jump["to_y"] as float)) <= LAND_TOLERANCE


## Teleports to `from`, jumps holding `direction` until landing and jump for
## `hold` frames (FULL_HOLD = until landing).
func _jump(from: Vector2, direction: int, hold: int) -> Dictionary:
	_release_all()
	await _teleport(from)
	var move: String = "move_left" if direction < 0 else "move_right"
	if direction != 0:
		Input.action_press(move)
	Input.action_press("jump")
	var min_y: float = _player.position.y
	var left_floor: bool = false
	var landed: bool = false
	for frame: int in MAX_AIR_FRAMES:
		await _wait(1)
		# Release exactly once: calling action_release on every frame keeps
		# is_action_just_released from ever firing, which hides variable jump.
		if hold != FULL_HOLD and frame + 1 == hold:
			Input.action_release("jump")
		min_y = minf(min_y, _player.position.y)
		if not _player.is_on_floor():
			left_floor = true
		elif left_floor:
			landed = true
			break
	_release_all()
	var land_y: float = _player.position.y
	await _wait(2)
	return {"min_y": min_y, "landed": landed, "land_y": land_y}


func _target_id() -> String:
	var target: Interactable = _carry.get_target()
	if target is PartPickup:
		return (target as PartPickup).part_id
	if target is CircuitSocket:
		return (target as CircuitSocket).socket_id
	return ""


func _ranges(xs: Array[float], step: float) -> String:
	if xs.is_empty():
		return "none"
	var parts: PackedStringArray = []
	var start: float = xs[0]
	var prev: float = xs[0]
	for i: int in range(1, xs.size() + 1):
		if i == xs.size() or xs[i] - prev > step + 0.01:
			parts.append("x %.0f..%.0f (%.0f px wide)" % [start, prev, prev - start + step])
			if i < xs.size():
				start = xs[i]
		if i < xs.size():
			prev = xs[i]
	return ", ".join(parts)


func _hold_name(hold: int) -> String:
	return "full" if hold == FULL_HOLD else "%df" % hold


func _teleport(at: Vector2) -> void:
	_player.respawn(at)
	await _wait(3)


func _interact() -> void:
	Input.action_press("interact")
	await _wait(1)
	Input.action_release("interact")
	await _wait(2)


func _wait(frames: int) -> void:
	for i: int in frames:
		await physics_frame


func _release_all() -> void:
	for action: String in ACTIONS:
		Input.action_release(action)
