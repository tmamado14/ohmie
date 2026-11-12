extends SceneTree
## Adversarial headless run through the menus and the room flow (QA), driven
## by real input events (keys, actions and mouse) through Input.parse_input_event.
## Progress goes to a temporary save file; the real save is never touched.
##
## 1. Splash: a key at many moments (first frame, mid-fade, between the
##    cards, just before and just after the natural end), and key spam; each
##    must land on exactly one title with the fade finished.
## 2. Title: selection wraps, Esc does nothing, accept followed by accept and
##    back spam every frame ends on one settled screen.
## 3. World select: past both ends, Esc + Enter in the same frame, locked
##    worlds clicked and accepted repeatedly (the card shakes back to rest),
##    the mouse hovering while keys move the selection, World 1 opened by a click.
## 4. Level select (fresh save): past every end, locked rooms clicked and
##    accepted repeatedly, the locked and Overtime panel text.
## 5. Room: Esc during the fade-in, right after it, during a zap freeze, on
##    the frame the door is entered, during the victory screen; R on the
##    victory screen (replay), E for the next room.
## 6. Progress: rooms 1-10 completed in turn through E; after each, the
##    completed and unlocked tiles; Overtime opens only after room 10; the
##    world card's "n / 13 rooms".
## 7. A corrupt save, a save of the wrong shape and a save deleted mid-session.
## Every ERROR / WARNING the engine logs is counted.
##
## A check that exposes a real bug FAILS. INFO lines record behaviour.
##
## Usage (exit code 0 = all checks passed):
##   godot --headless --path . --fixed-fps 60 --script res://tests/play_menus_break.gd


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


const TEMP_SAVE: String = "user://qa_menus_break_progress.json"
const MAX_WAIT_FRAMES: int = 900
const WORLD_ID: String = "old_workshop"
const ROOM_FILES: PackedStringArray = [
	"res://levels/w1_01.json", "res://levels/w1_02.json", "res://levels/w1_03.json",
	"res://levels/w1_04.json", "res://levels/w1_05.json", "res://levels/w1_06.json",
	"res://levels/w1_07.json", "res://levels/w1_08.json", "res://levels/w1_09.json",
	"res://levels/w1_10.json",
]
const OVERTIME_FILES: PackedStringArray = [
	"res://levels/w1_11.json", "res://levels/w1_12.json", "res://levels/w1_13.json",
]
## Frames after the boot scene starts at which the splash is skipped. The
## splash runs 2 x 2.8 s = 336 frames at 60 fps.
const SPLASH_SKIP_FRAMES: Array[int] = [0, 1, 2, 10, 30, 60, 130, 150, 162, 168, 175, 200, 300, 330, 334, 336, 338, 345, 360]

var _passed: int = 0
var _failed: int = 0
var _logger: ErrorCounter = null


func _initialize() -> void:
	_run()


