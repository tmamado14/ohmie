extends TestCase
## Tests for QuantityText (engineering text and prefixed values) and the
## style switch on GoalCondition.

const ENG: QuantityText.Style = QuantityText.Style.ENGINEERING
const FRACTION: QuantityText.Style = QuantityText.Style.FRACTION
const CURRENT: GoalCondition.Quantity = GoalCondition.Quantity.CURRENT
const VOLTAGE: GoalCondition.Quantity = GoalCondition.Quantity.VOLTAGE
const RESISTANCE: GoalCondition.Quantity = GoalCondition.Quantity.RESISTANCE
const INT_MAX: int = 9223372036854775807


func _q(text: String) -> Rational:
	return Rational.parse(text)


func _eng(text: String, unit: String) -> String:
	return QuantityText.format(_q(text), unit, ENG)


# --- engineering format ------------------------------------------------------------

func test_engineering_examples() -> void:
	assert_eq(_eng("43/10000", "A"), "4.3 mA", "the diode current")
	assert_eq(_eng("2200", "Ω"), "2.2 kΩ")
	assert_eq(_eng("-6", "V"), "-6 V")
	assert_eq(_eng("12", "V"), "12 V")
	assert_eq(_eng("1/50", "A"), "20 mA")
	assert_eq(_eng("1/300", "A"), "10/3 mA", "a third is never rounded")
	assert_eq(_eng("-43/10000", "A"), "-4.3 mA")


func test_engineering_volts_and_ohms_never_go_below_the_base_unit() -> void:
	assert_eq(_eng("7/10", "V"), "0.7 V")
	assert_eq(_eng("1/20", "V"), "0.05 V")
	assert_eq(_eng("1/8", "V"), "0.125 V")
	assert_eq(_eng("1/2", "Ω"), "0.5 Ω")
	assert_eq(_eng("1/3", "V"), "1/3 V")
	assert_eq(_eng("1500", "V"), "1.5 kV", "above the base unit volts use k")


func test_engineering_amps_and_watts_use_milli_below_one() -> void:
	assert_eq(_eng("1/3000", "A"), "1/3 mA", "below 1 m they stay in m")
	assert_eq(_eng("1/2000000", "A"), "0.0005 mA")
	assert_eq(_eng("1/8", "W"), "125 mW")
	assert_eq(_eng("1/2", "A"), "500 mA")


func test_engineering_zero_and_prefix_edges() -> void:
	assert_eq(_eng("0", "A"), "0 A")
	assert_eq(_eng("999", "Ω"), "999 Ω")
	assert_eq(_eng("1000", "Ω"), "1 kΩ")
	assert_eq(_eng("999999", "Ω"), "999.999 kΩ")
	assert_eq(_eng("1/1000", "A"), "1 mA")
	assert_eq(_eng("999/1000", "A"), "999 mA")
	assert_eq(_eng("1", "A"), "1 A")


func test_engineering_never_micro_and_mega() -> void:
	assert_eq(_eng("47/1000000", "A"), "0.047 mA", "µ is never printed")
	assert_eq(_eng("-1/400000", "A"), "-0.0025 mA")
	assert_eq(_eng("2200000", "Ω"), "2.2 MΩ")
	assert_eq(_eng("4700000000", "Ω"), "4700 MΩ", "1000 M or more keeps M")
	assert_eq(_eng("-1/1000000", "V"), "-0.000001 V")


func test_fraction_style_is_world_one_text() -> void:
	assert_eq(QuantityText.format(_q("3/2"), "A"), "3/2 A", "the default style")
	assert_eq(QuantityText.format(_q("3/2"), "A", FRACTION), "3/2 A")
	assert_eq(QuantityText.format(_q("2200"), "Ω", FRACTION), "2200 Ω")
	assert_eq(QuantityText.format(_q("-3/4"), "V", FRACTION), "-3/4 V")
	assert_eq(QuantityText.format(_q("0"), "A", FRACTION), "0 A")


func test_format_bad_values() -> void:
	assert_eq(QuantityText.format(null, "A", ENG), "ERROR")
	var invalid: Rational = Rational.new(1, 0)
	assert_error_pushed("zero denominator")
	assert_eq(QuantityText.format(invalid, "A"), "ERROR")
	assert_eq(QuantityText.split(null, "A").size(), 0)


func test_split() -> void:
	assert_eq(QuantityText.split(_q("43/10000"), "A", ENG), PackedStringArray(["4.3", "m"]))
	assert_eq(QuantityText.split(_q("43/10000"), "V", ENG), PackedStringArray(["0.0043", ""]))
	assert_eq(QuantityText.split(_q("0"), "A", ENG), PackedStringArray(["0", ""]))
	assert_eq(QuantityText.split(_q("43/10000"), "A"), PackedStringArray(["43/10000", ""]))


