extends TestCase
## Tests for DcPuzzleSearch with diode and Zener parts (and fixed devices on
## the base board).

const CURRENT: GoalCondition.Quantity = GoalCondition.Quantity.CURRENT
const VOLTAGE: GoalCondition.Quantity = GoalCondition.Quantity.VOLTAGE
const RESISTANCE: GoalCondition.Quantity = GoalCondition.Quantity.RESISTANCE


func _q(text: String) -> Rational:
	return Rational.parse(text)


func _slot(id: String, from_node: String, to_node: String) -> Dictionary:
	return {"id": id, "from": from_node, "to": to_node}


func _resistor(text: String) -> Dictionary:
	return {"kind": "resistor", "value": _q(text)}


func _battery(text: String) -> Dictionary:
	return {"kind": "battery", "value": _q(text)}


func _diode(drop: String) -> Dictionary:
	return {"kind": "diode", "value": _q(drop)}


func _zener(volts: String, drop: String) -> Dictionary:
	return {"kind": "zener", "value": _q(volts), "forward_drop": _q(drop)}


func _conditions(list: Array) -> Array[GoalCondition]:
	var conditions: Array[GoalCondition] = []
	for condition: GoalCondition in list:
		conditions.append(condition)
	return conditions


func _dicts(list: Array) -> Array[Dictionary]:
	var dicts: Array[Dictionary] = []
	for item: Dictionary in list:
		dicts.append(item)
	return dicts


# --- part texts ------------------------------------------------------------------------

func test_part_text() -> void:
	assert_eq(DcPuzzleSearch.part_text(_resistor("3")), "3 Ω")
	assert_eq(DcPuzzleSearch.part_text(_resistor("1/2")), "1/2 Ω")
	assert_eq(DcPuzzleSearch.part_text(_battery("6")), "6 V")
	assert_eq(DcPuzzleSearch.part_text(_diode("7/10")), "diode 7/10 V")
	assert_eq(DcPuzzleSearch.part_text(_zener("51/10", "7/10")), "zener 51/10 V fwd 7/10 V")
	assert_eq(DcPuzzleSearch.part_text({"kind": "capacitor", "value": _q("1")}), "")
	assert_eq(DcPuzzleSearch.part_text({"kind": "resistor", "value": "2"}), "")
	assert_eq(DcPuzzleSearch.part_text({"kind": "zener", "value": _q("5")}), "", "no forward drop")
	assert_eq(DcPuzzleSearch.PART_KINDS, ["resistor", "battery", "diode", "zener"] as Array[String])


# --- the one-placement room ------------------------------------------------------------

## Fixed 5 V (+ P0, - G), voltmeter A -> G, ammeter M -> G. Slots S1 P0 -> A,
## S2 A -> M (in series with the ammeter), S3 G -> A (facing the other way).
func _one_way_board() -> DcNetwork:
	var base: DcNetwork = DcNetwork.new()
	base.add_voltage_source("B", "P0", "G", _q("5"))
	base.add_voltmeter("VM", "A", "G")
	base.add_ammeter("AM", "M", "G")
	return base


func _one_way_slots() -> Array[Dictionary]:
	return _dicts([_slot("S1", "P0", "A"), _slot("S2", "A", "M"), _slot("S3", "G", "A")])


func test_exactly_one_placement_of_diode_and_resistors() -> void:
	# Goal: 0.7 V on the meter and 4.3 mA through the ammeter.
	# S1 = 1 kOhm, S2 = diode (anode A): V(A) = 0.7, i = 4.3 / 1000. Yes.
	#   ... with 2 kOhm in S3 as well, the diode current drops by 0.7 / 2000:
	#   no. With 2 kOhm in S1: 2.15 mA: no.
	# Diode in S1 (anode P0): V(A) is set by resistors, never 0.7: no.
	# Diode in S3 (anode G, cathode A): reverse biased, OFF: V(A) is a
	#   divider of 1 k and 2 k (10/3 or 5/3 V) or 5 V: no.
	var parts: Array[Dictionary] = [_diode("7/10"), _resistor("1000"), _resistor("2000")]
	var goal: Array[GoalCondition] = _conditions([GoalCondition.exactly("VM", VOLTAGE, _q("7/10")),
			GoalCondition.exactly("AM", CURRENT, _q("43/10000"))])
	var found: Array[Dictionary] = DcPuzzleSearch.find_solutions(_one_way_board(), _one_way_slots(),
			parts, goal)
	assert_eq(found.size(), 1)
	assert_eq(found[0], {"S1": "1000 Ω", "S2": "diode 7/10 V"})


