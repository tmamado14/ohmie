class_name PwlSolver
extends RefCounted
## Exact DC analysis of a network holding piecewise-linear devices (diodes,
## LEDs, Zeners; see PwlDevice and DiodeModel), by searching their states.
## DcSolver.solve calls this automatically for any network with a device; a
## network without devices never comes here.
##
## Algorithm. Every combination of device states is tried, in a fixed order
## (devices in element order, the last device's state changing fastest):
##   1. Each device branch is replaced by its state's linear stand-in: OPEN
##      becomes an open circuit whose voltage is still measured (internally a
##      voltmeter), VOLTAGE an ideal voltage source.
##   2. The combination is solved by DcSolver's exact linear solver (only the
##      quantities the check and the caller need).
##   3. If the linear status is OK, every condition of every device's state is
##      checked exactly (PwlCondition). A voltage condition on an OFF device
##      whose two ends lie in different connected parts cannot be read
##      directly: the parts' relative potential is free. It holds when some
##      choice of the parts' offsets satisfies all such conditions together,
##      which is decided exactly as a system of difference constraints
##      (Bellman-Ford with strictness tracked). Example: a battery whose loop
##      is closed only through two OFF diodes is not valid if its voltage
##      exceeds their two drops.
##   A combination is valid when its linear status is OK and every condition
##   holds.
##
## How the combinations' statuses combine:
##   - Any combination's linear solve gives ERROR (a value overflowed 64 bits)
##     -> ERROR. Never a guess.
##   - At least one valid combination: if there is exactly one, or every valid
##     combination gives the same node voltages, element voltages and element
##     currents, -> OK with those values (the device states of the first valid
##     combination). Valid combinations that disagree -> INDETERMINATE (e.g.
##     two identical diodes in parallel: ideal diodes do not say how they share
##     the current). SHORT and INDETERMINATE combinations are then ignored:
##     they are wrong guesses of the device states.
##   - No valid combination, and some combination is SHORT -> SHORT. This is a
##     real short: e.g. a battery directly across a forward diode (OFF breaks
##     the diode's condition, ON contradicts the battery).
##   - Otherwise, some combination is INDETERMINATE -> INDETERMINATE (e.g. two
##     ammeters in parallel elsewhere in the circuit).
##   - Otherwise -> ERROR "no consistent device states". For networks of
##     positive resistors, ideal sources, meters and diode-like devices this is
##     not expected to happen: the boundary rule (DiodeModel) makes the states
##     cover each characteristic exactly, and the randomised tests check it.
##
## Ohmmeters are measured once, with every device open (with all sources off,
## nothing forward-biases a diode), so a path only through a device reads OL.
##
## Cost: one partial linear solve per combination (the product of the
## devices' state counts: 2 per diode, 3 per Zener), plus one full solve for
## the answer, and one per valid combination when there is more than one.
## More than MAX_COMBINATIONS combinations is refused with ERROR.
##
## The input circuit's device elements are switched in place during the
## search and restored before returning.

## Upper bound on the number of state combinations (e.g. 16 diodes, or 10
## Zeners: 3^10 = 59049).
const MAX_COMBINATIONS: int = 65536

const _SOURCE: int = DcNetwork.Kind.VOLTAGE_SOURCE
const _VOLTMETER: int = DcNetwork.Kind.VOLTMETER
const _OHMMETER: int = DcNetwork.Kind.OHMMETER
const _OVERFLOW_MESSAGE: String = "a device condition does not fit in 64 bits"


## One device of a compiled circuit.
class _Device:
	extends RefCounted
	var id: String
	var model: PwlDevice
	var kind: int  # its DcNetwork.Kind
	var elements: Array[int] = []  # the compiled element of each branch


## The number of state combinations the search would try for `network`: the
## product of its devices' state counts (1 with no devices). 0 for a null
## network. Saturates at MAX_COMBINATIONS + 1.
static func combination_count(network: DcNetwork) -> int:
	if network == null:
		return 0
	var total: int = 1
	for id: String in network.get_element_ids():
		var model: PwlDevice = network.get_device(id)
		if model == null:
			continue
		total *= model.state_count()
		if total > MAX_COMBINATIONS:
			return MAX_COMBINATIONS + 1
	return total


