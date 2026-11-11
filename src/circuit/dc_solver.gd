class_name DcSolver
extends RefCounted
## Exact DC analysis of a DcNetwork: modified nodal analysis (MNA) solved with
## rational Gauss-Jordan elimination. Exact rationals only, never approximated.
##
## 1. Nodes joined by wires are merged (union-find). Every merged node is named
##    by its alphabetically smallest member.
## 2. Connected components are found over the conducting elements (resistors,
##    voltage sources, ammeters). Voltmeters and ohmmeters are open circuits.
##    Each component is grounded at its alphabetically smallest node, so
##    unconnected parts never make the system singular.
## 3. Voltage sources and ammeters (an ammeter is a 0 V source) are the MNA
##    branch equations V(first) - V(second) = volts. They are eliminated by
##    substitution before the matrix is built: nodes joined by sources form a
##    "supernode" whose members' voltages are fixed offsets from one root
##    (union-find with exact offsets). This is the same linear system as
##    textbook MNA with the source rows and columns solved first, so it has
##    the same solutions, but the matrix left to eliminate is much smaller.
##    - A source whose ends are already in one supernode closes a loop of
##      sources. If the loop's voltages do not sum to zero the equations are
##      inconsistent: SHORT. If they do, the loop current is undetermined:
##      INDETERMINATE. (SHORT wins when both happen.)
## 4. Kirchhoff's current law for every supernode that is not its component's
##    reference gives a conductance (Laplacian) system, solved exactly. With
##    positive resistances and the loops above excluded it always has exactly
##    one solution.
## 5. Source and ammeter currents are recovered from Kirchhoff's current law
##    by peeling the source forest from its leaves.
## 6. Every ohmmeter gets its own exact solve of the dead network (sources and
##    ammeters become wires, voltmeters and other ohmmeters are open): inject
##    1 A at a, take it out at b, reading = V(a) - V(b).
##
## Any 64-bit overflow gives status ERROR with a message (and push_error);
## never a wrong number. Sign conventions are listed in DcSolution. The input
## network is never modified, and the same network always gives the same
## result.
##
## Internals are shared with DcPuzzleSearch: a network is compiled once into
## index arrays (_Circuit), and slot elements are switched on and off in place.

const _LINEAR_OK: int = 0
const _LINEAR_INCONSISTENT: int = 1
const _LINEAR_SINGULAR: int = 2
const _LINEAR_OVERFLOW: int = 3

## Kind of a compiled element that is currently not part of the circuit (an
## empty puzzle slot).
const ABSENT: int = -1

const _WIRE: int = DcNetwork.Kind.WIRE
const _RESISTOR: int = DcNetwork.Kind.RESISTOR
const _SOURCE: int = DcNetwork.Kind.VOLTAGE_SOURCE
const _AMMETER: int = DcNetwork.Kind.AMMETER
const _VOLTMETER: int = DcNetwork.Kind.VOLTMETER
const _OHMMETER: int = DcNetwork.Kind.OHMMETER


## A network compiled to index arrays. Node indices follow sorted node names,
## so a smaller index is an alphabetically smaller name.
class _Circuit:
	extends RefCounted
	var node_names: Array[String] = []
	var node_index: Dictionary = {}  # node name -> index
	var merged: Array[int] = []  # node index -> index of its wire-merged node
	var ids: Array[String] = []
	var element_index: Dictionary = {}  # id -> element index
	var kinds: Array[int] = []  # DcNetwork.Kind, or ABSENT
	var node_a: Array[int] = []
	var node_b: Array[int] = []
	var values: Array[Rational] = []  # ohms or volts; null for other kinds
	var conductances: Array[Rational] = []  # 1 / ohms for resistors, else null

	func add_element(id: String, kind: int, a: int, b: int, value: Rational,
			conductance: Rational) -> int:
		element_index[id] = ids.size()
		ids.append(id)
		kinds.append(kind)
		node_a.append(a)
		node_b.append(b)
		values.append(value)
		conductances.append(conductance)
		return ids.size() - 1

	func set_element(index: int, kind: int, value: Rational, conductance: Rational) -> void:
		kinds[index] = kind
		values[index] = value
		conductances[index] = conductance


