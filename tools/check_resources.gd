extends SceneTree
## Verifies the resources built from the new (2x) art pack.
##
## Run from the project root (exit code 0 = all checks pass, 1 = at least one failed):
##   godot --headless --path . --script res://tools/check_resources.gd
##
## Covers: the five world TileSets and their composite atlases with the shelf platforms
## (tools/generate_platform_art.gd), the 256x256 player SpriteFrames (including the shared
## feet baseline), the theme track, the six music loops and the generated PNGs in assets/processed/.

const BuildTilesets := preload("res://tools/build_tilesets.gd")

const TILE_PX: int = 64
const HALF: float = 32.0
const ATLAS_PX: int = 256
const SOLID_TILE_IDS: Array[int] = [0, 1, 2, 3, 12, 13, 14]
const ONE_WAY_TILE_IDS: Array[int] = [4, 5, 6, 7]
const TILE_PLATFORM_LEFT: int = 4
const TILE_PLATFORM_MIDDLE: int = 5
const TILE_PLATFORM_RIGHT: int = 6
## One-way collision strip rows (surface 7 px below the cell top on screen).
const ONE_WAY_TOP_ROW: int = 14
const ONE_WAY_BOTTOM_ROW: int = 36
## Exact collision polygons (tile-centred points), as they have been since the strip moved to row 14.
const SOLID_POLYGON: Array[Vector2] = [Vector2(-32, -32), Vector2(32, -32), Vector2(32, 32), Vector2(-32, 32)]
const ONE_WAY_POLYGON: Array[Vector2] = [Vector2(-32, -18), Vector2(32, -18), Vector2(32, 5), Vector2(-32, 5)]
## The shelf art's top is authored on the strip's top row, so it is drawn unshifted.
const PLATFORM_TEXTURE_ORIGIN: Vector2i = Vector2i(0, 0)
## The drawn art top may differ from the strip top by at most this many source rows.
const PLATFORM_TOP_TOLERANCE: int = 1
## Per tile: the column range over which the plank's top must be exactly on the strip's top row
## (outside the rounded ends), so the walkable edge is straight and level across all four pieces.
const PLATFORM_FLAT_COLUMNS: Dictionary = {
	4: Vector2i(8, 63),
	5: Vector2i(0, 63),
	6: Vector2i(0, 55),
	7: Vector2i(8, 55),
}
## Largest per-channel difference (0-255, premultiplied RGB and alpha) allowed across a seam.
const SEAM_TOLERANCE: int = 8

## theme -> the pack's own atlas (the base the composite is copied from)
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
	# From tools/generate_electronics_art.gd.
	"res://assets/processed/diode_arrow_right.png": Vector2i(32, 32),
	"res://assets/processed/diode_arrow_left.png": Vector2i(32, 32),
	# The user's electronics set (World 2), used as is.
	"res://assets/interactive/electronics/parts/diode_rectifier.png": Vector2i(192, 128),
	"res://assets/interactive/electronics/parts/diode_signal.png": Vector2i(192, 128),
	"res://assets/interactive/electronics/parts/diode_schottky.png": Vector2i(192, 128),
	"res://assets/interactive/electronics/parts/diode_zener.png": Vector2i(192, 128),
}

## The user's axial diode pictures. Their leads are rows 51-62 (fully opaque 52-61, centre
## y 57.0) with rounded ends at x 7 and 184: inside the resistor's lead envelope (rows 50-63,
## x 7-185), so they seat on the socket stubs like a resistor.
const DIODE_PART_PATHS: Array[String] = [
	"res://assets/interactive/electronics/parts/diode_rectifier.png",
	"res://assets/interactive/electronics/parts/diode_signal.png",
	"res://assets/interactive/electronics/parts/diode_schottky.png",
	"res://assets/interactive/electronics/parts/diode_zener.png",
]
const DIODE_LEAD_SOLID_ROWS: Vector2i = Vector2i(52, 61)
const DIODE_LEAD_ENDS: Vector2i = Vector2i(7, 184)
## Safe text rect inside the diode pictures' value plaque (interior x 60-131, y 98-121).
const DIODE_PLAQUE_TEXT_RECT: Rect2i = Rect2i(62, 99, 68, 22)
const PLAQUE_MIN_LUMINANCE: float = 0.7

