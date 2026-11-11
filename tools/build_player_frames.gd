extends SceneTree
## Builds res://resources/player_frames.tres (SpriteFrames) from the 128x128 player poses.
##
## Run from the project root:
##   godot --headless --path . --script res://tools/build_player_frames.gd

const OUTPUT_PATH: String = "res://resources/player_frames.tres"
const PLAYER_DIR: String = "res://assets/player/"

## Each entry: animation name, frame files, frames per second, loops.
const ANIMATIONS: Array[Dictionary] = [
	{"name": "idle", "frames": ["front.png"], "fps": 1.0, "loop": true},
	{"name": "run", "frames": ["walk.png", "run.png"], "fps": 8.0, "loop": true},
	{"name": "jump", "frames": ["jump.png"], "fps": 1.0, "loop": false},
	{"name": "victory", "frames": ["victory.png"], "fps": 1.0, "loop": false},
	{"name": "back", "frames": ["back.png"], "fps": 1.0, "loop": false},
	{"name": "notice", "frames": ["idle.png"], "fps": 1.0, "loop": false},
]


func _init() -> void:
	var exit_code: int = _build()
	quit(exit_code)


func _build() -> int:
	var frames: SpriteFrames = SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")

	for anim: Dictionary in ANIMATIONS:
		var anim_name: StringName = StringName(anim["name"])
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, anim["fps"])
		frames.set_animation_loop(anim_name, anim["loop"])
		for file: String in anim["frames"]:
			var texture: Texture2D = load(PLAYER_DIR + file) as Texture2D
			if texture == null:
				push_error("build_player_frames: could not load %s" % (PLAYER_DIR + file))
				return 1
			frames.add_frame(anim_name, texture)

	var err: Error = ResourceSaver.save(frames, OUTPUT_PATH)
	if err != OK:
		push_error("build_player_frames: save failed (%s)" % error_string(err))
		return 1
	print("build_player_frames: saved %s with animations %s" % [OUTPUT_PATH, frames.get_animation_names()])
	return 0
