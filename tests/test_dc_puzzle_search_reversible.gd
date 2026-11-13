extends TestCase
## Tests for DcPuzzleSearch with parts that may sit in a slot either way round
## ("reversible": true on a battery, diode or Zener).

const CURRENT: GoalCondition.Quantity = GoalCondition.Quantity.CURRENT
const VOLTAGE: GoalCondition.Quantity = GoalCondition.Quantity.VOLTAGE


func _q(text: String) -> Rational:
	return Rational.parse(text)


func _slot(id: String, from_node: String, to_node: String) -> Dictionary:
	return {"id": id, "from": from_node, "to": to_node}


func _resistor(text: String, reversible: bool = false) -> Dictionary:
	return {"kind": "resistor", "value": _q(text), "reversible": reversible}


func _battery(text: String, reversible: bool = false) -> Dictionary:
	return {"kind": "battery", "value": _q(text), "reversible": reversible}


func _diode(drop: String, reversible: bool = false) -> Dictionary:
	return {"kind": "diode", "value": _q(drop), "reversible": reversible}


func _zener(volts: String, drop: String, reversible: bool = false) -> Dictionary:
	return {"kind": "zener", "value": _q(volts), "forward_drop": _q(drop), "reversible": reversible}


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


# --- texts and accessors ---------------------------------------------------------------

func test_placement_text() -> void:
	assert_eq(DcPuzzleSearch.placement_text(_diode("7/10"), false), "diode 7/10 V")
	assert_eq(DcPuzzleSearch.placement_text(_diode("7/10"), true), "diode 7/10 V reversed")
	assert_eq(DcPuzzleSearch.placement_text(_battery("6"), true), "6 V reversed")
	assert_eq(DcPuzzleSearch.placement_text(_zener("51/10", "7/10"), true),
			"zener 51/10 V fwd 7/10 V reversed")
	assert_eq(DcPuzzleSearch.placement_text(_resistor("3"), true), "3 Ω", "a resistor has no direction")
	assert_eq(DcPuzzleSearch.placement_text({"kind": "diode", "value": "1"}, true), "", "invalid part")
	assert_eq(DcPuzzleSearch.part_text(_diode("7/10", true)), "diode 7/10 V", "part_text ignores the flag")


func test_solution_accessors() -> void:
	var solution: Dictionary = {"S1": "diode 7/10 V reversed", "S2": "3 Ω"}
	assert_true(DcPuzzleSearch.is_reversed(solution, "S1"))
	assert_false(DcPuzzleSearch.is_reversed(solution, "S2"))
	assert_false(DcPuzzleSearch.is_reversed(solution, "S3"), "empty slot")
	assert_eq(DcPuzzleSearch.placed_part_text(solution, "S1"), "diode 7/10 V")
	assert_eq(DcPuzzleSearch.placed_part_text(solution, "S2"), "3 Ω")
	assert_eq(DcPuzzleSearch.placed_part_text(solution, "S3"), "")


func test_rejects_a_non_bool_reversible() -> void:
	var base: DcNetwork = DcNetwork.new()
	base.add_resistor("R", "A", "B", _q("1"))
	var parts: Array[Dictionary] = [{"kind": "diode", "value": _q("7/10"), "reversible": "yes"}]
	var goal: Array[GoalCondition] = []
	assert_eq(DcPuzzleSearch.find_solutions(base, _dicts([_slot("S1", "A", "B")]), parts, goal).size(), 0)
	assert_error_pushed("part 0 'reversible' must be a bool, got yes")


# --- one loop: 5 V, 1 kOhm lamp, one slot ------------------------------------------------