func _run() -> void:
	_logger = ErrorCounter.new()
	OS.add_logger(_logger)
	_delete_save()
	Room.level_override = ""
	await _section("1. splash", _splash)
	await _section("2. title", _title)
	await _section("3. world select", _world_select)
	await _section("4. level select", _level_select)
	await _section("5. room and Esc", _room_escapes)
	await _section("6. progress through rooms 1-10", _progress_chain)
	await _section("7. damaged saves", _damaged_saves)
	_delete_save()
	GameSession.reset()
	var errors: PackedStringArray = _logger.lines_since(0)
	_check(errors.is_empty(), "no ERROR or WARNING was logged during the whole run (%d logged)" % errors.size())
	for i: int in mini(errors.size(), 15):
		print("      " + errors[i])
	OS.remove_logger(_logger)
	print("")
	print("play_menus_break: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _section(name: String, body: Callable) -> void:
	print("")
	print("-- " + name)
	var before: int = _logger.count()
	await body.call()
	var lines: PackedStringArray = _logger.lines_since(before)
	_check(lines.is_empty(), "%s: no ERROR or WARNING (%d)" % [name, lines.size()])
	for i: int in mini(lines.size(), 8):
		print("      " + lines[i])


# --- 1. splash --------------------------------------------------------------------

func _splash() -> void:
	for skip_at: int in SPLASH_SKIP_FRAMES:
		await _boot_fresh(false)
		await _frames(skip_at)
		var card: int = (current_scene as SplashScreen).get_card_index() if current_scene is SplashScreen else -1
		await _key(KEY_ENTER)
		var ok: bool = await _wait_settled_on(func() -> bool: return current_scene is TitleScreen)
		_check(ok and _count_screens() == 1 and _cover_alpha() == 0.0,
				"skip at frame %d (card %d): one title, fade finished (titles %d, cover alpha %.2f)" % [
					skip_at, card, _count_screens(), _cover_alpha()])
	# Key spam through the whole splash: one key every 3 frames.
	await _boot_fresh(false)
	for i: int in 60:
		await _key(KEY_SPACE if i % 2 == 0 else KEY_ESCAPE)
		await _frames(1)
	var settled: bool = await _wait_settled_on(func() -> bool: return current_scene != null)
	_check(settled and _count_screens() == 1, "key spam (Space/Esc) through the splash and the title fade ends on one screen (%s)" % _scene_name())
	_check(current_scene is TitleScreen,
			"Space/Esc spam over the splash does not pass the title (on %s)" % _scene_name())
	# Mouse click skip.
	await _boot_fresh(false)
	await _frames(40)
	await _click(Vector2(640, 360))
	var clicked: bool = await _wait_settled_on(func() -> bool: return current_scene is TitleScreen)
	_check(clicked, "a mouse click skips the splash to the title")


# --- 2. title ---------------------------------------------------------------------

func _title() -> void:
	await _boot_to_title()
	var title: TitleScreen = current_scene as TitleScreen
	await _action(&"menu_up")
	_check(title.get_selected_text() == "Quit", "up from Play wraps to Quit (got %s)" % title.get_selected_text())
	await _action(&"menu_down")
	await _action(&"menu_down")
	_check(title.get_selected_text() == "Quit", "down twice from Quit wraps back to Quit (got %s)" % title.get_selected_text())
	await _action(&"menu_down")
	await _action(&"menu_back")
	await _frames(30)
	_check(current_scene == title, "Esc on the title does nothing (still on the title)")
	# Accept, then accept and back alternately every frame through the fade.
	await _action(&"menu_accept")
	for i: int in 40:
		await _action(&"menu_accept" if i % 2 == 0 else &"menu_back", false)
		await _frames(1)
	var settled: bool = await _wait_settled_on(func() -> bool: return current_scene != null)
	_check(settled and _count_screens() == 1, "accept then accept/back spam ends settled on one screen (%s)" % _scene_name())
	print("INFO  accept then 40 frames of accept/back spam ended on %s" % _scene_name())


# --- 3. world select ---------------------------------------------------------------

func _world_select() -> void:
	await _boot_to_title()
	await _action(&"menu_accept")
	if not await _wait_settled_on(func() -> bool: return current_scene is WorldSelect):
		_check(false, "Play opens the world select")
		return
	var worlds: WorldSelect = current_scene as WorldSelect
	for i: int in 3:
		await _action(&"menu_left")
	_check(worlds.get_selected_index() == 0, "left past the first world stays on World 1 (%d)" % worlds.get_selected_index())
	for i: int in 9:
		await _action(&"menu_right")
	_check(worlds.get_selected_index() == 4, "right past the last world stays on World 5 (%d)" % worlds.get_selected_index())
	# Locked worlds: accept repeatedly, then click every locked card repeatedly.
	for i: int in 6:
		await _action(&"menu_accept")
	await _frames(30)
	_check(current_scene == worlds and not ScreenFade.is_busy(self), "accepting a locked world six times stays on the world select")
	var cards: Array[WorldCard] = _world_cards(worlds)
	for round: int in 4:
		for c: int in range(1, cards.size()):
			await _click(cards[c].get_global_rect().get_center())
	await _frames(40)
	_check(current_scene == worlds and not ScreenFade.is_busy(self), "clicking each locked world card four times stays on the world select")
	var rest_ok: bool = true
	for card: WorldCard in cards:
		var body: Control = card.get_node_or_null(^"Body") as Control
		if body != null and absf(body.position.x) > 0.01:
			rest_ok = false
	_check(rest_ok, "every shaken card returns to rest (body x = 0)")
	_check(worlds.get_selected_index() == cards.size() - 1, "the last clicked card is selected (%d)" % worlds.get_selected_index())
	# Mouse resting over card 2 while the keys move the selection.
	await _motion(cards[2].get_global_rect().get_center())
	await _frames(2)
	_check(worlds.get_selected_index() == 2, "hovering card 3 selects it (%d)" % worlds.get_selected_index())
	await _action(&"menu_left")
	await _action(&"menu_left")
	await _frames(5)
	_check(worlds.get_selected_index() == 0, "keys move the selection away from the hovered card (%d)" % worlds.get_selected_index())
	await _motion(cards[2].get_global_rect().get_center() + Vector2(3, 3))
	await _frames(2)
	print("INFO  moving the mouse inside the hovered card 3 after the keys moved away: selected %d" % worlds.get_selected_index())
	# Esc and Enter in the same frame on World 1.
	worlds.select(0)
	await _frames(5)
	_press_raw_key(KEY_ESCAPE, true)
	_press_raw_key(KEY_ENTER, true)
	await _frames(1)
	_press_raw_key(KEY_ESCAPE, false)
	_press_raw_key(KEY_ENTER, false)
	var worlds_id: int = worlds.get_instance_id()
	var settled: bool = await _wait_settled_on(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != worlds_id)
	_check(settled and _count_screens() == 1, "Esc + Enter in the same frame leads to exactly one screen (%s)" % _scene_name())
	print("INFO  Esc + Enter together on the world select went to %s" % _scene_name())
	# Back to the world select and open World 1 with a mouse click.
	if current_scene is LevelSelect:
		await _action(&"menu_back")
	elif current_scene is TitleScreen:
		await _action(&"menu_accept")
	if not await _wait_settled_on(func() -> bool: return current_scene is WorldSelect):
		_check(false, "back on the world select")
		return
	worlds = current_scene as WorldSelect
	await _click(_world_cards(worlds)[0].get_global_rect().get_center())
	var opened: bool = await _wait_settled_on(func() -> bool: return current_scene is LevelSelect)
	_check(opened, "a click on World 1 opens its level select")


# --- 4. level select ---------------------------------------------------------------

func _level_select() -> void:
	_delete_save()
	var levels: LevelSelect = await _boot_to_level_select()
	if levels == null:
		return
	_check(levels.get_selected_file() == ROOM_FILES[0], "a fresh save selects room 1 (%s)" % levels.get_selected_file())
	for i: int in 3:
		await _action(&"menu_up")
		await _action(&"menu_left")
	_check(levels.get_selected_file() == ROOM_FILES[0], "up and left past the corner stay on room 1 (%s)" % levels.get_selected_file())
	for i: int in 8:
		await _action(&"menu_right")
	_check(levels.get_selected_file() == ROOM_FILES[4], "right past the row end stays on room 5 (%s)" % levels.get_selected_file())
	for i: int in 6:
		await _action(&"menu_down")
	_check(levels.get_selected_file() == OVERTIME_FILES[2], "down from room 5 past the bottom ends on room 13 (%s)" % levels.get_selected_file())
	_check(levels.get_info_title() == "13  ???", "a locked Overtime room's title shows '13  ???' (got '%s')" % levels.get_info_title())
	_check(levels.get_info_mission() == "Finish room 10 to unlock Overtime.",
			"its panel says 'Finish room 10 to unlock Overtime.' (got '%s')" % levels.get_info_mission())
	for i: int in 8:
		await _action(&"menu_right")
	_check(levels.get_selected_file() == OVERTIME_FILES[2], "right past room 13 stays on room 13")
	for i: int in 5:
		await _action(&"menu_accept")
	await _frames(30)
	_check(current_scene == levels and not ScreenFade.is_busy(self), "accepting a locked Overtime room five times does nothing")
	# Click every locked tile three times.
	var tiles: Array[RoomTile] = _room_tiles(levels)
	for round: int in 3:
		for tile: RoomTile in tiles:
			if not tile.can_start():
				await _click(tile.get_global_rect().get_center())
	await _frames(40)
	_check(current_scene == levels and not ScreenFade.is_busy(self), "clicking every locked room tile three times stays on the level select")
	levels.select_room(ROOM_FILES[1])
	_check(levels.get_info_title() == "2  ???" and levels.get_info_mission() == "Finish room 1 to unlock.",
			"room 2 reads '2  ???' / 'Finish room 1 to unlock.' (got '%s' / '%s')" % [levels.get_info_title(), levels.get_info_mission()])
	# Hover a tile with the mouse, then move with the keys.
	await _motion(tiles[7].get_global_rect().get_center())
	await _frames(2)
	_check(levels.get_selected_file() == ROOM_FILES[7], "hovering room 8 selects it (%s)" % levels.get_selected_file())
	await _action(&"menu_up")
	_check(levels.get_selected_file() == ROOM_FILES[2], "up from room 8 selects room 3 (%s)" % levels.get_selected_file())


# --- 5. room and Esc ---------------------------------------------------------------

func _room_escapes() -> void:
	_delete_save()
	var levels: LevelSelect = await _boot_to_level_select()
	if levels == null:
		return
	# a. Esc on the first frames of the fade-in.
	levels.select_room(ROOM_FILES[0])
	await _action(&"menu_accept")
	var started: bool = await _wait_for(func() -> bool: return _room() != null)
	_check(started, "room 1 starts")
	await _action(&"menu_back")
	var settled: bool = await _wait_settled_on(func() -> bool: return current_scene != null)
	print("INFO  Esc during the room's fade-in: settled on %s" % _scene_name())
	if current_scene is LevelSelect:
		await _action(&"menu_accept")
		await _wait_settled_on(func() -> bool: return _room() != null)
	_check(settled and _room() != null, "after Esc during the fade-in the game is in room 1 (on %s)" % _scene_name())
	# b. Esc right after the fade.
	await _action(&"menu_back")
	var back: bool = await _wait_settled_on(func() -> bool: return current_scene is LevelSelect)
	_check(back, "Esc right after the fade returns to the level select")
	# c. Esc during a zap freeze.
	await _action(&"menu_accept")
	if not await _wait_settled_on(func() -> bool: return _room() != null):
		_check(false, "room 1 starts again")
		return
	var room: Room = _room()
	_check(room.get_respawn().zap(), "a zap is accepted in room 1")
	await _frames(5)
	await _action(&"menu_back")
	back = await _wait_settled_on(func() -> bool: return current_scene is LevelSelect)
	_check(back, "Esc during the zap freeze returns to the level select")
	# d. Esc on the frame the door is entered.
	await _action(&"menu_accept")
	if not await _wait_settled_on(func() -> bool: return _room() != null):
		return
	room = _room()
	_plug_solution(room)
	await _frames(2)
	room.get_player().respawn(room.level_data.door - Vector2(70, 0))
	await _physics(3)
	Input.action_press("move_right")
	for i: int in 120:
		await physics_frame
		if room.is_complete():
			break
	Input.action_release("move_right")
	_check(room.is_complete(), "walking into the open door completes room 1")
	await _action(&"menu_back")
	back = await _wait_settled_on(func() -> bool: return current_scene is LevelSelect)
	_check(back, "Esc on the door-enter frame returns to the level select")
	levels = current_scene as LevelSelect
	if levels != null:
		_check(levels.get_tile_state(ROOM_FILES[0]) == RoomTile.State.COMPLETED, "room 1 is completed after Esc on the door frame")
		_check(levels.get_tile_state(ROOM_FILES[1]) == RoomTile.State.UNLOCKED, "room 2 is unlocked")
		_check(levels.get_selected_file() == ROOM_FILES[0], "the level select comes back on room 1 (%s)" % levels.get_selected_file())
	# e. R on the victory screen replays; then Esc during the victory screen.
	levels.select_room(ROOM_FILES[0])
	await _action(&"menu_accept")
	if not await _wait_settled_on(func() -> bool: return _room() != null):
		return
	room = _room()
	_plug_solution(room)
	await _frames(2)
	room.get_door().entered.emit()
	await _frames(30)
	_check(room.get_hud().is_level_complete_shown(), "the victory screen shows")
	_check(room.get_hud().get_victory_line() == Hud.VICTORY_NEXT_ROOM_MAP,
			"the victory line offers the next room and the map (got '%s')" % room.get_hud().get_victory_line())
	await _key(KEY_R)
	await _frames(5)
	var replay: Room = _room()
	_check(replay != null and replay != room and not replay.is_complete() and not replay.get_hud().is_level_complete_shown(),
			"R on the victory screen restarts room 1 fresh")
	_check(replay != null and replay.level_path == ROOM_FILES[0], "the replay is room 1")
	_check(replay != null and replay.get_hud().get_hint_text().ends_with(Hud.MAP_HINT), "the replay still offers Esc for the map")
	_plug_solution(replay)
	await _frames(2)
	replay.get_door().entered.emit()
	await _frames(30)
	await _action(&"menu_back")
	back = await _wait_settled_on(func() -> bool: return current_scene is LevelSelect)
	_check(back, "Esc during the victory screen returns to the level select")
	# f. E on the victory screen loads room 2; Esc during its fade-out of room 1.
	levels = current_scene as LevelSelect
	levels.select_room(ROOM_FILES[0])
	await _action(&"menu_accept")
	if not await _wait_settled_on(func() -> bool: return _room() != null):
		return
	room = _room()
	_plug_solution(room)
	await _frames(2)
	room.get_door().entered.emit()
	await _frames(10)
	await _action(&"interact")
	await _action(&"menu_back")
	await _action(&"restart")
	var next_ok: bool = await _wait_settled_on(func() -> bool: return current_scene != null)
	print("INFO  E then Esc then R on the victory screen: settled on %s%s" % [_scene_name(),
			(" " + _room().level_path) if _room() != null else ""])
	_check(next_ok and _count_screens() == 1, "E, Esc, R in quick succession end on one settled screen")


# --- 6. progress chain ---------------------------------------------------------------

func _progress_chain() -> void:
	_delete_save()
	var levels: LevelSelect = await _boot_to_level_select()
	if levels == null:
		return
	levels.select_room(ROOM_FILES[0])
	await _action(&"menu_accept")
	for i: int in ROOM_FILES.size():
		var file: String = ROOM_FILES[i]
		if not await _wait_settled_on(func() -> bool: return _room() != null and _room().level_path == file):
			_check(false, "room %d (%s) is loaded" % [i + 1, file])
			return
		var room: Room = _room()
		_check(_plug_solution(room), "room %d: a solution is plugged in" % (i + 1))
		await _frames(2)
		_check(room.get_door().is_open(), "room %d: the door opens" % (i + 1))
		room.get_door().entered.emit()
		await _frames(5)
		var progress: Progress = GameSession.progress()
		var world: CampaignWorld = Campaign.load_from_file(Campaign.DEFAULT_PATH).get_world(WORLD_ID)
		_check(progress.completed_count(world) == i + 1, "room %d: %d rooms completed (got %d)" % [i + 1, i + 1, progress.completed_count(world)])
		var overtime_open: bool = progress.is_overtime_open(world)
		_check(overtime_open == (i == ROOM_FILES.size() - 1),
				"room %d: Overtime is %s (got %s)" % [i + 1, "open" if i == ROOM_FILES.size() - 1 else "closed", overtime_open])
		var line: String = room.get_hud().get_victory_line()
		_check(line == Hud.VICTORY_NEXT_ROOM_MAP, "room %d: the victory line offers the next room (got '%s')" % [i + 1, line])
		var saved: String = FileAccess.get_file_as_string(TEMP_SAVE)
		_check(saved.contains(file), "room %d: the save file lists %s" % [i + 1, file])
		if i < ROOM_FILES.size() - 1:
			await _action(&"interact")
	# After room 10 the next room is Overtime room 11: go to the map instead.
	await _action(&"menu_back")
	if not await _wait_settled_on(func() -> bool: return current_scene is LevelSelect):
		_check(false, "Esc returns to the level select after room 10")
		return
	levels = current_scene as LevelSelect
	var all_done: bool = true
	for file: String in ROOM_FILES:
		all_done = all_done and levels.get_tile_state(file) == RoomTile.State.COMPLETED
	_check(all_done, "rooms 1-10 all show completed")
	var overtime_states: Array[int] = []
	for file: String in OVERTIME_FILES:
		overtime_states.append(levels.get_tile_state(file))
	var expected_overtime: bool = true
	for state: int in overtime_states:
		expected_overtime = expected_overtime and (state == RoomTile.State.UNLOCKED or state == RoomTile.State.UNBUILT)
	_check(expected_overtime, "the three Overtime rooms are unlocked together after room 10 (states %s)" % [overtime_states])
	_check(levels.get_selected_file() == ROOM_FILES[9], "the level select comes back on room 10 (%s)" % levels.get_selected_file())
	await _action(&"menu_back")
	if await _wait_settled_on(func() -> bool: return current_scene is WorldSelect):
		var text: String = _world_progress_text(current_scene as WorldSelect)
		_check(text == "10 / 13 rooms", "the World 1 card reads '10 / 13 rooms' (got '%s')" % text)


# --- 7. damaged saves ----------------------------------------------------------------

func _damaged_saves() -> void:
	for content: String in ["{not json", "", "[1, 2, 3]", "{\"completed\": [42, null, \"\", \"res://levels/w1_01.json\"]}",
			"{\"completed\": \"res://levels/w1_01.json\"}"]:
		var file: FileAccess = FileAccess.open(TEMP_SAVE, FileAccess.WRITE)
		file.store_string(content)
		file.close()
		var levels: LevelSelect = await _boot_to_level_select()
		var expect_one: bool = content.begins_with("{\"completed\": [42")
		if levels == null:
			_check(false, "save %s: the level select opens" % content.c_escape())
			continue
		var state: int = levels.get_tile_state(ROOM_FILES[0])
		var want: RoomTile.State = RoomTile.State.COMPLETED if expect_one else RoomTile.State.UNLOCKED
		_check(state == want, "save '%s': room 1 is %s (got %d)" % [content.c_escape(), RoomTile.State.keys()[want], state])
	# The save deleted while playing: the next completion writes a new one.
	_delete_save()
	var levels2: LevelSelect = await _boot_to_level_select()
	if levels2 == null:
		return
	levels2.select_room(ROOM_FILES[0])
	await _action(&"menu_accept")
	if not await _wait_settled_on(func() -> bool: return _room() != null):
		return
	_delete_save()
	var room: Room = _room()
	_plug_solution(room)
	await _frames(2)
	room.get_door().entered.emit()
	await _frames(5)
	_check(FileAccess.get_file_as_string(TEMP_SAVE).contains(ROOM_FILES[0]), "a save deleted mid-session is written again on completion")


# --- helpers ---------------------------------------------------------------------------

## Starts the boot scene with a fresh session on the temporary save.
func _boot_fresh(wait_for_splash: bool = true) -> void:
	await _clear_scene()
	GameSession.reset()
	GameSession.save_path = TEMP_SAVE
	var boot: Node = (load(ScreenFade.BOOT) as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	if wait_for_splash:
		await _wait_for(func() -> bool: return current_scene is SplashScreen)


func _boot_to_title() -> void:
	await _boot_fresh()
	await _key(KEY_SPACE)
	await _wait_settled_on(func() -> bool: return current_scene is TitleScreen)


func _boot_to_level_select() -> LevelSelect:
	await _boot_to_title()
	await _action(&"menu_accept")
	if not await _wait_settled_on(func() -> bool: return current_scene is WorldSelect):
		_check(false, "the world select opens")
		return null
	await _action(&"menu_accept")
	if not await _wait_settled_on(func() -> bool: return current_scene is LevelSelect):
		_check(false, "the level select opens")
		return null
	return current_scene as LevelSelect


func _clear_scene() -> void:
	await _wait_for(func() -> bool: return not ScreenFade.is_busy(self))
	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
	await _frames(2)


func _room() -> Room:
	if current_scene == null or not is_instance_valid(current_scene):
		return null
	var room: Room = current_scene.get_node_or_null(^"Room") as Room
	return room if room != null and room.level_data != null else null


## Screens (title, world select, level select, game, splash) directly under the root.
func _count_screens() -> int:
	var n: int = 0
	for child: Node in root.get_children():
		if child is TitleScreen or child is WorldSelect or child is LevelSelect or child is SplashScreen \
				or child.get_node_or_null(^"Room") != null:
			n += 1
	return n


func _scene_name() -> String:
	if current_scene == null:
		return "nothing"
	if current_scene is TitleScreen:
		return "title"
	if current_scene is WorldSelect:
		return "world select"
	if current_scene is LevelSelect:
		return "level select"
	if current_scene is SplashScreen:
		return "splash"
	if _room() != null:
		return "room"
	return current_scene.name


func _cover_alpha() -> float:
	var fade: ScreenFade = root.get_node_or_null(ScreenFade.NODE_NAME) as ScreenFade
	if fade == null:
		return 0.0
	var cover: ColorRect = fade.get_node_or_null(^"Cover") as ColorRect
	return cover.color.a if cover != null else 0.0


func _world_cards(worlds: WorldSelect) -> Array[WorldCard]:
	var cards: Array[WorldCard] = []
	for child: Node in worlds.get_children():
		if child is WorldCard:
			cards.append(child as WorldCard)
	cards.sort_custom(func(a: WorldCard, b: WorldCard) -> bool: return a.position.x < b.position.x)
	return cards


func _room_tiles(levels: LevelSelect) -> Array[RoomTile]:
	var tiles: Array[RoomTile] = []
	for number: int in range(1, 14):
		var tile: RoomTile = levels.get_node_or_null(NodePath("Room%d" % number)) as RoomTile
		if tile != null:
			tiles.append(tile)
	return tiles


func _world_progress_text(worlds: WorldSelect) -> String:
	var cards: Array[WorldCard] = _world_cards(worlds)
	if cards.is_empty():
		return ""
	var labels: Array[Node] = cards[0].find_children("Progress", "Label", true, false)
	return (labels[0] as Label).text if not labels.is_empty() else ""


func _plug_solution(room: Room) -> bool:
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


## Waits until `condition` holds and no fade is running.
func _wait_settled_on(condition: Callable) -> bool:
	for i: int in MAX_WAIT_FRAMES:
		if not ScreenFade.is_busy(self) and condition.call():
			await _frames(2)
			if not ScreenFade.is_busy(self) and condition.call():
				return true
		await process_frame
	return false


func _wait_for(condition: Callable) -> bool:
	for i: int in MAX_WAIT_FRAMES:
		if condition.call():
			return true
		await process_frame
	return bool(condition.call())


func _frames(count: int) -> void:
	for i: int in count:
		await process_frame


func _physics(count: int) -> void:
	for i: int in count:
		await physics_frame


func _action(action: StringName, release_after_frame: bool = true) -> void:
	var down: InputEventAction = InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	if release_after_frame:
		await process_frame
	var up: InputEventAction = InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame


func _key(keycode: Key) -> void:
	_press_raw_key(keycode, true)
	await process_frame
	_press_raw_key(keycode, false)
	await process_frame


func _press_raw_key(keycode: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _motion(at: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	root.push_input(event, true)
	await process_frame


func _click(at: Vector2) -> void:
	await _motion(at)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		root.push_input(event, true)
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