## Solves a compiled circuit by searching its device states. `wanted` and
## `everything` have DcSolver._solve_circuit's meaning. Works (and is tested)
## with no devices too: one combination, the plain linear result.
static func _solve_compiled(circuit: DcSolver._Circuit, wanted: Dictionary, everything: bool) -> DcSolution:
	var devices: Array[_Device] = []
	var failure: String = _collect_devices(circuit, devices)
	var total: int = 1
	if failure.is_empty():
		for device: _Device in devices:
			total *= device.model.state_count()
			if total > MAX_COMBINATIONS:
				failure = "more than %d combinations of device states" % MAX_COMBINATIONS
				break
	if not failure.is_empty():
		var message: String = "PwlSolver: %s; the circuit cannot be solved." % failure
		push_error(message)
		return _finish_blank(circuit, devices, wanted, everything, DcSolution.Status.ERROR, message)

	var search_wanted: Dictionary = wanted.duplicate()
	for device: _Device in devices:
		for e: int in device.elements:
			search_wanted[circuit.ids[e]] = true

	var states: Array[int] = []
	states.resize(devices.size())
	states.fill(0)
	var valid: Array = []  # Array of Array[int] state lists
	var first_valid: DcSolution = null
	var any_short: bool = false
	var any_indeterminate: bool = false
	var error_message: String = ""
	for combination: int in total:
		_apply_states(circuit, devices, states)
		var result: DcSolution = DcSolver._solve_circuit(circuit, search_wanted, false, false)
		if result.status == DcSolution.Status.ERROR:
			error_message = result.error_message
			break
		if result.status == DcSolution.Status.SHORT:
			any_short = true
		elif result.status == DcSolution.Status.INDETERMINATE:
			any_indeterminate = true
		else:
			var verdict: int = _check(circuit, devices, states, result)
			if verdict < 0:
				error_message = "PwlSolver: %s; the circuit cannot be solved exactly." % _OVERFLOW_MESSAGE
				push_error(error_message)
				break
			if verdict > 0:
				valid.append(states.duplicate())
				if first_valid == null:
					first_valid = result
		_advance(states, devices)

	if not error_message.is_empty():
		return _finish_blank(circuit, devices, wanted, everything, DcSolution.Status.ERROR, error_message)
	if valid.is_empty():
		if any_short:
			return _finish_blank(circuit, devices, wanted, everything, DcSolution.Status.SHORT, "")
		if any_indeterminate:
			return _finish_blank(circuit, devices, wanted, everything, DcSolution.Status.INDETERMINATE, "")
		var none: String = "PwlSolver: no consistent device states; the circuit cannot be solved."
		push_error(none)
		return _finish_blank(circuit, devices, wanted, everything, DcSolution.Status.ERROR, none)
	if valid.size() > 1:
		var agreement: int = _all_agree(circuit, devices, valid)
		if agreement < 0:
			var message: String = "PwlSolver: %s; the circuit cannot be solved exactly." % _OVERFLOW_MESSAGE
			push_error(message)
			return _finish_blank(circuit, devices, wanted, everything, DcSolution.Status.ERROR, message)
		if agreement == 0:
			return _finish_blank(circuit, devices, wanted, everything, DcSolution.Status.INDETERMINATE, "")

	var chosen: Array[int] = []
	chosen.assign(valid[0])
	_apply_states(circuit, devices, chosen)
	var solution: DcSolution = first_valid
	if everything:
		solution = DcSolver._solve_circuit(circuit, {}, true, false)
	var record_failure: String = _record_devices(solution, circuit, devices, chosen, everything)
	if not record_failure.is_empty():
		var message: String = "PwlSolver: %s; the circuit cannot be solved exactly." % record_failure
		push_error(message)
		return _finish_blank(circuit, devices, wanted, everything, DcSolution.Status.ERROR, message)
	_restore(circuit, devices)
	_measure_ohmmeters(circuit, wanted, everything, solution)
	return solution


