extends SceneTree
## QA screenshot set for World 1 rooms 1-10: for each room the initial state,
## one mid-play state that shows something interesting, and the solved state
## (door open); plus the victory screen of room 5 and three states of the
## text-fit fixture tests/fixtures/qa_text_fit.json. Must run with a real
## renderer (not --headless):
##   godot --path . --script res://tools/qa_world_shots.gd [-- <output dir>]
## Default output: res://tests/screenshots/qa/
##
## Slot contents are set through the socket API (pickup.take + socket.insert);
## carrying goes through the input map; Ohmie is placed with Player.respawn.

const MAIN_SCENE: String = "res://scenes/main.tscn"
const FIXTURE: String = "res://tests/fixtures/qa_text_fit.json"
const ACTIONS: PackedStringArray = ["move_left", "move_right", "move_down", "jump", "interact", "restart"]
const SETTLE_FRAMES: int = 30
const AUDIO_RELEASE_FRAMES: int = 10

## file, mid (slot -> part id), mid_at (Ohmie), mid_carry (part id picked up
## first, from its home), mid_name, solved (slot -> part id), solved_at.
const ROOMS: Array[Dictionary] = [
	{"file": "res://levels/w1_01.json", "mid": {}, "mid_carry": "b6", "mid_at": Vector2(640, 640), "mid_name": "carrying_at_slot",
		"solved": {"s1": "b6"}, "solved_at": Vector2(1000, 640)},
	{"file": "res://levels/w1_02.json", "mid": {"s1": "b6", "s2": "r2"}, "mid_carry": "", "mid_at": Vector2(424, 640), "mid_name": "wrong_resistor_3A",
		"solved": {"s1": "b6", "s2": "r3"}, "solved_at": Vector2(1000, 640)},
	{"file": "res://levels/w1_03.json", "mid": {"s1": "b9", "s2": "b3"}, "mid_carry": "", "mid_at": Vector2(752, 640), "mid_name": "two_batteries_short",
		"solved": {"s1": "b3", "s2": "r1"}, "solved_at": Vector2(300, 640)},
	{"file": "res://levels/w1_04.json", "mid": {"s1": "r3", "s2": "r1"}, "mid_carry": "", "mid_at": Vector2(688, 551), "mid_name": "decoys_4_ohm",
		"solved": {"s1": "r2", "s2": "r4"}, "solved_at": Vector2(1000, 640)},
	{"file": "res://levels/w1_05.json", "mid": {"s_top": "r3", "s_bot": "r2"}, "mid_carry": "", "mid_at": Vector2(752, 640), "mid_name": "swapped_branches",
		"solved": {"s_top": "r2", "s_bot": "r3"}, "solved_at": Vector2(300, 640)},
	{"file": "res://levels/w1_06.json", "mid": {"s1": "r4"}, "mid_carry": "", "mid_at": Vector2(752, 640), "mid_name": "one_slot_6V_on_meter",
		"solved": {"s1": "r4", "s2": "r2"}, "solved_at": Vector2(1000, 640)},
	{"file": "res://levels/w1_07.json", "mid": {"s1": "r_two", "s2": "r_one_ledge", "s3": "r_one_floor"}, "mid_carry": "", "mid_at": Vector2(512, 551), "mid_name": "decoy_5_2_ohm",
		"solved": {"s1": "r_half", "s2": "r_one_ledge", "s3": "r_one_floor"}, "solved_at": Vector2(1000, 640)},
	{"file": "res://levels/w1_08.json", "mid": {"s1": "b9", "s2": "b6"}, "mid_carry": "", "mid_at": Vector2(432, 640), "mid_name": "15V",
		"solved": {"s1": "b6", "s2": "b3"}, "solved_at": Vector2(1000, 608)},
	{"file": "res://levels/w1_09.json", "mid": {"s2": "b12", "s1": "r2"}, "mid_carry": "", "mid_at": Vector2(752, 640), "mid_name": "blown_lamp",
		"solved": {"s2": "b9", "s1": "r4"}, "solved_at": Vector2(1000, 640)},
	{"file": "res://levels/w1_10.json", "mid": {"p_top": "b9", "p_bot": "b12"}, "mid_carry": "r1", "mid_at": Vector2(752, 640), "mid_name": "short_carrying",
		"solved": {"p_top": "r3", "p_bot": "r6", "src": "b12", "ser": "r4a"}, "solved_at": Vector2(1100, 455)},
]

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

	for i: int in ROOMS.size():
		var spec: Dictionary = ROOMS[i]
		var prefix: String = "room_%02d" % (i + 1)
		await _shot(prefix + "_a_initial", spec["file"], func() -> void: await _physics(1))
		await _shot(prefix + "_b_" + String(spec["mid_name"]), spec["file"], func() -> void:
			if not String(spec["mid_carry"]).is_empty():
				await _teleport(_pickup(spec["mid_carry"]).global_position)
				await _interact()
			_fill(spec["mid"])
			await _teleport(spec["mid_at"]))
		await _shot(prefix + "_c_solved", spec["file"], func() -> void:
			_fill(spec["solved"])
			await _teleport(spec["solved_at"]))
	await _shot("room_05_d_victory", "res://levels/w1_05.json", func() -> void:
		_fill({"s_top": "r2", "s_bot": "r3"})
		await _physics(2)
		_room.get_door().entered.emit()
		await _physics(30))
	await _shot("room_02_e_put_down_beside_slots", "res://levels/w1_02.json", func() -> void:
		# Real put-downs (interact with nothing in reach) as close to each floor
		# slot as the reach rule allows, and in front of the door.
		_fill({"s1": "b6"})
		await _teleport(_pickup("r2").global_position)
		await _interact()
		await _teleport(Vector2(364, 640))
		await _interact()
		await _teleport(_pickup("r6").global_position)
		await _interact()
		await _teleport(Vector2(1180, 640))
		await _interact()
		await _teleport(Vector2(700, 640)))
	await _shot("fixture_a_initial", FIXTURE, func() -> void: await _physics(1))
	await _shot("fixture_b_resistor", FIXTURE, func() -> void:
		_fill({"s1": "r100"})
		await _teleport(Vector2(432, 640)))
	await _shot("fixture_c_battery_carrying", FIXTURE, func() -> void:
		await _teleport(_pickup("b32").global_position)
		await _interact()
		_fill({"s1": "b12"})
		await _teleport(Vector2(432, 640)))

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
		push_error("qa_world_shots: no room for %s" % file_name)
		return
	await setup.call()
	await _physics(SETTLE_FRAMES)
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = _out_dir.path_join(file_name + ".png")
	if image.save_png(path) != OK:
		push_error("qa_world_shots: could not save %s" % path)
		return
	var readings: PackedStringArray = []
	for i: int in _room.get_goal().condition_count():
		readings.append(_room.get_hud().get_reading_text(i))
	print("saved %s  readings %s door %s" % [path, readings, _room.get_door().is_open()])


func _fill(plan: Dictionary) -> void:
	for socket_id: Variant in plan:
		var pickup: PartPickup = _pickup(String(plan[socket_id]))
		for socket: CircuitSocket in _room.get_board().get_sockets():
			if socket.socket_id == String(socket_id) and pickup != null:
				pickup.take()
				socket.insert(pickup)


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
