class_name RoomTiles
extends TileMapLayer
## Fills this layer from a level's tile characters (GDD section 6).
##
## Uses the room theme's TileSet (res://resources/themes/<world>/tileset.tres):
## one atlas source, id 0, where tile ID n sits at atlas coords (n % 4, n / 4).
## Its tiles are 64 px; the layer is drawn at scale 0.5 so a cell is 32 px.

const SOURCE_ID: int = 0
const ATLAS_COLUMNS: int = 4
const NO_TILE: int = -1

const TILE_GROUND_TOP_LEFT: int = 0
const TILE_GROUND_TOP: int = 1
const TILE_GROUND_TOP_RIGHT: int = 2
const TILE_GROUND_FILL: int = 3
const TILE_PLATFORM_LEFT: int = 4
const TILE_PLATFORM_MIDDLE: int = 5
const TILE_PLATFORM_RIGHT: int = 6
const TILE_PLATFORM_SINGLE: int = 7
const TILE_WALL_PANEL: int = 12
const TILE_WARNING_PANEL: int = 13
const TILE_REINFORCED_BLOCK: int = 14
const TILE_SUPPORT_BEAM: int = 15

const CHAR_EMPTY: String = "."
const CHAR_GROUND: String = "#"
const CHAR_PLATFORM: String = "="
const CHAR_BLOCK: String = "B"
const CHAR_WALL: String = "W"
const CHAR_WARNING: String = "!"
const CHAR_BEAM: String = "|"
## Characters that count as solid when choosing ground corner tiles.
const SOLID_CHARACTERS: String = "#BW!"


## Clears the layer and sets one cell per non-empty tile character.
func build(rows: PackedStringArray) -> void:
	clear()
	for y: int in rows.size():
		for x: int in rows[y].length():
			var tile_id: int = _tile_id_at(rows, x, y)
			if tile_id != NO_TILE:
				set_cell(Vector2i(x, y), SOURCE_ID, atlas_coords_for(tile_id))


static func atlas_coords_for(tile_id: int) -> Vector2i:
	return Vector2i(tile_id % ATLAS_COLUMNS, floori(float(tile_id) / ATLAS_COLUMNS))


func _tile_id_at(rows: PackedStringArray, x: int, y: int) -> int:
	match rows[y][x]:
		CHAR_GROUND:
			return _ground_tile(rows, x, y)
		CHAR_PLATFORM:
			return _platform_tile(rows, x, y)
		CHAR_BLOCK:
			return TILE_REINFORCED_BLOCK
		CHAR_WALL:
			return TILE_WALL_PANEL
		CHAR_WARNING:
			return TILE_WARNING_PANEL
		CHAR_BEAM:
			return TILE_SUPPORT_BEAM
	return NO_TILE


func _ground_tile(rows: PackedStringArray, x: int, y: int) -> int:
	if _char_at(rows, x, y - 1) == CHAR_GROUND:
		return TILE_GROUND_FILL
	# Cells outside the room's left and right edges count as solid, so the
	# outer columns get a plain top tile.
	var open_left: bool = not _is_solid_or_outside(rows, x - 1, y)
	var open_right: bool = not _is_solid_or_outside(rows, x + 1, y)
	if open_left and not open_right:
		return TILE_GROUND_TOP_LEFT
	if open_right and not open_left:
		return TILE_GROUND_TOP_RIGHT
	return TILE_GROUND_TOP


func _platform_tile(rows: PackedStringArray, x: int, y: int) -> int:
	var joins_left: bool = _char_at(rows, x - 1, y) == CHAR_PLATFORM
	var joins_right: bool = _char_at(rows, x + 1, y) == CHAR_PLATFORM
	if joins_left and joins_right:
		return TILE_PLATFORM_MIDDLE
	if joins_right:
		return TILE_PLATFORM_LEFT
	if joins_left:
		return TILE_PLATFORM_RIGHT
	return TILE_PLATFORM_SINGLE


func _is_solid_or_outside(rows: PackedStringArray, x: int, y: int) -> bool:
	if x < 0 or x >= rows[y].length():
		return true
	return SOLID_CHARACTERS.contains(rows[y][x])


## Returns the character at (x, y), or CHAR_EMPTY outside the grid.
func _char_at(rows: PackedStringArray, x: int, y: int) -> String:
	if y < 0 or y >= rows.size() or x < 0 or x >= rows[y].length():
		return CHAR_EMPTY
	return rows[y][x]
