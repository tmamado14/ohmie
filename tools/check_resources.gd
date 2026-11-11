extends SceneTree
## Verifies the asset resources the vertical slice depends on.
##
## Run from the project root (exit code 0 = all checks pass, 1 = at least one failed):
##   godot --headless --path . --script res://tools/check_resources.gd

const TILESET_PATH: String = "res://resources/tileset.tres"
const FRAMES_PATH: String = "res://resources/player_frames.tres"
const MUSIC_PATH: String = "res://assets/audio/music_copper_works_loop_16s.wav"
const TILESET_IMAGE_PATH: String = "res://assets/environment/tileset_32px.png"

const SOLID_TILE_IDS: Array[int] = [0, 1, 2, 3, 12, 13, 14]
const ONE_WAY_TILE_IDS: Array[int] = [4, 5, 6, 7]
const ONE_WAY_TOP_ROW: int = 7
const ONE_WAY_BOTTOM_ROW: int = 20

## name -> [frame count, fps, loop]
const EXPECTED_ANIMATIONS: Dictionary = {
	"idle": [1, 1.0, true],
	"run": [2, 8.0, true],
	"jump": [1, 1.0, false],
	"victory": [1, 1.0, false],
	"back": [1, 1.0, false],
	"notice": [1, 1.0, false],
}

## path -> size
const EXPECTED_TEXTURES: Dictionary = {
	"res://assets/processed/socket_empty.png": Vector2i(104, 72),
	"res://assets/processed/socket_highlight.png": Vector2i(104, 72),
	"res://assets/processed/pickup_highlight.png": Vector2i(104, 72),
	"res://assets/processed/node_dot.png": Vector2i(16, 16),
	"res://assets/processed/terminal.png": Vector2i(32, 32),
}

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	_check_tileset()
	_check_platform_art_rows()
	_check_frames()
	_check_music()
	_check_textures()
	print("check_resources: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func _check_tileset() -> void:
	var tile_set: TileSet = load(TILESET_PATH) as TileSet
	_expect(tile_set != null, "TileSet loads from %s" % TILESET_PATH)
	if tile_set == null:
		return
	_expect(tile_set.tile_size == Vector2i(32, 32), "tile_size is 32x32")
	_expect(tile_set.get_physics_layers_count() == 2, "TileSet has 2 physics layers")
	if tile_set.get_physics_layers_count() == 2:
		_expect(tile_set.get_physics_layer_collision_layer(0) == 1, "physics layer 0 collision_layer == 1")
		_expect(tile_set.get_physics_layer_collision_layer(1) == 2, "physics layer 1 collision_layer == 2")
		_expect(tile_set.get_physics_layer_collision_mask(0) == 0, "physics layer 0 collision_mask == 0")
		_expect(tile_set.get_physics_layer_collision_mask(1) == 0, "physics layer 1 collision_mask == 0")
	_expect(tile_set.has_source(0), "TileSet has atlas source id 0")
	if not tile_set.has_source(0):
		return
	var source: TileSetAtlasSource = tile_set.get_source(0) as TileSetAtlasSource
	_expect(source != null, "source 0 is a TileSetAtlasSource")
	if source == null:
		return
	_expect(source.texture != null and source.texture.resource_path == TILESET_IMAGE_PATH, "source 0 texture is %s" % TILESET_IMAGE_PATH)
	_expect(source.texture_region_size == Vector2i(32, 32), "texture_region_size is 32x32")
	_expect(source.get_tiles_count() == 16, "atlas has 16 tiles (got %d)" % source.get_tiles_count())

	for tile_id: int in 16:
		var coords: Vector2i = Vector2i(tile_id % 4, tile_id / 4)
		_expect(source.has_tile(coords), "tile %d exists at %s" % [tile_id, coords])
		if not source.has_tile(coords):
			continue
		var data: TileData = source.get_tile_data(coords, 0)
		var world_count: int = data.get_collision_polygons_count(0)
		var one_way_count: int = data.get_collision_polygons_count(1)
		if tile_id in SOLID_TILE_IDS:
			_expect(world_count == 1 and one_way_count == 0, "tile %d: 1 polygon on layer 0, 0 on layer 1 (got %d, %d)" % [tile_id, world_count, one_way_count])
			if world_count == 1:
				var pts: PackedVector2Array = data.get_collision_polygon_points(0, 0)
				_expect(_bounds(pts) == Rect2(-16, -16, 32, 32), "tile %d: full 32x32 square (got %s)" % [tile_id, _bounds(pts)])
				_expect(not data.is_collision_polygon_one_way(0, 0), "tile %d: world polygon is not one-way" % tile_id)
		elif tile_id in ONE_WAY_TILE_IDS:
			_expect(world_count == 0 and one_way_count == 1, "tile %d: 0 polygons on layer 0, 1 on layer 1 (got %d, %d)" % [tile_id, world_count, one_way_count])
			if one_way_count == 1:
				_expect(data.is_collision_polygon_one_way(1, 0), "tile %d: layer 1 polygon is one-way" % tile_id)
				var pts: PackedVector2Array = data.get_collision_polygon_points(1, 0)
				var expected: Rect2 = Rect2(-16, ONE_WAY_TOP_ROW - 16, 32, ONE_WAY_BOTTOM_ROW - ONE_WAY_TOP_ROW + 1)
				_expect(_bounds(pts) == expected, "tile %d: strip covers rows 7-20 (got %s)" % [tile_id, _bounds(pts)])
		else:
			_expect(world_count == 0 and one_way_count == 0, "tile %d: no collision (got %d, %d)" % [tile_id, world_count, one_way_count])


## Confirms the platform tiles' opaque pixels really span rows 7-20, matching the collision strip.
func _check_platform_art_rows() -> void:
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path(TILESET_IMAGE_PATH))
	_expect(img != null, "tileset image loads")
	if img == null:
		return
	for tile_id: int in ONE_WAY_TILE_IDS:
		var ox: int = (tile_id % 4) * 32
		var oy: int = (tile_id / 4) * 32
		var top: int = 32
		var bottom: int = -1
		for y: int in 32:
			for x: int in 32:
				if img.get_pixel(ox + x, oy + y).a > 0.0:
					top = mini(top, y)
					bottom = maxi(bottom, y)
		_expect(top == ONE_WAY_TOP_ROW and bottom == ONE_WAY_BOTTOM_ROW, "tile %d art spans rows %d-%d (expected 7-20)" % [tile_id, top, bottom])