# --- devices --------------------------------------------------------------------------

## Fills `devices` with every present device element. Returns "" or a failure.
static func _collect_devices(circuit: DcSolver._Circuit, devices: Array[_Device]) -> String:
	for e: int in circuit.ids.size():
		var model: PwlDevice = circuit.models[e]
		if model == null or circuit.kinds[e] == DcSolver.ABSENT:
			continue
		if model.branch_count() != 1:
			return "device '%s' has %d branches; only two-terminal devices are supported" % [
					circuit.ids[e], model.branch_count()]
		var device: _Device = _Device.new()
		device.id = circuit.ids[e]
		device.model = model
		device.kind = model.network_kind()
		device.elements.append(e)
		devices.append(device)
	return ""


## Replaces every device branch by its stand-in for `states`.
static func _apply_states(circuit: DcSolver._Circuit, devices: Array[_Device], states: Array[int]) -> void:
	for i: int in devices.size():
		var device: _Device = devices[i]
		for b: int in device.elements.size():
			var e: int = device.elements[b]
			if device.model.branch_kind(states[i], b) == PwlDevice.BranchKind.VOLTAGE:
				circuit.set_element(e, _SOURCE, device.model.branch_value(states[i], b), null, device.model)
			else:
				circuit.set_element(e, _VOLTMETER, null, null, device.model)


## Puts every device element back to its own kind (which every solver pass
## treats as open).
static func _restore(circuit: DcSolver._Circuit, devices: Array[_Device]) -> void:
	for device: _Device in devices:
		for e: int in device.elements:
			circuit.set_element(e, device.kind, null, null, device.model)


## The next combination: the last device's state changes fastest.
static func _advance(states: Array[int], devices: Array[_Device]) -> void:
	for i: int in range(devices.size() - 1, -1, -1):
		states[i] += 1
		if states[i] < devices[i].model.state_count():
			return
		states[i] = 0


## The current from a branch's first node to its second through the device,
## in a solution of the current stand-ins. Null when it was not computed.
static func _branch_current(circuit: DcSolver._Circuit, e: int, result: DcSolution) -> Rational:
	if circuit.kinds[e] != _SOURCE:
		return Rational.new(0)
	var delivered: Rational = result.current_through(circuit.ids[e])
	if delivered == null:
		return null
	# A source reports the current leaving its plus (first) node into the
	# circuit; the current through it from first to second node is the opposite.
	return delivered.negate()


# --- validity -------------------------------------------------------------------------

## 1 when every condition of every device state holds in `result`, 0 when one
## does not, -1 on overflow.
static func _check(circuit: DcSolver._Circuit, devices: Array[_Device], states: Array[int],
		result: DcSolution) -> int:
	var deferred: Array = []  # [device, condition] pairs across connected parts
	for i: int in devices.size():
		var device: _Device = devices[i]
		for condition: PwlCondition in device.model.conditions(states[i]):
			if condition.quantity == PwlCondition.Quantity.BRANCH_CURRENTS:
				var total: Rational = Rational.new(0)
				for b: int in condition.coefficient_count():
					var c: Rational = condition.coefficient(b)
					if c.is_zero():
						continue
					var current: Rational = _branch_current(circuit, device.elements[b], result)
					if current == null:
						return -1
					var term: Rational = DcSolver._times(c, current)
					total = null if term == null else DcSolver._plus(total, term)
					if total == null:
						return -1
				if not condition.holds(total):
					return 0
				continue
			var e: int = device.elements[condition.branch]
			var volts: Rational = null
			if circuit.kinds[e] == _SOURCE:
				volts = circuit.values[e]
			elif result.meter_state(circuit.ids[e]) == DcSolution.MeterState.VALUE:
				volts = result.meter_reading(circuit.ids[e])
			else:
				deferred.append([device, condition])
				continue
			if not condition.holds(volts):
				return 0
	if deferred.is_empty():
		return 1
	return _offsets_feasible(circuit, deferred)


