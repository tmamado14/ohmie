extends SceneTree
## QA: checks that the music neither restarts nor stacks while moving between
## screens and rooms. Needs a real audio driver, so run it windowed (not
## --headless); prints a report and exits 1 when a check fails:
##   godot --path . --script res://tools/qa_music_check.gd
##
## Route: boot -> splash (skipped) -> title -> world select -> level select ->
## room 1 -> R -> Esc -> level select -> room 1 -> solved -> E (room 2) -> Esc
## -> world select -> title. Every frame it samples the Sfx music player (its
## stream, whether it plays, its playback position) and counts every
## AudioStreamPlayer in the tree that is playing a music stream. A restart is
## a jump back of more than RESTART_JUMP seconds that is not the loop wrapping.

const TEMP_SAVE: String = "user://qa_music_progress.json"
const RESTART_JUMP: float = 0.5
const LOOP_WRAP_MARGIN: float = 1.0
const AUDIO_RELEASE_FRAMES: int = 10

var _sfx: SfxPlayer = null
var _music: AudioStreamPlayer = null
var _last_pos: float = -1.0
var _restarts: PackedStringArray = []
var _max_playing: int = 0
var _not_playing_frames: int = 0
var _stage: String = ""
var _streams_seen: Dictionary = {}
var _silent_stages: Dictionary = {}


func _initialize() -> void:
	_run()


func _run() -> void:
	GameSession.reset()
	GameSession.save_path = TEMP_SAVE
	_delete_save()
	await process_frame
	_sfx = root.get_node_or_null(^"Sfx") as SfxPlayer
	if _sfx == null:
		print("FAIL  no Sfx autoload at /root/Sfx")
		quit(1)
		return
	_music = _sfx.get_node_or_null(^"Music") as AudioStreamPlayer
	var boot: Node = (load(ScreenFade.BOOT) as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	await _stage_wait("splash", 30)
	_key(KEY_SPACE)
	await _until("title", func() -> bool: return current_scene is TitleScreen and not ScreenFade.is_busy(self))
	await _stage_wait("title", 60)
	_action(&"menu_accept")
	await _until("world select", func() -> bool: return current_scene is WorldSelect and not ScreenFade.is_busy(self))
	await _stage_wait("world select", 30)
	_action(&"menu_accept")
	await _until("level select", func() -> bool: return current_scene is LevelSelect and not ScreenFade.is_busy(self))
	await _stage_wait("level select", 30)
	_action(&"menu_accept")
	await _until("room 1", func() -> bool: return _room() != null and not ScreenFade.is_busy(self))
	await _stage_wait("room 1", 60)
	_key(KEY_R)
	await _stage_wait("room 1 after R", 60)
	_action(&"menu_back")
	await _until("level select again", func() -> bool: return current_scene is LevelSelect and not ScreenFade.is_busy(self))
	await _stage_wait("level select again", 30)
	_action(&"menu_accept")
	await _until("room 1 again", func() -> bool: return _room() != null and not ScreenFade.is_busy(self))
	_plug_solution(_room())
	await _stage_wait("room 1 solved", 10)
	_room().get_door().entered.emit()
	await _stage_wait("room 1 victory", 60)
	_action(&"interact")
	await _until("room 2", func() -> bool:
		return _room() != null and _room().level_path.ends_with("w1_02.json") and not ScreenFade.is_busy(self))
	await _stage_wait("room 2", 60)
	_action(&"menu_back")
	await _until("level select 3", func() -> bool: return current_scene is LevelSelect and not ScreenFade.is_busy(self))
	_action(&"menu_back")
	await _until("world select 2", func() -> bool: return current_scene is WorldSelect and not ScreenFade.is_busy(self))
	_action(&"menu_back")
	await _until("title 2", func() -> bool: return current_scene is TitleScreen and not ScreenFade.is_busy(self))
	await _stage_wait("title 2", 60)

	var ok: bool = true
	print("music streams seen: %s" % [_streams_seen.keys()])
	print("most music players playing at once: %d" % _max_playing)
	print("frames with the Sfx music not playing (after the title): %d" % _not_playing_frames)
	if _restarts.is_empty():
		print("PASS  the music never restarted")
	else:
		ok = false
		print("FAIL  the music restarted %d time(s):" % _restarts.size())
		for line: String in _restarts:
			print("      " + line)
	if _max_playing > 1:
		ok = false
		print("FAIL  more than one music player played at once")
	else:
		print("PASS  never more than one music player at once")
	if _not_playing_frames > 0:
		ok = false
		print("FAIL  the music stopped for %d frames: %s" % [_not_playing_frames, _silent_stages])
	_sfx.stop_all()
	for i: int in AUDIO_RELEASE_FRAMES:
		await process_frame
	_delete_save()
	GameSession.reset()
	quit(0 if ok else 1)


func _sample() -> void:
	if _music == null:
		return
	var playing_count: int = 0
	for node: Node in root.find_children("*", "AudioStreamPlayer", true, false):
		var player: AudioStreamPlayer = node as AudioStreamPlayer
		if player.playing and player.stream != null and not player.stream.resource_path.get_file().begins_with("sfx_"):
			playing_count += 1
			_streams_seen[player.stream.resource_path] = true
	_max_playing = maxi(_max_playing, playing_count)
	if not _music.playing:
		if not _stage.contains("splash") and not _stage.ends_with(" title") and _stage != "title":
			_not_playing_frames += 1
			_silent_stages[_stage] = int(_silent_stages.get(_stage, 0)) + 1
		_last_pos = -1.0
		return
	var pos: float = _music.get_playback_position()
	var length: float = _music.stream.get_length() if _music.stream != null else 0.0
	if _last_pos >= 0.0 and pos < _last_pos - RESTART_JUMP:
		var wrapped: bool = length > 0.0 and _last_pos > length - LOOP_WRAP_MARGIN and pos < LOOP_WRAP_MARGIN
		if not wrapped:
			_restarts.append("during '%s': %.2f s -> %.2f s" % [_stage, _last_pos, pos])
	_last_pos = pos


func _stage_wait(stage: String, frames: int) -> void:
	_stage = stage
	for i: int in frames:
		await process_frame
		_sample()


func _until(stage: String, condition: Callable) -> void:
	_stage = "to " + stage
	for i: int in 600:
		if condition.call():
			return
		await process_frame
		_sample()
	print("FAIL  never reached %s" % stage)


func _room() -> Room:
	if current_scene == null:
		return null
	var room: Room = current_scene.get_node_or_null(^"Room") as Room
	return room if room != null and room.level_data != null else null


func _plug_solution(room: Room) -> void:
	var circuit: LevelCircuit = room.get_circuit()
	var parts: Array[PartPickup] = room.get_parts()
	var search_parts: Array[Dictionary] = []
	for pickup: PartPickup in parts:
		search_parts.append(pickup.part.to_search_dictionary())
	var solutions: Array[Dictionary] = DcPuzzleSearch.find_solutions(circuit.build_base_network(),
			circuit.get_slot_descriptors(), search_parts, room.get_goal().conditions, 1)
	if solutions.is_empty():
		return
	for socket: CircuitSocket in room.get_board().get_sockets():
		if not solutions[0].has(socket.socket_id):
			continue
		for pickup: PartPickup in parts:
			if pickup.is_loose() and pickup.part.label() == solutions[0][socket.socket_id]:
				pickup.take()
				socket.insert(pickup)
				break


func _action(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)


func _key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)


func _delete_save() -> void:
	if FileAccess.file_exists(TEMP_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))
