extends TestCase
## Tests for DiodeModel, PwlCondition and the PwlDevice base class.

const AT_MOST: PwlCondition.Relation = PwlCondition.Relation.AT_MOST
const AT_LEAST: PwlCondition.Relation = PwlCondition.Relation.AT_LEAST
const BELOW: PwlCondition.Relation = PwlCondition.Relation.BELOW
const ABOVE: PwlCondition.Relation = PwlCondition.Relation.ABOVE


func _q(text: String) -> Rational:
	return Rational.parse(text)


# --- PwlCondition ----------------------------------------------------------------------

func test_voltage_condition() -> void:
	var c: PwlCondition = PwlCondition.voltage(0, AT_MOST, _q("7/10"))
	assert_not_null(c)
	assert_eq(c.quantity, PwlCondition.Quantity.BRANCH_VOLTAGE)
	assert_eq(c.branch, 0)
	assert_eq(c.relation, AT_MOST)
	assert_rational_eq(c.bound, "7/10")
	assert_false(c.is_strict())
	assert_true(c.holds(_q("7/10")), "the boundary holds for <=")
	assert_true(c.holds(_q("-5")))
	assert_false(c.holds(_q("71/100")))
	assert_false(c.holds(null))
	assert_null(c.coefficient(0), "a voltage condition has no coefficients")
	assert_eq(c.coefficient_count(), 0)
	assert_eq(c.to_text(), "V0 <= 7/10")


func test_every_relation() -> void:
	var at_least: PwlCondition = PwlCondition.voltage(1, AT_LEAST, _q("-51/10"))
	assert_true(at_least.holds(_q("-51/10")))
	assert_false(at_least.holds(_q("-6")))
	assert_eq(at_least.to_text(), "V1 >= -51/10")
	var above: PwlCondition = PwlCondition.current(0, ABOVE, _q("0"))
	assert_true(above.is_strict())
	assert_false(above.holds(_q("0")), "the boundary fails for >")
	assert_true(above.holds(_q("1/1000000")))
	assert_eq(above.to_text(), "I0 > 0")
	var below: PwlCondition = PwlCondition.current(2, BELOW, _q("0"))
	assert_true(below.is_strict())
	assert_false(below.holds(_q("0")))
	assert_true(below.holds(_q("-1/3")))
	assert_eq(below.to_text(), "I2 < 0")


func test_current_sum_condition() -> void:
	# A future transistor's saturation test: Ic - 100 Ib <= 0 (branch 0 base,
	# branch 1 collector).
	var coefficients: Array[Rational] = [_q("-100"), _q("1")]
	var c: PwlCondition = PwlCondition.current_sum(coefficients, AT_MOST, _q("0"))
	assert_eq(c.quantity, PwlCondition.Quantity.BRANCH_CURRENTS)
	assert_eq(c.branch, -1)
	assert_eq(c.coefficient_count(), 2)
	assert_rational_eq(c.coefficient(0), "-100")
	assert_rational_eq(c.coefficient(1), "1")
	assert_rational_eq(c.coefficient(5), "0", "an unlisted branch counts as zero")
	assert_rational_eq(c.coefficient(-1), "0")
	assert_eq(c.to_text(), "-100 I0 + I1 <= 0")
	coefficients[0] = _q("5")
	assert_rational_eq(c.coefficient(0), "-100", "the condition keeps its own copy")
	var sparse: Array[Rational] = [null, _q("-1"), _q("0")]
	var minus: PwlCondition = PwlCondition.current_sum(sparse, AT_LEAST, _q("3/2"))
	assert_rational_eq(minus.coefficient(0), "0")
	assert_eq(minus.to_text(), "-I1 >= 3/2")


