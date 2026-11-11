extends TestCase
## Tests for GoalCondition.

const CURRENT: GoalCondition.Quantity = GoalCondition.Quantity.CURRENT
const VOLTAGE: GoalCondition.Quantity = GoalCondition.Quantity.VOLTAGE
const RESISTANCE: GoalCondition.Quantity = GoalCondition.Quantity.RESISTANCE
const POWER: GoalCondition.Quantity = GoalCondition.Quantity.POWER
const INT_MAX: int = 9223372036854775807


func _q(text: String) -> Rational:
	return Rational.parse(text)


## A working board:
##   B1 6 V (+ p, - g); AM p -> a; R1 a -> g 3 ohm (2 A); R4 p -> g 4 ohm (3/2 A);
##   W wire g -> h; VM a -> g (6 V); VMO a -> z (z touches nothing: OPEN).
##   Floating part: R2 and R3, 2 ohm each between x and y (no current);
##   OM x -> y reads 1 ohm; OMO x -> w reads OL.
func _board() -> DcNetwork:
	var net: DcNetwork = DcNetwork.new()
	net.add_voltage_source("B1", "p", "g", _q("6"))
	net.add_ammeter("AM", "p", "a")
	net.add_ammeter("AMR", "a", "a2")
	net.add_resistor("R1", "a2", "g", _q("3"))
	net.add_resistor("R4", "p", "g", _q("4"))
	net.add_wire("W", "g", "h")
	net.add_voltmeter("VM", "a", "g")
	net.add_voltmeter("VMO", "a", "z")
	net.add_resistor("R2", "x", "y", _q("2"))
	net.add_resistor("R3", "x", "y", _q("2"))
	net.add_ohmmeter("OM", "x", "y")
	net.add_ohmmeter("OMO", "x", "w")
	return net


func _ok() -> DcSolution:
	return DcSolver.solve(_board())


func _short() -> DcSolution:
	var net: DcNetwork = _board()
	net.add_wire("WS", "p", "g")
	return DcSolver.solve(net)


func _indeterminate() -> DcSolution:
	var net: DcNetwork = _board()
	net.add_ammeter("AM2", "p", "a")
	return DcSolver.solve(net)


## Status ERROR (overflow); the caller must claim the two pushed errors.
func _error() -> DcSolution:
	var net: DcNetwork = _board()
	net.add_voltage_source("BIG", "m", "n", Rational.new(INT_MAX))
	net.add_resistor("RBIG", "m", "n", Rational.new(1, 2))
	return DcSolver.solve(net)


func _parse(data: Dictionary) -> GoalCondition:
	return GoalCondition.from_dictionary(data)


# --- parsing ------------------------------------------------------------------------

func test_parse_equals() -> void:
	var c: GoalCondition = _parse({"of": "am1", "quantity": "current", "equals": "2"})
	assert_not_null(c)
	assert_eq(c.element_id, "am1")
	assert_eq(c.quantity, CURRENT)
	assert_rational_eq(c.equals, "2")
	assert_null(c.min_value)
	assert_null(c.max_value)


func test_parse_closed_range() -> void:
	var c: GoalCondition = _parse({"of": "lamp1", "quantity": "current", "min": "1", "max": "3/2"})
	assert_not_null(c)
	assert_null(c.equals)
	assert_rational_eq(c.min_value, "1")
	assert_rational_eq(c.max_value, "3/2")


func test_parse_one_sided() -> void:
	var low: GoalCondition = _parse({"of": "vm", "quantity": "voltage", "min": "0.5"})
	assert_rational_eq(low.min_value, "1/2")
	assert_null(low.max_value)
	var high: GoalCondition = _parse({"of": "r", "quantity": "power", "max": "-3/4"})
	assert_null(high.min_value)
	assert_rational_eq(high.max_value, "-3/4")


func test_parse_equal_bounds_is_allowed() -> void:
	var c: GoalCondition = _parse({"of": "x", "quantity": "voltage", "min": "2", "max": "2.0"})
	assert_not_null(c)


