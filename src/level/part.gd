class_name Part
extends RefCounted
## One carried part: a resistor (ohms) or a battery (volts), with its exact
## value. Pure data, immutable after create().

enum Kind { RESISTOR, BATTERY }

const KIND_NAMES: Array[String] = ["resistor", "battery"]
const UNITS: Array[String] = ["Ω", "V"]

var kind: Kind = Kind.RESISTOR
## Ohms for a resistor, volts for a battery. Always > 0.
var value: Rational = null


## A part of `part_kind` with `part_value` (> 0). Returns null (with
## push_error) for a null, invalid or non-positive value.
static func create(part_kind: Kind, part_value: Rational) -> Part:
	if part_value == null or not part_value.is_valid() or part_value.sign() <= 0:
		push_error("Part.create: a %s needs a value > 0." % KIND_NAMES[part_kind])
		return null
	var part: Part = Part.new()
	part.kind = part_kind
	part.value = part_value
	return part


## The Kind for "resistor" or "battery", or -1 for anything else.
static func kind_from_name(kind_name: String) -> int:
	return KIND_NAMES.find(kind_name)


func is_battery() -> bool:
	return kind == Kind.BATTERY


## "resistor" or "battery".
func kind_name() -> String:
	return KIND_NAMES[kind]


## "Ω" or "V".
func unit() -> String:
	return UNITS[kind]


## "3 Ω", "1/2 Ω", "6 V". The same text DcPuzzleSearch uses for its solutions.
func label() -> String:
	return "%s %s" % [value.to_text(), unit()]


## The form DcPuzzleSearch.find_solutions expects for one part.
func to_search_dictionary() -> Dictionary:
	return {"kind": kind_name(), "value": value}
