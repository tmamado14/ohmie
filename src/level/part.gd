class_name Part
extends RefCounted
## One carried part: a resistor (ohms), a battery (volts) or a diode (forward
## drop in volts), with its exact value. Pure data, immutable after create().
##
## A diode also has a look (`diode_style`: rectifier, signal or schottky; the
## picture only) and, like every part, the number style its texts use
## (`number_style`: World 1 fractions or World 2 engineering text).

enum Kind { RESISTOR, BATTERY, DIODE }

const KIND_NAMES: Array[String] = ["resistor", "battery", "diode"]
const UNITS: Array[String] = ["Ω", "V", "V"]
## The looks a diode may have (its picture); the first is the default.
const DIODE_STYLES: Array[String] = ["rectifier", "signal", "schottky"]
const DEFAULT_DIODE_STYLE: String = "rectifier"
## Put before a diode's value on its name tag: "diode 0.7 V".
const DIODE_TAG_PREFIX: String = "diode "

var kind: Kind = Kind.RESISTOR
## Ohms for a resistor (> 0), volts for a battery (> 0), the forward drop in
## volts for a diode (>= 0).
var value: Rational = null
## A diode's look, one of DIODE_STYLES ("" for other kinds).
var diode_style: String = ""
## How value_text() and tag_text() print the value.
var number_style: QuantityText.Style = QuantityText.Style.FRACTION


## A part of `part_kind` with `part_value` (> 0; a diode's drop may be 0).
## `look` is a diode's style ("" means the default; ignored for other kinds).
## Returns null (with push_error) for a null or invalid value, a value out of
## range, or an unknown diode style.
static func create(part_kind: Kind, part_value: Rational, look: String = "",
		numbers: QuantityText.Style = QuantityText.Style.FRACTION) -> Part:
	var lowest_sign: int = 0 if part_kind == Kind.DIODE else 1
	if part_value == null or not part_value.is_valid() or part_value.sign() < lowest_sign:
		push_error("Part.create: a %s needs a value %s 0." % [
				KIND_NAMES[part_kind], ">=" if part_kind == Kind.DIODE else ">"])
		return null
	var part: Part = Part.new()
	part.kind = part_kind
	part.value = part_value
	part.number_style = numbers
	if part_kind == Kind.DIODE:
		var chosen: String = DEFAULT_DIODE_STYLE if look.is_empty() else look
		if not DIODE_STYLES.has(chosen):
			push_error("Part.create: unknown diode style '%s' (expected %s)." % [look, ", ".join(DIODE_STYLES)])
			return null
		part.diode_style = chosen
	return part


## The Kind for "resistor", "battery" or "diode", or -1 for anything else.
static func kind_from_name(kind_name: String) -> int:
	return KIND_NAMES.find(kind_name)


func is_battery() -> bool:
	return kind == Kind.BATTERY


func is_diode() -> bool:
	return kind == Kind.DIODE


## True for a part whose picture has a direction (a battery's plus, a diode's
## anode on the left) and is mirrored to face its slot's `from` node.
func is_polarized() -> bool:
	return kind == Kind.BATTERY or kind == Kind.DIODE


## "resistor", "battery" or "diode".
func kind_name() -> String:
	return KIND_NAMES[kind]


## "Ω" or "V".
func unit() -> String:
	return UNITS[kind]


## The text that names the part in DcPuzzleSearch's solutions (and groups
## interchangeable parts): "3 Ω", "1/2 Ω", "6 V", "diode 7/10 V". Always in
## exact fractions, whatever number_style says.
func label() -> String:
	return DcPuzzleSearch.part_text(to_search_dictionary())


## The value with its unit in number_style: "3 Ω", "1/2 Ω", "6 V"; "1 kΩ",
## "0.7 V" in engineering style. What the part's plaque shows.
func value_text() -> String:
	return QuantityText.format(value, unit(), number_style)


## The name tag: value_text(), with "diode " before a diode's value.
func tag_text() -> String:
	return DIODE_TAG_PREFIX + value_text() if kind == Kind.DIODE else value_text()


## The form DcPuzzleSearch.find_solutions expects for one part.
func to_search_dictionary() -> Dictionary:
	return {"kind": kind_name(), "value": value}