## Solves `network` without modifying it. Never returns null.
static func solve(network: DcNetwork) -> DcSolution:
	if network == null:
		var solution: DcSolution = DcSolution.new()
		var message: String = "DcSolver.solve: network is null."
		push_error(message)
		solution.status = DcSolution.Status.ERROR
		solution.error_message = message
		return solution
	var no_extra_nodes: Array[String] = []
	return _solve_circuit(_compile(network, no_extra_nodes), {}, true)


# --- compiling ---------------------------------------------------------------------

## Compiles `network` (plus `extra_nodes`, which need not appear in it). Wire
## merging is done here, so elements added later must not be wires.
static func _compile(network: DcNetwork, extra_nodes: Array[String]) -> _Circuit:
	var circuit: _Circuit = _Circuit.new()
	var seen: Dictionary = {}
	for node: String in network.get_nodes():
		seen[node] = true
	for node: String in extra_nodes:
		seen[node] = true
	var names: Array[String] = []
	for key: String in seen.keys():
		names.append(key)
	names.sort()
	circuit.node_names = names
	for i: int in names.size():
		circuit.node_index[names[i]] = i
	var parent: Array[int] = _identity(names.size())
	for id: String in network.get_element_ids():
		var kind: int = network.get_kind(id)
		var a: int = circuit.node_index[network.get_node_a(id)]
		var b: int = circuit.node_index[network.get_node_b(id)]
		if kind == _WIRE:
			_union(parent, a, b)
		var value: Rational = network.get_value(id)
		var conductance: Rational = value.reciprocal() if kind == _RESISTOR else null
		circuit.add_element(id, kind, a, b, value, conductance)
	circuit.merged.resize(names.size())
	for i: int in names.size():
		circuit.merged[i] = _root(parent, i)
	return circuit


# --- solving -----------------------------------------------------------------------

## Solves a compiled circuit. With `everything` true every quantity is filled
## in. Otherwise only the elements whose ids are keys of `wanted` get voltage,
## current, power and meter values (used by the puzzle search, where only the
## goal conditions matter); node voltages and is_energized are then not set.
static func _solve_circuit(circuit: _Circuit, wanted: Dictionary, everything: bool) -> DcSolution:
	var solution: DcSolution = DcSolution.new()
	var any_ohmmeter: bool = false
	for e: int in circuit.ids.size():
		var kind: int = circuit.kinds[e]
		if kind == ABSENT:
			continue
		var id: String = circuit.ids[e]
		solution._kinds[id] = kind
		if kind == _AMMETER or kind == _VOLTMETER or kind == _OHMMETER:
			solution._meter_states[id] = DcSolution.MeterState.INVALID
			if kind == _OHMMETER and (everything or wanted.has(id)):
				any_ohmmeter = true

	var failure: String = _solve_live(circuit, wanted, everything, solution)
	if not failure.is_empty():
		var message: String = "DcSolver.solve: %s; the circuit cannot be solved exactly." % failure
		push_error(message)
		solution.status = DcSolution.Status.ERROR
		solution.error_message = message
		solution._node_voltages.clear()
		solution._voltages.clear()
		solution._currents.clear()
		solution._powers.clear()
		solution._meter_readings.clear()
		solution._energized = false
		for id: String in solution._meter_states.keys():
			solution._meter_states[id] = DcSolution.MeterState.INVALID

	if any_ohmmeter:
		_solve_ohmmeters(circuit, wanted, everything, solution)
	return solution


