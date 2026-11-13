extends SceneTree
## QA screenshot set for the overtime rooms w1_11..w1_13 (not pass/fail):
## initial state, mid-route states, each enemy at its closest approach to a
## path or pickup, parts put down inside a patrol (draw order and name tags),
## a returned part stacked on another, and the solved room. Must run with a
## real renderer (not --headless):
##   godot --path . --script res://tools/qa_overtime_shots.gd [-- <output dir>]
## Default output: res://tests/screenshots/qa_overtime/
##
## Enemies are posed by setting their position and then switching their
## processing off (so they hold still for the picture); slot contents and
## carrying go through the input map with Ohmie placed by Player.respawn.

const MAIN_SCENE: String = "res://scenes/main.tscn"
const W11: String = "res://levels/w1_11.json"
const W12: String = "res://levels/w1_12.json"
const W13: String = "res://levels/w1_13.json"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]
const SETTLE_FRAMES: int = 30
const AUDIO_RELEASE_FRAMES: int = 10

var _out_dir: String = ""
var _packed: PackedScene = null
var _room: Room = null


func _initialize() -> void:
	_run()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--") and _out_dir.is_empty():
			_out_dir = arg
	if _out_dir.is_empty():
		_out_dir = "res://tests/screenshots/qa_overtime"
	if _out_dir.begins_with("res://") or _out_dir.begins_with("user://"):
		_out_dir = ProjectSettings.globalize_path(_out_dir)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_packed = load(MAIN_SCENE) as PackedScene

	# --- w1_11 ---
	await _shot("w11_a_initial", W11, func() -> void: await _physics(1))
	await _shot("w11_b_jelly_under_step_carrying", W11, func() -> void:
		await _take("r2")
		_pose_patroller(0, 500.0)
		await _teleport(Vector2(500, 551)))
	await _shot("w11_c_part_in_jelly_path", W11, func() -> void:
		_pose_patroller(0, 476.0)
		await _take("r6")
		await _teleport(Vector2(470, 640))
		await _interact()
		await _teleport(Vector2(560, 640)))
	await _shot("w11_d_bounce_apex_carrying", W11, func() -> void:
		await _take("b6")
		_pose_patroller(0, 430.0)
		await _teleport(Vector2(336, 400))
		_room.get_player().set_frozen(true))
	await _shot("w11_e_stacked_return", W11, func() -> void:
		_fill({"src": "b10"})
		await _take("r1")
		await _teleport(Vector2(424, 391))
		await _interact()
		await _teleport(Vector2(688, 640))
		await _interact()
		_room.get_respawn().zap()
		await _physics(40)
		await _teleport(Vector2(480, 391)))
	await _shot("w11_f_solved", W11, func() -> void:
		_fill({"src": "r2", "ser": "b10"})
		await _teleport(Vector2(1100, 640)))

	# --- w1_12 ---
	await _shot("w12_a_initial", W12, func() -> void: await _physics(1))
	await _shot("w12_b_jelly_left_end_climb", W12, func() -> void:
		await _take("r1")
		_pose_patroller(1, 512.0)
		_pose_patroller(2, 344.0)
		await _teleport(Vector2(280, 551)))
	await _shot("w12_c_bot_and_spikes", W12, func() -> void:
		_pose_patroller(1, 520.0)
		_pose_patroller(2, 424.0)
		await _teleport(Vector2(420, 640)))
	await _shot("w12_d_part_on_jelly_platform", W12, func() -> void:
		_pose_patroller(2, 390.0)
		_pose_patroller(1, 600.0)
		await _take("r3")
		await _teleport(Vector2(384, 455))
		await _interact()
		await _teleport(Vector2(300, 359)))
	await _shot("w12_e_returned_into_bot_patrol", W12, func() -> void:
		_pose_patroller(1, 520.0)
		await _take("r2")
		await _teleport(Vector2(240, 551))
		await _interact()
		await _take("r4")
		await _teleport(Vector2(1112, 640))
		await _interact()
		await _teleport(Vector2(240, 551))
		await _interact()
		_room.get_respawn().zap()
		await _physics(40)
		_pose_patroller(1, 650.0)
		await _teleport(Vector2(760, 640)))
	await _shot("w12_f_solved", W12, func() -> void:
		_fill({"s_top": "r1", "s_bot": "r2"})
		await _teleport(Vector2(1100, 640)))

	# --- w1_13 ---
	await _shot("w13_a_initial", W13, func() -> void: await _physics(1))
	await _shot("w13_b_orb_low_at_ledge_lip", W13, func() -> void:
		await _take("b9")
		_pose_floater(Vector2(888, 440))
		_pose_patroller(2, 840.0)
		await _teleport(Vector2(930, 455)))
	await _shot("w13_c_orb_mid_gap", W13, func() -> void:
		await _take("b9")
		_pose_floater(Vector2(888, 370))
		_pose_patroller(2, 700.0)
		await _teleport(Vector2(960, 455)))
	await _shot("w13_d_island_between_hazards", W13, func() -> void:
		await _take("b6")
		_pose_patroller(2, 680.0)
		await _teleport(Vector2(352, 551)))
	await _shot("w13_e_shelf_over_door", W13, func() -> void:
		await _teleport(Vector2(110, 391)))
	await _shot("w13_f_solved", W13, func() -> void:
		_fill({"s_top": "b9", "s_bot": "b6"})
		await _teleport(Vector2(200, 640)))

	var sfx: SfxPlayer = root.get_node_or_null(^"Sfx") as SfxPlayer
	if sfx != null:
		sfx.stop_all()
	for i: int in AUDIO_RELEASE_FRAMES:
		await process_frame
	Room.level_override = ""
	quit(0)


