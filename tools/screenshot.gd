extends SceneTree
## Loads the main scene, lets it run for a short while, saves the viewport as a PNG.
##
## Must run with a real renderer (not --headless). The output path follows `--`
## and may be res://, user:// or an absolute path:
##   godot --path . --script res://tools/screenshot.gd -- res://tests/screenshots/room.png

const MAIN_SCENE: String = "res://scenes/main.tscn"
const WAIT_FRAMES: int = 60


func _initialize() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("screenshot: give the output PNG path after --")
		quit(1)
		return
	var output_path: String = args[0]
	if output_path.begins_with("res://") or output_path.begins_with("user://"):
		output_path = ProjectSettings.globalize_path(output_path)

	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		push_error("screenshot: could not load %s" % MAIN_SCENE)
		quit(1)
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	current_scene = main

	for i: int in WAIT_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw

	var image: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var err: Error = image.save_png(output_path)
	if err != OK:
		push_error("screenshot: could not save %s (%s)" % [output_path, error_string(err)])
		quit(1)
		return
	print("screenshot: saved %s (%dx%d)" % [output_path, image.get_width(), image.get_height()])
	quit(0)