## Fills `solution` for the live circuit. Returns "" on success (including
## SHORT and INDETERMINATE), otherwise a description of the failure.
static func _solve_live(circuit: _Circuit, wanted: Dictionary, everything: bool,
		solution: DcSolution) -> String:
	var zero: Rational = Rational.new(0)
	var n: int = circuit.node_names.size()
	var count: int = circuit.ids.size()
	var m: Array[int] = circuit.merged

	# Components over conducting elements.
	var component: Array[int] = _identity(n)
	for e: int in count:
		var kind: int = circuit.kinds[e]
		if kind == _RESISTOR or kind == _SOURCE or kind == _AMMETER:
			_union(component, m[circuit.node_a[e]], m[circuit.node_b[e]])

	# Supernodes: union-find where offset[x] = V(x) - V(parent of x).
	var super_parent: Array[int] = _identity(n)
	var offset: Array[Rational] = []
	offset.resize(n)
	offset.fill(zero)
	var inconsistent: bool = false
	var redundant: bool = false
	for e: int in count:
		var kind: int = circuit.kinds[e]
		if kind != _SOURCE and kind != _AMMETER:
			continue
		var p: int = m[circuit.node_a[e]]
		var q: int = m[circuit.node_b[e]]
		var root_p: int = _root(super_parent, p)
		var root_q: int = _root(super_parent, q)
		var offset_p: Rational = _offset_to_root(super_parent, offset, p, zero)
		var offset_q: Rational = _offset_to_root(super_parent, offset, q, zero)
		if offset_p == null or offset_q == null:
			return "a source voltage sum does not fit in 64 bits"
		var volts: Rational = circuit.values[e] if kind == _SOURCE else zero
		# gap = (V(p) - V(q)) - (V(root_p) - V(root_q))
		var gap: Rational = _minus(offset_p, offset_q)
		if gap == null:
			return "a source voltage sum does not fit in 64 bits"
		if root_p == root_q:
			if gap.equals(volts):
				redundant = true
			else:
				inconsistent = true
			continue
		# V(p) - V(q) = volts  =>  V(root_q) - V(root_p) = gap - volts.
		var delta: Rational = _minus(gap, volts)
		if delta == null:
			return "a source voltage sum does not fit in 64 bits"
		if root_p < root_q:
			super_parent[root_q] = root_p
			offset[root_q] = delta
		else:
			super_parent[root_p] = root_q
			offset[root_p] = delta.negate()
	if inconsistent:
		solution.status = DcSolution.Status.SHORT
		return ""
	if redundant:
		solution.status = DcSolution.Status.INDETERMINATE
		return ""

	# Flatten: every merged node's component, supernode root and offset.
	var comp_of: Array[int] = []
	comp_of.resize(n)
	comp_of.fill(-1)
	var root_of: Array[int] = []
	root_of.resize(n)
	root_of.fill(-1)
	var offset_of: Array[Rational] = []
	offset_of.resize(n)
	for x: int in n:
		if m[x] != x:
			continue
		comp_of[x] = _root(component, x)
		root_of[x] = _root(super_parent, x)
		offset_of[x] = _offset_to_root(super_parent, offset, x, zero)
		if offset_of[x] == null:
			return "a source voltage sum does not fit in 64 bits"

	# A component is active when it holds a non-zero source. In every other
	# component all voltages and currents are exactly zero, so it needs no
	# arithmetic. Unless `everything` is asked for, only components holding a
	# wanted element are solved.
	var active: Array[bool] = []
	active.resize(n)
	active.fill(false)
	for e: int in count:
		if circuit.kinds[e] == _SOURCE and not circuit.values[e].is_zero():
			active[comp_of[m[circuit.node_a[e]]]] = true
	var needed: Array[bool] = []
	needed.resize(n)
	needed.fill(everything)
	var branch_needed: Array[bool] = []
	branch_needed.resize(n)
	branch_needed.fill(everything)
	if not everything:
		for id: Variant in wanted.keys():
			var e: int = int(circuit.element_index.get(id, -1))
			if e < 0 or circuit.kinds[e] == ABSENT:
				continue
			var ca: int = comp_of[m[circuit.node_a[e]]]
			needed[ca] = true
			needed[comp_of[m[circuit.node_b[e]]]] = true
			if circuit.kinds[e] == _SOURCE or circuit.kinds[e] == _AMMETER:
				branch_needed[ca] = true

	# Each component's ground (its smallest merged node) has V = 0, which fixes
	# its supernode's root voltage. Every other supernode root of a component
	# being solved is an unknown.
	var known: Array[Rational] = []
	known.resize(n)
	for x: int in n:
		if m[x] == x and comp_of[x] == x:
			known[root_of[x]] = _minus(zero, offset_of[x])
	var unknown_index: Array[int] = []
	unknown_index.resize(n)
	unknown_index.fill(-1)
	var size: int = 0
	for x: int in n:
		if (m[x] == x and super_parent[x] == x and known[x] == null
				and active[comp_of[x]] and needed[comp_of[x]]):
			unknown_index[x] = size
			size += 1

	# Kirchhoff's current law per unknown supernode.
	var rows: Array[Array] = _zero_rows(size)
	for e: int in count:
		if circuit.kinds[e] != _RESISTOR:
			continue
		var x: int = m[circuit.node_a[e]]
		var y: int = m[circuit.node_b[e]]
		var sx: int = root_of[x]
		var sy: int = root_of[y]
		if sx == sy or not active[comp_of[x]] or not needed[comp_of[x]]:
			continue
		var g: Rational = circuit.conductances[e]
		# V(x) - V(y) = X(sx) - X(sy) + d
		var d: Rational = _minus(offset_of[x], offset_of[y])
		if d == null:
			return "a source voltage sum does not fit in 64 bits"
		var ix: int = unknown_index[sx]
		var iy: int = unknown_index[sy]
		var g_d: Rational = _times(g, d)
		if g_d == null:
			return "a conductance product does not fit in 64 bits"
		if ix >= 0:
			if not (_accumulate(rows, ix, ix, g, false) and _accumulate(rows, ix, size, g_d, true)):
				return "a conductance sum does not fit in 64 bits"
			if iy >= 0:
				if not _accumulate(rows, ix, iy, g, true):
					return "a conductance sum does not fit in 64 bits"
			else:
				var g_known: Rational = _times(g, known[sy])
				if g_known == null or not _accumulate(rows, ix, size, g_known, false):
					return "a conductance product does not fit in 64 bits"
		if iy >= 0:
			if not (_accumulate(rows, iy, iy, g, false) and _accumulate(rows, iy, size, g_d, false)):
				return "a conductance sum does not fit in 64 bits"
			if ix >= 0:
				if not _accumulate(rows, iy, ix, g, true):
					return "a conductance sum does not fit in 64 bits"
			else:
				var g_known: Rational = _times(g, known[sx])
				if g_known == null or not _accumulate(rows, iy, size, g_known, false):
					return "a conductance product does not fit in 64 bits"

	var unknowns: Array[Rational] = []
	var outcome: int = _eliminate(rows, size, unknowns)
	if outcome == _LINEAR_OVERFLOW:
		return "an intermediate value of the elimination does not fit in 64 bits"
	if outcome != _LINEAR_OK:
		return "internal error: the conductance system is singular"
	solution.status = DcSolution.Status.OK

	# Voltage of every merged node: zero in inactive components, null in
	# components that were not needed.
	var voltage: Array[Rational] = []
	voltage.resize(n)
	for x: int in n:
		if m[x] != x:
			continue
		var c: int = comp_of[x]
		if not active[c]:
			voltage[x] = zero
		elif needed[c]:
			var root: int = root_of[x]
			var root_voltage: Rational = known[root] if unknown_index[root] < 0 else unknowns[unknown_index[root]]
			voltage[x] = _plus(root_voltage, offset_of[x])
			if voltage[x] == null:
				return "a node voltage does not fit in 64 bits"

	# Resistor currents (first node to second node), where needed.
	var resistor_current: Array[Rational] = []
	resistor_current.resize(count)
	for e: int in count:
		if circuit.kinds[e] != _RESISTOR:
			continue
		var x: int = m[circuit.node_a[e]]
		if not (everything or branch_needed[comp_of[x]] or wanted.has(circuit.ids[e])):
			continue
		var v: Rational = _minus(voltage[x], voltage[m[circuit.node_b[e]]])
		if v == null:
			return "the voltage across '%s' does not fit in 64 bits" % circuit.ids[e]
		var i: Rational = _times(v, circuit.conductances[e])
		if i == null:
			return "the current through '%s' does not fit in 64 bits" % circuit.ids[e]
		resistor_current[e] = i

	var branch_current: Array[Rational] = []
	branch_current.resize(count)
	var failure: String = _branch_currents(circuit, comp_of, branch_needed, resistor_current,
			branch_current, zero)
	if not failure.is_empty():
		return failure

	# Per-element results.
	for e: int in count:
		var kind: int = circuit.kinds[e]
		if kind == ABSENT:
			continue
		var id: String = circuit.ids[e]
		if not everything and not wanted.has(id):
			continue
		var x: int = m[circuit.node_a[e]]
		var y: int = m[circuit.node_b[e]]
		var same_part: bool = comp_of[x] == comp_of[y]
		var v: Rational = null
		if same_part:
			v = _minus(voltage[x], voltage[y])
			if v == null:
				return "the voltage across '%s' does not fit in 64 bits" % id
			solution._voltages[id] = v
		if kind == _RESISTOR:
			var power: Rational = _times(v, resistor_current[e])
			if power == null:
				return "the power of '%s' does not fit in 64 bits" % id
			solution._currents[id] = resistor_current[e]
			solution._powers[id] = power
		elif kind == _SOURCE:
			var delivered: Rational = _minus(zero, branch_current[e])
			var power: Rational = _times(v, delivered)
			if power == null:
				return "the power of '%s' does not fit in 64 bits" % id
			solution._currents[id] = delivered
			solution._powers[id] = power
		elif kind == _AMMETER:
			solution._currents[id] = branch_current[e]
			solution._powers[id] = zero
			solution._meter_states[id] = DcSolution.MeterState.VALUE
			solution._meter_readings[id] = branch_current[e]
		elif kind == _VOLTMETER or kind == _OHMMETER:
			solution._currents[id] = zero
			solution._powers[id] = zero
			if kind == _VOLTMETER:
				if same_part:
					solution._meter_states[id] = DcSolution.MeterState.VALUE
					solution._meter_readings[id] = v
				else:
					solution._meter_states[id] = DcSolution.MeterState.OPEN

	if everything:
		for i: int in n:
			solution._node_voltages[circuit.node_names[i]] = voltage[m[i]]
		for e: int in count:
			if circuit.kinds[e] == _RESISTOR and not resistor_current[e].is_zero():
				solution._energized = true
	return ""