## Decides the voltage conditions whose branch ends lie in different
## connected parts. Each part's potential may be shifted by a free offset c;
## a condition V(x) - V(y) <relation> bound becomes a difference constraint
## on c(part of x) - c(part of y). Feasible exactly when the constraint graph
## has no negative cycle, with strict edges counted as "minus epsilon".
## Returns 1 feasible, 0 infeasible, -1 on overflow.
static func _offsets_feasible(circuit: DcSolver._Circuit, deferred: Array) -> int:
	var full: DcSolution = DcSolver._solve_circuit(circuit, {}, true, false)
	if full.status != DcSolution.Status.OK:
		return -1
	var part: Array[int] = _components(circuit)
	var edges: Array = []  # [from part, to part, weight, strict]
	var parts: Dictionary = {}
	for item: Array in deferred:
		var device: _Device = item[0]
		var condition: PwlCondition = item[1]
		var e: int = device.elements[condition.branch]
		var x: int = circuit.node_a[e]
		var y: int = circuit.node_b[e]
		var vx: Rational = full.node_voltage(circuit.node_names[x])
		var vy: Rational = full.node_voltage(circuit.node_names[y])
		var px: int = part[x]
		var py: int = part[y]
		if px == py:
			var v: Rational = DcSolver._minus(vx, vy)
			if v == null:
				return -1
			if not condition.holds(v):
				return 0
			continue
		# c(px) - c(py) <relation> w, with w = bound - vx + vy.
		var w: Rational = DcSolver._minus(condition.bound, vx)
		w = null if w == null else DcSolver._plus(w, vy)
		if w == null:
			return -1
		match condition.relation:
			PwlCondition.Relation.AT_MOST:
				edges.append([py, px, w, false])
			PwlCondition.Relation.BELOW:
				edges.append([py, px, w, true])
			PwlCondition.Relation.AT_LEAST:
				edges.append([px, py, w.negate(), false])
			PwlCondition.Relation.ABOVE:
				edges.append([px, py, w.negate(), true])
		parts[px] = true
		parts[py] = true
	if edges.is_empty():
		return 1
	var zero: Rational = Rational.new(0)
	var dist: Dictionary = {}  # part -> Rational
	var eps: Dictionary = {}  # part -> int (multiples of epsilon, <= 0)
	for p: int in parts.keys():
		dist[p] = zero
		eps[p] = 0
	for pass_index: int in parts.size() + 1:
		var changed: bool = false
		for edge: Array in edges:
			var u: int = edge[0]
			var v: int = edge[1]
			var candidate: Rational = DcSolver._plus(dist[u], edge[2])
			if candidate == null:
				return -1
			var candidate_eps: int = int(eps[u]) - (1 if edge[3] else 0)
			var c: int = candidate.compare(dist[v])
			if c < 0 or (c == 0 and candidate_eps < int(eps[v])):
				dist[v] = candidate
				eps[v] = candidate_eps
				changed = true
		if not changed:
			return 1
	return 0


## The connected part of every node, by DcSolver's rule: nodes joined by wires,
## resistors, voltage sources or ammeters (as currently set) are one part.
## Each part is named by one of its node indices.
static func _components(circuit: DcSolver._Circuit) -> Array[int]:
	var n: int = circuit.node_names.size()
	var m: Array[int] = circuit.merged
	var component: Array[int] = DcSolver._identity(n)
	for e: int in circuit.ids.size():
		var kind: int = circuit.kinds[e]
		if kind == DcNetwork.Kind.RESISTOR or kind == _SOURCE or kind == DcNetwork.Kind.AMMETER:
			DcSolver._union(component, m[circuit.node_a[e]], m[circuit.node_b[e]])
	var part: Array[int] = []
	part.resize(n)
	for x: int in n:
		part[x] = DcSolver._root(component, m[x])
	return part


