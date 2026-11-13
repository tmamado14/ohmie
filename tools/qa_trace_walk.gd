extends SceneTree
## QA trace (not pass/fail): stands Ohmie at x on the floor of a room, holds a
## direction for N frames and prints each frame's feet position, velocity and
## is_on_floor, plus which bounce pads see him. Hazards are switched off
## (process_mode) so the trace shows movement only.
##
## Usage:
##   godot --headless --path . --fixed-fps 60 --script res://tools/qa_trace_walk.gd -- \
##       --level=res://levels/w1_13.json --x=200 --y=640 --dir=1 --frames=40

const MAIN_SCENE: String = "res://scenes/main.tscn"


func _initialize() -> void:
	_run()


func _run() -> void:
	var x: float = 200.0
	var y: float = 640.0
	var dir: int = 1
	var frames: int = 40
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--x="):
			x = arg.substr(4).to_float()
		elif arg.begins_with("--y="):
			y = arg.substr(4).to_float()
		elif arg.begins_with("--dir="):
			dir = arg.substr(6).to_int()
		elif arg.begins_with("--frames="):
			frames = arg.substr(9).to_int()
	Room.level_override = Room.level_path_from_command_line()
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _wait(20)
	var room: Room = main.get_node(^"Room") as Room
	for hazard: Hazard in room.get_objects().get_hazards():
		hazard.process_mode = Node.PROCESS_MODE_DISABLED
	for pad: BouncePad in room.get_objects().get_pads():
		pad.bounced.connect(func(_b: Node2D, sy: float, _s: float) -> void: print("   bounce at surface %.0f" % sy))
	var player: Player = room.get_player()
	player.respawn(Vector2(x, y))
	await _wait(3)
	var action: String = "move_right" if dir > 0 else "move_left"
	Input.action_press(action)
	for k: int in frames:
		await _wait(1)
		print("%3d feet (%.2f, %.2f) vel (%.1f, %.1f) floor %s" % [k, player.position.x, player.position.y,
				player.velocity.x, player.velocity.y, player.is_on_floor()])
	Input.action_release(action)
	Room.level_override = ""
	quit(0)


func _wait(n: int) -> void:
	for i: int in n:
		await physics_frame