## Current of every voltage source and ammeter in a component marked in
## `branch_needed` (first node to second node through the element), from
## Kirchhoff's current law: the sources form a forest (loops were ruled out),
## so peel it from its leaves. Every resistor current in those components must
## already be in `resistor_current`.
static func _branch_currents(circuit: _Circuit, comp_of: Array[int], branch_needed: Array[bool],
		resistor_current: Array[Rational], branch_current: Array[Rational], zero: Rational) -> String:
	var n: int = circuit.node_names.size()
	var count: int = circuit.ids.size()
	var m: Array[int] = circuit.merged
	var incident: Array = []  # node -> Array of element indices, or null
	incident.resize(n)
	var degree: Array[int] = []
	degree.resize(n)
	degree.fill(0)
	var pending: int = 0
	for e: int in count:
		var kind: int = circuit.kinds[e]
		if kind != _SOURCE and kind != _AMMETER:
			continue
		var x: int = m[circuit.node_a[e]]
		if not branch_needed[comp_of[x]]:
			continue
		var y: int = m[circuit.node_b[e]]
		for node: int in [x, y]:
			if incident[node] == null:
				incident[node] = []
			(incident[node] as Array).append(e)
			degree[node] += 1
		pending += 1
	if pending == 0:
		return ""
	# residual[x]: current leaving x through everything resolved so far.
	var residual: Array[Rational] = []
	residual.resize(n)
	residual.fill(zero)
	for e: int in count:
		if circuit.kinds[e] != _RESISTOR:
			continue
		var x: int = m[circuit.node_a[e]]
		var y: int = m[circuit.node_b[e]]
		if x == y or degree[x] + degree[y] == 0 or not branch_needed[comp_of[x]]:
			continue
		residual[x] = _plus(residual[x], resistor_current[e])
		residual[y] = _minus(residual[y], resistor_current[e])
		if residual[x] == null or residual[y] == null:
			return "a current sum does not fit in 64 bits"
	var stack: Array[int] = []
	for x: int in range(n - 1, -1, -1):
		if degree[x] == 1:
			stack.append(x)
	var resolved: Array[bool] = []
	resolved.resize(count)
	resolved.fill(false)
	while not stack.is_empty():
		var x: int = stack.pop_back()
		if degree[x] != 1:
			continue
		var k: int = -1
		for candidate: int in incident[x]:
			if not resolved[candidate]:
				k = candidate
				break
		var plus_end: int = m[circuit.node_a[k]]
		# KCL at x: residual + (+I if x is the first node, else -I) = 0.
		var current: Rational = _minus(zero, residual[x]) if plus_end == x else residual[x]
		branch_current[k] = current
		resolved[k] = true
		pending -= 1
		degree[x] = 0
		var y: int = m[circuit.node_b[k]] if plus_end == x else plus_end
		residual[y] = _plus(residual[y], current) if y == plus_end else _minus(residual[y], current)
		if residual[y] == null:
			return "a current sum does not fit in 64 bits"
		degree[y] -= 1
		if degree[y] == 1:
			stack.append(y)
	if pending != 0:
		return "internal error: source currents could not be resolved"
	return ""


