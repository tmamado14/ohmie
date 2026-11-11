extends TestCase
## Tests for LevelCircuit (GDD 12.2): validation of a level's "circuit"
## object, build_network solved by DcSolver, and validate_goal.


## One loop: slot s1, slot s2, ammeter am1 and return wires. With a 6 V
## battery in either slot and a 3 ohm resistor in the other, am1 reads +2 A.
func _loop_board() -> Dictionary:
	return {
		"nodes": {
			"a": [0, 200], "n1": [224, 200], "n2": [224, 100], "n3": [448, 100],
			"c3": [448, 0], "m2": [336, 0], "m1": [112, 0], "c1": [0, 0],
		},
		"edges": [
			{"id": "s1", "type": "slot", "from": "a", "to": "n1"},
			{"id": "w1", "type": "wire", "from": "n1", "to": "n2"},
			{"id": "s2", "type": "slot", "from": "n2", "to": "n3"},
			{"id": "w2", "type": "wire", "from": "n3", "to": "c3"},
			{"id": "w3", "type": "wire", "from": "c3", "to": "m2"},
			{"id": "am1", "type": "ammeter", "from": "m1", "to": "m2"},
			{"id": "w4", "type": "wire", "from": "m1", "to": "c1"},
			{"id": "w5", "type": "wire", "from": "c1", "to": "a"},
		],
	}


## A fixed 6 V battery, a fixed 1 ohm resistor and a 2 ohm lamp rated 1..3/2 A
## in one loop with a slot, a voltmeter across the lamp.
func _lamp_board() -> Dictionary:
	return {
		"nodes": {"p": [0, 0], "q": [224, 0], "r": [448, 0], "s": [448, 200], "t": [0, 200]},
		"edges": [
			{"id": "bat", "type": "battery", "from": "p", "to": "t", "value": "6"},
			{"id": "s1", "type": "slot", "from": "p", "to": "q"},
			{"id": "r1", "type": "resistor", "from": "q", "to": "r", "value": "1"},
			{"id": "lamp1", "type": "lamp", "from": "r", "to": "s", "value": "2",
				"rated_min": "1", "rated_max": "3/2"},
			{"id": "vm1", "type": "voltmeter", "from": "r", "to": "s"},
			{"id": "w1", "type": "wire", "from": "s", "to": "t"},
		],
	}


## Two slots in parallel closed by an ohmmeter.
func _ohmmeter_board() -> Dictionary:
	return {
		"nodes": {
			"j1": [0, 100], "t1": [0, 0], "b1": [0, 200], "t2": [224, 0], "b2": [224, 200],
			"j2": [224, 100], "o1": [-64, 100], "o2": [288, 100], "x1": [-64, -100], "x2": [288, -100],
		},
		"edges": [
			{"id": "w1", "type": "wire", "from": "j1", "to": "t1"},
			{"id": "w2", "type": "wire", "from": "j1", "to": "b1"},
			{"id": "s1", "type": "slot", "from": "t1", "to": "t2"},
			{"id": "s2", "type": "slot", "from": "b1", "to": "b2"},
			{"id": "w3", "type": "wire", "from": "t2", "to": "j2"},
			{"id": "w4", "type": "wire", "from": "b2", "to": "j2"},
			{"id": "w5", "type": "wire", "from": "j1", "to": "o1"},
			{"id": "w6", "type": "wire", "from": "j2", "to": "o2"},
			{"id": "w7", "type": "wire", "from": "o1", "to": "x1"},
			{"id": "w8", "type": "wire", "from": "o2", "to": "x2"},
			{"id": "om1", "type": "ohmmeter", "from": "x1", "to": "x2"},
		],
	}


func _parse(data: Dictionary) -> LevelCircuit:
	return LevelCircuit.from_dictionary(data, "test")


func _battery(volts: int) -> Part:
	return Part.create(Part.Kind.BATTERY, Rational.new(volts))


func _resistor(num: int, den: int = 1) -> Part:
	return Part.create(Part.Kind.RESISTOR, Rational.new(num, den))


func _solve(circuit: LevelCircuit, filled: Dictionary) -> DcSolution:
	return DcSolver.solve(circuit.build_network(filled))


func _assert_rejected(data: Variant, fragment: String, message: String) -> void:
	assert_null(LevelCircuit.from_dictionary(data, "test"), message)
	assert_error_pushed(fragment, message)