func test_parse_every_quantity() -> void:
	assert_eq(_parse({"of": "x", "quantity": "current", "equals": "1"}).quantity, CURRENT)
	assert_eq(_parse({"of": "x", "quantity": "voltage", "equals": "1"}).quantity, VOLTAGE)
	assert_eq(_parse({"of": "x", "quantity": "resistance", "equals": "1"}).quantity, RESISTANCE)
	assert_eq(_parse({"of": "x", "quantity": "power", "equals": "1"}).quantity, POWER)


func test_parse_rejects_unknown_quantity() -> void:
	assert_null(_parse({"of": "x", "quantity": "charge", "equals": "1"}))
	assert_error_pushed("unknown quantity 'charge'")
	assert_null(_parse({"of": "x", "quantity": "Current", "equals": "1"}))
	assert_error_pushed("unknown quantity 'Current'")


func test_parse_rejects_missing_or_bad_fields() -> void:
	assert_null(_parse({"quantity": "current", "equals": "1"}))
	assert_error_pushed("'of' must be a non-empty element id")
	assert_null(_parse({"of": "", "quantity": "current", "equals": "1"}))
	assert_error_pushed("'of' must be a non-empty element id")
	assert_null(_parse({"of": 7, "quantity": "current", "equals": "1"}))
	assert_error_pushed("'of' must be a non-empty element id")
	assert_null(_parse({"of": "x", "equals": "1"}))
	assert_error_pushed("needs a 'quantity' string")
	assert_null(_parse({"of": "x", "quantity": "current", "eqauls": "1"}))
	assert_error_pushed("unknown key 'eqauls'")


func test_parse_rejects_missing_test() -> void:
	assert_null(_parse({"of": "x", "quantity": "current"}))
	assert_error_pushed("needs 'equals', 'min' or 'max'")


func test_parse_rejects_equals_with_range() -> void:
	assert_null(_parse({"of": "x", "quantity": "current", "equals": "1", "min": "0"}))
	assert_error_pushed("'equals' together with 'min'/'max'")
	assert_null(_parse({"of": "x", "quantity": "current", "equals": "1", "max": "2"}))
	assert_error_pushed("'equals' together with 'min'/'max'")


func test_parse_rejects_min_above_max() -> void:
	assert_null(_parse({"of": "x", "quantity": "current", "min": "3/2", "max": "1"}))
	assert_error_pushed("min 3/2 greater than max 1")


func test_parse_rejects_bad_numbers() -> void:
	assert_null(_parse({"of": "x", "quantity": "current", "equals": "two"}))
	assert_error_pushed("Rational.parse")
	assert_error_pushed("'equals' of 'x' is not a number")
	assert_null(_parse({"of": "x", "quantity": "current", "min": "1/0"}))
	assert_error_pushed("zero denominator")
	assert_error_pushed("'min' of 'x' is not a number")
	assert_null(_parse({"of": "x", "quantity": "current", "max": ""}))
	assert_error_pushed("Rational.parse")
	assert_error_pushed("'max' of 'x' is not a number")


func test_parse_rejects_non_string_numbers() -> void:
	# JSON numbers arrive as floats; they are refused rather than approximated.
	assert_null(_parse({"of": "x", "quantity": "current", "equals": 2.0}))
	assert_error_pushed("must be a string")
	assert_null(_parse({"of": "x", "quantity": "current", "max": 2}))
	assert_error_pushed("must be a string")


func test_exactly_and_between_constructors() -> void:
	var c: GoalCondition = GoalCondition.exactly("AM", CURRENT, _q("2"))
	assert_eq(c.element_id, "AM")
	assert_rational_eq(c.equals, "2")
	var r: GoalCondition = GoalCondition.between("VM", VOLTAGE, null, _q("5"))
	assert_null(r.min_value)
	assert_rational_eq(r.max_value, "5")


func test_constructors_reject_bad_input() -> void:
	assert_null(GoalCondition.exactly("", CURRENT, _q("2")))
	assert_error_pushed("needs an element id and a valid value")
	assert_null(GoalCondition.exactly("AM", CURRENT, null))
	assert_error_pushed("needs an element id and a valid value")
	assert_null(GoalCondition.between("AM", CURRENT, null, null))
	assert_error_pushed("needs a min, a max or both")
	assert_null(GoalCondition.between("", CURRENT, _q("1"), null))
	assert_error_pushed("element id must not be empty")
	assert_null(GoalCondition.between("AM", CURRENT, _q("2"), _q("1")))
	assert_error_pushed("greater than max")
	var invalid: Rational = Rational.new(1, 0)
	assert_error_pushed("zero denominator")
	assert_null(GoalCondition.between("AM", CURRENT, invalid, null))
	assert_error_pushed("invalid bound")