# --- ohmmeters ---------------------------------------------------------------------

static func _solve_ohmmeters(circuit: _Circuit, wanted: Dictionary, everything: bool,
		solution: DcSolution) -> void:
	var n: int = circuit.node_names.size()
	var count: int = circuit.ids.size()
	var m: Array[int] = circuit.merged
	# Dead network: voltage sources and ammeters become wires.
	var dead: Array[int] = _identity(n)
	for e: int in count:
		var kind: int = circuit.kinds[e]
		if kind == _SOURCE or kind == _AMMETER:
			_union(dead, m[circuit.node_a[e]], m[circuit.node_b[e]])
	var adjacency: Array = []  # dead node -> Array of neighbouring dead nodes, or null
	adjacency.resize(n)
	for e: int in count:
		if circuit.kinds[e] != _RESISTOR:
			continue
		var a: int = _root(dead, m[circuit.node_a[e]])
		var b: int = _root(dead, m[circuit.node_b[e]])
		if a == b:
			continue
		if adjacency[a] == null:
			adjacency[a] = []
		if adjacency[b] == null:
			adjacency[b] = []
		(adjacency[a] as Array).append(b)
		(adjacency[b] as Array).append(a)

	for e: int in count:
		if circuit.kinds[e] != _OHMMETER:
			continue
		var id: String = circuit.ids[e]
		if not everything and not wanted.has(id):
			continue
		var a: int = _root(dead, m[circuit.node_a[e]])
		var b: int = _root(dead, m[circuit.node_b[e]])
		if a == b:
			solution._meter_states[id] = DcSolution.MeterState.VALUE
			solution._meter_readings[id] = Rational.new(0)
			continue
		var reachable: Dictionary = _reachable(adjacency, a)
		if not reachable.has(b):
			solution._meter_states[id] = DcSolution.MeterState.OPEN
			continue
		var reading: Rational = _dead_resistance(circuit, dead, reachable, a, b)
		if reading == null:
			push_error("DcSolver.solve: the reading of ohmmeter '%s' does not fit in 64 bits." % id)
			solution._meter_states[id] = DcSolution.MeterState.INVALID
		else:
			solution._meter_states[id] = DcSolution.MeterState.VALUE
			solution._meter_readings[id] = reading