func _condition(of: String, quantity: String) -> Array[GoalCondition]:
	var conditions: Array[GoalCondition] = [
		GoalCondition.from_dictionary({"of": of, "quantity": quantity, "min": "0"})]
	return conditions


# --- parsing --------------------------------------------------------------------------

func test_valid_board_parses_nodes_and_edges() -> void:
	var circuit: LevelCircuit = _parse(_loop_board())
	assert_not_null(circuit)
	if circuit == null:
		return
	assert_eq(circuit.get_node_names().size(), 8)
	assert_eq(circuit.get_node_position("n3"), Vector2(448, 100))
	var edges: Array[LevelCircuit.Edge] = circuit.get_edges()
	assert_eq(edges.size(), 8)
	assert_eq(edges[2].id, "s2")
	assert_eq(edges[2].type, LevelCircuit.TYPE_SLOT)
	assert_eq(edges[2].from_node, "n2")
	assert_eq(edges[2].to_node, "n3")
	assert_true(circuit.get_edge("am1").is_meter())
	assert_null(circuit.get_edge("nope"))
	assert_eq(circuit.get_node_degree("a"), 2)


func test_values_and_lamp_ratings_parse() -> void:
	var circuit: LevelCircuit = _parse(_lamp_board())
	assert_not_null(circuit)
	if circuit == null:
		return
	assert_rational_eq(circuit.get_edge("bat").value, "6")
	assert_rational_eq(circuit.get_edge("r1").value, "1")
	var lamp: LevelCircuit.Edge = circuit.get_edge("lamp1")
	assert_rational_eq(lamp.value, "2")
	assert_rational_eq(lamp.rated_min, "1")
	assert_rational_eq(lamp.rated_max, "3/2")
	assert_null(circuit.get_edge("w1").value)


func test_slot_descriptors_match_puzzle_search_format() -> void:
	var circuit: LevelCircuit = _parse(_loop_board())
	var slots: Array[Dictionary] = circuit.get_slot_descriptors()
	assert_eq(slots.size(), 2)
	assert_eq(slots[0], {"id": "s1", "from": "a", "to": "n1"})
	assert_eq(slots[1], {"id": "s2", "from": "n2", "to": "n3"})


# --- build_network ----------------------------------------------------------------------

func test_base_network_leaves_slots_out() -> void:
	var circuit: LevelCircuit = _parse(_lamp_board())
	var network: DcNetwork = circuit.build_base_network()
	assert_false(network.has_element("s1"))
	assert_eq(network.get_kind("bat"), DcNetwork.Kind.VOLTAGE_SOURCE)
	assert_eq(network.get_node_a("bat"), "p", "battery plus is at 'from'")
	assert_eq(network.get_kind("lamp1"), DcNetwork.Kind.RESISTOR, "a lamp is a resistor")
	assert_rational_eq(network.get_value("lamp1"), "2")
	assert_eq(network.get_kind("vm1"), DcNetwork.Kind.VOLTMETER)
	assert_eq(network.get_kind("w1"), DcNetwork.Kind.WIRE)


func test_battery_in_first_slot_drives_two_amps() -> void:
	var circuit: LevelCircuit = _parse(_loop_board())
	var solution: DcSolution = _solve(circuit, {"s1": _battery(6), "s2": _resistor(3)})
	assert_eq(solution.status, DcSolution.Status.OK)
	assert_rational_eq(solution.meter_reading("am1"), "2")
	assert_rational_eq(solution.voltage_across("s1"), "6", "plus at the slot's 'from'")
	assert_rational_eq(solution.current_through("s1"), "2", "the battery delivers 2 A")
	assert_true(solution.is_energized())


func test_battery_in_second_slot_also_drives_two_amps() -> void:
	var circuit: LevelCircuit = _parse(_loop_board())
	var solution: DcSolution = _solve(circuit, {"s1": _resistor(3), "s2": _battery(6)})
	assert_eq(solution.status, DcSolution.Status.OK)
	assert_rational_eq(solution.meter_reading("am1"), "2")


func test_open_loop_and_no_battery_read_zero() -> void:
	var circuit: LevelCircuit = _parse(_loop_board())
	var empty: DcSolution = _solve(circuit, {})
	assert_eq(empty.status, DcSolution.Status.OK)
	assert_rational_eq(empty.meter_reading("am1"), "0")
	assert_false(empty.is_energized())
	var open: DcSolution = _solve(circuit, {"s1": _battery(6)})
	assert_rational_eq(open.meter_reading("am1"), "0")
	var dead: DcSolution = _solve(circuit, {"s1": _resistor(2), "s2": _resistor(3)})
	assert_rational_eq(dead.meter_reading("am1"), "0")