## Diode direction badges: the same brass disc as polarity_plus.png, ink marks mirrored.
const DIODE_BADGE_RIGHT: String = "res://assets/processed/diode_arrow_right.png"
const DIODE_BADGE_LEFT: String = "res://assets/processed/diode_arrow_left.png"
const POLARITY_PLUS: String = "res://assets/processed/polarity_plus.png"
## Solid ink (the ink colour is about 0.10); compared inside the disc's rim only, because the
## disc is lit from the upper left and is deliberately not mirrored.
const BADGE_INK_LUMINANCE: float = 0.12
const BADGE_MARK_RADIUS: float = 11.0
## Mirrored ink pixels may differ at a couple of anti-aliased edges over the unevenly lit disc.
const BADGE_MIRROR_TOLERANCE: int = 2
## Faint shadow pixels (alpha 4-5) sit beside the diode leads; "clear" means below this.
const DIODE_CLEAR_ALPHA: float = 16.0 / 255.0
## Three rows above the centre line, the right-pointing triangle is still ink at x 12 and the
## gap before the cathode bar is clear at x 18.
const BADGE_TRIANGLE_PROBE: Vector2i = Vector2i(12, 13)
const BADGE_GAP_PROBE: Vector2i = Vector2i(18, 13)

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
	_check_builder_constants()
	for theme: String in TILESETS:
		var composite_path: String = BuildTilesets.COMPOSITE_PATH_FORMAT % theme
		_check_tileset(theme, composite_path)
		_check_composite_atlas(theme, TILESETS[theme], composite_path)
	_check_frames()
	_check_music()
	_check_textures()
	_check_pickup_highlight_centre()
	_check_part_leads()
	_check_fixture_stubs()
	_check_diode_parts()
	_check_diode_badges()
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
				_expect(pts == PackedVector2Array(SOLID_POLYGON), "%s tile %d: solid polygon points unchanged (got %s)" % [theme, tile_id, pts])
				_expect(not data.is_collision_polygon_one_way(0, 0), "%s tile %d: world polygon is not one-way" % [theme, tile_id])
		elif tile_id in ONE_WAY_TILE_IDS:
			_expect(world_count == 0 and one_way_count == 1, "%s tile %d: 0 polygons on layer 0, 1 on layer 1 (got %d, %d)" % [theme, tile_id, world_count, one_way_count])
			if one_way_count == 1:
				_expect(data.is_collision_polygon_one_way(1, 0), "%s tile %d: layer 1 polygon is one-way" % [theme, tile_id])
				var pts: PackedVector2Array = data.get_collision_polygon_points(1, 0)
				_expect(_bounds(pts) == one_way_rect, "%s tile %d: strip covers rows 14-36 (got %s)" % [theme, tile_id, _bounds(pts)])
				_expect(pts == PackedVector2Array(ONE_WAY_POLYGON), "%s tile %d: one-way polygon points unchanged (got %s)" % [theme, tile_id, pts])
			_expect(data.texture_origin == PLATFORM_TEXTURE_ORIGIN, "%s tile %d: texture_origin is %s (got %s)" % [theme, tile_id, PLATFORM_TEXTURE_ORIGIN, data.texture_origin])
		else:
			_expect(world_count == 0 and one_way_count == 0, "%s tile %d: no collision (got %d, %d)" % [theme, tile_id, world_count, one_way_count])


## The builder's own constants must still describe the same strip and art placement.
func _check_builder_constants() -> void:
	_expect(BuildTilesets.ONE_WAY_TOP_ROW == ONE_WAY_TOP_ROW and BuildTilesets.ONE_WAY_BOTTOM_ROW == ONE_WAY_BOTTOM_ROW,
			"build_tilesets.gd: strip rows are %d-%d" % [ONE_WAY_TOP_ROW, ONE_WAY_BOTTOM_ROW])
	_expect(BuildTilesets.PLATFORM_TEXTURE_ORIGIN == PLATFORM_TEXTURE_ORIGIN, "build_tilesets.gd: platform texture_origin is %s" % PLATFORM_TEXTURE_ORIGIN)
	_expect(BuildTilesets.SOLID_TILE_IDS == SOLID_TILE_IDS and BuildTilesets.ONE_WAY_TILE_IDS == ONE_WAY_TILE_IDS, "build_tilesets.gd: solid and one-way tile IDs unchanged")
	_expect(BuildTilesets.THEMES == TILESETS, "build_tilesets.gd: same five themes and pack atlases")


