extends SceneTree
## QA: screenshots of the world select and the level select with rooms 1-10
## completed (Overtime open), from a temporary save. Windowed only:
##   godot --path . --script res://tools/qa_menu_progress_shots.gd
## Output: res://tests/screenshots/qa/menu_*.png

const OUTPUT_DIR: String = "res://tests/screenshots/qa/"
const TEMP_SAVE: String = "user://qa_menu_progress_shots.json"
const AUDIO_RELEASE_FRAMES: int = 10


func _initialize() -> void:
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var progress: Progress = Progress.new()
	for n: int in range(1, 11):
		progress.mark_completed("res://levels/w1_%02d.json" % n)
	ProgressStore.save(progress, TEMP_SAVE)
	GameSession.reset()
	GameSession.save_path = TEMP_SAVE
	var boot: Node = (load(ScreenFade.BOOT) as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	await _until(func() -> bool: return current_scene is SplashScreen)
	_key(KEY_SPACE)
	await _until(func() -> bool: return current_scene is TitleScreen and not ScreenFade.is_busy(self))
	_action(&"menu_accept")
	await _until(func() -> bool: return current_scene is WorldSelect and not ScreenFade.is_busy(self))
	await _seconds(0.4)
	await _save("menu_world_select_10_done.png")
	_action(&"menu_accept")
	await _until(func() -> bool: return current_scene is LevelSelect and not ScreenFade.is_busy(self))
	await _seconds(0.4)
	await _save("menu_level_select_10_done.png")
	var levels: LevelSelect = current_scene as LevelSelect
	levels.select_room("res://levels/w1_13.json")
	await _seconds(0.4)
	await _save("menu_level_select_room_13.png")
	levels.select_room("res://levels/w1_07.json")
	await _seconds(0.4)
	await _save("menu_level_select_room_07_completed.png")
	var sfx: SfxPlayer = root.get_node_or_null(^"Sfx") as SfxPlayer
	if sfx != null:
		sfx.stop_all()
	for i: int in AUDIO_RELEASE_FRAMES:
		await process_frame
	if FileAccess.file_exists(TEMP_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))
	GameSession.reset()
	quit(0)


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = ProjectSettings.globalize_path(OUTPUT_DIR + file_name)
	root.get_texture().get_image().save_png(path)
	print("saved %s" % path)


func _until(condition: Callable) -> void:
	for i: int in 900:
		if condition.call():
			return
		await process_frame


func _seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


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