## 5 V (+ P, - G), lamp 1 kOhm A -> G, one slot between P and A facing
## P -> A (forward) or A -> P (backward). Goal: (5 - 0.7) / 1000 = 43/10000 A
## through the lamp, which only a conducting diode gives (an empty slot
## carries nothing).
func _one_loop(slot_from: String, slot_to: String, diode: Dictionary) -> Array[Dictionary]:
	var base: DcNetwork = DcNetwork.new()
	base.add_voltage_source("B", "P", "G", _q("5"))
	base.add_resistor("LAMP", "A", "G", _q("1000"))
	var parts: Array[Dictionary] = [diode]
	var goal: Array[GoalCondition] = _conditions([GoalCondition.exactly("LAMP", CURRENT, _q("43/10000"))])
	return DcPuzzleSearch.find_solutions(base, _dicts([_slot("S1", slot_from, slot_to)]), parts, goal)


func test_reversible_diode_follows_the_slot_direction() -> void:
	var forward: Array[Dictionary] = _one_loop("P", "A", _diode("7/10", true))
	assert_eq(forward, [{"S1": "diode 7/10 V"}] as Array[Dictionary])
	assert_false(DcPuzzleSearch.is_reversed(forward[0], "S1"))
	var backward: Array[Dictionary] = _one_loop("A", "P", _diode("7/10", true))
	assert_eq(backward, [{"S1": "diode 7/10 V reversed"}] as Array[Dictionary])
	assert_true(DcPuzzleSearch.is_reversed(backward[0], "S1"))
	assert_eq(DcPuzzleSearch.placed_part_text(backward[0], "S1"), "diode 7/10 V")


func test_fixed_diode_in_a_backward_slot_has_no_solution() -> void:
	assert_eq(_one_loop("P", "A", _diode("7/10")), [{"S1": "diode 7/10 V"}] as Array[Dictionary])
	assert_eq(_one_loop("A", "P", _diode("7/10")).size(), 0)
	var no_key: Dictionary = {"kind": "diode", "value": _q("7/10")}
	assert_eq(_one_loop("A", "P", no_key).size(), 0, "\"reversible\" absent")


func test_reversible_resistor_is_not_reversed() -> void:
	# 5 V across 1000 + 250 Ohm: 1/250 A. A "reversible" resistor is one solution.
	var base: DcNetwork = DcNetwork.new()
	base.add_voltage_source("B", "P", "G", _q("5"))
	base.add_resistor("LAMP", "A", "G", _q("1000"))
	var goal: Array[GoalCondition] = _conditions([GoalCondition.exactly("LAMP", CURRENT, _q("1/250"))])
	var found: Array[Dictionary] = DcPuzzleSearch.find_solutions(base, _dicts([_slot("S1", "A", "P")]),
			_dicts([_resistor("250", true)]), goal)
	assert_eq(found, [{"S1": "250 Ω"}] as Array[Dictionary])


# --- the w2_01 shape: two opposite parallel slots ---------------------------------------

## levels/w2_01.json: 6 V (+ c1, - c2); c1 = u0 = u1 = l0 (node "A"); c4 = u2 =
## l2 = l1 (node "B"); lamp 1 kOhm c4 -> c3, ammeter c3 -> c2. Slots s_fwd
## u1 -> u2 (A -> B) and s_rev l1 -> l0 (B -> A). Goal: 3..6 mA in the lamp.
## A conducting diode A -> B gives (6 - 0.7) / 1000 = 5.3 mA, with or without
## the 2 kOhm across it; the resistor alone gives 6 / 3000 = 2 mA; a diode
## B -> A is off.
func _w2_01_base() -> DcNetwork:
	var base: DcNetwork = DcNetwork.new()
	base.add_voltage_source("bat1", "c1", "c2", _q("6"))
	base.add_ammeter("am1", "c3", "c2")
	base.add_resistor("lamp1", "c4", "c3", _q("1000"))
	base.add_wire("w1", "c1", "u0")
	base.add_wire("w2", "u0", "l0")
	base.add_wire("w3", "c4", "u2")
	base.add_wire("w4", "u2", "l2")
	base.add_wire("w5", "u0", "u1")
	base.add_wire("w6", "l1", "l2")
	return base