func _shot(file_name: String, level: String, setup: Callable) -> void:
	_release_all()
	Room.level_override = level
	if current_scene != null:
		current_scene.queue_free()
	await _physics(2)
	var main: Node = _packed.instantiate()
	root.add_child(main)
	current_scene = main
	await _physics(SETTLE_FRAMES)
	_room = main.get_node_or_null(^"Room") as Room
	if _room == null:
		push_error("qa_overtime_shots: no room for %s" % file_name)
		return
	await setup.call()
	await _physics(SETTLE_FRAMES)
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = _out_dir.path_join(file_name + ".png")
	if image.save_png(path) != OK:
		push_error("qa_overtime_shots: could not save %s" % path)
		return
	var target: Interactable = _room.get_carry().get_target()
	print("saved %s  door %s  target %s" % [path, _room.get_door().is_open(), target.name if target != null else "none"])


## Puts hazard number `index` (file order) at floor x `x` and holds it still.
func _pose_patroller(index: int, x: float) -> void:
	var hazards: Array[Hazard] = _room.get_objects().get_hazards()
	if index >= hazards.size():
		return
	var hazard: Hazard = hazards[index]
	hazard.position.x = x
	hazard.process_mode = Node.PROCESS_MODE_DISABLED


func _pose_floater(at: Vector2) -> void:
	for hazard: Hazard in _room.get_objects().get_hazards():
		if hazard is Floater:
			hazard.position = at
			hazard.process_mode = Node.PROCESS_MODE_DISABLED


func _fill(plan: Dictionary) -> void:
	for socket_id: Variant in plan:
		var pickup: PartPickup = _pickup(String(plan[socket_id]))
		for socket: CircuitSocket in _room.get_board().get_sockets():
			if socket.socket_id == String(socket_id) and pickup != null:
				pickup.take()
				socket.insert(pickup)


func _take(id: String) -> void:
	var pickup: PartPickup = _pickup(id)
	await _teleport(pickup.global_position)
	await _interact()


func _pickup(id: String) -> PartPickup:
	for pickup: PartPickup in _room.get_parts():
		if pickup.part_id == id:
			return pickup
	return null


func _teleport(at: Vector2) -> void:
	_room.get_player().respawn(at)
	await _physics(3)


func _interact() -> void:
	Input.action_press("interact")
	await _physics(2)
	Input.action_release("interact")
	await _physics(2)


func _physics(frames: int) -> void:
	for i: int in frames:
		await physics_frame


func _release_all() -> void:
	for action: String in ACTIONS:
		Input.action_release(action)