func test_unscalable_value_falls_back_to_the_exact_fraction() -> void:
	# 2^62 / (2^63 - 1), about 0.5 A, with a huge odd denominator: scaling to
	# m would overflow, so the exact base-unit fraction is printed instead (no
	# error, no rounding).
	var half: Rational = Rational.new(4611686018427387904, INT_MAX)
	assert_eq(QuantityText.format(half, "A", ENG), "4611686018427387904/9223372036854775807 A")


func test_decimal_text() -> void:
	assert_eq(QuantityText.decimal_text(_q("43/10")), "4.3")
	assert_eq(QuantityText.decimal_text(_q("-1/8")), "-0.125")
	assert_eq(QuantityText.decimal_text(_q("7")), "7")
	assert_eq(QuantityText.decimal_text(_q("1/20")), "0.05")
	assert_eq(QuantityText.decimal_text(_q("10/3")), "10/3")
	assert_eq(QuantityText.decimal_text(_q("7/6")), "7/6", "a factor 3 beside a 2")
	assert_eq(QuantityText.decimal_text(_q("0")), "0")
	assert_eq(QuantityText.decimal_text(null), "ERROR")
	# 1/2^62 needs 62 decimal places: does not fit, so the fraction is kept.
	assert_eq(QuantityText.decimal_text(Rational.new(1, 4611686018427387904)), "1/4611686018427387904")


func test_format_range() -> void:
	assert_eq(QuantityText.format_range(_q("1/200"), _q("1/50"), "A", ENG), "5–20 mA")
	assert_eq(QuantityText.format_range(_q("1/2000"), _q("1/500"), "A", ENG), "0.5–2 mA")
	assert_eq(QuantityText.format_range(_q("1/2"), _q("2"), "A", ENG), "500 mA–2 A")
	assert_eq(QuantityText.format_range(_q("1/2"), _q("2"), "V", ENG), "0.5–2 V")
	assert_eq(QuantityText.format_range(_q("0"), _q("1/50"), "A", ENG), "0–20 mA")
	assert_eq(QuantityText.format_range(_q("1"), _q("3/2"), "A"), "1–3/2 A")
	assert_eq(QuantityText.format_range(_q("1"), _q("3/2"), "A", FRACTION, "-"), "1-3/2 A")
	assert_eq(QuantityText.format_range(null, _q("1"), "A", ENG), "ERROR")


# --- parse -----------------------------------------------------------------------------

func test_parse_part_values() -> void:
	assert_rational_eq(QuantityText.parse("1k"), "1000")
	assert_rational_eq(QuantityText.parse("4.7k"), "4700")
	assert_rational_eq(QuantityText.parse("220"), "220")
	assert_rational_eq(QuantityText.parse("0.7"), "7/10")
	assert_rational_eq(QuantityText.parse("1/2"), "1/2")
	assert_rational_eq(QuantityText.parse("2.2M"), "2200000")
	assert_rational_eq(QuantityText.parse("-6"), "-6")
	assert_rational_eq(QuantityText.parse("10m"), "1/100")
	assert_rational_eq(QuantityText.parse("100u"), "1/10000")
	assert_rational_eq(QuantityText.parse("47µ"), "47/1000000")
	assert_rational_eq(QuantityText.parse(" 3.3k "), "3300", "surrounding spaces")
	assert_rational_eq(QuantityText.parse("1/3k"), "1000/3")
	assert_rational_eq(QuantityText.parse("0"), "0")
	assert_rational_eq(QuantityText.parse("5.1"), "51/10")


func test_parse_round_trips_engineering_numbers() -> void:
	for text: String in ["43/10000", "2200", "7/10", "1/300", "47/1000000", "2200000"]:
		var value: Rational = _q(text)
		var parts: PackedStringArray = QuantityText.split(value, "A", ENG)
		var prefix: String = "u" if parts[1] == QuantityText.MICRO else parts[1]
		assert_rational_eq(QuantityText.parse(parts[0] + prefix), text, text)


func test_parse_rejects_garbage() -> void:
	for text: String in ["", "k", "1kk", "abc", "1.2.3", "--1", "1x", "1 k", "1.k", ".5", "1e3",
			"1K", "1/", "/2", "-", "4.7kΩ"]:
		assert_null(QuantityText.parse(text), "'%s'" % text)
		assert_error_pushed("QuantityText.parse: '%s' is not a value" % text, "'%s'" % text)


func test_parse_rejects_zero_denominator_and_overflow() -> void:
	assert_null(QuantityText.parse("1/0"))
	assert_error_pushed("zero denominator")
	assert_error_pushed("QuantityText.parse: '1/0' is not a valid value")
	assert_null(QuantityText.parse("99999999999999999999"))
	assert_error_pushed("does not fit in 64 bits")
	assert_error_pushed("QuantityText.parse: '99999999999999999999'")
	assert_null(QuantityText.parse("9223372036854775807k"))
	assert_error_pushed("QuantityText.parse: '9223372036854775807k' does not fit in 64 bits")


