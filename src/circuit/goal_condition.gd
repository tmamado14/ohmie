class_name GoalCondition
extends RefCounted
## One condition a level's goal must satisfy, tested exactly against a
## DcSolution: "the current through am1 is 2 A", "the voltage on vm1 is
## between 1 and 3/2 V", "the resistance on om1 is at least 1 ohm".
##
## Exactly one kind of test is set: `equals`, or a closed range from
## `min_value` to `max_value` where either end may be null (one-sided). Both
## ends of a range are inclusive.
##
## Data form (all numbers are strings, parsed exactly by Rational.parse):
##   {"of": "am1", "quantity": "current", "equals": "2"}
##   {"of": "lamp1", "quantity": "current", "min": "1", "max": "3/2"}
## Allowed keys: of, quantity, equals, min, max. Quantities: current, voltage,
## resistance, power.

enum Quantity { CURRENT, VOLTAGE, RESISTANCE, POWER }

const _QUANTITY_NAMES: Array[String] = ["current", "voltage", "resistance", "power"]
const _UNITS: Array[String] = ["A", "V", "Ω", "W"]
const _ALLOWED_KEYS: Array[String] = ["of", "quantity", "equals", "min", "max"]
const _RANGE_DASH: String = "–"

var element_id: String = ""
var quantity: Quantity = Quantity.CURRENT
var equals: Rational = null
var min_value: Rational = null
var max_value: Rational = null


## Builds a condition testing for an exact value. Returns null (with
## push_error) for an empty id or a null/invalid value.
static func exactly(id: String, what: Quantity, value: Rational) -> GoalCondition:
	if id.is_empty() or value == null or not value.is_valid():
		push_error("GoalCondition.exactly: needs an element id and a valid value.")
		return null
	var condition: GoalCondition = GoalCondition.new()
	condition.element_id = id
	condition.quantity = what
	condition.equals = value
	return condition


## Builds a closed range condition; either end may be null, not both.
## Returns null (with push_error) on bad input or when low > high.
static func between(id: String, what: Quantity, low: Rational, high: Rational) -> GoalCondition:
	if id.is_empty():
		push_error("GoalCondition.between: element id must not be empty.")
		return null
	if low == null and high == null:
		push_error("GoalCondition.between: '%s' needs a min, a max or both." % id)
		return null
	if (low != null and not low.is_valid()) or (high != null and not high.is_valid()):
		push_error("GoalCondition.between: '%s' has an invalid bound." % id)
		return null
	if low != null and high != null and low.compare(high) > 0:
		push_error("GoalCondition.between: '%s' has min %s greater than max %s." % [
				id, low.to_text(), high.to_text()])
		return null
	var condition: GoalCondition = GoalCondition.new()
	condition.element_id = id
	condition.quantity = what
	condition.min_value = low
	condition.max_value = high
	return condition


## Parses the data form described above. Returns null (with push_error) for a
## missing or empty "of", an unknown quantity, an unknown key, no test at all,
## "equals" together with "min"/"max", a value that is not a string or does
## not parse, or min > max.
static func from_dictionary(data: Dictionary) -> GoalCondition:
	for key: Variant in data.keys():
		if typeof(key) != TYPE_STRING or not _ALLOWED_KEYS.has(String(key)):
			push_error("GoalCondition.from_dictionary: unknown key '%s' (allowed: %s)." % [
					str(key), ", ".join(_ALLOWED_KEYS)])
			return null
	if typeof(data.get("of")) != TYPE_STRING or String(data["of"]).is_empty():
		push_error("GoalCondition.from_dictionary: 'of' must be a non-empty element id string.")
		return null
	var id: String = data["of"]
	if typeof(data.get("quantity")) != TYPE_STRING:
		push_error("GoalCondition.from_dictionary: '%s' needs a 'quantity' string (%s)." % [
				id, ", ".join(_QUANTITY_NAMES)])
		return null
	var what: int = _QUANTITY_NAMES.find(String(data["quantity"]))
	if what < 0:
		push_error("GoalCondition.from_dictionary: unknown quantity '%s' (expected %s)." % [
				String(data["quantity"]), ", ".join(_QUANTITY_NAMES)])
		return null
	var has_equals: bool = data.has("equals")
	var has_range: bool = data.has("min") or data.has("max")
	if has_equals and has_range:
		push_error("GoalCondition.from_dictionary: '%s' has 'equals' together with 'min'/'max'." % id)
		return null
	if not has_equals and not has_range:
		push_error("GoalCondition.from_dictionary: '%s' needs 'equals', 'min' or 'max'." % id)
		return null
	if has_equals:
		var value: Rational = _parse_value(data, "equals", id)
		if value == null:
			return null
		return exactly(id, what as Quantity, value)
	var low: Rational = null
	var high: Rational = null
	if data.has("min"):
		low = _parse_value(data, "min", id)
		if low == null:
			return null
	if data.has("max"):
		high = _parse_value(data, "max", id)
		if high == null:
			return null
	return between(id, what as Quantity, low, high)


