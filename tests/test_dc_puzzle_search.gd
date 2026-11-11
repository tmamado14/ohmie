extends TestCase
## Tests for DcPuzzleSearch.

const CURRENT: GoalCondition.Quantity = GoalCondition.Quantity.CURRENT
const VOLTAGE: GoalCondition.Quantity = GoalCondition.Quantity.VOLTAGE
const RESISTANCE: GoalCondition.Quantity = GoalCondition.Quantity.RESISTANCE
const POWER: GoalCondition.Quantity = GoalCondition.Quantity.POWER


func _q(text: String) -> Rational:
	return Rational.parse(text)


func _slot(id: String, from_node: String, to_node: String) -> Dictionary:
	return {"id": id, "from": from_node, "to": to_node}


func _resistor(text: String) -> Dictionary:
	return {"kind": "resistor", "value": _q(text)}


func _battery(text: String) -> Dictionary:
	return {"kind": "battery", "value": _q(text)}


func _equals(id: String, what: GoalCondition.Quantity, text: String) -> Array[GoalCondition]:
	var conditions: Array[GoalCondition] = [GoalCondition.exactly(id, what, _q(text))]
	return conditions


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


## Loop A -S1- B -S2- C -AM- A, with the ammeter's nodes as given.
func _loop(ammeter_from: String, ammeter_to: String) -> DcNetwork:
	var base: DcNetwork = DcNetwork.new()
	base.add_ammeter("AM", ammeter_from, ammeter_to)
	return base


func _loop_parts() -> Array[Dictionary]:
	var parts: Array[Dictionary] = [_battery("6"), _resistor("2"), _resistor("3"), _resistor("6")]
	return parts


# --- the two reference boards ----------------------------------------------------------

func test_series_loop_battery_and_resistor_either_order() -> void:
	# Slots S1 A -> B and S2 B -> C, ammeter A -> C closes the loop.
	# Battery in S1 (+ at A): it delivers current out of A, through the
	# ammeter A -> C, through S2 back to B (its minus): the ammeter reads +2.
	# Battery in S2 (+ at B): current leaves B through S1 to A, then through
	# the ammeter A -> C to C (its minus): again +2. Both slots point the same
	# way round the loop, so both orders give +2 A: exactly two solutions.
	var slots: Array[Dictionary] = [_slot("S1", "A", "B"), _slot("S2", "B", "C")]
	var found: Array[Dictionary] = DcPuzzleSearch.find_solutions(_loop("A", "C"), slots,
			_loop_parts(), _equals("AM", CURRENT, "2"))
	assert_eq(found.size(), 2)
	assert_eq(found[0], {"S1": "6 V", "S2": "3 Ω"})
	assert_eq(found[1], {"S1": "3 Ω", "S2": "6 V"})


func test_series_loop_with_reversed_ammeter() -> void:
	# The same loop measured C -> A reads -2 in both orders.
	var slots: Array[Dictionary] = [_slot("S1", "A", "B"), _slot("S2", "B", "C")]
	var plus_two: Array[Dictionary] = DcPuzzleSearch.find_solutions(_loop("C", "A"), slots,
			_loop_parts(), _equals("AM", CURRENT, "2"))
	assert_eq(plus_two.size(), 0)
	var minus_two: Array[Dictionary] = DcPuzzleSearch.find_solutions(_loop("C", "A"), slots,
			_loop_parts(), _equals("AM", CURRENT, "-2"))
	assert_eq(minus_two.size(), 2)


func test_series_loop_with_one_slot_turned_round() -> void:
	# S2 now runs C -> B. A battery there has + at C: it pushes current
	# through the ammeter from C to A, which reads -2. Only the battery in S1
	# gives +2, so there is exactly one solution.
	var slots: Array[Dictionary] = [_slot("S1", "A", "B"), _slot("S2", "C", "B")]
	var found: Array[Dictionary] = DcPuzzleSearch.find_solutions(_loop("A", "C"), slots,
			_loop_parts(), _equals("AM", CURRENT, "2"))
	assert_eq(found.size(), 1)
	assert_eq(found[0], {"S1": "6 V", "S2": "3 Ω"})