func test_condition_rejects_bad_input() -> void:
	assert_null(PwlCondition.voltage(-1, AT_MOST, _q("1")))
	assert_error_pushed("PwlCondition.voltage")
	assert_null(PwlCondition.voltage(0, AT_MOST, null))
	assert_error_pushed("PwlCondition.voltage")
	assert_null(PwlCondition.current(-2, ABOVE, _q("0")))
	assert_error_pushed("PwlCondition.current")
	assert_null(PwlCondition.current(0, ABOVE, Rational.new(1, 0)))
	assert_error_pushed("zero denominator")
	assert_error_pushed("PwlCondition.current")
	var zeros: Array[Rational] = [_q("0"), null]
	assert_null(PwlCondition.current_sum(zeros, AT_MOST, _q("0")))
	assert_error_pushed("at least one non-zero coefficient")
	var none: Array[Rational] = []
	assert_null(PwlCondition.current_sum(none, AT_MOST, _q("0")))
	assert_error_pushed("at least one non-zero coefficient")
	var invalid: Array[Rational] = [Rational.new(1, 0)]
	assert_error_pushed("zero denominator")
	assert_null(PwlCondition.current_sum(invalid, AT_MOST, _q("0")))
	assert_error_pushed("invalid Rational")


# --- DiodeModel ------------------------------------------------------------------------

func test_plain_diode_model() -> void:
	var d: DiodeModel = DiodeModel.diode(_q("7/10"))
	assert_not_null(d)
	assert_false(d.is_zener())
	assert_rational_eq(d.forward_drop, "7/10")
	assert_null(d.zener_voltage)
	assert_eq(d.terminal_names(), ["anode", "cathode"] as Array[String])
	assert_eq(d.terminal_count(), 2)
	assert_eq(d.branch_count(), 1)
	assert_eq(d.branch_terminals(0), [0, 1] as Array[int])
	assert_eq(d.branch_terminals(1), [] as Array[int])
	assert_eq(d.state_count(), 2)
	assert_eq(d.state_name(DiodeModel.State.OFF), "off")
	assert_eq(d.state_name(DiodeModel.State.ON), "on")
	assert_eq(d.state_name(DiodeModel.State.BREAKDOWN), "", "a plain diode has no breakdown")
	assert_eq(d.state_name(-1), "")
	assert_eq(d.network_kind(), DcNetwork.Kind.DIODE)
	assert_eq(d.parameters_text(), "7/10")


func test_plain_diode_stand_ins_and_conditions() -> void:
	var d: DiodeModel = DiodeModel.diode(_q("2"))
	assert_eq(d.branch_kind(DiodeModel.State.OFF, 0), PwlDevice.BranchKind.OPEN)
	assert_null(d.branch_value(DiodeModel.State.OFF, 0))
	assert_eq(d.branch_kind(DiodeModel.State.ON, 0), PwlDevice.BranchKind.VOLTAGE)
	assert_rational_eq(d.branch_value(DiodeModel.State.ON, 0), "2")
	assert_null(d.branch_value(DiodeModel.State.ON, 1), "no second branch")
	assert_eq(d.branch_kind(DiodeModel.State.BREAKDOWN, 0), PwlDevice.BranchKind.OPEN)
	assert_null(d.branch_value(DiodeModel.State.BREAKDOWN, 0))
	var off: Array[PwlCondition] = d.conditions(DiodeModel.State.OFF)
	assert_eq(off.size(), 1)
	assert_eq(off[0].to_text(), "V0 <= 2")
	var on: Array[PwlCondition] = d.conditions(DiodeModel.State.ON)
	assert_eq(on.size(), 1)
	assert_eq(on[0].to_text(), "I0 > 0")
	assert_eq(d.conditions(DiodeModel.State.BREAKDOWN).size(), 0)
	assert_eq(d.conditions(-1).size(), 0)


func test_zener_model() -> void:
	var z: DiodeModel = DiodeModel.zener(_q("7/10"), _q("51/10"))
	assert_true(z.is_zener())
	assert_rational_eq(z.zener_voltage, "51/10")
	assert_eq(z.state_count(), 3)
	assert_eq(z.state_name(DiodeModel.State.OFF), "off")
	assert_eq(z.state_name(DiodeModel.State.ON), "forward")
	assert_eq(z.state_name(DiodeModel.State.BREAKDOWN), "breakdown")
	assert_eq(z.state_name(3), "")
	assert_eq(z.network_kind(), DcNetwork.Kind.ZENER)
	assert_eq(z.parameters_text(), "7/10 51/10")
	assert_eq(z.branch_kind(DiodeModel.State.BREAKDOWN, 0), PwlDevice.BranchKind.VOLTAGE)
	assert_rational_eq(z.branch_value(DiodeModel.State.BREAKDOWN, 0), "-51/10")
	assert_rational_eq(z.branch_value(DiodeModel.State.ON, 0), "7/10")
	var off: Array[PwlCondition] = z.conditions(DiodeModel.State.OFF)
	assert_eq(off.size(), 2)
	assert_eq(off[0].to_text(), "V0 <= 7/10")
	assert_eq(off[1].to_text(), "V0 >= -51/10")
	assert_eq(z.conditions(DiodeModel.State.BREAKDOWN)[0].to_text(), "I0 < 0")


