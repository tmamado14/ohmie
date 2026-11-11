extends SceneTree
## Loads the main scene, lets it run for a short while, saves the viewport as a PNG.
##
## Must run with a real renderer (not --headless). The output path follows `--`
## and may be res://, user:// or an absolute path:
##   godot --path . --script res://tools/screenshot.gd -- res://tests/screenshots/room.png
##
## Options after the path:
##   --level=res://levels/<file>.json  load that level (read by the room itself)
##   --solve                           plug the level's first solution into its
##                                     sockets (found with PuzzleSolver) before
##                                     the capture

const MAIN_SCENE: String = "res://scenes/main.tscn"
const ROOM_PATH: NodePath = ^"Room"
const WAIT_FRAMES: int = 60
const SOLVE_FLAG: String = "--solve"
const AUDIO_RELEASE_FRAMES: int = 10


func _initialize() -> void:
	_run()


func _run() -> void:
	var output_path: String = ""
	var solve: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg == SOLVE_FLAG:
			solve = true
		elif not arg.begins_with("--") and output_path.is_empty():
			output_path = arg
	if output_path.is_empty():
		push_error("screenshot: give the output PNG path after --")
		quit(1)
		return
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

	await process_frame
	if solve and not _plug_in_first_solution(main.get_node_or_null(ROOM_PATH) as Room):
		quit(1)
		return

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
	await _stop_audio()
	quit(0)


## Stops all sound and gives the audio thread time to release the streams, so
## the engine does not report them as leaked at exit.
func _stop_audio() -> void:
	var sfx: SfxPlayer = root.get_node_or_null(SfxPlayer.AUTOLOAD_PATH) as SfxPlayer
	if sfx == null:
		return
	sfx.stop_all()
	for i: int in AUDIO_RELEASE_FRAMES:
		await process_frame


## Moves loose resistors into the sockets as the first PuzzleSolver solution says.
func _plug_in_first_solution(room: Room) -> bool:
	if room == null or room.get_circuit() == null:
		push_error("screenshot: no loaded room to solve")
		return false
	var circuit: LevelCircuit = room.get_circuit()
	var pickups: Array[ResistorPickup] = room.get_pickups()
	var values: Array[Rational] = []
	for pickup: ResistorPickup in pickups:
		values.append(pickup.value)
	var solutions: Array[Dictionary] = PuzzleSolver.find_solutions(circuit.build_base_graph(),
			circuit.get_socket_descriptors(), values, room.get_target())
	if solutions.is_empty():
		push_error("screenshot: the level has no solution to plug in")
		return false
	var solution: Dictionary = solutions[0]
	for socket: CircuitSocket in room.get_board().get_sockets():
		if not solution.has(socket.socket_id):
			continue
		for pickup: ResistorPickup in pickups:
			if pickup.is_loose() and pickup.value.to_text() == solution[socket.socket_id]:
				pickup.take()
				socket.insert(pickup)
				break
	return true
