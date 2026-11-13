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
## An empty slot is an open circuit (nothing is added). A part is placed
## forward as above. A battery, diode or Zener marked "reversible" is also
## tried reversed: the same element with its ends swapped, as if added
## from s.to to s.from (plus or anode at s.to). Readings of that slot element
## then follow the part's own direction, so the game must build a reversed
## part the same way. A resistor ignores "reversible" (it has no direction).
## Any assignment holding a device (in a slot or on the base board) is solved
## by PwlSolver's state search; the others exactly as before.
##
## Every assignment is tried in which each part (by index) is used at most once
## and any slot may stay empty. An assignment is a solution when the solve
## status is OK and every condition is met. Parts of the same kind and value
## are interchangeable: assignments that differ only in which of them was used
## are one solution (a forward placement uses a non-reversible copy first, so
## mixing reversible and fixed copies of one part never repeats a solution).
## Placing the same parts in different slots, or the same part the other way
## round, is a different solution.
##
## Order: slots in the given order; for each slot "empty" first, then the
## distinct parts in order of first appearance, each forward then reversed.
##
## Speed: the base board is compiled once; each assignment only switches slot
## entries in place and solves for the elements the conditions name. Cost is
## one exact solve per distinct assignment: at most
## sum over k of C(slots, k) * parts! / (parts - k)!, about 2 * 10^5 for
## 6 slots and 9 all-different parts, far fewer when parts repeat. Each
## reversible part placed doubles its assignments (factor 2^r with r
## reversible parts in the slots). An assignment with devices costs one
## partial solve per combination of their states (PwlSolver).

## The part kinds find_solutions accepts.
const PART_KINDS: Array[String] = ["resistor", "battery", "diode", "zener"]
## The part kinds that honour "reversible": true.
const REVERSIBLE_KINDS: Array[String] = ["battery", "diode", "zener"]
## Appended to a part's text in a solution when it sits reversed.
const REVERSED_SUFFIX: String = " reversed"


## base: the fixed board (wires, fixed resistors and sources, meters). Not
##   modified.
## slots: each { "id": String, "from": String, "to": String }; ids must be
##   unique and not used in base.
## parts: each a Dictionary:
##   { "kind": "resistor", "value": ohms (> 0) }
##   { "kind": "battery",  "value": volts }
##   { "kind": "diode",    "value": forward drop (>= 0) }
##   { "kind": "zener",    "value": Zener voltage (> 0), "forward_drop": (>= 0) }
##   All values are Rationals. Optional "reversible": bool (default false).
## conditions: every one must be met (an empty list accepts any OK circuit).
## max_solutions: the search stops once this many are found; 0 or less returns
##   an empty array.
## Returns each solution as { slot id: placement_text(part, reversed) } ("3 Ω",
## "6 V", "diode 7/10 V", "zener 51/10 V fwd 7/10 V", "diode 7/10 V reversed");
## empty slots omitted. Read a slot with is_reversed and placed_part_text.
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
		var reversible: bool = _is_reversible(part)
		var index: int = state.type_texts.find(text)
		if index < 0:
			index = state.type_texts.size()
			state.type_texts.append(text)
			state.remaining_fixed.append(0)
			state.remaining_reversible.append(0)
		if reversible:
			state.remaining_reversible[index] += 1
		else:
			state.remaining_fixed[index] += 1
		if index < state.type_kinds.size():
			continue
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
		state.slot_from.append(state.circuit.node_a[element])
		state.slot_to.append(state.circuit.node_b[element])
	for condition: GoalCondition in conditions:
		state.wanted[condition.element_id] = true
	state.conditions = conditions
	state.max_solutions = max_solutions
	state.assignment.resize(slots.size())
	state.assignment.fill(-1)
	state.reversed.resize(slots.size())
	state.reversed.fill(false)
	state.solutions = solutions
	_search(state, 0)
	return solutions


