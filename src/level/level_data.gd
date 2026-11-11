class_name LevelData
extends RefCounted
## One level as described in GDD section 6, parsed from a JSON file.
##
## Parsing only: no circuit math happens here. The goal (the optional "goal"
## object, or the legacy "target" field) is parsed by LevelGoal.
## `pickups` and `circuit` are stored as parsed and only checked for the right
## container type; the objects that use them validate their own contents.

const ROW_COUNT: int = 23
const COLUMN_COUNT: int = 40
const TILE_CHARACTERS: String = ".#=BW!|"
const DEFAULT_WORLD: String = "old_workshop"
const REQUIRED_FIELDS: PackedStringArray = [
	"id", "title", "teaches", "tiles", "spawn", "door", "pickups", "circuit",
]

var id: String = ""
var title: String = ""
var teaches: String = ""
## Optional: the world whose theme the room uses (res://resources/themes/<world>/).
var world: String = DEFAULT_WORLD
## What solves the level and the mission text (never null on a loaded level).
var goal: LevelGoal = null
## The goal's target resistance as text, for example "1" or "3/2". Kept for
## older callers; prefer `goal`.
var target_text: String = ""
## ROW_COUNT strings of COLUMN_COUNT tile characters each, top row first.
var tile_rows: PackedStringArray = PackedStringArray()
## Bottom centre of Ohmie at the start, in pixels.
var spawn: Vector2 = Vector2.ZERO
## Bottom centre of the exit door, in pixels.
var door: Vector2 = Vector2.ZERO
var pickups: Array[Dictionary] = []
var circuit: Dictionary = {}


## Reads and parses a level file. Returns null and pushes an error on any problem.
static func load_from_file(path: String) -> LevelData:
	if not FileAccess.file_exists(path):
		push_error("LevelData: file not found: %s" % path)
		return null
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("LevelData: %s: file is empty or unreadable (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null
	var json: JSON = JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		push_error("LevelData: %s: invalid JSON at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return from_dictionary(json.data, path)


## Builds a level from already-parsed JSON data. `source` names the origin in error messages.
static func from_dictionary(data: Variant, source: String) -> LevelData:
	if not data is Dictionary:
		push_error("LevelData: %s: top level must be a JSON object" % source)
		return null
	var dict: Dictionary = data
	for field: String in REQUIRED_FIELDS:
		if not dict.has(field):
			push_error("LevelData: %s: missing field '%s'" % [source, field])
			return null

	var level: LevelData = LevelData.new()
	for field: String in ["id", "title", "teaches"]:
		if not dict[field] is String:
			push_error("LevelData: %s: field '%s' must be a string" % [source, field])
			return null
	level.id = dict["id"]
	level.title = dict["title"]
	level.teaches = dict["teaches"]
	level.goal = LevelGoal.from_level(dict, source)
	if level.goal == null:
		return null
	if level.goal.target != null:
		level.target_text = level.goal.target.to_text()
	if dict.has("world"):
		if not dict["world"] is String or (dict["world"] as String).strip_edges().is_empty():
			push_error("LevelData: %s: field 'world' must be a non-empty string" % source)
			return null
		level.world = dict["world"]

	if not _parse_tiles(dict["tiles"], source, level):
		return null

	var spawn_point: Variant = _parse_point(dict["spawn"], "spawn", source)
	if spawn_point == null:
		return null
	level.spawn = spawn_point
	var door_point: Variant = _parse_point(dict["door"], "door", source)
	if door_point == null:
		return null
	level.door = door_point

	if not dict["pickups"] is Array:
		push_error("LevelData: %s: field 'pickups' must be an array" % source)
		return null
	var raw_pickups: Array = dict["pickups"]
	for i: int in raw_pickups.size():
		if not raw_pickups[i] is Dictionary:
			push_error("LevelData: %s: pickups[%d] must be an object" % [source, i])
			return null
	level.pickups.assign(raw_pickups)

	if not dict["circuit"] is Dictionary:
		push_error("LevelData: %s: field 'circuit' must be an object" % source)
		return null
	level.circuit = dict["circuit"]
	return level


static func _parse_tiles(value: Variant, source: String, level: LevelData) -> bool:
	if not value is Array:
		push_error("LevelData: %s: field 'tiles' must be an array of strings" % source)
		return false
	var rows: Array = value
	if rows.size() != ROW_COUNT:
		push_error("LevelData: %s: 'tiles' has %d rows, expected %d" % [source, rows.size(), ROW_COUNT])
		return false
	var result: PackedStringArray = PackedStringArray()
	for y: int in rows.size():
		if not rows[y] is String:
			push_error("LevelData: %s: tiles row %d must be a string" % [source, y])
			return false
		var row: String = rows[y]
		if row.length() != COLUMN_COUNT:
			push_error("LevelData: %s: tiles row %d has %d characters, expected %d" % [source, y, row.length(), COLUMN_COUNT])
			return false
		for x: int in row.length():
			if not TILE_CHARACTERS.contains(row[x]):
				push_error("LevelData: %s: unknown tile character '%s' at row %d, column %d" % [source, row[x], y, x])
				return false
		result.append(row)
	level.tile_rows = result
	return true


## Returns a Vector2 for a JSON [x, y] pair, or null after pushing an error.
static func _parse_point(value: Variant, field: String, source: String) -> Variant:
	if not value is Array:
		push_error("LevelData: %s: field '%s' must be an [x, y] array" % [source, field])
		return null
	var pair: Array = value
	if pair.size() != 2 or not _is_number(pair[0]) or not _is_number(pair[1]):
		push_error("LevelData: %s: field '%s' must be two numbers [x, y]" % [source, field])
		return null
	return Vector2(float(pair[0]), float(pair[1]))


static func _is_number(value: Variant) -> bool:
	return value is float or value is int