func test_diode_direction_is_fixed_by_the_slot() -> void:
	# Light the path through S3 only: a diode there faces G -> A, so with the
	# battery pushing A positive it never conducts. Asking for any current in
	# S3 finds nothing with the diode in S3.
	var parts: Array[Dictionary] = [_diode("7/10"), _resistor("1000")]
	var goal: Array[GoalCondition] = _conditions([GoalCondition.between("S3", CURRENT, null, _q("-1/1000000"))])
	var found: Array[Dictionary] = DcPuzzleSearch.find_solutions(_one_way_board(), _one_way_slots(),
			parts, goal)
	for solution: Dictionary in found:
		assert_ne(solution.get("S3", ""), "diode 7/10 V", str(solution))
	assert_true(found.size() > 0, "a resistor in S3 does carry current")


func test_condition_on_a_diode_in_a_slot() -> void:
	# A condition may name the slot that holds the diode: its current and
	# state come from the device. 4.3 mA through S2 needs the diode there.
	var parts: Array[Dictionary] = [_diode("7/10"), _resistor("1000")]
	var goal: Array[GoalCondition] = _conditions([GoalCondition.exactly("S2", CURRENT, _q("43/10000")),
			GoalCondition.exactly("S2", VOLTAGE, _q("7/10"))])
	var found: Array[Dictionary] = DcPuzzleSearch.find_solutions(_one_way_board(), _one_way_slots(),
			parts, goal)
	assert_eq(found, [{"S1": "1000 Ω", "S2": "diode 7/10 V"}] as Array[Dictionary])


func test_zener_regulator_room() -> void:
	# 12 V (+ P, - G); fixed 10 kOhm load N -> G with a voltmeter. S1 P -> N,
	# S2 G -> N (a Zener there has its anode at G: reverse biased). Goal 5.1 V.
	# Only S1 = 1 kOhm with the Zener in S2 regulates at 5.1 V. A diode in S1
	# with the Zener in S2 is a short (nothing limits the current): rejected.
	var base: DcNetwork = DcNetwork.new()
	base.add_voltage_source("B", "P", "G", _q("12"))
	base.add_resistor("RL", "N", "G", _q("10000"))
	base.add_voltmeter("VM", "N", "G")
	var slots: Array[Dictionary] = _dicts([_slot("S1", "P", "N"), _slot("S2", "G", "N")])
	var parts: Array[Dictionary] = [_zener("51/10", "7/10"), _resistor("1000"), _diode("7/10")]
	var goal: Array[GoalCondition] = _conditions([GoalCondition.exactly("VM", VOLTAGE, _q("51/10"))])
	var found: Array[Dictionary] = DcPuzzleSearch.find_solutions(base, slots, parts, goal)
	assert_eq(found, [{"S1": "1000 Ω", "S2": "zener 51/10 V fwd 7/10 V"}] as Array[Dictionary])


func test_identical_diodes_count_once() -> void:
	# Two silicon diodes and a resistor in a three-slot series loop: the two
	# diodes are interchangeable, so each arrangement is listed once.
	var base: DcNetwork = DcNetwork.new()
	base.add_voltage_source("B", "P", "G", _q("5"))
	base.add_ammeter("AM", "C", "G")
	var slots: Array[Dictionary] = _dicts([_slot("S1", "P", "A"), _slot("S2", "A", "B"), _slot("S3", "B", "C")])
	var parts: Array[Dictionary] = [_diode("7/10"), _diode("7/10"), _resistor("1000")]
	# (5 - 1.4) / 1000 = 9/2500 A in every order of the three.
	var goal: Array[GoalCondition] = _conditions([GoalCondition.exactly("AM", CURRENT, _q("9/2500"))])
	var found: Array[Dictionary] = DcPuzzleSearch.find_solutions(base, slots, parts, goal)
	assert_eq(found.size(), 3)
	assert_eq(found[0], {"S1": "diode 7/10 V", "S2": "diode 7/10 V", "S3": "1000 Ω"})


