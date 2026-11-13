class_name LevelPart
extends RefCounted
## One entry of a level's "parts" list: {"id", "kind", "value", "pos"} and,
## for a diode only, an optional "style" (Part.DIODE_STYLES), with the part
## parsed once into a Part.
##
## "kind" is "resistor", "battery" or "diode". "value" is a string read by
## QuantityText.parse ("3/2", "0.7", "1k"): ohms or volts, > 0; a diode's
## forward drop in volts, >= 0.

const ALLOWED_KEYS: Array[String] = ["id", "kind", "value", "pos", "style"]
const STYLE_KEY: String = "style"

var id: String = ""
var part: Part = null
## Floor point under the part (bottom centre), in pixels.
var position: Vector2 = Vector2.ZERO


## Parses every entry of `raw` (the level's "parts" value) into `out`. Returns
## false and pushes an error naming the problem if `raw` is not an array or any
## entry is invalid (`out` is then left empty). Every part prints its texts in
## `numbers`.
static func parse_all(raw: Variant, source: String, out: Array[LevelPart],
		numbers: QuantityText.Style = QuantityText.Style.FRACTION) -> bool:
	out.clear()
	if not raw is Array:
		push_error("LevelPart: %s: field 'parts' must be an array" % source)
		return false
	var entries: Array = raw
	var seen: Dictionary = {}
	for i: int in entries.size():
		var entry: LevelPart = _parse_one(entries[i], i, source, numbers)
		if entry == null:
			out.clear()
			return false
		if seen.has(entry.id):
			push_error("LevelPart: %s: part id '%s' is used more than once" % [source, entry.id])
			out.clear()
			return false
		seen[entry.id] = true
		out.append(entry)
	return true


static func _parse_one(raw: Variant, index: int, source: String,
		numbers: QuantityText.Style) -> LevelPart:
	if not raw is Dictionary:
		push_error("LevelPart: %s: parts[%d] must be an object" % [source, index])
		return null
	var entry: Dictionary = raw
	if not entry.get("id") is String or String(entry["id"]).is_empty():
		push_error("LevelPart: %s: parts[%d] needs a non-empty string 'id'" % [source, index])
		return null
	var id: String = entry["id"]
	for key: Variant in entry.keys():
		if not ALLOWED_KEYS.has(str(key)):
			push_error("LevelPart: %s: part '%s' has unknown field '%s' (allowed: %s)" % [
					source, id, str(key), ", ".join(ALLOWED_KEYS)])
			return null
	var kind: int = Part.kind_from_name(String(entry["kind"])) if entry.get("kind") is String else -1
	if kind < 0:
		push_error("LevelPart: %s: part '%s' needs 'kind' \"resistor\", \"battery\" or \"diode\"" % [source, id])
		return null
	var look: String = ""
	if entry.has(STYLE_KEY):
		if kind != Part.Kind.DIODE:
			push_error("LevelPart: %s: part '%s' has 'style', which only a diode may have" % [source, id])
			return null
		if not entry[STYLE_KEY] is String or not Part.DIODE_STYLES.has(String(entry[STYLE_KEY])):
			push_error("LevelPart: %s: part '%s' has an invalid 'style' (expected %s)" % [
					source, id, ", ".join(Part.DIODE_STYLES)])
			return null
		look = entry[STYLE_KEY]
	if not entry.get("value") is String:
		push_error("LevelPart: %s: part '%s' needs 'value' as a string like \"3/2\"" % [source, id])
		return null
	var value: Rational = QuantityText.parse(entry["value"], true)
	if value == null:
		# Report why as a plain number would have failed (the message from
		# before prefixes were accepted).
		Rational.parse(entry["value"])
	var lowest_sign: int = 0 if kind == Part.Kind.DIODE else 1
	if value == null or not value.is_valid() or value.sign() < lowest_sign:
		push_error("LevelPart: %s: part '%s' has an invalid 'value' '%s' (must be %s 0)" % [
				source, id, entry["value"], ">=" if kind == Part.Kind.DIODE else ">"])
		return null
	var point: Variant = entry.get("pos", null)
	if not point is Array or (point as Array).size() != 2 \
			or not _is_number((point as Array)[0]) or not _is_number((point as Array)[1]):
		push_error("LevelPart: %s: part '%s' needs 'pos' as two numbers [x, y]" % [source, id])
		return null
	var pair: Array = point
	var level_part: LevelPart = LevelPart.new()
	level_part.id = id
	level_part.part = Part.create(kind as Part.Kind, value, look, numbers)
	level_part.position = Vector2(float(pair[0]), float(pair[1]))
	return level_part


static func _is_number(value: Variant) -> bool:
	return value is float or value is int