## The live value this condition tests, or null when it is not available
## (unknown id, bad status, an OPEN or INVALID meter, a RESISTANCE condition on
## anything but an ohmmeter, a current through a wire).
##   CURRENT:    an ammeter's reading, else current_through.
##   VOLTAGE:    a voltmeter's reading, else voltage_across.
##   RESISTANCE: an ohmmeter's reading only.
##   POWER:      power_of.
func value_in(solution: DcSolution) -> Rational:
	if solution == null:
		return null
	var kind: int = solution.element_kind(element_id)
	match quantity:
		Quantity.CURRENT:
			if kind == DcNetwork.Kind.AMMETER:
				return solution.meter_reading(element_id)
			return solution.current_through(element_id)
		Quantity.VOLTAGE:
			if kind == DcNetwork.Kind.VOLTMETER:
				return solution.meter_reading(element_id)
			return solution.voltage_across(element_id)
		Quantity.RESISTANCE:
			if kind == DcNetwork.Kind.OHMMETER:
				return solution.meter_reading(element_id)
			return null
		Quantity.POWER:
			return solution.power_of(element_id)
	return null


## True when the value is available and passes the test exactly.
func is_met(solution: DcSolution) -> bool:
	return passes(value_in(solution))


## True when `value` (not null) passes the test exactly.
func passes(value: Rational) -> bool:
	if value == null or not value.is_valid():
		return false
	if equals != null:
		return value.equals(equals)
	if min_value != null and value.compare(min_value) < 0:
		return false
	if max_value != null and value.compare(max_value) > 0:
		return false
	return min_value != null or max_value != null


## "A", "V", "Ω" or "W".
func unit() -> String:
	return _UNITS[quantity]


## "current", "voltage", "resistance" or "power".
func quantity_name() -> String:
	return _QUANTITY_NAMES[quantity]


## "2 A"; a range "1–3/2 A" (en dash); one-sided "≥ 1 A" or "≤ 2 A".
func target_text() -> String:
	if equals != null:
		return "%s %s" % [equals.to_text(), unit()]
	if min_value != null and max_value != null:
		return "%s%s%s %s" % [min_value.to_text(), _RANGE_DASH, max_value.to_text(), unit()]
	if min_value != null:
		return "≥ %s %s" % [min_value.to_text(), unit()]
	if max_value != null:
		return "≤ %s %s" % [max_value.to_text(), unit()]
	return "---"


## The live value as a meter would show it:
##   "3/2 A" when a value is available (including "0 A" for no current);
##   RESISTANCE (ohmmeters): "OL" when OPEN, "ERROR" when INVALID;
##   CURRENT / VOLTAGE / POWER: "SHORT", "???" (INDETERMINATE) or "ERROR" from
##   the main status; otherwise "---" when there is no defined value (an OPEN
##   voltmeter, a current through a wire);
##   "ERROR" for a null solution, an unknown id, or a RESISTANCE condition on
##   anything but an ohmmeter.
func reading_text(solution: DcSolution) -> String:
	if solution == null or not solution.has_element(element_id):
		return "ERROR"
	if quantity == Quantity.RESISTANCE:
		if solution.element_kind(element_id) != DcNetwork.Kind.OHMMETER:
			return "ERROR"
		match solution.meter_state(element_id):
			DcSolution.MeterState.VALUE:
				return _with_unit(solution.meter_reading(element_id))
			DcSolution.MeterState.OPEN:
				return "OL"
		return "ERROR"
	match solution.status:
		DcSolution.Status.SHORT:
			return "SHORT"
		DcSolution.Status.INDETERMINATE:
			return "???"
		DcSolution.Status.ERROR:
			return "ERROR"
	var value: Rational = value_in(solution)
	if value == null:
		return "---"
	return _with_unit(value)


func _with_unit(value: Rational) -> String:
	return "%s %s" % [value.to_text(), unit()]


static func _parse_value(data: Dictionary, key: String, id: String) -> Rational:
	var raw: Variant = data[key]
	if typeof(raw) != TYPE_STRING:
		push_error("GoalCondition.from_dictionary: '%s' of '%s' must be a string like \"3/2\", got %s." % [
				key, id, type_string(typeof(raw))])
		return null
	var value: Rational = Rational.parse(String(raw))
	if value == null:
		push_error("GoalCondition.from_dictionary: '%s' of '%s' is not a number: '%s'." % [
				key, id, String(raw)])
		return null
	return value