# --- values -------------------------------------------------------------------------------

func test_value_in_for_each_quantity_and_kind() -> void:
	var sol: DcSolution = _ok()
	assert_eq(sol.status, DcSolution.Status.OK)
	assert_rational_eq(GoalCondition.exactly("AM", CURRENT, _q("0")).value_in(sol), "2", "ammeter (R4 bypasses it)")
	assert_rational_eq(GoalCondition.exactly("R1", CURRENT, _q("0")).value_in(sol), "2", "resistor current")
	assert_rational_eq(GoalCondition.exactly("B1", CURRENT, _q("0")).value_in(sol), "7/2", "source delivers")
	assert_rational_eq(GoalCondition.exactly("VM", VOLTAGE, _q("0")).value_in(sol), "6", "voltmeter")
	assert_rational_eq(GoalCondition.exactly("R4", VOLTAGE, _q("0")).value_in(sol), "6", "resistor voltage")
	assert_rational_eq(GoalCondition.exactly("B1", VOLTAGE, _q("0")).value_in(sol), "6", "source voltage")
	assert_rational_eq(GoalCondition.exactly("OM", RESISTANCE, _q("0")).value_in(sol), "1", "ohmmeter")
	assert_rational_eq(GoalCondition.exactly("R1", POWER, _q("0")).value_in(sol), "12", "resistor power")
	assert_rational_eq(GoalCondition.exactly("B1", POWER, _q("0")).value_in(sol), "21", "source power 6 * 7/2")


func test_value_in_unavailable() -> void:
	var sol: DcSolution = _ok()
	assert_null(GoalCondition.exactly("W", CURRENT, _q("0")).value_in(sol), "wire current")
	assert_null(GoalCondition.exactly("VMO", VOLTAGE, _q("0")).value_in(sol), "open voltmeter")
	assert_null(GoalCondition.exactly("OMO", RESISTANCE, _q("0")).value_in(sol), "open ohmmeter")
	assert_null(GoalCondition.exactly("R1", RESISTANCE, _q("0")).value_in(sol), "resistance needs an ohmmeter")
	assert_null(GoalCondition.exactly("nope", CURRENT, _q("0")).value_in(sol), "unknown id")
	assert_null(GoalCondition.exactly("AM", CURRENT, _q("0")).value_in(null), "no solution")
	assert_null(GoalCondition.exactly("AM", CURRENT, _q("0")).value_in(_short()), "SHORT")
	assert_null(GoalCondition.exactly("R1", POWER, _q("0")).value_in(_indeterminate()), "INDETERMINATE")


func test_is_met_equals() -> void:
	var sol: DcSolution = _ok()
	assert_true(GoalCondition.exactly("R1", CURRENT, _q("2")).is_met(sol))
	assert_false(GoalCondition.exactly("R1", CURRENT, _q("3")).is_met(sol))
	assert_true(GoalCondition.exactly("R4", CURRENT, _q("1.5")).is_met(sol), "1.5 is exactly 3/2")
	assert_false(GoalCondition.exactly("R4", CURRENT, _q("1.4999")).is_met(sol))
	assert_true(GoalCondition.exactly("OM", RESISTANCE, _q("1")).is_met(sol))


func test_is_met_closed_range_is_inclusive() -> void:
	var sol: DcSolution = _ok()  # R1 carries exactly 2 A
	assert_true(GoalCondition.between("R1", CURRENT, _q("2"), _q("3")).is_met(sol), "low end")
	assert_true(GoalCondition.between("R1", CURRENT, _q("1"), _q("2")).is_met(sol), "high end")
	assert_true(GoalCondition.between("R1", CURRENT, _q("2"), _q("2")).is_met(sol), "point range")
	assert_true(GoalCondition.between("R1", CURRENT, _q("1"), _q("3")).is_met(sol), "inside")
	assert_false(GoalCondition.between("R1", CURRENT, _q("5/2"), _q("3")).is_met(sol), "below")
	assert_false(GoalCondition.between("R1", CURRENT, _q("1"), _q("3/2")).is_met(sol), "above")


