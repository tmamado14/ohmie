extends SceneTree
## Verifies the resources built from the new (2x) art pack.
##
## Run from the project root (exit code 0 = all checks pass, 1 = at least one failed):
##   godot --headless --path . --script res://tools/check_resources.gd
##
## Covers: the five world TileSets, the 256x256 player SpriteFrames (including the shared
## feet baseline), the theme track, the six music loops and the generated PNGs in assets/processed/.

const TILE_PX: int = 64
const HALF: float = 32.0
const SOLID_TILE_IDS: Array[int] = [0, 1, 2, 3, 12, 13, 14]
const ONE_WAY_TILE_IDS: Array[int] = [4, 5, 6, 7]
## One-way collision strip rows (surface 7 px below the cell top on screen).
const ONE_WAY_TOP_ROW: int = 14
const ONE_WAY_BOTTOM_ROW: int = 36
## Rows the platform art occupies in the atlas.
const PLATFORM_ART_TOP_ROW: int = 18
const PLATFORM_ART_BOTTOM_ROW: int = 40
## Platform art is drawn this far up (TileData.texture_origin.y) so its top meets the strip.
const PLATFORM_ART_SHIFT_UP: int = 4

## theme -> atlas texture path
const TILESETS: Dictionary = {
	"old_workshop": "res://assets/environment/tileset_64px.png",
	"copper_foundry": "res://assets/worlds/level_02_copper_foundry/tileset_64px.png",
	"substation_switchyard": "res://assets/worlds/level_03_substation_switchyard/tileset_64px.png",
	"signal_clocktower": "res://assets/worlds/level_04_signal_clocktower/tileset_64px.png",
	"high_voltage_transmitter": "res://assets/worlds/level_05_high_voltage_transmitter/tileset_64px.png",
}

const FRAMES_PATH: String = "res://resources/themes/player_frames.tres"
const FRAME_PX: int = 256
## Row of the lowest shoe pixel (alpha >= 0.5) shared by every grounded pose.
const FEET_BASELINE_ROW: int = 249
## Airborne pose, deliberately not on the baseline.
const AIRBORNE_ANIMATIONS: Array[String] = ["jump"]

## name -> [frame count, fps, loop]
const EXPECTED_ANIMATIONS: Dictionary = {
	"idle": [1, 1.0, true],
	"run": [2, 8.0, true],
	"jump": [1, 1.0, false],
	"victory": [1, 1.0, false],
	"back": [1, 1.0, false],
	"notice": [1, 1.0, false],
}

const MUSIC_PATHS: Array[String] = [
	"res://assets/audio/music_old_workshop_swing_16s.wav",
	"res://assets/audio/music_level_02_copper_foundry_16s.wav",
	"res://assets/audio/music_level_03_substation_switchyard_16s.wav",
	"res://assets/audio/music_level_04_signal_clocktower_16s.wav",
	"res://assets/audio/music_level_05_high_voltage_transmitter_16s.wav",
	"res://assets/audio/music_copper_works_loop_16s.wav",
]

## The game's theme (menus and the Old Workshop), the user's own track.
const THEME_MUSIC_PATH: String = "res://assets/audio/Ohmie BGM.mp3"
const THEME_MUSIC_MIN_SECONDS: float = 60.0

## path -> size
const EXPECTED_TEXTURES: Dictionary = {
	"res://assets/processed/socket_empty.png": Vector2i(208, 144),
	"res://assets/processed/socket_highlight.png": Vector2i(208, 144),
	"res://assets/processed/fixed_backing.png": Vector2i(208, 144),
	"res://assets/processed/pickup_highlight.png": Vector2i(208, 144),
	"res://assets/processed/node_dot.png": Vector2i(32, 32),
	"res://assets/processed/exit_door_open_aligned.png": Vector2i(216, 320),
	# From tools/generate_parts_art.gd.
	"res://assets/processed/part_battery.png": Vector2i(192, 128),
	"res://assets/processed/part_resistor_blank.png": Vector2i(192, 128),
	"res://assets/processed/meter_ammeter.png": Vector2i(208, 144),
	"res://assets/processed/meter_voltmeter.png": Vector2i(208, 144),
	"res://assets/processed/meter_ohmmeter.png": Vector2i(208, 144),
	"res://assets/processed/lamp_off.png": Vector2i(208, 144),
	"res://assets/processed/lamp_on.png": Vector2i(208, 144),
	"res://assets/processed/lamp_blown.png": Vector2i(208, 144),
	"res://assets/processed/polarity_plus.png": Vector2i(32, 32),
	"res://assets/processed/polarity_minus.png": Vector2i(32, 32),
}