func test_divider_voltmeter_two_volts() -> void:
	# Fixed 6 V (+ P, - G); S1 P -> M, S2 M -> G; voltmeter across S2.
	# V(S2) = 6 * R2 / (R1 + R2) = 2  =>  R1 = 2 * R2: (2, 1) and (4, 2).
	# One slot empty never gives 2 V: S2 empty reads 6, S1 empty reads 0.
	var base: DcNetwork = DcNetwork.new()
	base.add_voltage_source("B", "P", "G", _q("6"))
	base.add_voltmeter("VM", "M", "G")
	var slots: Array[Dictionary] = [_slot("S1", "P", "M"), _slot("S2", "M", "G")]
	var parts: Array[Dictionary] = [_resistor("1"), _resistor("2"), _resistor("3"), _resistor("4")]
	var found: Array[Dictionary] = DcPuzzleSearch.find_solutions(base, slots, parts,
			_equals("VM", VOLTAGE, "2"))
	assert_eq(found.size(), 2)
	assert_eq(found[0], {"S1": "2 Ω", "S2": "1 Ω"})
	assert_eq(found[1], {"S1": "4 Ω", "S2": "2 Ω"})


# --- de-duplication, limits, empty results ------------------------------------------------

## 2 V (+ P, - G), ammeter P -> A, two parallel slots A -> G.
func _parallel_board() -> DcNetwork:
	var base: DcNetwork = DcNetwork.new()
	base.add_voltage_source("B", "P", "G", _q("2"))
	base.add_ammeter("AM", "P", "A")
	return base


func _parallel_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = [_slot("S1", "A", "G"), _slot("S2", "A", "G")]
	return slots


func test_identical_resistors_count_once() -> void:
	var parts: Array[Dictionary] = [_resistor("2"), _resistor("2")]
	var found: Array[Dictionary] = DcPuzzleSearch.find_solutions(_parallel_board(), _parallel_slots(),
			parts, _equals("AM", CURRENT, "2"))
	assert_eq(found.size(), 1)
	assert_eq(found[0], {"S1": "2 Ω", "S2": "2 Ω"})


func test_identical_resistors_with_another_part() -> void:
	# 2 || 2 = 1 or a single 1 in either slot. 1 || 2 = 2/3 draws 3 A: no.
	var parts: Array[Dictionary] = [_resistor("2"), _resistor("1"), _resistor("2")]
	var found: Array[Dictionary] = DcPuzzleSearch.find_solutions(_parallel_board(), _parallel_slots(),
			parts, _equals("AM", CURRENT, "2"))
	assert_eq(found.size(), 3)
	assert_eq(found[0], {"S2": "1 Ω"})
	assert_eq(found[1], {"S1": "2 Ω", "S2": "2 Ω"})
	assert_eq(found[2], {"S1": "1 Ω"})


func test_identical_batteries_count_once() -> void:
	var slots: Array[Dictionary] = [_slot("S1", "A", "B"), _slot("S2", "B", "C"), _slot("S3", "C", "D")]
	var base: DcNetwork = _loop("A", "D")
	# Two 3 V batteries in series with the 3 ohm: 6 V / 3 ohm = 2 A, in any
	# order of the three slots: 3 positions for the resistor = 3 solutions.
	var parts: Array[Dictionary] = [_battery("3"), _battery("3"), _resistor("3")]
	var found: Array[Dictionary] = DcPuzzleSearch.find_solutions(base, slots, parts,
			_equals("AM", CURRENT, "2"))
	assert_eq(found.size(), 3)
	assert_eq(found[0], {"S1": "3 V", "S2": "3 V", "S3": "3 Ω"})


func test_fraction_texts() -> void:
	var parts: Array[Dictionary] = [_resistor("1/2"), _resistor("2")]
	var found: Array[Dictionary] = DcPuzzleSearch.find_solutions(_parallel_board(), _parallel_slots(),
			parts, _equals("AM", CURRENT, "4"))
	assert_eq(found.size(), 2)
	assert_eq(found[0], {"S2": "1/2 Ω"})
	var battery_parts: Array[Dictionary] = [_battery("3/2"), _resistor("3/4")]
	var slots: Array[Dictionary] = [_slot("S1", "A", "B"), _slot("S2", "B", "C")]
	var loop: Array[Dictionary] = DcPuzzleSearch.find_solutions(_loop("A", "C"), slots,
			battery_parts, _equals("AM", CURRENT, "2"))
	assert_eq(loop.size(), 2)
	assert_eq(loop[0], {"S1": "3/2 V", "S2": "3/4 Ω"})


func test_no_solution_returns_empty() -> void:
	var found: Array[Dictionary] = DcPuzzleSearch.find_solutions(_loop("A", "C"),
			_dicts([_slot("S1", "A", "B"), _slot("S2", "B", "C")]),
			_loop_parts(), _equals("AM", CURRENT, "100"))
	assert_eq(found.size(), 0)


