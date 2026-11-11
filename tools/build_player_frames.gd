extends SceneTree
## Builds res://resources/themes/player_frames.tres (SpriteFrames) from the 256x256 player
## poses in res://assets/player/. Animations: idle, run, jump, victory, back, notice.
##
## Run from the project root:
##   godot --headless --path . --script res://tools/build_player_frames.gd
##
## Every frame is 256x256 and drawn at scale 0.5. Three source frames need fixing, which is
## done with an AtlasTexture over the original PNG (the PNG itself is never changed):
##   - region crops out stray fragments the pack's atlas slicer left at the frame edges
##     (walk.png row 73; idle.png row 53 and rows 245-249; run.png rows 245-249);
##   - margin.position.y moves the pose down so its lowest opaque pixel (alpha >= 0.5) lands
##     on row 249, the baseline every grounded pose shares. run.png's lowest pixel is its dust
##     puff at row 225 (shoes end at 222), idle.png's is a shoe at row 229.
## margin.size.y is 256 minus the rows kept, so each AtlasTexture is still 256x256.
## jump.png is deliberately not shifted: it is an airborne pose (shoes end at row 223, its
## motion lines reach row 249).

const OUTPUT_PATH: String = "res://resources/themes/player_frames.tres"
const PLAYER_DIR: String = "res://assets/player/"
const FRAME_PX: int = 256

## file -> [first source row kept, rows kept, rows to move down]. Files not listed are used whole.
const FRAME_FIXES: Dictionary = {
	"walk.png": [76, 180, 0],
	"run.png": [0, 229, 24],
	"idle.png": [56, 181, 20],
}

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
			var texture: Texture2D = _frame_texture(file)
			if texture == null:
				return 1
			frames.add_frame(anim_name, texture)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir()))
	var err: Error = ResourceSaver.save(frames, OUTPUT_PATH)
	if err != OK:
		push_error("build_player_frames: save failed (%s)" % error_string(err))
		return 1
	print("build_player_frames: saved %s with animations %s" % [OUTPUT_PATH, frames.get_animation_names()])
	return 0


func _frame_texture(file: String) -> Texture2D:
	var source: Texture2D = load(PLAYER_DIR + file) as Texture2D
	if source == null:
		push_error("build_player_frames: could not load %s" % (PLAYER_DIR + file))
		return null
	if Vector2i(source.get_size()) != Vector2i(FRAME_PX, FRAME_PX):
		push_error("build_player_frames: %s is %s, expected 256x256" % [file, source.get_size()])
		return null
	if not FRAME_FIXES.has(file):
		return source
	var fix: Array = FRAME_FIXES[file]
	var first_row: int = fix[0]
	var row_count: int = fix[1]
	var shift: int = fix[2]
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = source
	atlas.region = Rect2(0, first_row, FRAME_PX, row_count)
	atlas.margin = Rect2(0, first_row + shift, 0, FRAME_PX - row_count)
	atlas.filter_clip = true
	return atlas