## Resistance between distinct, connected dead nodes a and b: ground b, inject
## 1 A at a, return V(a). Null on overflow.
static func _dead_resistance(circuit: _Circuit, dead: Array[int], reachable: Dictionary,
		a: int, b: int) -> Rational:
	var members: Array[int] = []
	for key: int in reachable.keys():
		if key != b:
			members.append(key)
	members.sort()
	var index: Dictionary = {}
	for i: int in members.size():
		index[members[i]] = i
	var size: int = members.size()
	var rows: Array[Array] = _zero_rows(size)
	var m: Array[int] = circuit.merged
	for e: int in circuit.ids.size():
		if circuit.kinds[e] != _RESISTOR:
			continue
		var x: int = _root(dead, m[circuit.node_a[e]])
		var y: int = _root(dead, m[circuit.node_b[e]])
		if x == y or not reachable.has(x):
			continue
		var ix: int = int(index.get(x, -1))
		var iy: int = int(index.get(y, -1))
		var g: Rational = circuit.conductances[e]
		if not (_accumulate(rows, ix, ix, g, false) and _accumulate(rows, iy, iy, g, false)
				and _accumulate(rows, ix, iy, g, true) and _accumulate(rows, iy, ix, g, true)):
			return null
	rows[index[a]][size] = Rational.new(1)
	var values: Array[Rational] = []
	if _eliminate(rows, size, values) != _LINEAR_OK:
		return null
	return values[index[a]]


# --- exact arithmetic helpers (null means overflow) ---------------------------------

static func _plus(a: Rational, b: Rational) -> Rational:
	if b.is_zero():
		return a
	if a.is_zero():
		return b
	return a.add(b)


static func _minus(a: Rational, b: Rational) -> Rational:
	if b.is_zero():
		return a
	if a.is_zero():
		return b.negate()
	return a.sub(b)


static func _times(a: Rational, b: Rational) -> Rational:
	if a.is_zero():
		return a
	if b.is_zero():
		return b
	return a.mul(b)


static func _offset_to_root(parent: Array[int], offset: Array[Rational], x: int,
		zero: Rational) -> Rational:
	var total: Rational = zero
	while parent[x] != x:
		total = _plus(total, offset[x])
		if total == null:
			return null
		x = parent[x]
	return total


# --- linear algebra ----------------------------------------------------------------