func test_no_slots_checks_the_base_alone() -> void:
	var base: DcNetwork = _parallel_board()
	base.add_resistor("R", "A", "G", _q("1"))
	var no_slots: Array[Dictionary] = []
	var no_parts: Array[Dictionary] = []
	var met: Array[Dictionary] = DcPuzzleSearch.find_solutions(base, no_slots, no_parts,
			_equals("AM", CURRENT, "2"))
	assert_eq(met.size(), 1)
	assert_eq(met[0], {})
	var unmet: Array[Dictionary] = DcPuzzleSearch.find_solutions(base, no_slots, no_parts,
			_equals("AM", CURRENT, "3"))
	assert_eq(unmet.size(), 0)


func test_max_solutions_is_respected() -> void:
	var slots: Array[Dictionary] = [_slot("S1", "A", "G"), _slot("S2", "A", "G"), _slot("S3", "A", "G")]
	var parts: Array[Dictionary] = [_resistor("1"), _resistor("2"), _resistor("3"), _resistor("4")]
	var anything: Array[GoalCondition] = []
	var all: Array[Dictionary] = DcPuzzleSearch.find_solutions(_parallel_board(), slots, parts, anything, 100000)
	# Every assignment is OK: sum over k of C(3, k) * 4! / (4 - k)! = 1 + 12 + 36 + 24.
	assert_eq(all.size(), 73)
	var three: Array[Dictionary] = DcPuzzleSearch.find_solutions(_parallel_board(), slots, parts, anything, 3)
	assert_eq(three.size(), 3)
	assert_eq(three, all.slice(0, 3))
	assert_eq(DcPuzzleSearch.find_solutions(_parallel_board(), slots, parts, anything, 0).size(), 0)
	assert_eq(DcPuzzleSearch.find_solutions(_parallel_board(), slots, parts, anything, -5).size(), 0)
	assert_eq(DcPuzzleSearch.find_solutions(_parallel_board(), slots, parts, anything).size(), 73,
			"default limit 200")


func test_short_and_indeterminate_assignments_are_rejected() -> void:
	# Each slot is in parallel with the base 2 V source (through the ideal
	# ammeter). A 1 V battery there contradicts it (SHORT); a 2 V battery
	# makes an equal-battery loop (INDETERMINATE). With no conditions at all,
	# only the empty board (an open circuit, OK) is left.
	var anything: Array[GoalCondition] = []
	var parts: Array[Dictionary] = [_battery("1"), _battery("2"), _battery("2")]
	var found: Array[Dictionary] = DcPuzzleSearch.find_solutions(_parallel_board(),
			_parallel_slots(), parts, anything)
	assert_eq(found.size(), 1)
	assert_eq(found[0], {})


func test_condition_on_an_empty_slot_is_not_met() -> void:
	var slots: Array[Dictionary] = [_slot("S1", "A", "B"), _slot("S2", "B", "C")]
	var power: Array[GoalCondition] = [GoalCondition.between("S2", POWER, null, _q("1000"))]
	var found: Array[Dictionary] = DcPuzzleSearch.find_solutions(_loop("A", "C"), slots,
			_loop_parts(), power)
	for solution: Dictionary in found:
		assert_true(solution.has("S2"), str(solution))
	assert_true(found.size() > 0)


func test_base_network_is_not_modified() -> void:
	var base: DcNetwork = _parallel_board()
	var before: String = base.to_text()
	DcPuzzleSearch.find_solutions(base, _parallel_slots(), _dicts([_resistor("2"), _resistor("2")]),
			_equals("AM", CURRENT, "2"))
	assert_eq(base.to_text(), before)


# --- invalid input --------------------------------------------------------------------------

func test_rejects_invalid_input() -> void:
	var slots: Array[Dictionary] = _parallel_slots()
	var parts: Array[Dictionary] = [_resistor("2")]
	var conditions: Array[GoalCondition] = _equals("AM", CURRENT, "1")
	assert_eq(DcPuzzleSearch.find_solutions(null, slots, parts, conditions).size(), 0)
	assert_error_pushed("base network is null")

	var missing: Array[Dictionary] = [{"id": "S1", "from": "A"}]
	assert_eq(DcPuzzleSearch.find_solutions(_parallel_board(), missing, parts, conditions).size(), 0)
	assert_error_pushed("needs a non-empty String 'to'")

	var duplicate: Array[Dictionary] = [_slot("S1", "A", "G"), _slot("S1", "A", "G")]
	assert_eq(DcPuzzleSearch.find_solutions(_parallel_board(), duplicate, parts, conditions).size(), 0)
	assert_error_pushed("slot id 'S1' is not unique")

	var clash: Array[Dictionary] = [_slot("AM", "A", "G")]
	assert_eq(DcPuzzleSearch.find_solutions(_parallel_board(), clash, parts, conditions).size(), 0)
	assert_error_pushed("slot id 'AM' is not unique")

	var bad_kind: Array[Dictionary] = [{"kind": "capacitor", "value": _q("1")}]
	assert_eq(DcPuzzleSearch.find_solutions(_parallel_board(), slots, bad_kind, conditions).size(), 0)
	assert_error_pushed("needs kind")

	var text_value: Array[Dictionary] = [{"kind": "resistor", "value": "2"}]
	assert_eq(DcPuzzleSearch.find_solutions(_parallel_board(), slots, text_value, conditions).size(), 0)
	assert_error_pushed("needs a valid Rational 'value'")

	var zero_ohm: Array[Dictionary] = [_resistor("0")]
	assert_eq(DcPuzzleSearch.find_solutions(_parallel_board(), slots, zero_ohm, conditions).size(), 0)
	assert_error_pushed("must be > 0 ohms")

	var null_condition: Array[GoalCondition] = [null]
	assert_eq(DcPuzzleSearch.find_solutions(_parallel_board(), slots, parts, null_condition).size(), 0)
	assert_error_pushed("condition 0 is null")