func test_battery_shorted_by_the_loop_is_short() -> void:
	# Battery in s1 and nothing but wires and the ammeter around it: s2 empty is
	# open, so build a loop where the battery sees only the ammeter.
	var data: Dictionary = _loop_board()
	(data["edges"] as Array).append({"id": "w6", "type": "wire", "from": "n2", "to": "n3"})
	var circuit: LevelCircuit = _parse(data)
	var solution: DcSolution = _solve(circuit, {"s1": _battery(6)})
	assert_eq(solution.status, DcSolution.Status.SHORT)


func test_lamp_current_and_voltmeter() -> void:
	var circuit: LevelCircuit = _parse(_lamp_board())
	var solution: DcSolution = _solve(circuit, {"s1": _resistor(1)})
	assert_eq(solution.status, DcSolution.Status.OK)
	assert_rational_eq(solution.current_through("lamp1"), "3/2", "6 V / (1 + 1 + 2) ohm")
	assert_rational_eq(solution.meter_reading("vm1"), "3")
	var open: DcSolution = _solve(circuit, {})
	assert_rational_eq(open.current_through("lamp1"), "0")


func test_ohmmeter_board() -> void:
	var circuit: LevelCircuit = _parse(_ohmmeter_board())
	var both: DcSolution = _solve(circuit, {"s1": _resistor(2), "s2": _resistor(2)})
	assert_eq(both.meter_state("om1"), DcSolution.MeterState.VALUE)
	assert_rational_eq(both.meter_reading("om1"), "1")
	var one: DcSolution = _solve(circuit, {"s2": _resistor(2)})
	assert_rational_eq(one.meter_reading("om1"), "2")
	var none: DcSolution = _solve(circuit, {})
	assert_eq(none.meter_state("om1"), DcSolution.MeterState.OPEN)


func test_build_network_rejects_unknown_slot_id() -> void:
	var circuit: LevelCircuit = _parse(_loop_board())
	var network: DcNetwork = circuit.build_network({"nope": _resistor(2)})
	assert_false(network.has_element("nope"))
	assert_error_pushed("'nope' is not a slot")


func test_build_network_rejects_a_value_that_is_not_a_part() -> void:
	var circuit: LevelCircuit = _parse(_loop_board())
	var network: DcNetwork = circuit.build_network({"s1": Rational.new(2)})
	assert_false(network.has_element("s1"))
	assert_error_pushed("slot 's1' is not a Part")
	network = circuit.build_network({"s1": "2"})
	assert_false(network.has_element("s1"))
	assert_error_pushed("slot 's1' is not a Part")


# --- validate_goal ----------------------------------------------------------------------

func test_validate_goal_accepts_sensible_conditions() -> void:
	var circuit: LevelCircuit = _parse(_lamp_board())
	for pair: Array in [["vm1", "voltage"], ["lamp1", "current"], ["lamp1", "power"], ["bat", "power"],
			["s1", "power"], ["r1", "power"], ["r1", "voltage"], ["s1", "current"]]:
		assert_true(circuit.validate_goal(_condition(pair[0], pair[1])), "%s %s" % pair)
	var ohm: LevelCircuit = _parse(_ohmmeter_board())
	assert_true(ohm.validate_goal(_condition("om1", "resistance")))


func test_validate_goal_rejects_unknown_element() -> void:
	var circuit: LevelCircuit = _parse(_loop_board())
	assert_false(circuit.validate_goal(_condition("am9", "current")))
	assert_error_pushed("'am9', which is not an edge")


func test_validate_goal_rejects_quantities_an_element_lacks() -> void:
	var circuit: LevelCircuit = _parse(_lamp_board())
	assert_false(circuit.validate_goal(_condition("lamp1", "resistance")))
	assert_error_pushed("resistance goal cannot be measured on lamp 'lamp1'")
	assert_false(circuit.validate_goal(_condition("vm1", "power")))
	assert_error_pushed("power goal cannot be measured on voltmeter 'vm1'")
	assert_false(circuit.validate_goal(_condition("w1", "current")))
	assert_error_pushed("current goal cannot be measured on wire 'w1'")
	assert_false(circuit.validate_goal(_condition("w1", "voltage")))
	assert_error_pushed("voltage goal cannot be measured on wire 'w1'")


