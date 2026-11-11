class_name DcPuzzleSearch
extends RefCounted
## Finds every way of filling a board's slots with the available parts so
## that the closed DC circuit meets all of a level's goal conditions.
##
## A part is a resistor or a battery. A resistor in slot s becomes
## add_resistor(s.id, s.from, s.to, value); a battery becomes
## add_voltage_source(s.id, s.from, s.to, value), plus terminal at s.from.
## An empty slot is an open circuit (nothing is added).
##
## Every assignment is tried in which each part (by index) is used at most once
## and any slot may stay empty. An assignment is a solution when the solve
## status is OK and every condition is met. Parts of the same kind and value
## are interchangeable: assignments that differ only in which of them was used
## are one solution. Placing the same parts in different slots is a different
## solution.
##
## Order: slots in the given order; for each slot "empty" first, then the
## distinct parts in order of first appearance.
##
## Speed: the base board is compiled once; each assignment only switches slot
## entries in place and solves for the elements the conditions name. Cost is
## one exact solve per distinct assignment: at most
## sum over k of C(slots, k) * parts! / (parts - k)!, about 2 * 10^5 for
## 6 slots and 9 all-different parts, far fewer when parts repeat.


## base: the fixed board (wires, fixed resistors and sources, meters). Not
##   modified.
## slots: each { "id": String, "from": String, "to": String }; ids must be
##   unique and not used in base.
## parts: each { "kind": "resistor" | "battery", "value": Rational }; a
##   resistor's value must be > 0.
## conditions: every one must be met (an empty list accepts any OK circuit).
## max_solutions: the search stops once this many are found; 0 or less returns
##   an empty array.
## Returns each solution as { slot id: "3 Ω" or "6 V" }; empty slots omitted.
## Invalid input calls push_error and returns an empty array.
static func find_solutions(base: DcNetwork, slots: Array[Dictionary], parts: Array[Dictionary],
		conditions: Array[GoalCondition], max_solutions: int = 200) -> Array[Dictionary]:
	var solutions: Array[Dictionary] = []
	if not _validate(base, slots, parts, conditions):
		return solutions
	if max_solutions <= 0:
		return solutions

	var state: _Search = _Search.new()
	# Group interchangeable parts: one type per distinct (kind, value).
	for part: Dictionary in parts:
		var is_battery: bool = String(part["kind"]) == "battery"
		var value: Rational = part["value"]
		var text: String = "%s %s" % [value.to_text(), "V" if is_battery else "Ω"]
		var index: int = state.type_texts.find(text)
		if index < 0:
			state.type_texts.append(text)
			state.type_kinds.append(DcNetwork.Kind.VOLTAGE_SOURCE if is_battery else DcNetwork.Kind.RESISTOR)
			state.type_values.append(value)
			state.type_conductances.append(null if is_battery else value.reciprocal())
			state.remaining.append(1)
		else:
			state.remaining[index] += 1

	var slot_nodes: Array[String] = []
	for slot: Dictionary in slots:
		slot_nodes.append(String(slot["from"]))
		slot_nodes.append(String(slot["to"]))
	state.circuit = DcSolver._compile(base, slot_nodes)
	for slot: Dictionary in slots:
		var element: int = state.circuit.add_element(String(slot["id"]), DcSolver.ABSENT,
				state.circuit.node_index[String(slot["from"])],
				state.circuit.node_index[String(slot["to"])], null, null)
		state.slot_elements.append(element)
		state.slot_ids.append(String(slot["id"]))
	for condition: GoalCondition in conditions:
		state.wanted[condition.element_id] = true
	state.conditions = conditions
	state.max_solutions = max_solutions
	state.assignment.resize(slots.size())
	state.assignment.fill(-1)
	state.solutions = solutions
	_search(state, 0)
	return solutions


class _Search:
	extends RefCounted
	var circuit: DcSolver._Circuit
	var slot_elements: Array[int] = []
	var slot_ids: Array[String] = []
	var wanted: Dictionary = {}
	var conditions: Array[GoalCondition] = []
	var max_solutions: int = 0
	var type_texts: Array[String] = []
	var type_kinds: Array[int] = []
	var type_values: Array[Rational] = []
	var type_conductances: Array[Rational] = []
	var remaining: Array[int] = []
	var assignment: Array[int] = []
	var solutions: Array[Dictionary] = []


static func _search(state: _Search, slot_index: int) -> void:
	if slot_index == state.slot_elements.size():
		_evaluate(state)
		return
	var element: int = state.slot_elements[slot_index]
	state.assignment[slot_index] = -1
	state.circuit.set_element(element, DcSolver.ABSENT, null, null)
	_search(state, slot_index + 1)
	for t: int in state.type_texts.size():
		if state.solutions.size() >= state.max_solutions:
			break
		if state.remaining[t] == 0:
			continue
		state.remaining[t] -= 1
		state.assignment[slot_index] = t
		state.circuit.set_element(element, state.type_kinds[t], state.type_values[t],
				state.type_conductances[t])
		_search(state, slot_index + 1)
		state.remaining[t] += 1
	state.assignment[slot_index] = -1
	state.circuit.set_element(element, DcSolver.ABSENT, null, null)


static func _evaluate(state: _Search) -> void:
	if state.solutions.size() >= state.max_solutions:
		return
	var result: DcSolution = DcSolver._solve_circuit(state.circuit, state.wanted, false)
	if result.status != DcSolution.Status.OK:
		return
	for condition: GoalCondition in state.conditions:
		if not condition.is_met(result):
			return
	var solution: Dictionary = {}
	for s: int in state.slot_ids.size():
		var t: int = state.assignment[s]
		if t >= 0:
			solution[state.slot_ids[s]] = state.type_texts[t]
	state.solutions.append(solution)


static func _validate(base: DcNetwork, slots: Array[Dictionary], parts: Array[Dictionary],
		conditions: Array[GoalCondition]) -> bool:
	if base == null:
		push_error("DcPuzzleSearch.find_solutions: base network is null.")
		return false
	var slot_ids: Dictionary = {}
	for slot: Dictionary in slots:
		for key: String in ["id", "from", "to"]:
			if typeof(slot.get(key)) != TYPE_STRING or String(slot[key]).is_empty():
				push_error("DcPuzzleSearch.find_solutions: slot %s needs a non-empty String '%s'." % [
						str(slot), key])
				return false
		var id: String = slot["id"]
		if slot_ids.has(id) or base.has_element(id):
			push_error("DcPuzzleSearch.find_solutions: slot id '%s' is not unique." % id)
			return false
		slot_ids[id] = true
	for i: int in parts.size():
		var part: Dictionary = parts[i]
		var kind: Variant = part.get("kind")
		if typeof(kind) != TYPE_STRING or not (String(kind) == "resistor" or String(kind) == "battery"):
			push_error("DcPuzzleSearch.find_solutions: part %d needs kind \"resistor\" or \"battery\"." % i)
			return false
		var raw: Variant = part.get("value")
		if not (raw is Rational) or not (raw as Rational).is_valid():
			push_error("DcPuzzleSearch.find_solutions: part %d needs a valid Rational 'value'." % i)
			return false
		var value: Rational = raw
		if String(kind) == "resistor" and value.sign() <= 0:
			push_error("DcPuzzleSearch.find_solutions: resistor part %d must be > 0 ohms, got %s." % [
					i, value.to_text()])
			return false
	for i: int in conditions.size():
		if conditions[i] == null:
			push_error("DcPuzzleSearch.find_solutions: condition %d is null." % i)
			return false
	return true