func test_zero_and_negative_batteries_are_allowed() -> void:
	var slots: Array[Dictionary] = [_slot("S1", "A", "B"), _slot("S2", "B", "C")]
	var parts: Array[Dictionary] = [_battery("-6"), _resistor("3")]
	# A -6 V battery with + at A drives the loop the other way: -2 A.
	var found: Array[Dictionary] = DcPuzzleSearch.find_solutions(_loop("A", "C"), slots, parts,
			_equals("AM", CURRENT, "-2"))
	assert_eq(found.size(), 2)


# --- agreement with a plain brute force ---------------------------------------------------

## Tries every assignment by part index, builds a fresh DcNetwork for each and
## uses the public DcSolver.solve. Returns the distinct solutions.
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
			var part: Dictionary = parts[chosen[s]]
			var value: Rational = part["value"]
			var slot: Dictionary = slots[s]
			if part["kind"] == "battery":
				net.add_voltage_source(slot["id"], slot["from"], slot["to"], value)
				solution[slot["id"]] = value.to_text() + " V"
			else:
				net.add_resistor(slot["id"], slot["from"], slot["to"], value)
				solution[slot["id"]] = value.to_text() + " Ω"
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


func _assert_same_solutions(base: DcNetwork, slots: Array[Dictionary], parts: Array[Dictionary],
		conditions: Array[GoalCondition], label: String) -> int:
	var expected: Array[Dictionary] = _brute_force(base, slots, parts, conditions)
	var actual: Array[Dictionary] = DcPuzzleSearch.find_solutions(base, slots, parts, conditions, 100000)
	assert_eq(actual.size(), expected.size(), label)
	for solution: Dictionary in expected:
		assert_true(actual.has(solution), "%s: missing %s" % [label, str(solution)])
	return expected.size()


func test_agrees_with_brute_force() -> void:
	# Fixed 6 V (+ P, - G), ammeter P -> A, voltmeter M -> G, ohmmeter M -> G.
	# Slots S1 A -> M, S2 M -> G, S3 A -> G.
	var base: DcNetwork = DcNetwork.new()
	base.add_voltage_source("B0", "P", "G", _q("6"))
	base.add_ammeter("AM", "P", "A")
	base.add_voltmeter("VM", "M", "G")
	base.add_ohmmeter("OM", "M", "G")
	var slots: Array[Dictionary] = [_slot("S1", "A", "M"), _slot("S2", "M", "G"), _slot("S3", "A", "G")]
	var parts: Array[Dictionary] = [_resistor("2"), _resistor("2"), _resistor("3"), _resistor("6"),
			_battery("3")]
	var condition_sets: Array = [
		_equals("AM", CURRENT, "3"),
		_conditions([GoalCondition.between("VM", VOLTAGE, _q("1"), _q("3"))]),
		_equals("OM", RESISTANCE, "1"),
		_conditions([GoalCondition.between("S1", POWER, _q("2"), null)]),
		_conditions([GoalCondition.between("B0", CURRENT, null, _q("2"))]),
		_conditions([GoalCondition.between("AM", CURRENT, _q("1"), null),
				GoalCondition.between("VM", VOLTAGE, null, _q("4"))]),
		_conditions([GoalCondition.between("S3", CURRENT, null, _q("0"))]),
	]
	var total: int = 0
	for i: int in condition_sets.size():
		var conditions: Array[GoalCondition] = condition_sets[i]
		total += _assert_same_solutions(base, slots, parts, conditions, "condition set %d" % i)
	assert_true(total > 20, "the condition sets should have solutions to compare: %d" % total)
