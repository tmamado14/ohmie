class_name LevelObject
extends RefCounted
## One entry of a level's optional "objects" list: a bounce pad, an enemy or a
## hazard. Parsing and validation only; RoomObjects turns entries into nodes.
##
##   { "type": "bounce_pad", "pos": [x, y] }
##   { "type": "patroller", "kind": "jelly" | "bot", "pos": [x, y],
##     "left": x, "right": x, "speed": px/s (optional, default 60) }
##   { "type": "floater", "kind": "spark_orb", "from": [x, y], "to": [x, y],
##     "speed": px/s (optional, default 80) }
##   { "type": "hazard", "kind": "spikes" | "live_wire", "pos": [x, y] }
##
## `pos` is the floor point under the object (bottom centre). A patroller walks
## between x = left and x = right (left <= pos.x <= right). A floater's `from`
## and `to` are centre points. Every speed must be > 0.

const TYPE_BOUNCE_PAD: String = "bounce_pad"
const TYPE_PATROLLER: String = "patroller"
const TYPE_FLOATER: String = "floater"
const TYPE_HAZARD: String = "hazard"
const TYPES: PackedStringArray = [TYPE_BOUNCE_PAD, TYPE_PATROLLER, TYPE_FLOATER, TYPE_HAZARD]

const KIND_JELLY: String = "jelly"
const KIND_BOT: String = "bot"
const KIND_SPARK_ORB: String = "spark_orb"
const KIND_SPIKES: String = "spikes"
const KIND_LIVE_WIRE: String = "live_wire"
const PATROLLER_KINDS: PackedStringArray = [KIND_JELLY, KIND_BOT]
const FLOATER_KINDS: PackedStringArray = [KIND_SPARK_ORB]
const HAZARD_KINDS: PackedStringArray = [KIND_SPIKES, KIND_LIVE_WIRE]

const DEFAULT_PATROLLER_SPEED: float = 60.0
const DEFAULT_FLOATER_SPEED: float = 80.0

## One of TYPES.
var type: String = ""
## The art and behaviour variant ("" for a bounce pad).
var kind: String = ""
## Floor point under the object (bounce pad, patroller start, hazard); for a
## floater, its `from` centre point.
var position: Vector2 = Vector2.ZERO
## Patroller only: the x range it walks.
var left: float = 0.0
var right: float = 0.0
## Floater only: the two centre points it moves between.
var from_point: Vector2 = Vector2.ZERO
var to_point: Vector2 = Vector2.ZERO
## Patroller and floater: pixels per second.
var speed: float = 0.0


## Parses every entry of `raw` (the level's "objects" value) into `out`.
## Returns false and pushes an error naming the problem if `raw` is not an
## array or any entry is invalid (`out` is then left empty).
static func parse_all(raw: Variant, source: String, out: Array[LevelObject]) -> bool:
	out.clear()
	if not raw is Array:
		push_error("LevelObject: %s: field 'objects' must be an array" % source)
		return false
	var entries: Array = raw
	for i: int in entries.size():
		var entry: LevelObject = _parse_one(entries[i], i, source)
		if entry == null:
			out.clear()
			return false
		out.append(entry)
	return true


