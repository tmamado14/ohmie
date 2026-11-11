extends SceneTree
## QA screenshot set: sets up named game states one after another and saves
## each as a PNG. Must run with a real renderer (not --headless):
##   godot --path . --script res://tools/qa_screenshots.gd -- res://tests/screenshots/qa
##
## Socket contents are set through the socket API (pickup.take + socket.insert),
## carrying and the level-complete state go through the input map, and loose
## resistors are moved with place_loose to the spots a put-down can reach
## (measured by tests/play_break.gd).

const MAIN_SCENE: String = "res://scenes/main.tscn"
const SLICE: String = "res://levels/slice_01.json"
const DEV: String = "res://levels/dev_room.json"
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
		_out_dir = "res://tests/screenshots/qa"
	if _out_dir.begins_with("res://") or _out_dir.begins_with("user://"):
		_out_dir = ProjectSettings.globalize_path(_out_dir)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_packed = load(MAIN_SCENE) as PackedScene

	await _shot("qa_01_initial", SLICE, _setup_nothing)
	await _shot("qa_02_carry_at_highlighted_socket", SLICE, _setup_carry_at_s1)
	await _shot("qa_03_one_socket_open", SLICE, _setup_one_socket)
	await _shot("qa_04_two_sockets_3_2", SLICE, _setup_two_sockets)
	await _shot("qa_05_solved_door_open", SLICE, _setup_solved)
	await _shot("qa_06_level_complete", SLICE, _setup_complete)
	await _shot("qa_07_decoy_wrong_value", SLICE, _setup_decoy)
	await _shot("qa_08_put_down_edge_cases", SLICE, _setup_edge_drops)
	await _shot("qa_09_pickup_highlight", SLICE, _setup_pickup_highlight)
	await _shot("qa_10_empty_socket_steals_target", SLICE, _setup_socket_steals)
	await _shot("qa_11_ohmie_at_floor_socket", SLICE, _setup_at_s3)
	await _shot("qa_12_dev_room_pit_lip", DEV, _setup_dev_pit_lip)

	var sfx: SfxPlayer = root.get_node_or_null(SfxPlayer.AUTOLOAD_PATH) as SfxPlayer
	if sfx != null:
		sfx.stop_all()
	for i: int in AUDIO_RELEASE_FRAMES:
		await process_frame
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
		push_error("qa_screenshots: no room for %s" % file_name)
		return
	await setup.call()
	await _physics(SETTLE_FRAMES)
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = _out_dir.path_join(file_name + ".png")
	var err: Error = image.save_png(path)
	if err != OK:
		push_error("qa_screenshots: could not save %s" % path)
		return
	print("saved %s  readout '%s' door %s complete %s carrying %s" % [path, _room.get_hud().get_equivalent_text(),
			_room.get_door().is_open(), _room.is_complete(), _room.get_carry().is_carrying()])


# --- setups --------------------------------------------------------------------------

func _setup_nothing() -> void:
	await _physics(1)


func _setup_carry_at_s1() -> void:
	await _teleport(Vector2(272, 455))
	await _interact()
	await _teleport(Vector2(512, 551))


func _setup_one_socket() -> void:
	_fill({"s1": "r_half"})
	await _teleport(Vector2(512, 551))


func _setup_two_sockets() -> void:
	_fill({"s1": "r_half", "s2": "r_one_ledge"})
	await _teleport(Vector2(736, 455))


func _setup_solved() -> void:
	_fill({"s1": "r_half", "s2": "r_one_ledge", "s3": "r_one_floor"})
	await _teleport(Vector2(1060, 640))


func _setup_complete() -> void:
	_fill({"s1": "r_half", "s2": "r_one_ledge", "s3": "r_one_floor"})
	await _teleport(Vector2(1100, 640))
	Input.action_press("move_right")
	for i: int in 120:
		await _physics(1)
		if _room.is_complete():
			break
	Input.action_release("move_right")


func _setup_decoy() -> void:
	_fill({"s1": "r_two", "s2": "r_one_ledge", "s3": "r_one_floor"})
	await _teleport(Vector2(400, 640))


func _setup_edge_drops() -> void:
	# Spots a put-down reaches: the left ledge's end, the left screen edge,
	# and the nearest allowed spot beside the 2 ohm decoy.
	_pickup("r_half").place_loose(Vector2(368, 455))
	_pickup("r_one_floor").place_loose(Vector2(18, 640))
	_pickup("r_one_ledge").place_loose(Vector2(327, 640))
	await _teleport(Vector2(560, 640))


func _setup_pickup_highlight() -> void:
	await _teleport(Vector2(300, 640))


func _setup_socket_steals() -> void:
	_pickup("r_one_floor").place_loose(Vector2(670, 640))
	await _teleport(Vector2(712, 640))


func _setup_at_s3() -> void:
	_fill({"s3": "r_one_floor"})
	await _teleport(Vector2(736, 640))


func _setup_dev_pit_lip() -> void:
	_pickup("r3").place_loose(Vector2(976, 640))
	await _teleport(Vector2(900, 640))


# --- helpers ------------------------------------------------------------------------

func _fill(plan: Dictionary) -> void:
	for socket_id: String in plan:
		var pickup: ResistorPickup = _pickup(plan[socket_id])
		for socket: CircuitSocket in _room.get_board().get_sockets():
			if socket.socket_id == socket_id:
				pickup.take()
				socket.insert(pickup)


func _pickup(id: String) -> ResistorPickup:
	for pickup: ResistorPickup in _room.get_pickups():
		if pickup.pickup_id == id:
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