class _Search:
	extends RefCounted
	var circuit: DcSolver._Circuit
	var slot_elements: Array[int] = []
	var slot_ids: Array[String] = []
	var slot_from: Array[int] = []  # the slot's from node index
	var slot_to: Array[int] = []
	var wanted: Dictionary = {}
	var conditions: Array[GoalCondition] = []
	var max_solutions: int = 0
	var type_texts: Array[String] = []
	var type_kinds: Array[int] = []
	var type_values: Array[Rational] = []
	var type_conductances: Array[Rational] = []
	var type_models: Array[PwlDevice] = []  # the device model of a diode or Zener type
	var remaining_fixed: Array[int] = []  # copies left that sit forward only
	var remaining_reversible: Array[int] = []  # copies left that may sit either way
	var assignment: Array[int] = []
	var reversed: Array[bool] = []
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
		state.assignment[slot_index] = t
		state.circuit.set_element(element, state.type_kinds[t], state.type_values[t],
				state.type_conductances[t], state.type_models[t])
		# Forward: use a fixed copy first, so a reversible copy stays free for
		# a later reversed placement (every feasible assignment is reached once).
		if state.remaining_fixed[t] > 0:
			state.remaining_fixed[t] -= 1
			_search(state, slot_index + 1)
			state.remaining_fixed[t] += 1
		elif state.remaining_reversible[t] > 0:
			state.remaining_reversible[t] -= 1
			_search(state, slot_index + 1)
			state.remaining_reversible[t] += 1
		if state.remaining_reversible[t] > 0 and state.solutions.size() < state.max_solutions:
			state.remaining_reversible[t] -= 1
			state.reversed[slot_index] = true
			state.circuit.node_a[element] = state.slot_to[slot_index]
			state.circuit.node_b[element] = state.slot_from[slot_index]
			_search(state, slot_index + 1)
			state.circuit.node_a[element] = state.slot_from[slot_index]
			state.circuit.node_b[element] = state.slot_to[slot_index]
			state.reversed[slot_index] = false
			state.remaining_reversible[t] += 1
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
			solution[state.slot_ids[s]] = state.type_texts[t] + (REVERSED_SUFFIX if state.reversed[s] else "")
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


## The text of a part placed in a slot: part_text(part), followed by
## REVERSED_SUFFIX (" reversed") when `reversed` and the kind has a direction
## (battery, diode, zener). A resistor never gets the suffix. "" for an
## invalid part, without an error.
static func placement_text(part: Dictionary, reversed: bool) -> String:
	var text: String = part_text(part)
	if text.is_empty() or not reversed or not REVERSIBLE_KINDS.has(String(part.get("kind"))):
		return text
	return text + REVERSED_SUFFIX


## True when `solution` (from find_solutions) holds a part in `slot_id` that
## sits reversed (plus or anode at the slot's `to`). False for a forward part
## or an empty slot.
static func is_reversed(solution: Dictionary, slot_id: String) -> bool:
	return str(solution.get(slot_id, "")).ends_with(REVERSED_SUFFIX)


## The part_text of the part in `slot_id` of `solution`, whichever way it
## sits ("diode 7/10 V" for "diode 7/10 V reversed"); "" for an empty slot.
## Use it to count which parts a solution uses.
static func placed_part_text(solution: Dictionary, slot_id: String) -> String:
	var text: String = str(solution.get(slot_id, ""))
	return text.trim_suffix(REVERSED_SUFFIX)


static func _is_reversible(part: Dictionary) -> bool:
	return bool(part.get("reversible", false)) and REVERSIBLE_KINDS.has(String(part["kind"]))


static func _validate_part(part: Dictionary, i: int) -> bool:
	var kind: Variant = part.get("kind")
	if typeof(kind) != TYPE_STRING or not PART_KINDS.has(String(kind)):
		push_error("DcPuzzleSearch.find_solutions: part %d needs kind \"resistor\", \"battery\", \"diode\" or \"zener\"." % i)
		return false
	if part.has("reversible") and typeof(part["reversible"]) != TYPE_BOOL:
		push_error("DcPuzzleSearch.find_solutions: part %d 'reversible' must be a bool, got %s." % [
				i, str(part["reversible"])])
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