static func _parse_one(raw: Variant, index: int, source: String) -> LevelObject:
	var name: String = "objects[%d]" % index
	if not raw is Dictionary:
		push_error("LevelObject: %s: %s must be an object" % [source, name])
		return null
	var dict: Dictionary = raw
	if not dict.get("type") is String or not TYPES.has(String(dict["type"])):
		push_error("LevelObject: %s: %s has unknown or missing 'type' '%s' (expected %s)" % [
				source, name, str(dict.get("type", "")), ", ".join(TYPES)])
		return null
	var entry: LevelObject = LevelObject.new()
	entry.type = dict["type"]
	name = "%s (%s)" % [name, entry.type]
	if not _check_keys(dict, _allowed_keys(entry.type), name, source):
		return null
	match entry.type:
		TYPE_BOUNCE_PAD:
			var pad_pos: Variant = _point(dict, "pos", name, source)
			if pad_pos == null:
				return null
			entry.position = pad_pos
		TYPE_PATROLLER:
			if not _parse_kind(dict, PATROLLER_KINDS, name, source, entry):
				return null
			var walker_pos: Variant = _point(dict, "pos", name, source)
			if walker_pos == null:
				return null
			entry.position = walker_pos
			for field: String in ["left", "right"]:
				if not _is_number(dict.get(field)):
					push_error("LevelObject: %s: %s needs '%s' as a number" % [source, name, field])
					return null
			entry.left = float(dict["left"])
			entry.right = float(dict["right"])
			if entry.left > entry.right:
				push_error("LevelObject: %s: %s has 'left' %s greater than 'right' %s" % [
						source, name, str(dict["left"]), str(dict["right"])])
				return null
			if entry.position.x < entry.left or entry.position.x > entry.right:
				push_error("LevelObject: %s: %s has 'pos' x %s outside 'left'..'right' (%s..%s)" % [
						source, name, str((dict["pos"] as Array)[0]), str(dict["left"]), str(dict["right"])])
				return null
			if not _parse_speed(dict, DEFAULT_PATROLLER_SPEED, name, source, entry):
				return null
		TYPE_FLOATER:
			if not _parse_kind(dict, FLOATER_KINDS, name, source, entry):
				return null
			var from_value: Variant = _point(dict, "from", name, source)
			if from_value == null:
				return null
			var to_value: Variant = _point(dict, "to", name, source)
			if to_value == null:
				return null
			entry.from_point = from_value
			entry.to_point = to_value
			entry.position = from_value
			if not _parse_speed(dict, DEFAULT_FLOATER_SPEED, name, source, entry):
				return null
		TYPE_HAZARD:
			if not _parse_kind(dict, HAZARD_KINDS, name, source, entry):
				return null
			var hazard_pos: Variant = _point(dict, "pos", name, source)
			if hazard_pos == null:
				return null
			entry.position = hazard_pos
	return entry


static func _allowed_keys(object_type: String) -> PackedStringArray:
	match object_type:
		TYPE_PATROLLER:
			return PackedStringArray(["type", "kind", "pos", "left", "right", "speed"])
		TYPE_FLOATER:
			return PackedStringArray(["type", "kind", "from", "to", "speed"])
		TYPE_HAZARD:
			return PackedStringArray(["type", "kind", "pos"])
	return PackedStringArray(["type", "pos"])


static func _check_keys(dict: Dictionary, allowed: PackedStringArray, name: String, source: String) -> bool:
	for key: Variant in dict.keys():
		if not allowed.has(str(key)):
			push_error("LevelObject: %s: %s has unknown field '%s' (allowed: %s)" % [
					source, name, str(key), ", ".join(allowed)])
			return false
	return true


static func _parse_kind(dict: Dictionary, kinds: PackedStringArray, name: String, source: String,
		entry: LevelObject) -> bool:
	if not dict.get("kind") is String or not kinds.has(String(dict["kind"])):
		push_error("LevelObject: %s: %s has unknown or missing 'kind' '%s' (expected %s)" % [
				source, name, str(dict.get("kind", "")), ", ".join(kinds)])
		return false
	entry.kind = dict["kind"]
	return true


static func _parse_speed(dict: Dictionary, default_speed: float, name: String, source: String,
		entry: LevelObject) -> bool:
	if not dict.has("speed"):
		entry.speed = default_speed
		return true
	if not _is_number(dict["speed"]) or float(dict["speed"]) <= 0.0:
		push_error("LevelObject: %s: %s needs 'speed' as a number > 0, got '%s'" % [
				source, name, str(dict["speed"])])
		return false
	entry.speed = float(dict["speed"])
	return true


## The Vector2 of dict[field] as [x, y], or null after pushing an error.
static func _point(dict: Dictionary, field: String, name: String, source: String) -> Variant:
	var value: Variant = dict.get(field, null)
	if not value is Array or (value as Array).size() != 2 \
			or not _is_number((value as Array)[0]) or not _is_number((value as Array)[1]):
		push_error("LevelObject: %s: %s needs '%s' as two numbers [x, y]" % [source, name, field])
		return null
	var pair: Array = value
	return Vector2(float(pair[0]), float(pair[1]))


static func _is_number(value: Variant) -> bool:
	return value is float or value is int
