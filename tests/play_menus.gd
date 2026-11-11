extends SceneTree
## Scripted headless run through the menus, from the boot scene to a room and
## back, with progress saved to a temporary file (never the real save):
## - boot shows the splash; a key press skips to the title;
## - Play (Enter) leads to the world select; a locked world does not open;
##   World 1 opens the level select;
## - a locked room cannot be started; the first unlocked room starts and its
##   title matches the level file; Esc returns to the level select;
## - the room is completed (its slots filled with a DcPuzzleSearch solution,
##   then the door's `entered` signal, the path the door itself takes); the
##   victory line offers the next room and the map; E loads the next room;
##   Esc goes back to the level select, where the room shows as completed and
##   the next built room as unlocked; the save file has it, and reloading
##   progress from disk keeps it.
##
## Room-agnostic: it uses whichever World 1 rooms are built.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --fixed-fps 60 --script res://tests/play_menus.gd

const TEMP_SAVE: String = "user://test_play_menus_progress.json"
const MAX_WAIT_FRAMES: int = 600
## Frames to let a rejected action (locked world or room) play out.
const REJECT_FRAMES: int = 40

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_delete_save()
	GameSession.reset()
	GameSession.save_path = TEMP_SAVE
	Room.level_override = ""
	var exit_code: int = await _run_checks()
	_delete_save()
	GameSession.reset()
	print("")
	print("play_menus: %d passed, %d failed" % [_passed, _failed])
	quit(exit_code)


func _run_checks() -> int:
	var campaign: Campaign = Campaign.load_from_file(Campaign.DEFAULT_PATH)
	var world: CampaignWorld = campaign.get_world("old_workshop") if campaign != null else null
	if world == null or world.first_built_room() == null:
		_check(false, "the campaign has World 1 with a built room")
		return 1
	var first_room: CampaignRoom = world.first_built_room()
	var next_room: CampaignRoom = world.next_built_room(first_room)

	if not await _check_splash_and_title():
		return 1
	if not await _check_world_select():
		return 1
	if not await _check_level_select_start(first_room, next_room):
		return 1
	if not await _check_complete_room(first_room, next_room):
		return 1
	return 0 if _failed == 0 else 1


func _check_splash_and_title() -> bool:
	print("-- splash and title")
	_check(ProjectSettings.get_setting("application/run/main_scene", "") == ScreenFade.BOOT,
			"the main scene is the boot scene")
	_check(SplashScreen.producer() == "TUP ECE", "the producer is TUP ECE (got '%s')" % SplashScreen.producer())
	var packed: PackedScene = load(ScreenFade.BOOT) as PackedScene
	var boot: Node = packed.instantiate()
	root.add_child(boot)
	current_scene = boot
	var splash_shown: bool = await _wait_for(func() -> bool: return current_scene is SplashScreen)
	_check(splash_shown, "boot shows the splash")
	if not splash_shown:
		return false
	_check(GameSession.from_menus, "boot starts a menu session")
	await _frames(20)
	_check((current_scene as SplashScreen).get_card_index() == 0, "the splash starts on the engine card")
	await _send_key(KEY_SPACE)
	var title_shown: bool = await _wait_for(func() -> bool:
		return current_scene is TitleScreen and not ScreenFade.is_busy(self))
	_check(title_shown, "a key press skips to the title")
	if not title_shown:
		return false
	_check((current_scene as TitleScreen).get_selected_text() == "Play", "Play is selected first")
	return true


func _check_world_select() -> bool:
	print("-- world select")
	await _send_action(&"menu_accept")
	var shown: bool = await _wait_for(func() -> bool:
		return current_scene is WorldSelect and not ScreenFade.is_busy(self))
	_check(shown, "Play leads to the world select")
	if not shown:
		return false
	var worlds: WorldSelect = current_scene as WorldSelect
	_check(worlds.get_card_count() == 5, "five world cards (got %d)" % worlds.get_card_count())
	_check(worlds.get_selected_world_id() == "old_workshop", "World 1 is selected first")
	await _send_action(&"menu_right")
	await _frames(2)
	_check(worlds.get_selected_world_id() == "copper_foundry", "right arrow selects World 2")
	await _send_action(&"menu_accept")
	await _frames(REJECT_FRAMES)
	_check(current_scene == worlds and not ScreenFade.is_busy(self), "a locked world does not open")
	await _send_action(&"menu_left")
	await _frames(2)
	await _send_action(&"menu_accept")
	shown = await _wait_for(func() -> bool:
		return current_scene is LevelSelect and not ScreenFade.is_busy(self))
	_check(shown, "World 1 opens the level select")
	_check(GameSession.world_id == "old_workshop", "the session remembers World 1")
	return shown