func test_is_met_one_sided() -> void:
	var sol: DcSolution = _ok()
	assert_true(GoalCondition.between("R1", CURRENT, _q("2"), null).is_met(sol))
	assert_false(GoalCondition.between("R1", CURRENT, _q("5/2"), null).is_met(sol))
	assert_true(GoalCondition.between("R1", CURRENT, null, _q("2")).is_met(sol))
	assert_false(GoalCondition.between("R1", CURRENT, null, _q("3/2")).is_met(sol))
	# AMR (a -> a2) points with the 2 A flow, so it reads +2.
	assert_true(GoalCondition.between("AMR", CURRENT, _q("0"), null).is_met(sol))
	assert_false(GoalCondition.between("AMR", CURRENT, null, _q("0")).is_met(sol))


func test_is_met_negative_values() -> void:
	var net: DcNetwork = _board()
	net.add_ammeter("BACK", "h", "hh")
	net.add_resistor("RB", "hh", "p", _q("6"))
	# RB: from p (6 V above g) through RB to hh, then BACK from hh to h (= g).
	# The current flows hh -> h, so BACK (h -> hh) reads -1.
	var sol: DcSolution = DcSolver.solve(net)
	assert_rational_eq(GoalCondition.exactly("BACK", CURRENT, _q("0")).value_in(sol), "-1")
	assert_true(GoalCondition.between("BACK", CURRENT, null, _q("0")).is_met(sol))
	assert_true(GoalCondition.exactly("BACK", CURRENT, _q("-1")).is_met(sol))


func test_is_met_false_when_unavailable() -> void:
	var c: GoalCondition = GoalCondition.between("AM", CURRENT, null, _q("100"))
	assert_true(c.is_met(_ok()))
	assert_false(c.is_met(_short()))
	assert_false(c.is_met(_indeterminate()))
	assert_false(c.is_met(null))
	assert_false(GoalCondition.between("VMO", VOLTAGE, null, _q("100")).is_met(_ok()))
	assert_false(GoalCondition.between("OMO", RESISTANCE, _q("0"), null).is_met(_ok()))


func test_resistance_condition_ignores_live_status() -> void:
	assert_true(GoalCondition.exactly("OM", RESISTANCE, _q("1")).is_met(_short()))
	assert_true(GoalCondition.exactly("OM", RESISTANCE, _q("1")).is_met(_indeterminate()))


func test_passes() -> void:
	var c: GoalCondition = GoalCondition.between("x", CURRENT, _q("1"), _q("2"))
	assert_true(c.passes(_q("3/2")))
	assert_false(c.passes(_q("5/2")))
	assert_false(c.passes(null))
	assert_false(GoalCondition.new().passes(_q("1")), "a condition with no test passes nothing")


# --- text -------------------------------------------------------------------------------

func test_unit_and_quantity_name() -> void:
	assert_eq(GoalCondition.exactly("x", CURRENT, _q("1")).unit(), "A")
	assert_eq(GoalCondition.exactly("x", VOLTAGE, _q("1")).unit(), "V")
	assert_eq(GoalCondition.exactly("x", RESISTANCE, _q("1")).unit(), "Ω")
	assert_eq(GoalCondition.exactly("x", POWER, _q("1")).unit(), "W")
	assert_eq(GoalCondition.exactly("x", POWER, _q("1")).quantity_name(), "power")
	assert_eq(GoalCondition.exactly("x", RESISTANCE, _q("1")).quantity_name(), "resistance")


func test_target_text() -> void:
	assert_eq(_parse({"of": "x", "quantity": "current", "equals": "2"}).target_text(), "2 A")
	assert_eq(_parse({"of": "x", "quantity": "current", "min": "1", "max": "3/2"}).target_text(), "1–3/2 A")
	assert_eq(_parse({"of": "x", "quantity": "current", "min": "1"}).target_text(), "≥ 1 A")
	assert_eq(_parse({"of": "x", "quantity": "current", "max": "2"}).target_text(), "≤ 2 A")
	assert_eq(_parse({"of": "x", "quantity": "voltage", "equals": "-0.75"}).target_text(), "-3/4 V")
	assert_eq(_parse({"of": "x", "quantity": "resistance", "equals": "1"}).target_text(), "1 Ω")
	assert_eq(_parse({"of": "x", "quantity": "power", "min": "1/2", "max": "12"}).target_text(), "1/2–12 W")
	assert_eq(GoalCondition.new().target_text(), "---")