func test_w2_01_shape_lists_every_direction() -> void:
	var slots: Array[Dictionary] = _dicts([_slot("s_fwd", "u1", "u2"), _slot("s_rev", "l1", "l0")])
	var goal: Array[GoalCondition] = _conditions([GoalCondition.between("lamp1", CURRENT, _q("3/1000"),
			_q("6/1000"))])
	var parts: Array[Dictionary] = [_diode("7/10", true), _resistor("2000")]
	var found: Array[Dictionary] = DcPuzzleSearch.find_solutions(_w2_01_base(), slots, parts, goal)
	assert_eq(found, [
		{"s_rev": "diode 7/10 V reversed"},
		{"s_fwd": "diode 7/10 V"},
		{"s_fwd": "diode 7/10 V", "s_rev": "2000 Ω"},
		{"s_fwd": "2000 Ω", "s_rev": "diode 7/10 V reversed"},
	] as Array[Dictionary])
	# Both parts count as used, whichever way the diode sits.
	var used: Dictionary = {}
	for solution: Dictionary in found:
		for slot: Dictionary in slots:
			var text: String = DcPuzzleSearch.placed_part_text(solution, slot["id"])
			if not text.is_empty():
				used[text] = true
	assert_eq(used, {"diode 7/10 V": true, "2000 Ω": true})
	# Without the flag: the two forward solutions only (today's validator output).
	var fixed: Array[Dictionary] = DcPuzzleSearch.find_solutions(_w2_01_base(), slots,
			_dicts([_diode("7/10"), _resistor("2000")]), goal)
	assert_eq(fixed, [{"s_fwd": "diode 7/10 V"}, {"s_fwd": "diode 7/10 V", "s_rev": "2000 Ω"}] as Array[Dictionary])


# --- batteries and Zeners ------------------------------------------------------------------

## A slot A -> B and a fixed 2 Ohm resistor A -> B. A 6 V battery with plus at
## A drives +3 A through the resistor (A to B); reversed, -3 A.
func test_reversible_battery() -> void:
	var base: DcNetwork = DcNetwork.new()
	base.add_resistor("R", "A", "B", _q("2"))
	var slots: Array[Dictionary] = _dicts([_slot("S1", "A", "B")])
	var parts: Array[Dictionary] = [_battery("6", true)]
	var either: Array[GoalCondition] = _conditions([
			GoalCondition.between("R", CURRENT, _q("-3"), _q("3")),
			GoalCondition.between("S1", VOLTAGE, _q("6"), null)])
	# The slot's voltage reads from the part's own plus to minus: 6 V both ways.
	var found: Array[Dictionary] = DcPuzzleSearch.find_solutions(base, slots, parts, either)
	assert_eq(found, [{"S1": "6 V"}, {"S1": "6 V reversed"}] as Array[Dictionary])
	var plus_three: Array[GoalCondition] = _conditions([GoalCondition.exactly("R", CURRENT, _q("3"))])
	assert_eq(DcPuzzleSearch.find_solutions(base, slots, parts, plus_three), [{"S1": "6 V"}] as Array[Dictionary])
	var minus_three: Array[GoalCondition] = _conditions([GoalCondition.exactly("R", CURRENT, _q("-3"))])
	assert_eq(DcPuzzleSearch.find_solutions(base, slots, parts, minus_three),
			[{"S1": "6 V reversed"}] as Array[Dictionary])
	# Off by default: a plain battery is never turned round.
	assert_eq(DcPuzzleSearch.find_solutions(base, slots, _dicts([_battery("6")]), minus_three).size(), 0)