# --- rejections ---------------------------------------------------------------------------

func test_rejects_non_object() -> void:
	_assert_rejected([1, 2], "must be an object", "array instead of object")


func test_rejects_missing_section() -> void:
	var data: Dictionary = _loop_board()
	data.erase("edges")
	_assert_rejected(data, "missing 'edges'", "no edges")


func test_rejects_old_terminals_field() -> void:
	var data: Dictionary = _loop_board()
	data["terminals"] = ["a", "n3"]
	_assert_rejected(data, "unknown field 'terminals'", "terminals")


func test_rejects_empty_edges() -> void:
	var data: Dictionary = _loop_board()
	data["edges"] = []
	_assert_rejected(data, "'edges' is empty", "no edges at all")


func test_rejects_node_that_is_not_a_point() -> void:
	var data: Dictionary = _loop_board()
	data["nodes"]["n1"] = [64]
	_assert_rejected(data, "node 'n1' must be two numbers", "one coordinate")
	data["nodes"]["n1"] = ["64", 100]
	_assert_rejected(data, "node 'n1' must be two numbers", "string coordinate")
	data["nodes"] = [[0, 0]]
	_assert_rejected(data, "'nodes' must be an object", "nodes as array")


func test_rejects_duplicate_edge_id() -> void:
	var data: Dictionary = _loop_board()
	data["edges"][1]["id"] = "s1"
	_assert_rejected(data, "edge id 's1' is used more than once", "duplicate id")


func test_rejects_edge_without_id() -> void:
	var data: Dictionary = _loop_board()
	data["edges"][0].erase("id")
	_assert_rejected(data, "needs a non-empty string 'id'", "missing id")


func test_rejects_unknown_edge_type() -> void:
	for old: String in ["socket", "fixed", "diode"]:
		var data: Dictionary = _loop_board()
		data["edges"][0]["type"] = old
		_assert_rejected(data, "unknown type '%s'" % old, old)


func test_rejects_unknown_edge_field() -> void:
	var data: Dictionary = _loop_board()
	data["edges"][0]["value"] = "2"
	_assert_rejected(data, "slot edge 's1' has unknown field 'value'", "slot with a value")
	data = _lamp_board()
	data["edges"][2]["ohms"] = "1"
	_assert_rejected(data, "resistor edge 'r1' has unknown field 'ohms'", "old ohms field")


func test_rejects_unknown_nodes() -> void:
	var data: Dictionary = _loop_board()
	data["edges"][0]["from"] = "nowhere"
	_assert_rejected(data, "unknown node 'nowhere'", "unknown from")
	data = _loop_board()
	data["edges"][0]["to"] = "elsewhere"
	_assert_rejected(data, "unknown node 'elsewhere'", "unknown to")


func test_rejects_edge_from_a_node_to_itself() -> void:
	var data: Dictionary = _loop_board()
	data["edges"][0]["to"] = "a"
	_assert_rejected(data, "starts and ends at the same node", "self loop")


func test_rejects_missing_or_bad_values() -> void:
	for index: int in [0, 2, 3]:  # battery, resistor, lamp
		var data: Dictionary = _lamp_board()
		data["edges"][index].erase("value")
		_assert_rejected(data, "needs 'value' as a string", "no value on edges[%d]" % index)
	var bad: Dictionary = _lamp_board()
	bad["edges"][2]["value"] = "two"
	_assert_rejected(bad, "invalid 'value' value 'two'", "text value")
	assert_error_pushed("Rational.parse", "the parser's own error")
	for text: String in ["0", "-1/2"]:
		var data: Dictionary = _lamp_board()
		data["edges"][0]["value"] = text
		_assert_rejected(data, "must have 'value' > 0", "battery value " + text)


func test_rejects_bad_lamp_ratings() -> void:
	var data: Dictionary = _lamp_board()
	data["edges"][3].erase("rated_max")
	_assert_rejected(data, "needs 'rated_max'", "no rated_max")
	data = _lamp_board()
	data["edges"][3].erase("rated_min")
	_assert_rejected(data, "needs 'rated_min'", "no rated_min")
	data = _lamp_board()
	data["edges"][3]["rated_min"] = "2"
	_assert_rejected(data, "rated_min 2 greater than rated_max 3/2", "min above max")
	data = _lamp_board()
	data["edges"][3]["rated_min"] = "0"
	_assert_rejected(data, "must have 'rated_min' > 0", "zero rating")