## The composite atlas (tools/generate_platform_art.gd): 256x256, a pixel copy of the pack atlas
## outside the platform cells, shelf art whose top sits on the strip's top row, and no seams.
func _check_composite_atlas(theme: String, pack_path: String, composite_path: String) -> void:
	var texture: Texture2D = load(composite_path) as Texture2D
	_expect(texture != null and Vector2i(texture.get_size()) == Vector2i(ATLAS_PX, ATLAS_PX), "%s: composite texture %s loads at 256x256" % [theme, composite_path])
	var composite: Image = _load_image(composite_path)
	var pack: Image = _load_image(pack_path)
	if composite == null or pack == null:
		return
	composite.convert(Image.FORMAT_RGBA8)
	pack.convert(Image.FORMAT_RGBA8)
	_expect(composite.get_size() == Vector2i(ATLAS_PX, ATLAS_PX), "%s: composite image is 256x256 (got %s)" % [theme, composite.get_size()])
	if composite.get_size() != pack.get_size():
		return

	for tile_id: int in 16:
		if tile_id in ONE_WAY_TILE_IDS:
			continue
		var origin: Vector2i = _cell_origin(tile_id)
		var differing: int = 0
		for y: int in TILE_PX:
			for x: int in TILE_PX:
				if composite.get_pixel(origin.x + x, origin.y + y) != pack.get_pixel(origin.x + x, origin.y + y):
					differing += 1
		_expect(differing == 0, "%s tile %d: composite cell is pixel-identical to the pack (%d pixels differ)" % [theme, tile_id, differing])

	for tile_id: int in ONE_WAY_TILE_IDS:
		var origin: Vector2i = _cell_origin(tile_id)
		var opaque_top: int = TILE_PX
		var any_top: int = TILE_PX
		for y: int in TILE_PX:
			for x: int in TILE_PX:
				var a: float = composite.get_pixel(origin.x + x, origin.y + y).a
				if a > 0.0:
					any_top = mini(any_top, y)
				if a >= 0.5:
					opaque_top = mini(opaque_top, y)
		# A positive texture_origin.y draws the art higher.
		var drawn_top: int = opaque_top - PLATFORM_TEXTURE_ORIGIN.y
		_expect(absi(drawn_top - ONE_WAY_TOP_ROW) <= PLATFORM_TOP_TOLERANCE, "%s tile %d: drawn art top row %d is on the strip top %d" % [theme, tile_id, drawn_top, ONE_WAY_TOP_ROW])
		_expect(any_top - PLATFORM_TEXTURE_ORIGIN.y >= ONE_WAY_TOP_ROW - PLATFORM_TOP_TOLERANCE, "%s tile %d: nothing drawn above row %d (first pixel on row %d)" % [theme, tile_id, ONE_WAY_TOP_ROW - PLATFORM_TOP_TOLERANCE, any_top])
		var flat: Vector2i = PLATFORM_FLAT_COLUMNS[tile_id]
		var not_level: int = 0
		for x: int in range(flat.x, flat.y + 1):
			var above: float = composite.get_pixel(origin.x + x, origin.y + opaque_top - 1).a if opaque_top > 0 else 0.0
			if composite.get_pixel(origin.x + x, origin.y + opaque_top).a < 0.5 or above >= 0.5:
				not_level += 1
		_expect(not_level == 0, "%s tile %d: plank top is level on row %d across columns %d-%d (%d columns off)" % [theme, tile_id, opaque_top, flat.x, flat.y, not_level])

	_expect_seam(theme, composite, TILE_PLATFORM_MIDDLE, TILE_PLATFORM_MIDDLE, "middle|middle")
	_expect_seam(theme, composite, TILE_PLATFORM_LEFT, TILE_PLATFORM_MIDDLE, "left|middle")
	_expect_seam(theme, composite, TILE_PLATFORM_MIDDLE, TILE_PLATFORM_RIGHT, "middle|right")


## Right-most column of `left_tile` against the left-most column of `right_tile`.
func _expect_seam(theme: String, atlas: Image, left_tile: int, right_tile: int, label: String) -> void:
	var a_origin: Vector2i = _cell_origin(left_tile) + Vector2i(TILE_PX - 1, 0)
	var b_origin: Vector2i = _cell_origin(right_tile)
	var worst: int = 0
	for y: int in TILE_PX:
		var a: Color = atlas.get_pixel(a_origin.x, a_origin.y + y)
		var b: Color = atlas.get_pixel(b_origin.x, b_origin.y + y)
		worst = maxi(worst, _channel_difference(a, b))
	_expect(worst <= SEAM_TOLERANCE, "%s: %s seam differs by at most %d per channel (got %d)" % [theme, label, SEAM_TOLERANCE, worst])


## Largest difference over premultiplied R, G, B and alpha, in 0-255 levels.
func _channel_difference(a: Color, b: Color) -> int:
	var d: float = maxf(absf(a.r * a.a - b.r * b.a), absf(a.g * a.a - b.g * b.a))
	d = maxf(d, maxf(absf(a.b * a.a - b.b * b.a), absf(a.a - b.a)))
	return roundi(d * 255.0)