## Carried parts: leads on rows 50-63 (centre y 57) from x 7 to x 185, like the resistor icons.
const PART_PATHS: Array[String] = [
	"res://assets/processed/part_battery.png",
	"res://assets/processed/part_resistor_blank.png",
]
## Board fixtures: copper stubs on rows 65-78 (centre y 72) meeting both side edges, like the socket.
const FIXTURE_PATHS: Array[String] = [
	"res://assets/processed/meter_ammeter.png",
	"res://assets/processed/meter_voltmeter.png",
	"res://assets/processed/meter_ohmmeter.png",
	"res://assets/processed/lamp_off.png",
	"res://assets/processed/lamp_on.png",
	"res://assets/processed/lamp_blown.png",
]

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	for theme: String in TILESETS:
		_check_tileset(theme, TILESETS[theme])
		_check_platform_art_rows(theme, TILESETS[theme])
	_check_frames()
	_check_music()
	_check_textures()
	_check_pickup_highlight_centre()
	_check_part_leads()
	_check_fixture_stubs()
	print("check_resources: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func _check_tileset(theme: String, texture_path: String) -> void:
	var path: String = "res://resources/themes/%s/tileset.tres" % theme
	var tile_set: TileSet = load(path) as TileSet
	_expect(tile_set != null, "TileSet loads from %s" % path)
	if tile_set == null:
		return
	_expect(tile_set.tile_size == Vector2i(TILE_PX, TILE_PX), "%s: tile_size is 64x64" % theme)
	_expect(tile_set.get_physics_layers_count() == 2, "%s: 2 physics layers" % theme)
	if tile_set.get_physics_layers_count() == 2:
		_expect(tile_set.get_physics_layer_collision_layer(0) == 1, "%s: physics layer 0 collision_layer == 1" % theme)
		_expect(tile_set.get_physics_layer_collision_layer(1) == 2, "%s: physics layer 1 collision_layer == 2" % theme)
		_expect(tile_set.get_physics_layer_collision_mask(0) == 0, "%s: physics layer 0 collision_mask == 0" % theme)
		_expect(tile_set.get_physics_layer_collision_mask(1) == 0, "%s: physics layer 1 collision_mask == 0" % theme)
	_expect(tile_set.get_source_count() == 1 and tile_set.has_source(0), "%s: exactly one source, id 0" % theme)
	if not tile_set.has_source(0):
		return
	var source: TileSetAtlasSource = tile_set.get_source(0) as TileSetAtlasSource
	_expect(source != null, "%s: source 0 is a TileSetAtlasSource" % theme)
	if source == null:
		return
	_expect(source.texture != null and source.texture.resource_path == texture_path, "%s: texture is %s" % [theme, texture_path])
	_expect(source.texture_region_size == Vector2i(TILE_PX, TILE_PX), "%s: texture_region_size is 64x64" % theme)
	_expect(source.use_texture_padding, "%s: use_texture_padding is on" % theme)
	_expect(source.get_tiles_count() == 16, "%s: 16 tiles (got %d)" % [theme, source.get_tiles_count()])

	var one_way_rect: Rect2 = Rect2(-HALF, ONE_WAY_TOP_ROW - HALF, TILE_PX, ONE_WAY_BOTTOM_ROW - ONE_WAY_TOP_ROW + 1)
	for tile_id: int in 16:
		var coords: Vector2i = Vector2i(tile_id % 4, tile_id / 4)
		_expect(source.has_tile(coords), "%s: tile %d exists at %s" % [theme, tile_id, coords])
		if not source.has_tile(coords):
			continue
		var data: TileData = source.get_tile_data(coords, 0)
		var world_count: int = data.get_collision_polygons_count(0)
		var one_way_count: int = data.get_collision_polygons_count(1)
		if tile_id in SOLID_TILE_IDS:
			_expect(world_count == 1 and one_way_count == 0, "%s tile %d: 1 polygon on layer 0, 0 on layer 1 (got %d, %d)" % [theme, tile_id, world_count, one_way_count])
			if world_count == 1:
				var pts: PackedVector2Array = data.get_collision_polygon_points(0, 0)
				_expect(_bounds(pts) == Rect2(-HALF, -HALF, TILE_PX, TILE_PX), "%s tile %d: full 64x64 square (got %s)" % [theme, tile_id, _bounds(pts)])
				_expect(not data.is_collision_polygon_one_way(0, 0), "%s tile %d: world polygon is not one-way" % [theme, tile_id])
		elif tile_id in ONE_WAY_TILE_IDS:
			_expect(world_count == 0 and one_way_count == 1, "%s tile %d: 0 polygons on layer 0, 1 on layer 1 (got %d, %d)" % [theme, tile_id, world_count, one_way_count])
			if one_way_count == 1:
				_expect(data.is_collision_polygon_one_way(1, 0), "%s tile %d: layer 1 polygon is one-way" % [theme, tile_id])
				var pts: PackedVector2Array = data.get_collision_polygon_points(1, 0)
				_expect(_bounds(pts) == one_way_rect, "%s tile %d: strip covers rows 14-36 (got %s)" % [theme, tile_id, _bounds(pts)])
			_expect(data.texture_origin == Vector2i(0, PLATFORM_ART_SHIFT_UP), "%s tile %d: texture_origin is (0, %d) (got %s)" % [theme, tile_id, PLATFORM_ART_SHIFT_UP, data.texture_origin])
			_expect(PLATFORM_ART_TOP_ROW - PLATFORM_ART_SHIFT_UP == ONE_WAY_TOP_ROW, "%s tile %d: drawn art top meets strip top" % [theme, tile_id])
		else:
			_expect(world_count == 0 and one_way_count == 0, "%s tile %d: no collision (got %d, %d)" % [theme, tile_id, world_count, one_way_count])


## Confirms the platform tiles' opaque pixels span exactly rows 18-40 (drawn 4 px higher).
func _check_platform_art_rows(theme: String, texture_path: String) -> void:
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path(texture_path))
	_expect(img != null and not img.is_empty(), "%s: atlas image loads" % theme)
	if img == null or img.is_empty():
		return
	for tile_id: int in ONE_WAY_TILE_IDS:
		var ox: int = (tile_id % 4) * TILE_PX
		var oy: int = (tile_id / 4) * TILE_PX
		var top: int = TILE_PX
		var bottom: int = -1
		for y: int in TILE_PX:
			for x: int in TILE_PX:
				if img.get_pixel(ox + x, oy + y).a > 0.0:
					top = mini(top, y)
					bottom = maxi(bottom, y)
		_expect(top == PLATFORM_ART_TOP_ROW and bottom == PLATFORM_ART_BOTTOM_ROW, "%s tile %d art spans rows %d-%d (expected 18-40)" % [theme, tile_id, top, bottom])


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
			_expect(tex != null and Vector2i(tex.get_size()) == Vector2i(FRAME_PX, FRAME_PX), "'%s' frame %d is a 256x256 texture" % [anim_name, i])
			if tex == null:
				continue
			var feet: int = _feet_row(tex)
			if anim_name in AIRBORNE_ANIMATIONS:
				print("check_resources: '%s' frame %d lowest opaque row %d (airborne, not checked)" % [anim_name, i, feet])
			else:
				_expect(feet == FEET_BASELINE_ROW, "'%s' frame %d feet on row %d (got %d)" % [anim_name, i, FEET_BASELINE_ROW, feet])