## Full solves of every valid combination. 1 when they all agree on every node
## voltage and every element voltage and current, 0 when they do not, -1 on
## overflow.
static func _all_agree(circuit: DcSolver._Circuit, devices: Array[_Device], valid: Array) -> int:
	var first: String = ""
	for i: int in valid.size():
		var states: Array[int] = []
		states.assign(valid[i])
		_apply_states(circuit, devices, states)
		var solution: DcSolution = DcSolver._solve_circuit(circuit, {}, true, false)
		if solution.status != DcSolution.Status.OK:
			return -1
		if not _record_devices(solution, circuit, devices, states, true).is_empty():
			return -1
		var signature: String = _signature(circuit, solution)
		if i == 0:
			first = signature
		elif signature != first:
			return 0
	return 1


static func _signature(circuit: DcSolver._Circuit, solution: DcSolution) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for node_name: String in circuit.node_names:
		lines.append("n %s %s" % [node_name, _text(solution.node_voltage(node_name))])
	for id: String in circuit.ids:
		lines.append("e %s %s %s" % [id, _text(solution.voltage_across(id)), _text(solution.current_through(id))])
	return "\n".join(lines)


static func _text(value: Rational) -> String:
	return "-" if value == null else value.to_text()


# --- results --------------------------------------------------------------------------

## Turns the stand-ins' entries in an OK `solution` into device entries for
## the chosen `states` (the circuit must still hold those stand-ins). Returns
## "" or a failure.
static func _record_devices(solution: DcSolution, circuit: DcSolver._Circuit, devices: Array[_Device],
		states: Array[int], everything: bool) -> String:
	for i: int in devices.size():
		var device: _Device = devices[i]
		var e: int = device.elements[0]
		var id: String = device.id
		solution._kinds[id] = device.kind
		solution._meter_states.erase(id)
		solution._meter_readings.erase(id)
		var current: Rational = _branch_current(circuit, e, solution)
		if current == null:
			return "the current through '%s' was not computed" % id
		var volts: Rational = solution._voltages.get(id, null)
		var power: Rational = Rational.new(0)
		if volts != null:
			power = DcSolver._times(volts, current)
			if power == null:
				return "the power of '%s' does not fit in 64 bits" % id
		solution._currents[id] = current
		solution._powers[id] = power
		solution._device_states[id] = states[i]
		solution._device_state_names[id] = device.model.state_name(states[i])
		if everything and not current.is_zero():
			solution._energized = true
	return ""


## A solution with no values (status SHORT, INDETERMINATE or ERROR), shaped
## like DcSolver's for those statuses: every element's kind, every meter
## INVALID, ohmmeters measured. Restores the devices first.
static func _finish_blank(circuit: DcSolver._Circuit, devices: Array[_Device], wanted: Dictionary,
		everything: bool, status: DcSolution.Status, message: String) -> DcSolution:
	_restore(circuit, devices)
	var solution: DcSolution = DcSolution.new()
	solution.status = status
	solution.error_message = message
	for e: int in circuit.ids.size():
		var kind: int = circuit.kinds[e]
		if kind == DcSolver.ABSENT:
			continue
		var id: String = circuit.ids[e]
		solution._kinds[id] = kind
		if kind == DcNetwork.Kind.AMMETER or kind == _VOLTMETER or kind == _OHMMETER:
			solution._meter_states[id] = DcSolution.MeterState.INVALID
	_measure_ohmmeters(circuit, wanted, everything, solution)
	return solution


## Measures the ohmmeters (devices must be restored, so they are open).
static func _measure_ohmmeters(circuit: DcSolver._Circuit, wanted: Dictionary, everything: bool,
		solution: DcSolution) -> void:
	for e: int in circuit.ids.size():
		if circuit.kinds[e] == _OHMMETER and (everything or wanted.has(circuit.ids[e])):
			DcSolver._solve_ohmmeters(circuit, wanted, everything, solution)
			return
