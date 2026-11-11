extends SceneTree
## Builds one TileSet per world from the new (2x) art pack in res://assets/.
##
## Run from the project root:
##   godot --headless --path . --script res://tools/build_tilesets.gd
##
## Writes res://resources/themes/<theme>/tileset.tres for every theme in THEMES.
##
## Layout matches the old set: tile ID n (0-15) lives at atlas coords (n % 4, n / 4) in
## atlas source 0. Tiles are 64x64 and are meant to be drawn by a TileMapLayer with
## scale (0.5, 0.5) and texture_filter = LINEAR, so one 64 px tile covers one 32 px cell.
##
## Physics layer 0 (collision_layer 1, "world"): full 64x64 square on solid tiles.
## Physics layer 1 (collision_layer 2, "one-way platform"): one-way strip on platform tiles.
## The platform art occupies rows 18-40 in all five sets, but levels assume the standing
## surface is 7 px below the 32 px cell top (row 14 at 2x). So the strip covers rows 14-36
## (same 23-row thickness) and the platform art is drawn 4 source px higher with
## TileData.texture_origin, so its top edge meets the strip's top.
## Both layers have collision_mask 0 (see docs/ASSETS.md for why).

const OUTPUT_DIR: String = "res://resources/themes/"
const SOURCE_ID: int = 0
const TILE_PX: int = 64
const ATLAS_COLUMNS: int = 4
const TILE_COUNT: int = 16

const PHYSICS_LAYER_WORLD: int = 0
const PHYSICS_LAYER_ONE_WAY: int = 1
const COLLISION_BIT_WORLD: int = 1
const COLLISION_BIT_ONE_WAY: int = 2

const SOLID_TILE_IDS: Array[int] = [0, 1, 2, 3, 12, 13, 14]
const ONE_WAY_TILE_IDS: Array[int] = [4, 5, 6, 7]

## Platform strip covers pixel rows 14 to 36 inclusive (top edge y=14, bottom edge y=37)
## of the 64 px tile. At scale 0.5 that is y 7.0 to 18.5 inside the 32 px cell.
const ONE_WAY_TOP_ROW: int = 14
const ONE_WAY_BOTTOM_ROW: int = 36
## Platform art (rows 18-40) is drawn this many source px higher to sit on the strip.
## Positive texture_origin.y moves the drawn texture up.
const ONE_WAY_ART_SHIFT_UP: int = 4

## theme name -> atlas texture
const THEMES: Dictionary = {
	"old_workshop": "res://assets/environment/tileset_64px.png",
	"copper_foundry": "res://assets/worlds/level_02_copper_foundry/tileset_64px.png",
	"substation_switchyard": "res://assets/worlds/level_03_substation_switchyard/tileset_64px.png",
	"signal_clocktower": "res://assets/worlds/level_04_signal_clocktower/tileset_64px.png",
	"high_voltage_transmitter": "res://assets/worlds/level_05_high_voltage_transmitter/tileset_64px.png",
}


func _init() -> void:
	var failures: int = 0
	for theme: String in THEMES:
		failures += _build(theme, THEMES[theme])
	quit(1 if failures > 0 else 0)


func _build(theme: String, texture_path: String) -> int:
	var texture: Texture2D = load(texture_path) as Texture2D
	if texture == null:
		push_error("build_tilesets: could not load %s" % texture_path)
		return 1
	if Vector2i(texture.get_size()) != Vector2i(TILE_PX * ATLAS_COLUMNS, TILE_PX * ATLAS_COLUMNS):
		push_error("build_tilesets: %s is %s, expected 256x256" % [texture_path, texture.get_size()])
		return 1

	var tile_set: TileSet = TileSet.new()
	tile_set.tile_size = Vector2i(TILE_PX, TILE_PX)

	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(PHYSICS_LAYER_WORLD, COLLISION_BIT_WORLD)
	tile_set.set_physics_layer_collision_mask(PHYSICS_LAYER_WORLD, 0)
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(PHYSICS_LAYER_ONE_WAY, COLLISION_BIT_ONE_WAY)
	tile_set.set_physics_layer_collision_mask(PHYSICS_LAYER_ONE_WAY, 0)

	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE_PX, TILE_PX)
	# Default, stated explicitly: pads each tile so Linear filtering does not bleed neighbours in.
	source.use_texture_padding = true
	tile_set.add_source(source, SOURCE_ID)

	for tile_id: int in TILE_COUNT:
		var coords: Vector2i = Vector2i(tile_id % ATLAS_COLUMNS, tile_id / ATLAS_COLUMNS)
		source.create_tile(coords)
		var data: TileData = source.get_tile_data(coords, 0)
		if tile_id in SOLID_TILE_IDS:
			_add_polygon(data, PHYSICS_LAYER_WORLD, _full_square(), false)
		elif tile_id in ONE_WAY_TILE_IDS:
			_add_polygon(data, PHYSICS_LAYER_ONE_WAY, _one_way_strip(), true)
			data.texture_origin = Vector2i(0, ONE_WAY_ART_SHIFT_UP)

	var dir: String = OUTPUT_DIR + theme + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var output_path: String = dir + "tileset.tres"
	var err: Error = ResourceSaver.save(tile_set, output_path)
	if err != OK:
		push_error("build_tilesets: save failed for %s (%s)" % [output_path, error_string(err)])
		return 1
	print("build_tilesets: saved %s with %d tiles" % [output_path, source.get_tiles_count()])
	return 0


func _add_polygon(data: TileData, layer: int, points: PackedVector2Array, one_way: bool) -> void:
	data.add_collision_polygon(layer)
	var index: int = data.get_collision_polygons_count(layer) - 1
	data.set_collision_polygon_points(layer, index, points)
	data.set_collision_polygon_one_way(layer, index, one_way)


## Polygon points are relative to the tile centre, so a 64 px tile spans -32..32.
func _full_square() -> PackedVector2Array:
	var h: float = TILE_PX / 2.0
	return PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])


func _one_way_strip() -> PackedVector2Array:
	var h: float = TILE_PX / 2.0
	var top: float = ONE_WAY_TOP_ROW - h
	var bottom: float = ONE_WAY_BOTTOM_ROW + 1 - h
	return PackedVector2Array([Vector2(-h, top), Vector2(h, top), Vector2(h, bottom), Vector2(-h, bottom)])
