class_name LevelData
extends RefCounted
## One level file (GDD 12.4, the only format), parsed and fully validated:
## tiles, positions, parts, the circuit and the goal (every condition must name
## an element of the circuit that has that quantity).
##
## An optional "objects" list holds bounce pads, enemies and hazards
## (LevelObject).
##
## Parsing only: no circuit math happens here. Any problem pushes an error that
## names the file and the field, and the loader returns null.

const ROW_COUNT: int = 23
const COLUMN_COUNT: int = 40
const TILE_CHARACTERS: String = ".#=BW!|"
const DEFAULT_WORLD: String = "old_workshop"
const REQUIRED_FIELDS: PackedStringArray = [
	"id", "title", "mission", "goal", "tiles", "spawn", "door", "parts", "circuit",
]
const OPTIONAL_FIELDS: PackedStringArray = ["world", "teaches", "objects"]

var id: String = ""
var title: String = ""
## Optional note for designers: what the room teaches.
var teaches: String = ""
## The world whose theme the room uses (res://resources/themes/<world>/).
var world: String = DEFAULT_WORLD
## The one-line mission shown on the sign, e.g. "Draw 2 A.".
var mission: String = ""
## Every condition must hold for the door to open (never empty).
var goal: Array[GoalCondition] = []
## ROW_COUNT strings of COLUMN_COUNT tile characters each, top row first.
var tile_rows: PackedStringArray = PackedStringArray()
## Bottom centre of Ohmie at the start, in pixels.
var spawn: Vector2 = Vector2.ZERO
## Bottom centre of the exit door, in pixels.
var door: Vector2 = Vector2.ZERO
## The carried parts lying in the room, in file order.
var parts: Array[LevelPart] = []
var circuit: LevelCircuit = null
## Bounce pads, enemies and hazards, in file order (empty when the file has none).
var objects: Array[LevelObject] = []


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
	for key: Variant in dict.keys():
		if not REQUIRED_FIELDS.has(str(key)) and not OPTIONAL_FIELDS.has(str(key)):
			push_error("LevelData: %s: unknown field '%s'" % [source, str(key)])
			return null
	for field: String in REQUIRED_FIELDS:
		if not dict.has(field):
			push_error("LevelData: %s: missing field '%s'" % [source, field])
			return null

	var level: LevelData = LevelData.new()
	for field: String in ["id", "title", "mission"]:
		if not dict[field] is String or (dict[field] as String).strip_edges().is_empty():
			push_error("LevelData: %s: field '%s' must be a non-empty string" % [source, field])
			return null
	level.id = dict["id"]
	level.title = dict["title"]
	level.mission = (dict["mission"] as String).strip_edges()
	if dict.has("teaches"):
		if not dict["teaches"] is String:
			push_error("LevelData: %s: field 'teaches' must be a string" % source)
			return null
		level.teaches = dict["teaches"]
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

	if not LevelPart.parse_all(dict["parts"], source, level.parts):
		return null
	if dict.has("objects") and not LevelObject.parse_all(dict["objects"], source, level.objects):
		return null
	level.circuit = LevelCircuit.from_dictionary(dict["circuit"], source)
	if level.circuit == null:
		return null
	if not _parse_goal(dict["goal"], source, level):
		return null
	if not level.circuit.validate_goal(level.goal, source):
		return null
	return level


## The level's goal: its mission and conditions together.
func make_goal() -> LevelGoal:
	return LevelGoal.create(mission, goal)


static func _parse_goal(value: Variant, source: String, level: LevelData) -> bool:
	if not value is Array or (value as Array).is_empty():
		push_error("LevelData: %s: field 'goal' must be a non-empty array of conditions" % source)
		return false
	var raw: Array = value
	for i: int in raw.size():
		if not raw[i] is Dictionary:
			push_error("LevelData: %s: goal[%d] must be an object" % [source, i])
			return false
		var condition: GoalCondition = GoalCondition.from_dictionary(raw[i])
		if condition == null:
			push_error("LevelData: %s: goal[%d] is invalid (see the error above)" % [source, i])
			return false
		level.goal.append(condition)
	return true


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