## `size` rows of `size` + 1 entries (the last is the right-hand side), all
## null. In the matrix, null stands for an exact zero so zero entries are
## skipped.
static func _zero_rows(size: int) -> Array[Array]:
	var rows: Array[Array] = []
	for r: int in size:
		var row: Array = []
		row.resize(size + 1)
		rows.append(row)
	return rows


## Adds (or subtracts) `value` to rows[r][c]. Does nothing when r or c is -1
## or the value is zero. Returns false on overflow.
static func _accumulate(rows: Array[Array], r: int, c: int, value: Rational, subtract: bool) -> bool:
	if r < 0 or c < 0 or value.is_zero():
		return true
	var current: Variant = rows[r][c]
	var total: Rational = null
	if current == null:
		total = value.negate() if subtract else value
	elif subtract:
		total = (current as Rational).sub(value)
	else:
		total = (current as Rational).add(value)
	if total == null:
		return false
	rows[r][c] = null if total.is_zero() else total
	return true


## Gauss-Jordan elimination of a square system with augmented rows. On
## _LINEAR_OK fills `values` with the unique solution. Otherwise returns
## _LINEAR_INCONSISTENT (no solution), _LINEAR_SINGULAR (consistent, more than
## one solution) or _LINEAR_OVERFLOW. Pivots are the first non-zero entry in
## row order, so the result is deterministic. `rows` is consumed.
static func _eliminate(rows: Array[Array], size: int, values: Array[Rational]) -> int:
	var pivot_row: int = 0
	var pivot_columns: Array[int] = []
	for col: int in size:
		var found: int = -1
		for r: int in range(pivot_row, size):
			if rows[r][col] != null:
				found = r
				break
		if found < 0:
			continue
		if found != pivot_row:
			var swap: Array = rows[found]
			rows[found] = rows[pivot_row]
			rows[pivot_row] = swap
		var prow: Array = rows[pivot_row]
		var pivot: Rational = prow[col]
		if not (pivot.numerator == 1 and pivot.denominator == 1):
			var inverse: Rational = pivot.reciprocal()
			for j: int in range(col, size + 1):
				if prow[j] != null:
					var scaled: Rational = (prow[j] as Rational).mul(inverse)
					if scaled == null:
						return _LINEAR_OVERFLOW
					prow[j] = scaled
		for r: int in size:
			if r == pivot_row:
				continue
			var row: Array = rows[r]
			if row[col] == null:
				continue
			var factor: Rational = row[col]
			for j: int in range(col + 1, size + 1):
				if prow[j] == null:
					continue
				var product: Rational = factor.mul(prow[j])
				if product == null:
					return _LINEAR_OVERFLOW
				var updated: Rational = null
				if row[j] == null:
					updated = product.negate()
				else:
					updated = (row[j] as Rational).sub(product)
				if updated == null:
					return _LINEAR_OVERFLOW
				row[j] = null if updated.is_zero() else updated
			row[col] = null
		pivot_columns.append(col)
		pivot_row += 1
	for r: int in range(pivot_row, size):
		if rows[r][size] != null:
			return _LINEAR_INCONSISTENT
	if pivot_row < size:
		return _LINEAR_SINGULAR
	values.clear()
	values.resize(size)
	var zero: Rational = Rational.new(0)
	for r: int in size:
		var rhs: Variant = rows[r][size]
		values[pivot_columns[r]] = rhs if rhs != null else zero
	return _LINEAR_OK


# --- union-find on indices ---------------------------------------------------------

static func _identity(n: int) -> Array[int]:
	var parent: Array[int] = []
	parent.resize(n)
	for i: int in n:
		parent[i] = i
	return parent


static func _root(parent: Array[int], x: int) -> int:
	while parent[x] != x:
		x = parent[x]
	return x


## Joins two groups. The smaller index (alphabetically smaller name) becomes
## the root.
static func _union(parent: Array[int], a: int, b: int) -> void:
	var root_a: int = _root(parent, a)
	var root_b: int = _root(parent, b)
	if root_a == root_b:
		return
	if root_a < root_b:
		parent[root_b] = root_a
	else:
		parent[root_a] = root_b


static func _reachable(adjacency: Array, start: int) -> Dictionary:
	var seen: Dictionary = {start: true}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var node: int = queue.pop_back()
		if adjacency[node] == null:
			continue
		for neighbour: int in adjacency[node]:
			if not seen.has(neighbour):
				seen[neighbour] = true
				queue.append(neighbour)
	return seen