func _cell_origin(tile_id: int) -> Vector2i:
	return Vector2i(tile_id % 4, tile_id / 4) * TILE_PX


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


## The user's diode pictures: leads inside the resistor's lead envelope (so they seat on the
## socket stubs at the resistor offset (8, 15)), lead ends at x 7 and 184, and a clear plaque
## text rect.
func _check_diode_parts() -> void:
	for path: String in DIODE_PART_PATHS:
		var img: Image = _load_image(path)
		if img == null:
			continue
		img.convert(Image.FORMAT_RGBA8)
		for x: int in [10, 20, 172, 182]:
			var solid: bool = true
			for y: int in range(DIODE_LEAD_SOLID_ROWS.x, DIODE_LEAD_SOLID_ROWS.y + 1):
				solid = solid and img.get_pixel(x, y).a > 0.5
			_expect(solid, "%s: lead opaque on rows %d-%d at x %d" % [path, DIODE_LEAD_SOLID_ROWS.x, DIODE_LEAD_SOLID_ROWS.y, x])
			_expect(img.get_pixel(x, 49).a < DIODE_CLEAR_ALPHA and img.get_pixel(x, 64).a < DIODE_CLEAR_ALPHA, "%s: lead inside rows 50-63 at x %d" % [path, x])
		_expect(img.get_pixel(DIODE_LEAD_ENDS.x, 57).a > 0.5 and img.get_pixel(DIODE_LEAD_ENDS.y, 57).a > 0.5, "%s: leads reach x %d and x %d" % [path, DIODE_LEAD_ENDS.x, DIODE_LEAD_ENDS.y])
		_expect(img.get_pixel(DIODE_LEAD_ENDS.x - 2, 57).a < DIODE_CLEAR_ALPHA and img.get_pixel(DIODE_LEAD_ENDS.y + 2, 57).a < DIODE_CLEAR_ALPHA, "%s: leads end within the resistor's x 7-185" % path)
		var dark: int = 0
		for y: int in range(DIODE_PLAQUE_TEXT_RECT.position.y, DIODE_PLAQUE_TEXT_RECT.end.y):
			for x: int in range(DIODE_PLAQUE_TEXT_RECT.position.x, DIODE_PLAQUE_TEXT_RECT.end.x):
				var c: Color = img.get_pixel(x, y)
				if c.a < 0.99 or c.get_luminance() < PLAQUE_MIN_LUMINANCE:
					dark += 1
		_expect(dark == 0, "%s: plaque text rect %s is clear cream (%d pixels not)" % [path, DIODE_PLAQUE_TEXT_RECT, dark])


## The diode badges share polarity_plus.png's disc (identical alpha), their ink marks are
## mirror images, and the right one points right.
func _check_diode_badges() -> void:
	var right: Image = _load_image(DIODE_BADGE_RIGHT)
	var left: Image = _load_image(DIODE_BADGE_LEFT)
	var plus: Image = _load_image(POLARITY_PLUS)
	if right == null or left == null or plus == null:
		return
	for img: Image in [right, left, plus]:
		img.convert(Image.FORMAT_RGBA8)
	var alpha_diff: int = 0
	var mirror_diff: int = 0
	var w: int = right.get_width()
	for y: int in right.get_height():
		for x: int in w:
			if absf(right.get_pixel(x, y).a - plus.get_pixel(x, y).a) > 0.004 or absf(left.get_pixel(x, y).a - plus.get_pixel(x, y).a) > 0.004:
				alpha_diff += 1
			var inside_rim: bool = Vector2(x + 0.5, y + 0.5).distance_to(Vector2(w, right.get_height()) * 0.5) < BADGE_MARK_RADIUS
			if inside_rim and _badge_ink(right, x, y) != _badge_ink(left, w - 1 - x, y):
				mirror_diff += 1
	_expect(alpha_diff == 0, "diode badges have polarity_plus.png's disc outline (%d alpha pixels differ)" % alpha_diff)
	_expect(mirror_diff <= BADGE_MIRROR_TOLERANCE, "diode badge ink marks are mirror images (%d pixels differ, %d allowed)" % [mirror_diff, BADGE_MIRROR_TOLERANCE])
	_expect(_badge_ink(right, BADGE_TRIANGLE_PROBE.x, BADGE_TRIANGLE_PROBE.y) and not _badge_ink(right, BADGE_GAP_PROBE.x, BADGE_GAP_PROBE.y),
			"diode_arrow_right.png points right (triangle on the left, cathode bar on the right)")


func _badge_ink(img: Image, x: int, y: int) -> bool:
	var c: Color = img.get_pixel(x, y)
	return c.a > 0.5 and c.get_luminance() < BADGE_INK_LUMINANCE
