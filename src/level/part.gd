class_name Part
extends RefCounted
## One carried part: a resistor (ohms), a battery (volts) or a diode (forward
## drop in volts), with its exact value. Kind, value and looks are fixed after
## create(); only a diode's direction (`flipped`) changes, and only when the
## player turns it (set_flipped).
##
## A diode also has a look (`diode_style`: rectifier, signal or schottky; the
## picture only) and, like every part, the number style its texts use
## (`number_style`: World 1 fractions or World 2 engineering text).
##
## Direction (GDD 11, "Board and parts"): a diode not flipped is drawn as the
## art is, anode on the screen-left and the cathode stripe on the right, and
## conducts left to right; flipped, the picture is mirrored (stripe on the
## left) and it conducts right to left. Batteries cannot be flipped (their
## plus faces their slot's `from` node).

enum Kind { RESISTOR, BATTERY, DIODE }

const KIND_NAMES: Array[String] = ["resistor", "battery", "diode"]
const UNITS: Array[String] = ["Ω", "V", "V"]
## The looks a diode may have (its picture); the first is the default.
const DIODE_STYLES: Array[String] = ["rectifier", "signal", "schottky"]
const DEFAULT_DIODE_STYLE: String = "rectifier"
## Put before a diode's value on its name tag: "diode 0.7 V".
const DIODE_TAG_PREFIX: String = "diode "
## Put after a diode's value on its name tag: the way it conducts on screen.
const TAG_ARROW_RIGHT: String = " →"
const TAG_ARROW_LEFT: String = " ←"
## The puzzle search's key for a part it may also try the other way round.
const SEARCH_REVERSIBLE_KEY: String = "reversible"

var kind: Kind = Kind.RESISTOR
## Ohms for a resistor (> 0), volts for a battery (> 0), the forward drop in
## volts for a diode (>= 0).
var value: Rational = null
## A diode's look, one of DIODE_STYLES ("" for other kinds).
var diode_style: String = ""
## How value_text() and tag_text() print the value.
var number_style: QuantityText.Style = QuantityText.Style.FRACTION
## A diode turned end for end: anode on the screen-right, stripe on the left.
## Always false for a part that is not flippable.
var flipped: bool = false


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
## anode on the left of the art).
func is_polarized() -> bool:
	return kind == Kind.BATTERY or kind == Kind.DIODE


## True for a part the player may turn end for end (a diode).
func is_flippable() -> bool:
	return kind == Kind.DIODE


## Sets a flippable part's direction. Returns false (and changes nothing) for
## a part that cannot be flipped.
func set_flipped(turned: bool) -> bool:
	if not is_flippable():
		return false
	flipped = turned
	return true


## A new Part with the same kind, value, looks, number style and direction.
func copy() -> Part:
	var twin: Part = Part.new()
	twin.kind = kind
	twin.value = value
	twin.diode_style = diode_style
	twin.number_style = number_style
	twin.flipped = flipped
	return twin


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


## The name tag: value_text(); a diode's reads "diode 0.7 V →" (conducts left
## to right, not flipped) or "diode 0.7 V ←" (flipped).
func tag_text() -> String:
	if kind != Kind.DIODE:
		return value_text()
	return DIODE_TAG_PREFIX + value_text() + (TAG_ARROW_LEFT if flipped else TAG_ARROW_RIGHT)


## The form DcPuzzleSearch.find_solutions expects for one part. A flippable
## part is marked "reversible": the search tries it both ways round.
func to_search_dictionary() -> Dictionary:
	var search: Dictionary = {"kind": kind_name(), "value": value}
	if is_flippable():
		search[SEARCH_REVERSIBLE_KEY] = true
	return search