func test_boundary_points_belong_to_off_only() -> void:
	# At v = Vf with i = 0, OFF holds and ON does not; likewise at v = -Vz.
	var z: DiodeModel = DiodeModel.zener(_q("7/10"), _q("51/10"))
	var off: Array[PwlCondition] = z.conditions(DiodeModel.State.OFF)
	assert_true(off[0].holds(_q("7/10")) and off[1].holds(_q("7/10")))
	assert_false(z.conditions(DiodeModel.State.ON)[0].holds(_q("0")))
	assert_true(off[0].holds(_q("-51/10")) and off[1].holds(_q("-51/10")))
	assert_false(z.conditions(DiodeModel.State.BREAKDOWN)[0].holds(_q("0")))


func test_same_as() -> void:
	var d: DiodeModel = DiodeModel.diode(_q("7/10"))
	assert_true(d.same_as(DiodeModel.diode(_q("0.7"))))
	assert_false(d.same_as(DiodeModel.diode(_q("3/10"))))
	assert_false(d.same_as(DiodeModel.zener(_q("7/10"), _q("5"))))
	assert_false(d.same_as(null))
	var z: DiodeModel = DiodeModel.zener(_q("7/10"), _q("5"))
	assert_true(z.same_as(DiodeModel.zener(_q("7/10"), _q("5"))))
	assert_false(z.same_as(DiodeModel.zener(_q("7/10"), _q("6"))))


func test_zero_drop_is_allowed() -> void:
	var d: DiodeModel = DiodeModel.diode(_q("0"))
	assert_not_null(d)
	assert_rational_eq(d.branch_value(DiodeModel.State.ON, 0), "0")


func test_model_rejects_bad_values() -> void:
	assert_null(DiodeModel.diode(null))
	assert_error_pushed("DiodeModel.diode: the forward drop must be")
	assert_null(DiodeModel.diode(_q("-1/2")))
	assert_error_pushed("got -1/2")
	assert_null(DiodeModel.diode(Rational.new(3, 0)))
	assert_error_pushed("zero denominator")
	assert_error_pushed("DiodeModel.diode")
	assert_null(DiodeModel.zener(_q("-1"), _q("5")))
	assert_error_pushed("DiodeModel.zener: the forward drop")
	assert_null(DiodeModel.zener(_q("7/10"), _q("0")))
	assert_error_pushed("Zener voltage must be a valid value > 0, got 0")
	assert_null(DiodeModel.zener(_q("7/10"), null))
	assert_error_pushed("got null")


# --- PwlDevice base ----------------------------------------------------------------------

func test_base_class_methods_report_not_implemented() -> void:
	var base: PwlDevice = PwlDevice.new()
	assert_eq(base.terminal_names().size(), 0)
	assert_error_pushed("terminal_names: not implemented")
	assert_eq(base.terminal_count(), 0)
	assert_error_pushed("terminal_names: not implemented")
	assert_eq(base.branch_count(), 0)
	assert_error_pushed("branch_count: not implemented")
	assert_eq(base.branch_terminals(0).size(), 0)
	assert_error_pushed("branch_terminals: not implemented")
	assert_eq(base.state_count(), 0)
	assert_error_pushed("state_count: not implemented")
	assert_eq(base.state_name(0), "")
	assert_error_pushed("state_name: not implemented")
	assert_eq(base.branch_kind(0, 0), PwlDevice.BranchKind.OPEN)
	assert_error_pushed("branch_kind: not implemented")
	assert_null(base.branch_value(0, 0))
	assert_error_pushed("branch_value: not implemented")
	assert_eq(base.conditions(0).size(), 0)
	assert_error_pushed("conditions: not implemented")
	assert_eq(base.network_kind(), -1)
	assert_error_pushed("network_kind: not implemented")
	assert_eq(base.parameters_text(), "")
	assert_error_pushed("parameters_text: not implemented")