func test_fixed_diode_on_the_base_board() -> void:
	# A fixed red LED (2 V) A -> G in the base; one slot P -> A. 9 V source.
	# 20 mA through the LED needs (9 - 2) / R = 1/50: R = 350.
	var base: DcNetwork = DcNetwork.new()
	base.add_voltage_source("B", "P", "G", _q("9"))
	base.add_diode("LED", "A", "G", _q("2"))
	var slots: Array[Dictionary] = _dicts([_slot("S1", "P", "A")])
	var parts: Array[Dictionary] = [_resistor("100"), _resistor("350"), _resistor("1000")]
	var goal: Array[GoalCondition] = _conditions([GoalCondition.exactly("LED", CURRENT, _q("1/50"))])
	var found: Array[Dictionary] = DcPuzzleSearch.find_solutions(base, slots, parts, goal)
	assert_eq(found, [{"S1": "350 Ω"}] as Array[Dictionary])
	assert_true(base.has_devices(), "the base board is unchanged")
	assert_eq(base.element_count(), 2)


func test_ohmmeter_goal_with_a_diode_slot() -> void:
	# An ohmmeter across a slot: a diode there reads OL, so a resistance goal
	# can only be met by a resistor.
	var base: DcNetwork = DcNetwork.new()
	base.add_ohmmeter("OM", "A", "B")
	var slots: Array[Dictionary] = _dicts([_slot("S1", "A", "B")])
	var parts: Array[Dictionary] = [_diode("0"), _resistor("2")]
	var goal: Array[GoalCondition] = _conditions([GoalCondition.between("OM", RESISTANCE, null, _q("1000"))])
	var found: Array[Dictionary] = DcPuzzleSearch.find_solutions(base, slots, parts, goal)
	assert_eq(found, [{"S1": "2 Ω"}] as Array[Dictionary])


func test_rejects_bad_device_parts() -> void:
	var base: DcNetwork = _one_way_board()
	var slots: Array[Dictionary] = _one_way_slots()
	var goal: Array[GoalCondition] = []
	assert_eq(DcPuzzleSearch.find_solutions(base, slots, _dicts([_diode("-1/2")]), goal).size(), 0)
	assert_error_pushed("diode part 0 needs a forward drop >= 0, got -1/2")
	assert_eq(DcPuzzleSearch.find_solutions(base, slots, _dicts([_zener("0", "7/10")]), goal).size(), 0)
	assert_error_pushed("zener part 0 needs a Zener voltage > 0")
	var no_drop: Array[Dictionary] = [{"kind": "zener", "value": _q("5")}]
	assert_eq(DcPuzzleSearch.find_solutions(base, slots, no_drop, goal).size(), 0)
	assert_error_pushed("needs a Rational 'forward_drop' >= 0")
	assert_eq(DcPuzzleSearch.find_solutions(base, slots, _dicts([_zener("5", "-1")]), goal).size(), 0)
	assert_error_pushed("needs a Rational 'forward_drop' >= 0")
	var capacitor: Array[Dictionary] = [{"kind": "capacitor", "value": _q("1")}]
	assert_eq(DcPuzzleSearch.find_solutions(base, slots, capacitor, goal).size(), 0)
	assert_error_pushed("needs kind \"resistor\", \"battery\", \"diode\" or \"zener\"")


# --- agreement with a brute force over fresh networks ------------------------------------