## 12 V (+ P, - G), 1 kOhm P -> N, voltmeter N -> G, one slot N -> G. A Zener
## forward (anode N) clamps at 0.7 V; reversed (anode G) it regulates at 5.1 V.
func test_reversible_zener() -> void:
	var base: DcNetwork = DcNetwork.new()
	base.add_voltage_source("B", "P", "G", _q("12"))
	base.add_resistor("R", "P", "N", _q("1000"))
	base.add_voltmeter("VM", "N", "G")
	var slots: Array[Dictionary] = _dicts([_slot("S1", "N", "G")])
	var parts: Array[Dictionary] = [_zener("51/10", "7/10", true)]
	var clamp: Array[GoalCondition] = _conditions([GoalCondition.exactly("VM", VOLTAGE, _q("7/10"))])
	assert_eq(DcPuzzleSearch.find_solutions(base, slots, parts, clamp),
			[{"S1": "zener 51/10 V fwd 7/10 V"}] as Array[Dictionary])
	var regulate: Array[GoalCondition] = _conditions([GoalCondition.exactly("VM", VOLTAGE, _q("51/10"))])
	assert_eq(DcPuzzleSearch.find_solutions(base, slots, parts, regulate),
			[{"S1": "zener 51/10 V fwd 7/10 V reversed"}] as Array[Dictionary])


# --- duplicates -----------------------------------------------------------------------------

## 5 V (+ P, - G), lamp 1 kOhm C -> G, slots S1 P -> A and S2 (A -> C or
## C -> A). Two identical diodes conduct in series: (5 - 1.4) / 1000 = 9/2500 A.
func _two_diodes(s2_from: String, s2_to: String, parts: Array[Dictionary]) -> Array[Dictionary]:
	var base: DcNetwork = DcNetwork.new()
	base.add_voltage_source("B", "P", "G", _q("5"))
	base.add_resistor("LAMP", "C", "G", _q("1000"))
	var slots: Array[Dictionary] = _dicts([_slot("S1", "P", "A"), _slot("S2", s2_from, s2_to)])
	var goal: Array[GoalCondition] = _conditions([GoalCondition.exactly("LAMP", CURRENT, _q("9/2500"))])
	return DcPuzzleSearch.find_solutions(base, slots, parts, goal)


func test_identical_reversible_diodes_merge() -> void:
	var both: Array[Dictionary] = _dicts([_diode("7/10", true), _diode("7/10", true)])
	assert_eq(_two_diodes("A", "C", both), [{"S1": "diode 7/10 V", "S2": "diode 7/10 V"}] as Array[Dictionary])
	assert_eq(_two_diodes("C", "A", both),
			[{"S1": "diode 7/10 V", "S2": "diode 7/10 V reversed"}] as Array[Dictionary])
	# One fixed and one reversible copy: the forward slot takes the fixed one.
	var mixed: Array[Dictionary] = _dicts([_diode("7/10", true), _diode("7/10")])
	assert_eq(_two_diodes("C", "A", mixed),
			[{"S1": "diode 7/10 V", "S2": "diode 7/10 V reversed"}] as Array[Dictionary])
	var fixed: Array[Dictionary] = _dicts([_diode("7/10"), _diode("7/10")])
	assert_eq(_two_diodes("C", "A", fixed).size(), 0)


# --- agreement with a brute force over fresh networks --------------------------------------

func _add_part(net: DcNetwork, id: String, a: String, b: String, part: Dictionary) -> void:
	match String(part["kind"]):
		"resistor":
			net.add_resistor(id, a, b, part["value"])
		"battery":
			net.add_voltage_source(id, a, b, part["value"])
		"diode":
			net.add_diode(id, a, b, part["value"])
		"zener":
			net.add_zener(id, a, b, part["forward_drop"], part["value"])


## Every assignment of part indices, each tried forward and (when allowed)
## reversed by building the element from slot.to to slot.from; equal solution
## dictionaries are kept once.
func _brute_force(base: DcNetwork, slots: Array[Dictionary], parts: Array[Dictionary],
		conditions: Array[GoalCondition]) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var used: Array[bool] = []
	used.resize(parts.size())
	used.fill(false)
	var chosen: Array[int] = []
	chosen.resize(slots.size())
	chosen.fill(-1)
	var flipped: Array[bool] = []
	flipped.resize(slots.size())
	flipped.fill(false)
	_brute_step(0, base, slots, parts, conditions, used, chosen, flipped, found)
	return found


