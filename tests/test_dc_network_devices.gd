extends TestCase
## Tests for the device elements of DcNetwork (add_diode, add_zener and the
## accessors around them).


func _q(text: String) -> Rational:
	return Rational.parse(text)


func test_add_diode() -> void:
	var net: DcNetwork = DcNetwork.new()
	assert_false(net.has_devices())
	assert_true(net.add_diode("D1", "a", "k", _q("7/10")))
	assert_true(net.has_devices())
	assert_eq(net.get_kind("D1"), DcNetwork.Kind.DIODE)
	assert_eq(net.get_node_a("D1"), "a", "the anode is the first node")
	assert_eq(net.get_node_b("D1"), "k", "the cathode is the second node")
	assert_null(net.get_value("D1"), "device parameters live on get_device")
	var model: DiodeModel = net.get_device("D1")
	assert_not_null(model)
	assert_false(model.is_zener())
	assert_rational_eq(model.forward_drop, "7/10")
	assert_eq(net.get_nodes(), ["a", "k"] as Array[String])
	assert_eq(net.element_count(), 1)


func test_add_zener() -> void:
	var net: DcNetwork = DcNetwork.new()
	assert_true(net.add_zener("Z1", "g", "n", _q("7/10"), _q("51/10")))
	assert_eq(net.get_kind("Z1"), DcNetwork.Kind.ZENER)
	var model: DiodeModel = net.get_device("Z1")
	assert_true(model.is_zener())
	assert_rational_eq(model.zener_voltage, "51/10")
	assert_true(net.has_devices())


func test_get_device_on_other_elements() -> void:
	var net: DcNetwork = DcNetwork.new()
	net.add_resistor("R1", "a", "b", _q("2"))
	net.add_voltage_source("B1", "a", "b", _q("6"))
	assert_null(net.get_device("R1"))
	assert_null(net.get_device("B1"))
	assert_null(net.get_device("nope"))
	assert_false(net.has_devices())


func test_kind_names_and_device_kinds() -> void:
	assert_eq(DcNetwork.kind_name(DcNetwork.Kind.DIODE), "diode")
	assert_eq(DcNetwork.kind_name(DcNetwork.Kind.ZENER), "zener")
	assert_eq(DcNetwork.kind_name(DcNetwork.Kind.OHMMETER), "ohmmeter", "older kinds keep their numbers")
	assert_true(DcNetwork.is_device_kind(DcNetwork.Kind.DIODE))
	assert_true(DcNetwork.is_device_kind(DcNetwork.Kind.ZENER))
	assert_false(DcNetwork.is_device_kind(DcNetwork.Kind.RESISTOR))
	assert_false(DcNetwork.is_device_kind(DcNetwork.Kind.VOLTAGE_SOURCE))
	assert_false(DcNetwork.is_device_kind(-1))


func test_to_text_and_duplicate() -> void:
	var net: DcNetwork = DcNetwork.new()
	net.add_voltage_source("B1", "p", "g", _q("5"))
	net.add_diode("D1", "p", "x", _q("2"))
	net.add_zener("Z1", "g", "x", _q("7/10"), _q("51/10"))
	assert_eq(net.to_text(), "voltage_source B1 p g 5\ndiode D1 p x 2\nzener Z1 g x 7/10 51/10")
	var copy: DcNetwork = net.duplicate_network()
	assert_eq(copy.to_text(), net.to_text())
	assert_true(copy.has_devices())
	assert_true(copy.get_device("D1") == net.get_device("D1"), "models are immutable and shared")
	copy.add_diode("D2", "x", "g", _q("3/10"))
	assert_false(net.has_element("D2"), "the copy is independent")


func test_rejects_bad_devices() -> void:
	var net: DcNetwork = DcNetwork.new()
	assert_false(net.add_diode("", "a", "k", _q("1")))
	assert_error_pushed("element id must not be empty")
	assert_false(net.add_diode("D1", "a", "", _q("1")))
	assert_error_pushed("empty node name")
	assert_false(net.add_diode("D1", "a", "k", null))
	assert_error_pushed("add_diode: device 'D1' needs a forward drop >= 0")
	assert_false(net.add_diode("D1", "a", "k", _q("-7/10")))
	assert_error_pushed("needs a forward drop >= 0")
	assert_false(net.add_zener("Z1", "a", "k", _q("7/10"), _q("0")))
	assert_error_pushed("Zener 'Z1' needs a Zener voltage > 0")
	assert_false(net.add_zener("Z1", "a", "k", _q("7/10"), null))
	assert_error_pushed("needs a Zener voltage > 0")
	assert_false(net.add_zener("Z1", "a", "k", _q("-1"), _q("5")))
	assert_error_pushed("add_zener: device 'Z1' needs a forward drop >= 0")
	assert_eq(net.element_count(), 0, "nothing was added")
	assert_false(net.has_devices())
	net.add_resistor("R1", "a", "b", _q("1"))
	assert_false(net.add_diode("R1", "a", "b", _q("1")))
	assert_error_pushed("duplicate element id 'R1'")
	assert_false(net.has_devices())