func test_reading_text_values() -> void:
	var sol: DcSolution = _ok()
	assert_eq(GoalCondition.exactly("R1", CURRENT, _q("0")).reading_text(sol), "2 A")
	assert_eq(GoalCondition.exactly("R4", CURRENT, _q("0")).reading_text(sol), "3/2 A")
	assert_eq(GoalCondition.exactly("AM", CURRENT, _q("0")).reading_text(sol), "2 A")
	assert_eq(GoalCondition.exactly("B1", CURRENT, _q("0")).reading_text(sol), "7/2 A")
	assert_eq(GoalCondition.exactly("R2", CURRENT, _q("0")).reading_text(sol), "0 A", "no current")
	assert_eq(GoalCondition.exactly("VM", VOLTAGE, _q("0")).reading_text(sol), "6 V")
	assert_eq(GoalCondition.exactly("R1", POWER, _q("0")).reading_text(sol), "12 W")
	assert_eq(GoalCondition.exactly("OM", RESISTANCE, _q("0")).reading_text(sol), "1 Ω")


func test_reading_text_open_meters() -> void:
	var sol: DcSolution = _ok()
	assert_eq(GoalCondition.exactly("OMO", RESISTANCE, _q("0")).reading_text(sol), "OL")
	assert_eq(GoalCondition.exactly("VMO", VOLTAGE, _q("0")).reading_text(sol), "---")
	assert_eq(GoalCondition.exactly("W", CURRENT, _q("0")).reading_text(sol), "---", "wire current")


func test_reading_text_bad_status() -> void:
	var short: DcSolution = _short()
	assert_eq(GoalCondition.exactly("AM", CURRENT, _q("0")).reading_text(short), "SHORT")
	assert_eq(GoalCondition.exactly("VM", VOLTAGE, _q("0")).reading_text(short), "SHORT")
	assert_eq(GoalCondition.exactly("R1", POWER, _q("0")).reading_text(short), "SHORT")
	assert_eq(GoalCondition.exactly("OM", RESISTANCE, _q("0")).reading_text(short), "1 Ω",
			"an ohmmeter does not care about the live circuit")
	var indeterminate: DcSolution = _indeterminate()
	assert_eq(GoalCondition.exactly("AM", CURRENT, _q("0")).reading_text(indeterminate), "???")
	assert_eq(GoalCondition.exactly("VM", VOLTAGE, _q("0")).reading_text(indeterminate), "???")
	var error: DcSolution = _error()
	assert_error_pushed("Rational.mul")
	assert_error_pushed("DcSolver.solve")
	assert_eq(error.status, DcSolution.Status.ERROR)
	assert_eq(GoalCondition.exactly("AM", CURRENT, _q("0")).reading_text(error), "ERROR")
	assert_eq(GoalCondition.exactly("R1", POWER, _q("0")).reading_text(error), "ERROR")


func test_reading_text_invalid_ohmmeter_and_bad_targets() -> void:
	var net: DcNetwork = DcNetwork.new()
	net.add_resistor("R1", "a", "m", Rational.new(INT_MAX))
	net.add_resistor("R2", "m", "b", Rational.new(INT_MAX))
	net.add_ohmmeter("OM", "a", "b")
	var sol: DcSolution = DcSolver.solve(net)
	assert_error_pushed("Rational.add")
	assert_error_pushed("ohmmeter 'OM'")
	assert_eq(GoalCondition.exactly("OM", RESISTANCE, _q("0")).reading_text(sol), "ERROR")
	assert_eq(GoalCondition.exactly("R1", RESISTANCE, _q("0")).reading_text(sol), "ERROR",
			"resistance of a non-ohmmeter")
	assert_eq(GoalCondition.exactly("nope", CURRENT, _q("0")).reading_text(sol), "ERROR", "unknown id")
	assert_eq(GoalCondition.exactly("R1", CURRENT, _q("0")).reading_text(null), "ERROR", "no solution")