func _brute_step(index: int, base: DcNetwork, slots: Array[Dictionary], parts: Array[Dictionary],
		conditions: Array[GoalCondition], used: Array[bool], chosen: Array[int], flipped: Array[bool],
		found: Array[Dictionary]) -> void:
	if index == slots.size():
		var net: DcNetwork = base.duplicate_network()
		var solution: Dictionary = {}
		for s: int in slots.size():
			if chosen[s] < 0:
				continue
			var a: String = slots[s]["from"]
			var b: String = slots[s]["to"]
			if flipped[s]:
				_add_part(net, slots[s]["id"], b, a, parts[chosen[s]])
			else:
				_add_part(net, slots[s]["id"], a, b, parts[chosen[s]])
			solution[slots[s]["id"]] = DcPuzzleSearch.placement_text(parts[chosen[s]], flipped[s])
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
	_brute_step(index + 1, base, slots, parts, conditions, used, chosen, flipped, found)
	for i: int in parts.size():
		if used[i]:
			continue
		used[i] = true
		chosen[index] = i
		var directions: Array[bool] = [false]
		if bool(parts[i].get("reversible", false)) and String(parts[i]["kind"]) != "resistor":
			directions.append(true)
		for direction: bool in directions:
			flipped[index] = direction
			_brute_step(index + 1, base, slots, parts, conditions, used, chosen, flipped, found)
		flipped[index] = false
		used[i] = false
	chosen[index] = -1


func test_agrees_with_brute_force() -> void:
	# Fixed 6 V (+ P, - G), ammeter P -> A, voltmeter M -> G, fixed diode
	# M -> X (0.3 V) and 4 Ohm X -> G. Slots S1 A -> M, S2 M -> G, S3 G -> A.
	var base: DcNetwork = DcNetwork.new()
	base.add_voltage_source("B0", "P", "G", _q("6"))
	base.add_ammeter("AM", "P", "A")
	base.add_voltmeter("VM", "M", "G")
	base.add_diode("DF", "M", "X", _q("3/10"))
	base.add_resistor("RX", "X", "G", _q("4"))
	var slots: Array[Dictionary] = _dicts([_slot("S1", "A", "M"), _slot("S2", "M", "G"), _slot("S3", "G", "A")])
	var parts: Array[Dictionary] = [_diode("7/10", true), _diode("7/10"), _resistor("2", true),
			_zener("3", "7/10", true), _battery("3", true)]
	var condition_sets: Array = [
		_conditions([GoalCondition.between("AM", CURRENT, _q("1/2"), null)]),
		_conditions([GoalCondition.between("VM", VOLTAGE, _q("1"), _q("3"))]),
		_conditions([GoalCondition.exactly("VM", VOLTAGE, _q("7/10"))]),
		_conditions([GoalCondition.between("S2", CURRENT, null, _q("0"))]),
		_conditions([]),
	]
	var total: int = 0
	var reversed_total: int = 0
	for i: int in condition_sets.size():
		var conditions: Array[GoalCondition] = condition_sets[i]
		var expected: Array[Dictionary] = _brute_force(base, slots, parts, conditions)
		var actual: Array[Dictionary] = DcPuzzleSearch.find_solutions(base, slots, parts, conditions, 100000)
		assert_eq(actual.size(), expected.size(), "condition set %d" % i)
		for solution: Dictionary in expected:
			assert_true(actual.has(solution), "condition set %d: missing %s" % [i, str(solution)])
			for slot: Dictionary in slots:
				if DcPuzzleSearch.is_reversed(solution, slot["id"]):
					reversed_total += 1
		total += expected.size()
	assert_true(total > 60, "the condition sets should have solutions to compare: %d" % total)
	assert_true(reversed_total > 20, "reversed placements should appear: %d" % reversed_total)
