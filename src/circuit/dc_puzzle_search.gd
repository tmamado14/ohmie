class_name DcPuzzleSearch
extends RefCounted
## Finds every way of filling a board's slots with the available parts so
## that the closed DC circuit meets all of a level's goal conditions.
##
## A part is a resistor, a battery, a diode or a Zener. In slot s:
##   resistor  add_resistor(s.id, s.from, s.to, value)
##   battery   add_voltage_source(s.id, s.from, s.to, value), plus at s.from
##   diode     add_diode(s.id, s.from, s.to, value): anode at s.from, value =
##             forward drop (an LED or Schottky is a diode with its own drop)
##   zener     add_zener(s.id, s.from, s.to, forward_drop, value): anode at
##             s.from, value = Zener voltage
## An empty slot is an open circuit (nothing is added). A slot's direction is
## fixed: a battery or diode is never turned round by the search.
## Any assignment holding a device (in a slot or on the base board) is solved
## by PwlSolver's state search; the others exactly as before.
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
## 6 slots and 9 all-different parts, far fewer when parts repeat. An
## assignment with devices costs one partial solve per combination of their
## states (PwlSolver).

## The part kinds find_solutions accepts.
const PART_KINDS: Array[String] = ["resistor", "battery", "diode", "zener"]


## base: the fixed board (wires, fixed resistors and sources, meters). Not
##   modified.
## slots: each { "id": String, "from": String, "to": String }; ids must be
##   unique and not used in base.
## parts: each a Dictionary:
##   { "kind": "resistor", "value": ohms (> 0) }
##   { "kind": "battery",  "value": volts }
##   { "kind": "diode",    "value": forward drop (>= 0) }
##   { "kind": "zener",    "value": Zener voltage (> 0), "forward_drop": (>= 0) }
##   All values are Rationals.
## conditions: every one must be met (an empty list accepts any OK circuit).
## max_solutions: the search stops once this many are found; 0 or less returns
##   an empty array.
## Returns each solution as { slot id: part_text(part) } ("3 Ω", "6 V",
## "diode 7/10 V", "zener 51/10 V fwd 7/10 V"); empty slots omitted.
## Invalid input calls push_error and returns an empty array.
static func find_solutions(base: DcNetwork, slots: Array[Dictionary], parts: Array[Dictionary],
		conditions: Array[GoalCondition], max_solutions: int = 200) -> Array[Dictionary]:
	var solutions: Array[Dictionary] = []
	if not _validate(base, slots, parts, conditions):
		return solutions
	if max_solutions <= 0:
		return solutions

	var state: _Search = _Search.new()
	# Group interchangeable parts: one type per distinct text (kind and values).
	for part: Dictionary in parts:
		var kind: String = part["kind"]
		var value: Rational = part["value"]
		var text: String = part_text(part)
		var index: int = state.type_texts.find(text)
		if index >= 0:
			state.remaining[index] += 1
			continue
		state.type_texts.append(text)
		state.remaining.append(1)
		match kind:
			"resistor":
				state.type_kinds.append(DcNetwork.Kind.RESISTOR)
				state.type_values.append(value)
				state.type_conductances.append(value.reciprocal())
				state.type_models.append(null)
			"battery":
				state.type_kinds.append(DcNetwork.Kind.VOLTAGE_SOURCE)
				state.type_values.append(value)
				state.type_conductances.append(null)
				state.type_models.append(null)
			_:
				var model: DiodeModel = DiodeModel.diode(value) if kind == "diode" \
						else DiodeModel.zener(part["forward_drop"], value)
				state.type_kinds.append(model.network_kind())
				state.type_values.append(null)
				state.type_conductances.append(null)
				state.type_models.append(model)

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
	var type_models: Array[PwlDevice] = []  # the device model of a diode or Zener type
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
				state.type_conductances[t], state.type_models[t])
		_search(state, slot_index + 1)
		state.remaining[t] += 1
	state.assignment[slot_index] = -1
	state.circuit.set_element(element, DcSolver.ABSENT, null, null)


static func _evaluate(state: _Search) -> void:
	if state.solutions.size() >= state.max_solutions:
		return
	var result: DcSolution = null
	if state.circuit.has_devices():
		result = PwlSolver._solve_compiled(state.circuit, state.wanted, false)
	else:
		result = DcSolver._solve_circuit(state.circuit, state.wanted, false)
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
		if not _validate_part(parts[i], i):
			return false
	for i: int in conditions.size():
		if conditions[i] == null:
			push_error("DcPuzzleSearch.find_solutions: condition %d is null." % i)
			return false
	return true


## The text that names a part in a solution and groups interchangeable parts:
##   resistor "3 Ω", battery "6 V", diode "diode 7/10 V",
##   zener "zener 51/10 V fwd 7/10 V" (Zener voltage, then forward drop).
## The part must be valid (see find_solutions); "" otherwise, without an error.
static func part_text(part: Dictionary) -> String:
	var raw: Variant = part.get("value")
	if not (raw is Rational) or not (raw as Rational).is_valid():
		return ""
	var value: Rational = raw
	match part.get("kind"):
		"resistor":
			return "%s Ω" % value.to_text()
		"battery":
			return "%s V" % value.to_text()
		"diode":
			return "diode %s V" % value.to_text()
		"zener":
			var drop: Variant = part.get("forward_drop")
			if not (drop is Rational) or not (drop as Rational).is_valid():
				return ""
			return "zener %s V fwd %s V" % [value.to_text(), (drop as Rational).to_text()]
	return ""


static func _validate_part(part: Dictionary, i: int) -> bool:
	var kind: Variant = part.get("kind")
	if typeof(kind) != TYPE_STRING or not PART_KINDS.has(String(kind)):
		push_error("DcPuzzleSearch.find_solutions: part %d needs kind \"resistor\", \"battery\", \"diode\" or \"zener\"." % i)
		return false
	var raw: Variant = part.get("value")
	if not (raw is Rational) or not (raw as Rational).is_valid():
		push_error("DcPuzzleSearch.find_solutions: part %d needs a valid Rational 'value'." % i)
		return false
	var value: Rational = raw
	match String(kind):
		"resistor":
			if value.sign() <= 0:
				push_error("DcPuzzleSearch.find_solutions: resistor part %d must be > 0 ohms, got %s." % [
						i, value.to_text()])
				return false
		"diode":
			if value.sign() < 0:
				push_error("DcPuzzleSearch.find_solutions: diode part %d needs a forward drop >= 0, got %s." % [
						i, value.to_text()])
				return false
		"zener":
			if value.sign() <= 0:
				push_error("DcPuzzleSearch.find_solutions: zener part %d needs a Zener voltage > 0, got %s." % [
						i, value.to_text()])
				return false
			var drop: Variant = part.get("forward_drop")
			if not (drop is Rational) or not (drop as Rational).is_valid() or (drop as Rational).sign() < 0:
				push_error("DcPuzzleSearch.find_solutions: zener part %d needs a Rational 'forward_drop' >= 0." % i)
				return false
	return true