# --- GoalCondition style ----------------------------------------------------------------

func _diode_solution() -> DcSolution:
	# 5 V, 1 kOhm, silicon diode: 4.3 mA, 4.3 V on the resistor.
	var net: DcNetwork = DcNetwork.new()
	net.add_voltage_source("B1", "p", "g", _q("5"))
	net.add_resistor("R1", "p", "x", _q("1000"))
	net.add_diode("D1", "x", "g", _q("7/10"))
	net.add_voltmeter("VM", "p", "x")
	net.add_ohmmeter("OM", "p", "x")
	return DcSolver.solve(net)


func test_goal_condition_default_style_is_unchanged() -> void:
	var sol: DcSolution = _diode_solution()
	var current: GoalCondition = GoalCondition.exactly("D1", CURRENT, _q("43/10000"))
	assert_eq(current.style, FRACTION)
	assert_eq(current.target_text(), "43/10000 A")
	assert_eq(current.reading_text(sol), "43/10000 A")
	assert_true(current.is_met(sol))


func test_goal_condition_engineering_style() -> void:
	var sol: DcSolution = _diode_solution()
	var current: GoalCondition = GoalCondition.exactly("D1", CURRENT, _q("43/10000"))
	current.style = ENG
	assert_eq(current.target_text(), "4.3 mA")
	assert_eq(current.reading_text(sol), "4.3 mA")
	assert_true(current.is_met(sol), "style changes text only")
	var volts: GoalCondition = GoalCondition.exactly("VM", VOLTAGE, _q("43/10"))
	volts.style = ENG
	assert_eq(volts.reading_text(sol), "4.3 V")
	var drop: GoalCondition = GoalCondition.exactly("D1", VOLTAGE, _q("7/10"))
	drop.style = ENG
	assert_eq(drop.reading_text(sol), "0.7 V")
	var ohms: GoalCondition = GoalCondition.exactly("OM", RESISTANCE, _q("1000"))
	ohms.style = ENG
	assert_eq(ohms.reading_text(sol), "1 kΩ")
	var lit: GoalCondition = GoalCondition.between("D1", CURRENT, _q("1/1000"), _q("1/50"))
	lit.style = ENG
	assert_eq(lit.target_text(), "1–20 mA")
	assert_true(lit.is_met(sol), "4.3 mA is within 1-20 mA")
	var rated: GoalCondition = GoalCondition.between("D1", CURRENT, _q("1/200"), _q("1/50"))
	rated.style = ENG
	assert_false(rated.is_met(sol), "4.3 mA is below 5 mA")
	var at_least: GoalCondition = GoalCondition.between("D1", CURRENT, _q("1/2000"), null)
	at_least.style = ENG
	assert_eq(at_least.target_text(), "≥ 0.5 mA")
	var at_most: GoalCondition = GoalCondition.between("D1", CURRENT, null, _q("1/50"))
	at_most.style = ENG
	assert_eq(at_most.target_text(), "≤ 20 mA")


# --- goal values parsed with prefixes ------------------------------------------------------

func test_goal_values_accept_prefixes() -> void:
	var milli: GoalCondition = GoalCondition.from_dictionary({"of": "x", "quantity": "current", "equals": "4.3m"})
	assert_rational_eq(milli.equals, "43/10000")
	var kilo: GoalCondition = GoalCondition.from_dictionary({"of": "x", "quantity": "voltage", "min": "1k",
			"max": "2.2k"})
	assert_rational_eq(kilo.min_value, "1000")
	assert_rational_eq(kilo.max_value, "2200")


func test_goal_values_without_prefixes_are_unchanged() -> void:
	for text: String in ["2", "3/2", "0.5", "-0.75", "0", "12", "51/10"]:
		var condition: GoalCondition = GoalCondition.from_dictionary({"of": "x", "quantity": "current",
				"equals": text})
		assert_true(condition.equals.equals(Rational.parse(text)), text)


func test_goal_value_with_a_bad_prefix_is_rejected() -> void:
	assert_null(GoalCondition.from_dictionary({"of": "x", "quantity": "current", "equals": "4.3x"}))
	assert_error_pushed("Rational.parse: '4.3x' is not a number")
	assert_error_pushed("'equals' of 'x' is not a number")


func test_quiet_parsing_pushes_nothing() -> void:
	assert_null(QuantityText.parse("abc", true))
	assert_null(QuantityText.parse("1/0", true))
	assert_null(QuantityText.parse("9223372036854775807k", true))
	assert_null(Rational.parse("two", true))
	assert_null(Rational.parse("99999999999999999999", true))
	assert_rational_eq(QuantityText.parse("4.7k", true), "4700")
	assert_rational_eq(Rational.parse("3/2", true), "3/2")
