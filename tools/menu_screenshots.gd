extends SceneTree
## Drives the boot scene through the menus and saves screenshots to
## res://tests/screenshots/menus/:
##   splash_engine.png, splash_producer.png, title.png, world_select.png,
##   world_select_locked.png (a locked world selected), level_select.png,
##   level_select_locked_attempt.png (a locked room chosen, mid-shake),
##   room_victory_menus.png (the room started from the menus, solved: the
##   menu victory line and the "Esc map" hint).
##
## Uses a temporary save in which the first built room of World 1 is
## completed, so the level select shows completed, unlocked, locked and
## not-built tiles. The real save is never touched.
##
## Must run with a real renderer (not --headless):
##   godot --path . --script res://tools/menu_screenshots.gd

const OUTPUT_DIR: String = "res://tests/screenshots/menus/"
const TEMP_SAVE: String = "user://menu_screenshots_progress.json"
const MAX_WAIT_SECONDS: float = 10.0
const AUDIO_RELEASE_FRAMES: int = 10


func _initialize() -> void:
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_write_progress()
	GameSession.reset()
	GameSession.save_path = TEMP_SAVE
	Room.level_override = ""
	var ok: bool = await _capture_all()
	_delete_save()
	GameSession.reset()
	await _stop_audio()
	quit(0 if ok else 1)


func _capture_all() -> bool:
	var boot: Node = (load(ScreenFade.BOOT) as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	if not await _wait_for(func() -> bool: return current_scene is SplashScreen):
		return _fail("the splash never appeared")
	var splash: SplashScreen = current_scene as SplashScreen
	# Card 0 is fully faded in 0.5 s after it starts; capture in the middle of its hold.
	await _seconds(1.2)
	await _save("splash_engine.png")
	if not await _wait_for(func() -> bool: return splash.get_card_index() == 1):
		return _fail("the producer card never appeared")
	await _seconds(1.2)
	await _save("splash_producer.png")
	_send_key(KEY_SPACE)
	if not await _wait_for(func() -> bool: return current_scene is TitleScreen and not ScreenFade.is_busy(self)):
		return _fail("the title never appeared")
	await _seconds(1.0)
	await _save("title.png")

	_send_action(&"menu_accept")
	if not await _wait_for(func() -> bool: return current_scene is WorldSelect and not ScreenFade.is_busy(self)):
		return _fail("the world select never appeared")
	await _seconds(0.4)
	await _save("world_select.png")
	var worlds: WorldSelect = current_scene as WorldSelect
	worlds.select(2)
	await _seconds(0.3)
	_send_action(&"menu_accept")
	await _seconds(0.08)
	await _save("world_select_locked.png")
	worlds.select(0)
	await _seconds(0.3)

	_send_action(&"menu_accept")
	if not await _wait_for(func() -> bool: return current_scene is LevelSelect and not ScreenFade.is_busy(self)):
		return _fail("the level select never appeared")
	await _seconds(0.4)
	await _save("level_select.png")
	var levels: LevelSelect = current_scene as LevelSelect
	var locked_file: String = ""
	var campaign: Campaign = Campaign.load_from_file(Campaign.DEFAULT_PATH)
	for room: CampaignRoom in campaign.get_world("old_workshop").rooms:
		if levels.get_tile_state(room.file) == RoomTile.State.LOCKED:
			locked_file = room.file
			break
	if not locked_file.is_empty():
		levels.select_room(locked_file)
		await _seconds(0.3)
		_send_action(&"menu_accept")
		await _seconds(0.06)
		await _save("level_select_locked_attempt.png")
		await _seconds(0.3)

	# Into the first unlocked room, solved, through the door: the menu victory line.
	var start_file: String = ""
	for room: CampaignRoom in campaign.get_world("old_workshop").rooms:
		if levels.get_tile_state(room.file) == RoomTile.State.UNLOCKED:
			start_file = room.file
			break
	if start_file.is_empty():
		return true
	levels.select_room(start_file)
	await _seconds(0.2)
	_send_action(&"menu_accept")
	if not await _wait_for(func() -> bool: return _current_room() != null and not ScreenFade.is_busy(self)):
		return _fail("the room never started")
	var room_node: Room = _current_room()
	await _seconds(0.5)
	if _plug_in_first_solution(room_node):
		await _seconds(0.3)
		room_node.get_door().entered.emit()
		await _seconds(0.6)
		await _save("room_victory_menus.png")
	return true


func _current_room() -> Room:
	return current_scene.get_node_or_null(^"Room") as Room if current_scene != null else null


## Moves loose parts into the slots as the first DcPuzzleSearch solution says (as tools/screenshot.gd does).
func _plug_in_first_solution(room: Room) -> bool:
	var circuit: LevelCircuit = room.get_circuit()
	var parts: Array[PartPickup] = room.get_parts()
	var search_parts: Array[Dictionary] = []
	for pickup: PartPickup in parts:
		search_parts.append(pickup.part.to_search_dictionary())
	var solutions: Array[Dictionary] = DcPuzzleSearch.find_solutions(circuit.build_base_network(),
			circuit.get_slot_descriptors(), search_parts, room.get_goal().conditions, 1)
	if solutions.is_empty():
		return false
	var solution: Dictionary = solutions[0]
	for socket: CircuitSocket in room.get_board().get_sockets():
		if not solution.has(socket.socket_id):
			continue
		for pickup: PartPickup in parts:
			if pickup.is_loose() and pickup.part.label() == solution[socket.socket_id]:
				pickup.take()
				socket.insert(pickup)
				break
	return true


func _write_progress() -> void:
	var campaign: Campaign = Campaign.load_from_file(Campaign.DEFAULT_PATH)
	var progress: Progress = Progress.new()
	var first: String = campaign.first_built_room() if campaign != null else ""
	progress.mark_completed(first)
	ProgressStore.save(progress, TEMP_SAVE)


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUTPUT_DIR + file_name)
	var err: Error = image.save_png(path)
	if err != OK:
		push_error("menu_screenshots: could not save %s (%s)" % [path, error_string(err)])
	else:
		print("menu_screenshots: saved %s (%dx%d)" % [path, image.get_width(), image.get_height()])


func _wait_for(condition: Callable) -> bool:
	var deadline: float = Time.get_ticks_msec() + MAX_WAIT_SECONDS * 1000.0
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return bool(condition.call())


func _seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _send_action(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)


func _send_key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)


func _fail(message: String) -> bool:
	push_error("menu_screenshots: " + message)
	return false


func _delete_save() -> void:
	if FileAccess.file_exists(TEMP_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))


func _stop_audio() -> void:
	var sfx: SfxPlayer = root.get_node_or_null(SfxPlayer.AUTOLOAD_PATH) as SfxPlayer
	if sfx != null:
		sfx.stop_all()
	for i: int in AUDIO_RELEASE_FRAMES:
		await process_frame
