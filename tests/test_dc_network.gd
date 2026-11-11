extends TestCase
## Tests for DcNetwork.


func test_adds_every_kind() -> void:
	var net: DcNetwork = DcNetwork.new()
	assert_true(net.add_wire("w1", "a", "b"))
	assert_true(net.add_resistor("r1", "b", "c", Rational.new(3, 2)))
	assert_true(net.add_voltage_source("v1", "c", "a", Rational.new(6)))
	assert_true(net.add_ammeter("am1", "a", "d"))
	assert_true(net.add_voltmeter("vm1", "d", "c"))
	assert_true(net.add_ohmmeter("om1", "a", "c"))
	assert_eq(net.element_count(), 6)
	assert_eq(net.get_kind("w1"), DcNetwork.Kind.WIRE)
	assert_eq(net.get_kind("r1"), DcNetwork.Kind.RESISTOR)
	assert_eq(net.get_kind("v1"), DcNetwork.Kind.VOLTAGE_SOURCE)
	assert_eq(net.get_kind("am1"), DcNetwork.Kind.AMMETER)
	assert_eq(net.get_kind("vm1"), DcNetwork.Kind.VOLTMETER)
	assert_eq(net.get_kind("om1"), DcNetwork.Kind.OHMMETER)


func test_accessors() -> void:
	var net: DcNetwork = DcNetwork.new()
	net.add_resistor("r1", "b", "c", Rational.new(3, 2))
	net.add_voltage_source("v1", "plus", "minus", Rational.new(-5))
	net.add_wire("w1", "a", "b")
	assert_true(net.has_element("r1"))
	assert_false(net.has_element("nope"))
	assert_eq(net.get_node_a("v1"), "plus")
	assert_eq(net.get_node_b("v1"), "minus")
	assert_rational_eq(net.get_value("r1"), "3/2")
	assert_rational_eq(net.get_value("v1"), "-5")
	assert_null(net.get_value("w1"))
	var expected_ids: Array[String] = ["r1", "v1", "w1"]
	assert_eq(net.get_element_ids(), expected_ids)
	var expected_nodes: Array[String] = ["a", "b", "c", "minus", "plus"]
	assert_eq(net.get_nodes(), expected_nodes)


func test_unknown_ids_give_sentinels_without_errors() -> void:
	var net: DcNetwork = DcNetwork.new()
	assert_eq(net.get_kind("x"), -1)
	assert_eq(net.get_node_a("x"), "")
	assert_eq(net.get_node_b("x"), "")
	assert_null(net.get_value("x"))
	assert_eq(net.element_count(), 0)
	var no_nodes: Array[String] = []
	assert_eq(net.get_nodes(), no_nodes)


func test_voltage_source_may_be_zero_or_negative() -> void:
	var net: DcNetwork = DcNetwork.new()
	assert_true(net.add_voltage_source("v0", "a", "b", Rational.new(0)))
	assert_true(net.add_voltage_source("vn", "a", "b", Rational.new(-3, 4)))


func test_same_node_at_both_ends_is_allowed() -> void:
	var net: DcNetwork = DcNetwork.new()
	assert_true(net.add_resistor("r", "a", "a", Rational.new(1)))
	assert_true(net.add_voltage_source("v", "b", "b", Rational.new(1)))


func test_rejects_duplicate_ids_across_kinds() -> void:
	var net: DcNetwork = DcNetwork.new()
	assert_true(net.add_wire("e1", "a", "b"))
	assert_false(net.add_resistor("e1", "a", "b", Rational.new(1)))
	assert_error_pushed("duplicate element id 'e1'")
	assert_false(net.add_ammeter("e1", "a", "b"))
	assert_error_pushed("duplicate element id 'e1'")
	assert_eq(net.element_count(), 1)
	assert_eq(net.get_kind("e1"), DcNetwork.Kind.WIRE)


func test_rejects_empty_names() -> void:
	var net: DcNetwork = DcNetwork.new()
	assert_false(net.add_wire("", "a", "b"))
	assert_error_pushed("element id must not be empty")
	assert_false(net.add_voltmeter("v", "", "b"))
	assert_error_pushed("empty node name")
	assert_false(net.add_ohmmeter("o", "a", ""))
	assert_error_pushed("empty node name")
	assert_eq(net.element_count(), 0)


func test_rejects_bad_resistances() -> void:
	var net: DcNetwork = DcNetwork.new()
	assert_false(net.add_resistor("r0", "a", "b", Rational.new(0)))
	assert_error_pushed("must be > 0 ohms")
	assert_false(net.add_resistor("rn", "a", "b", Rational.new(-2)))
	assert_error_pushed("must be > 0 ohms")
	assert_false(net.add_resistor("rnull", "a", "b", null))
	assert_error_pushed("has no valid value")
	var invalid: Rational = Rational.new(1, 0)
	assert_error_pushed("zero denominator")
	assert_false(net.add_resistor("rinv", "a", "b", invalid))
	assert_error_pushed("has no valid value")
	assert_eq(net.element_count(), 0)


func test_rejects_bad_source_values() -> void:
	var net: DcNetwork = DcNetwork.new()
	assert_false(net.add_voltage_source("v", "a", "b", null))
	assert_error_pushed("has no valid value")
	var invalid: Rational = Rational.new(3, 0)
	assert_error_pushed("zero denominator")
	assert_false(net.add_voltage_source("v", "a", "b", invalid))
	assert_error_pushed("has no valid value")
	assert_eq(net.element_count(), 0)


func test_duplicate_network_is_independent() -> void:
	var net: DcNetwork = DcNetwork.new()
	net.add_resistor("r1", "a", "b", Rational.new(2))
	var copy: DcNetwork = net.duplicate_network()
	copy.add_wire("w1", "b", "c")
	assert_eq(net.element_count(), 1)
	assert_eq(copy.element_count(), 2)
	assert_rational_eq(copy.get_value("r1"), "2")


func test_to_text_is_sorted_and_complete() -> void:
	var net: DcNetwork = DcNetwork.new()
	net.add_voltmeter("vm", "x", "y")
	net.add_voltage_source("b1", "p", "g", Rational.new(9, 2))
	net.add_resistor("r1", "p", "g", Rational.new(3))
	net.add_wire("w", "g", "y")
	assert_eq(net.to_text(), "voltage_source b1 p g 9/2\nresistor r1 p g 3\nvoltmeter vm x y\nwire w g y")
	assert_eq(DcNetwork.new().to_text(), "")


func test_kind_name() -> void:
	assert_eq(DcNetwork.kind_name(DcNetwork.Kind.AMMETER), "ammeter")
	assert_eq(DcNetwork.kind_name(DcNetwork.Kind.OHMMETER), "ohmmeter")
	assert_eq(DcNetwork.kind_name(-1), "")
	assert_eq(DcNetwork.kind_name(99), "")