func _bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var rect: Rect2 = Rect2(points[0], Vector2.ZERO)
	for p: Vector2 in points:
		rect = rect.expand(p)
	return rect


func _check_frames() -> void:
	var frames: SpriteFrames = load(FRAMES_PATH) as SpriteFrames
	_expect(frames != null, "SpriteFrames loads from %s" % FRAMES_PATH)
	if frames == null:
		return
	var names: PackedStringArray = frames.get_animation_names()
	_expect(not frames.has_animation(&"default"), "no 'default' animation")
	_expect(names.size() == EXPECTED_ANIMATIONS.size(), "exactly %d animations (got %s)" % [EXPECTED_ANIMATIONS.size(), names])
	for anim_name: String in EXPECTED_ANIMATIONS:
		var spec: Array = EXPECTED_ANIMATIONS[anim_name]
		_expect(frames.has_animation(anim_name), "animation '%s' exists" % anim_name)
		if not frames.has_animation(anim_name):
			continue
		var count: int = frames.get_frame_count(anim_name)
		var fps: float = frames.get_animation_speed(anim_name)
		var loops: bool = frames.get_animation_loop(anim_name)
		_expect(count == spec[0], "'%s' has %d frames (got %d)" % [anim_name, spec[0], count])
		_expect(is_equal_approx(fps, spec[1]), "'%s' runs at %s fps (got %s)" % [anim_name, spec[1], fps])
		_expect(loops == spec[2], "'%s' loop == %s (got %s)" % [anim_name, spec[2], loops])
		for i: int in count:
			var tex: Texture2D = frames.get_frame_texture(anim_name, i)
			_expect(tex != null and tex.get_size() == Vector2(128, 128), "'%s' frame %d is a 128x128 texture" % [anim_name, i])


func _check_music() -> void:
	var stream: AudioStreamWAV = load(MUSIC_PATH) as AudioStreamWAV
	_expect(stream != null, "music loads as AudioStreamWAV")
	if stream == null:
		return
	_expect(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "music loop_mode is LOOP_FORWARD (got %d)" % stream.loop_mode)
	_expect(stream.loop_begin == 0, "music loop_begin == 0 (got %d)" % stream.loop_begin)
	var total_frames: int = roundi(stream.get_length() * stream.mix_rate)
	_expect(absi(stream.loop_end - total_frames) <= 1, "music loop_end covers whole file (loop_end %d, frames %d)" % [stream.loop_end, total_frames])


func _check_textures() -> void:
	for path: String in EXPECTED_TEXTURES:
		var tex: Texture2D = load(path) as Texture2D
		_expect(tex != null, "texture loads: %s" % path)
		if tex != null:
			var size: Vector2i = Vector2i(tex.get_size())
			_expect(size == EXPECTED_TEXTURES[path], "%s is %s (got %s)" % [path, EXPECTED_TEXTURES[path], size])