## Lowest row (in the 256x256 frame as drawn) holding a pixel with alpha >= 0.5. Reads the
## source PNG directly, then applies the AtlasTexture's region and margin if there is one.
func _feet_row(tex: Texture2D) -> int:
	var source_path: String = tex.resource_path
	var region: Rect2i = Rect2i(0, 0, FRAME_PX, FRAME_PX)
	var draw_y: int = 0
	var atlas: AtlasTexture = tex as AtlasTexture
	if atlas != null:
		source_path = atlas.atlas.resource_path
		region = Rect2i(atlas.region)
		draw_y = int(atlas.margin.position.y)
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path(source_path))
	if img == null or img.is_empty():
		return -1
	for y: int in range(region.end.y - 1, region.position.y - 1, -1):
		for x: int in range(region.position.x, region.end.x):
			if img.get_pixel(x, y).a >= 0.5:
				return y - region.position.y + draw_y
	return -1


func _check_music() -> void:
	var theme: AudioStreamMP3 = load(THEME_MUSIC_PATH) as AudioStreamMP3
	_expect(theme != null, "%s loads as AudioStreamMP3" % THEME_MUSIC_PATH)
	if theme != null:
		_expect(theme.loop, "%s loops" % THEME_MUSIC_PATH)
		_expect(theme.get_length() > THEME_MUSIC_MIN_SECONDS, "%s is longer than %.0f s (got %.1f s)" % [
				THEME_MUSIC_PATH, THEME_MUSIC_MIN_SECONDS, theme.get_length()])
	for path: String in MUSIC_PATHS:
		var stream: AudioStreamWAV = load(path) as AudioStreamWAV
		_expect(stream != null, "%s loads as AudioStreamWAV" % path)
		if stream == null:
			continue
		_expect(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s loop_mode is LOOP_FORWARD (got %d)" % [path, stream.loop_mode])
		_expect(stream.loop_begin == 0, "%s loop_begin == 0 (got %d)" % [path, stream.loop_begin])
		var total_frames: int = roundi(stream.get_length() * stream.mix_rate)
		_expect(absi(stream.loop_end - total_frames) <= 1, "%s loop_end covers whole file (loop_end %d, frames %d)" % [path, stream.loop_end, total_frames])


func _check_textures() -> void:
	for path: String in EXPECTED_TEXTURES:
		var tex: Texture2D = load(path) as Texture2D
		_expect(tex != null, "texture loads: %s" % path)
		if tex != null:
			var size: Vector2i = Vector2i(tex.get_size())
			_expect(size == EXPECTED_TEXTURES[path], "%s is %s (got %s)" % [path, EXPECTED_TEXTURES[path], size])


## The pickup highlight must not overlap any resistor icon drawn centred on it, at (8, 8).
func _check_pickup_highlight_centre() -> void:
	var path: String = "res://assets/processed/pickup_highlight.png"
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		_expect(false, "pickup_highlight.png loads as an image")
		return
	var dir: String = "res://assets/interactive/resistors/"
	var icon_paths: Array[String] = []
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".png"):
			icon_paths.append(dir + file)
	icon_paths.append_array(PART_PATHS)
	for icon_path: String in icon_paths:
		var file: String = icon_path.get_file()
		var icon: Image = Image.load_from_file(ProjectSettings.globalize_path(icon_path))
		if icon == null or icon.is_empty():
			_expect(false, "%s loads as an image" % file)
			continue
		var overlap: int = 0
		for y: int in icon.get_height():
			for x: int in icon.get_width():
				if icon.get_pixel(x, y).a > 0.0 and img.get_pixel(x + 8, y + 8).a > 0.0:
					overlap += 1
		_expect(overlap == 0, "pickup_highlight does not overlap %s drawn at (8, 8) (%d pixels overlap)" % [file, overlap])