func _check_level_select_start(first_room: CampaignRoom, next_room: CampaignRoom) -> bool:
	print("-- level select")
	var levels: LevelSelect = current_scene as LevelSelect
	_check(levels.get_selected_file() == first_room.file, "the first built room is selected first (%s)" % first_room.file)
	_check(levels.get_tile_state(first_room.file) == RoomTile.State.UNLOCKED, "the first built room is unlocked")
	_check(levels.get_tile_state("res://levels/w1_13.json") != RoomTile.State.UNLOCKED,
			"an Overtime room is not open yet")
	var data: LevelData = LevelData.load_from_file(first_room.file)
	_check(levels.get_info_title() == "%d  %s" % [first_room.number, data.title],
			"the panel shows '%d  %s' (got '%s')" % [first_room.number, data.title, levels.get_info_title()])
	_check(levels.get_info_mission() == data.mission, "the panel shows the mission '%s'" % data.mission)
	if next_room != null:
		_check(levels.get_tile_state(next_room.file) == RoomTile.State.LOCKED, "the next built room is locked")
		levels.select_room(next_room.file)
		_check(levels.get_info_title() == "%d  ???" % next_room.number, "a locked room's title shows as ???")
		await _send_action(&"menu_accept")
		await _frames(REJECT_FRAMES)
		_check(current_scene == levels, "a locked room cannot be started")
		levels.select_room(first_room.file)
	await _send_action(&"menu_accept")
	var room: Room = await _wait_for_room(first_room.file)
	_check(room != null, "the first unlocked room starts")
	if room == null:
		return false
	_check(room.level_data.title == data.title, "the room's title is '%s'" % data.title)
	_check(room.get_hud().get_hint_text().ends_with(Hud.MAP_HINT), "the control hint mentions Esc for the map")
	await _send_action(&"menu_back")
	var back: bool = await _wait_for(func() -> bool:
		return current_scene is LevelSelect and not ScreenFade.is_busy(self))
	_check(back, "Esc in a room returns to the level select")
	if back:
		_check((current_scene as LevelSelect).get_selected_file() == first_room.file,
				"the level select comes back on the room just left")
	return back


func _check_complete_room(first_room: CampaignRoom, next_room: CampaignRoom) -> bool:
	print("-- complete a room")
	await _send_action(&"menu_accept")
	var room: Room = await _wait_for_room(first_room.file)
	if room == null:
		_check(false, "the room starts again")
		return false
	await _frames(10)
	if not _plug_in_first_solution(room):
		_check(false, "the room has a solution to plug in")
		return false
	await _frames(2)
	_check(room.get_door().is_open(), "the solution opens the door")
	room.get_door().entered.emit()
	await _frames(2)
	_check(room.is_complete(), "the door completes the room")
	var expected_line: String = Hud.VICTORY_NEXT_ROOM_MAP if next_room != null else Hud.VICTORY_MAP_PLAY_AGAIN
	_check(room.get_hud().get_victory_line() == expected_line,
			"the victory line reads '%s' (got '%s')" % [expected_line, room.get_hud().get_victory_line()])
	_check(GameSession.progress().is_completed(first_room.file), "the session records the room as completed")
	var saved_text: String = FileAccess.get_file_as_string(TEMP_SAVE)
	_check(saved_text.contains(first_room.file), "the save file lists the room")

	if next_room != null:
		await _send_action(&"interact")
		var next: Room = await _wait_for_room(next_room.file)
		_check(next != null, "E loads the next built room (%s)" % next_room.file)
	await _send_action(&"menu_back")
	var back: bool = await _wait_for(func() -> bool:
		return current_scene is LevelSelect and not ScreenFade.is_busy(self))
	_check(back, "Esc returns to the level select")
	if not back:
		return false
	var levels: LevelSelect = current_scene as LevelSelect
	_check(levels.get_tile_state(first_room.file) == RoomTile.State.COMPLETED, "the room's tile shows completed")
	if next_room != null:
		_check(levels.get_tile_state(next_room.file) == RoomTile.State.UNLOCKED, "the next built room is now unlocked")
	var reloaded: Progress = ProgressStore.load_from(TEMP_SAVE)
	_check(reloaded.is_completed(first_room.file), "progress reloaded from disk keeps the completed room")
	_check(GameSession.progress().save_path == TEMP_SAVE, "the session saves to the temporary file, not the real save")
	return true


## Moves loose parts into the slots as the first DcPuzzleSearch solution says.
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


## Waits until the current scene is the game with a loaded room playing `file`.
func _wait_for_room(file: String) -> Room:
	var found: bool = await _wait_for(func() -> bool:
		if current_scene == null or ScreenFade.is_busy(self):
			return false
		var candidate: Room = current_scene.get_node_or_null(^"Room") as Room
		return candidate != null and candidate.level_data != null and candidate.level_path == file)
	return current_scene.get_node_or_null(^"Room") as Room if found else null


func _wait_for(condition: Callable) -> bool:
	for i: int in MAX_WAIT_FRAMES:
		if condition.call():
			return true
		await process_frame
	return bool(condition.call())


func _frames(count: int) -> void:
	for i: int in count:
		await process_frame


func _send_action(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func _send_key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func _delete_save() -> void:
	if FileAccess.file_exists(TEMP_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))


func _check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("PASS  " + description)
	else:
		_failed += 1
		print("FAIL  " + description)