func _add_part(net: DcNetwork, slot: Dictionary, part: Dictionary) -> void:
	var id: String = slot["id"]
	var a: String = slot["from"]
	var b: String = slot["to"]
	match String(part["kind"]):
		"resistor":
			net.add_resistor(id, a, b, part["value"])
		"battery":
			net.add_voltage_source(id, a, b, part["value"])
		"diode":
			net.add_diode(id, a, b, part["value"])
		"zener":
			net.add_zener(id, a, b, part["forward_drop"], part["value"])


func _brute_force(base: DcNetwork, slots: Array[Dictionary], parts: Array[Dictionary],
		conditions: Array[GoalCondition]) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var used: Array[bool] = []
	used.resize(parts.size())
	used.fill(false)
	var chosen: Array[int] = []
	chosen.resize(slots.size())
	chosen.fill(-1)
	_brute_step(0, base, slots, parts, conditions, used, chosen, found)
	return found


func _brute_step(index: int, base: DcNetwork, slots: Array[Dictionary], parts: Array[Dictionary],
		conditions: Array[GoalCondition], used: Array[bool], chosen: Array[int],
		found: Array[Dictionary]) -> void:
	if index == slots.size():
		var net: DcNetwork = base.duplicate_network()
		var solution: Dictionary = {}
		for s: int in slots.size():
			if chosen[s] < 0:
				continue
			_add_part(net, slots[s], parts[chosen[s]])
			solution[slots[s]["id"]] = DcPuzzleSearch.part_text(parts[chosen[s]])
		var result: DcSolution = DcSolver.solve(net)
		if result.status != DcSolution.Status.OK:
			return
		for condition: GoalCondition in conditions:
			if not condition.is_met(result):
				return
		if not found.has(solution):
			found.append(solution)
		return
	chosen[index] = -1
	_brute_step(index + 1, base, slots, parts, conditions, used, chosen, found)
	for i: int in parts.size():
		if used[i]:
			continue
		used[i] = true
		chosen[index] = i
		_brute_step(index + 1, base, slots, parts, conditions, used, chosen, found)
		used[i] = false
	chosen[index] = -1


func test_agrees_with_brute_force() -> void:
	# Fixed 6 V (+ P, - G), ammeter P -> A, voltmeter M -> G, fixed diode
	# M -> G (0.3 V). Slots S1 A -> M, S2 M -> G, S3 G -> A.
	var base: DcNetwork = DcNetwork.new()
	base.add_voltage_source("B0", "P", "G", _q("6"))
	base.add_ammeter("AM", "P", "A")
	base.add_voltmeter("VM", "M", "G")
	base.add_diode("DF", "M", "X", _q("3/10"))
	base.add_resistor("RX", "X", "G", _q("4"))
	var slots: Array[Dictionary] = _dicts([_slot("S1", "A", "M"), _slot("S2", "M", "G"), _slot("S3", "G", "A")])
	var parts: Array[Dictionary] = [_resistor("2"), _resistor("3"), _diode("7/10"), _zener("3", "7/10"),
			_battery("3")]
	var condition_sets: Array = [
		_conditions([GoalCondition.between("AM", CURRENT, _q("1/2"), null)]),
		_conditions([GoalCondition.between("VM", VOLTAGE, _q("1"), _q("3"))]),
		_conditions([GoalCondition.exactly("VM", VOLTAGE, _q("7/10"))]),
		_conditions([GoalCondition.between("DF", CURRENT, _q("1/10"), null)]),
		_conditions([GoalCondition.between("S2", CURRENT, null, _q("0"))]),
		_conditions([]),
	]
	var total: int = 0
	for i: int in condition_sets.size():
		var conditions: Array[GoalCondition] = condition_sets[i]
		var expected: Array[Dictionary] = _brute_force(base, slots, parts, conditions)
		var actual: Array[Dictionary] = DcPuzzleSearch.find_solutions(base, slots, parts, conditions, 100000)
		assert_eq(actual.size(), expected.size(), "condition set %d" % i)
		for solution: Dictionary in expected:
			assert_true(actual.has(solution), "condition set %d: missing %s" % [i, str(solution)])
		total += expected.size()
	assert_true(total > 40, "the condition sets should have solutions to compare: %d" % total)
