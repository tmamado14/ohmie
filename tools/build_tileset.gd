extends SceneTree
## Builds res://resources/tileset.tres from res://assets/environment/tileset_32px.png.
##
## Run from the project root:
##   godot --headless --path . --script res://tools/build_tileset.gd
##
## Tile ID n (0-15) lives at atlas coords (n % 4, n / 4) in atlas source 0.
## Physics layer 0 (collision_layer 1, "world"): full-cell squares on solid tiles.
## Physics layer 1 (collision_layer 2, "one-way platform"): one-way strip on platform tiles.
## Both physics layers have collision_mask 0: tiles never scan for other bodies, so a
## body that clears bit 2 from its own mask really does pass through one-way platforms.

const TEXTURE_PATH: String = "res://assets/environment/tileset_32px.png"
const OUTPUT_PATH: String = "res://resources/tileset.tres"
const SOURCE_ID: int = 0
const TILE_PX: int = 32
const ATLAS_COLUMNS: int = 4
const TILE_COUNT: int = 16

const PHYSICS_LAYER_WORLD: int = 0
const PHYSICS_LAYER_ONE_WAY: int = 1
const COLLISION_BIT_WORLD: int = 1
const COLLISION_BIT_ONE_WAY: int = 2

const SOLID_TILE_IDS: Array[int] = [0, 1, 2, 3, 12, 13, 14]
const ONE_WAY_TILE_IDS: Array[int] = [4, 5, 6, 7]

## Platform strip covers pixel rows 7 to 20 inclusive (top edge y=7, bottom edge y=21).
const ONE_WAY_TOP_ROW: int = 7
const ONE_WAY_BOTTOM_ROW: int = 20


func _init() -> void:
	var exit_code: int = _build()
	quit(exit_code)


func _build() -> int:
	var texture: Texture2D = load(TEXTURE_PATH) as Texture2D
	if texture == null:
		push_error("build_tileset: could not load %s" % TEXTURE_PATH)
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
	tile_set.add_source(source, SOURCE_ID)

	for tile_id: int in TILE_COUNT:
		var coords: Vector2i = Vector2i(tile_id % ATLAS_COLUMNS, tile_id / ATLAS_COLUMNS)
		source.create_tile(coords)
		var data: TileData = source.get_tile_data(coords, 0)
		if tile_id in SOLID_TILE_IDS:
			_add_polygon(data, PHYSICS_LAYER_WORLD, _full_square(), false)
		elif tile_id in ONE_WAY_TILE_IDS:
			_add_polygon(data, PHYSICS_LAYER_ONE_WAY, _one_way_strip(), true)

	var err: Error = ResourceSaver.save(tile_set, OUTPUT_PATH)
	if err != OK:
		push_error("build_tileset: save failed (%s)" % error_string(err))
		return 1
	print("build_tileset: saved %s with %d tiles" % [OUTPUT_PATH, source.get_tiles_count()])
	return 0


func _add_polygon(data: TileData, layer: int, points: PackedVector2Array, one_way: bool) -> void:
	data.add_collision_polygon(layer)
	var index: int = data.get_collision_polygons_count(layer) - 1
	data.set_collision_polygon_points(layer, index, points)
	data.set_collision_polygon_one_way(layer, index, one_way)


## Polygon points are relative to the tile centre, so a 32 px tile spans -16..16.
func _full_square() -> PackedVector2Array:
	var h: float = TILE_PX / 2.0
	return PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])


func _one_way_strip() -> PackedVector2Array:
	var h: float = TILE_PX / 2.0
	var top: float = ONE_WAY_TOP_ROW - h
	var bottom: float = ONE_WAY_BOTTOM_ROW + 1 - h
	return PackedVector2Array([Vector2(-h, top), Vector2(h, top), Vector2(h, bottom), Vector2(-h, bottom)])
