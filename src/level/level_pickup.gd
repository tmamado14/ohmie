class_name LevelPickup
extends RefCounted
## One loose resistor from a level's "pickups" list, with its value parsed
## once into an exact Rational.

var id: String = ""
var ohms: Rational = null
## Floor point under the resistor (bottom centre), in pixels.
var position: Vector2 = Vector2.ZERO


## Parses every entry of `raw` into `out`. Returns false and pushes an error
## naming the problem if any entry is invalid (`out` is then left empty).
static func parse_all(raw: Array[Dictionary], source: String, out: Array[LevelPickup]) -> bool:
	out.clear()
	var seen: Dictionary = {}
	for i: int in raw.size():
		var pickup: LevelPickup = _parse_one(raw[i], i, source)
		if pickup == null:
			out.clear()
			return false
		if seen.has(pickup.id):
			push_error("LevelPickup: %s: pickup id '%s' is used more than once" % [source, pickup.id])
			out.clear()
			return false
		seen[pickup.id] = true
		out.append(pickup)
	return true


static func _parse_one(entry: Dictionary, index: int, source: String) -> LevelPickup:
	if not entry.has("id") or not entry["id"] is String or String(entry["id"]).is_empty():
		push_error("LevelPickup: %s: pickups[%d] needs a non-empty string 'id'" % [source, index])
		return null
	var pickup: LevelPickup = LevelPickup.new()
	pickup.id = entry["id"]
	if not entry.has("ohms") or not entry["ohms"] is String:
		push_error("LevelPickup: %s: pickup '%s' needs 'ohms' as a string" % [source, pickup.id])
		return null
	var value: Rational = Rational.parse(entry["ohms"])
	if value == null or not value.is_valid() or value.sign() <= 0:
		push_error("LevelPickup: %s: pickup '%s' has an invalid 'ohms' value '%s' (must be > 0)" % [source, pickup.id, entry["ohms"]])
		return null
	pickup.ohms = value
	var point: Variant = entry.get("pos", null)
	if not point is Array or (point as Array).size() != 2 \
			or not _is_number((point as Array)[0]) or not _is_number((point as Array)[1]):
		push_error("LevelPickup: %s: pickup '%s' needs 'pos' as two numbers [x, y]" % [source, pickup.id])
		return null
	var pair: Array = point
	pickup.position = Vector2(float(pair[0]), float(pair[1]))
	return pickup


static func _is_number(value: Variant) -> bool:
	return value is float or value is int