func _load_image(path: String) -> Image:
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	_expect(img != null and not img.is_empty(), "%s loads as an image" % path)
	if img == null or img.is_empty():
		return null
	return img


## Leads of a carried part: opaque on rows 50-63 at both ends (x 7 and x 185), clear just
## outside them, so the part seats on the socket stubs exactly like a resistor icon.
func _check_part_leads() -> void:
	for path: String in PART_PATHS:
		var img: Image = _load_image(path)
		if img == null:
			continue
		for x: int in [7, 10, 182, 185]:
			_expect(img.get_pixel(x, 50).a > 0.5 and img.get_pixel(x, 63).a > 0.5, "%s: lead covers rows 50-63 at x %d" % [path, x])
			_expect(img.get_pixel(x, 49).a == 0.0 and img.get_pixel(x, 64).a == 0.0, "%s: lead is clear at rows 49 and 64 at x %d" % [path, x])
		_expect(img.get_pixel(6, 57).a == 0.0 and img.get_pixel(186, 57).a == 0.0, "%s: leads end at x 7 and x 185" % path)


## Stubs of a board fixture: opaque on rows 65-78 at both side edges, clear above and below.
func _check_fixture_stubs() -> void:
	for path: String in FIXTURE_PATHS:
		var img: Image = _load_image(path)
		if img == null:
			continue
		var right: int = img.get_width() - 1
		for x: int in [0, right]:
			_expect(img.get_pixel(x, 65).a > 0.5 and img.get_pixel(x, 72).a > 0.5 and img.get_pixel(x, 78).a > 0.5, "%s: stub covers rows 65-78 at x %d" % [path, x])
			_expect(img.get_pixel(x, 63).a == 0.0 and img.get_pixel(x, 80).a == 0.0, "%s: stub is clear at rows 63 and 80 at x %d" % [path, x])
