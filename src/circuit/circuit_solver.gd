## Kept for the planned collapse replay; not used by gameplay yet.
class_name CircuitSolver
extends RefCounted
## Equivalent resistance between the terminals by series-parallel reduction
## (GDD section 3, "Solving").
##
## 1. If the terminals are unset, or a terminal touches no edge: OPEN.
## 2. Merge wire-joined nodes. Each group is named by its alphabetically
##    smallest node. If the terminals are now the same node: OK, 0.
## 3. If no path of resistors joins the terminals: OPEN. Otherwise every edge
##    outside the terminals' connected part is removed with a PRUNE step
##    (sorted by id). This keeps unconnected clutter, even clutter that is not
##    series-parallel, from affecting the answer.
## 4. Repeat, restarting after every change, until nothing applies:
##    prune (a self-loop, or an edge touching a non-terminal node of degree 1),
##    else parallel merge (two edges joining the same pair of nodes),
##    else series merge (a non-terminal node with exactly two edges).
##    Each rule acts on the edge with the smallest id (plain string order)
##    that it applies to, so the step list is deterministic.
## 5. One edge left: OK with its value. None: OPEN. Otherwise: UNSUPPORTED.
##
## Merged edges get ids "m1", "m2", ... skipping any id already in the graph.
## The input graph is never modified.


class _WorkEdge:
	extends RefCounted
	var id: String
	var node_a: String
	var node_b: String
	var value: Rational

	func _init(edge_id: String, a: String, b: String, ohms: Rational) -> void:
		id = edge_id
		node_a = a
		node_b = b
		value = ohms

	func joins(a: String, b: String) -> bool:
		return (node_a == a and node_b == b) or (node_a == b and node_b == a)

	func other_end(node: String) -> String:
		return node_b if node_a == node else node_a


## Solves `graph` without modifying it.
static func solve(graph: CircuitGraph) -> CircuitResult:
	var result: CircuitResult = CircuitResult.new()
	if graph == null:
		return _fail(result, "CircuitSolver.solve: graph is null.")
	if not graph.has_terminals():
		result.status = CircuitResult.Status.OPEN
		return result

	var raw_a: String = graph.get_terminal_a()
	var raw_b: String = graph.get_terminal_b()
	var edge_ids: Array[String] = graph.get_edge_ids()
	var touched: Dictionary = {}
	for id: String in edge_ids:
		touched[graph.get_edge_node_a(id)] = true
		touched[graph.get_edge_node_b(id)] = true
	if not touched.has(raw_a) or not touched.has(raw_b):
		result.status = CircuitResult.Status.OPEN
		return result

	# Merge wire-joined nodes.
	var parent: Dictionary = {}  # node -> parent node
	for id: String in edge_ids:
		if graph.is_wire(id):
			_union(parent, graph.get_edge_node_a(id), graph.get_edge_node_b(id))
	var term_a: String = _find(parent, raw_a)
	var term_b: String = _find(parent, raw_b)
	if term_a == term_b:
		result.status = CircuitResult.Status.OK
		result.value = Rational.from_int(0)
		return result

	var work: Dictionary = {}  # id -> _WorkEdge
	for id: String in edge_ids:
		if not graph.is_wire(id):
			work[id] = _WorkEdge.new(id,
					_find(parent, graph.get_edge_node_a(id)),
					_find(parent, graph.get_edge_node_b(id)),
					graph.get_edge_ohms(id))

	# Keep only the part connected to the terminals.
	var reachable: Dictionary = _reachable_nodes(work, term_a)
	if not reachable.has(term_b):
		result.status = CircuitResult.Status.OPEN
		return result
	for id: String in _sorted_ids(work):
		var edge: _WorkEdge = work[id]
		if not reachable.has(edge.node_a):
			result.steps.append(_prune_step(edge))
			work.erase(id)

	var used_ids: Dictionary = {}
	for id: String in edge_ids:
		used_ids[id] = true
	var next_number: Array[int] = [1]

	# Every prune or merge removes exactly one edge, so the loop can change the
	# graph at most once per edge. Going past that means something is broken;
	# report it instead of looping forever.
	var changes_left: int = work.size()
	while true:
		if changes_left < 0:
			return _fail(result, "CircuitSolver.solve: reduction did not finish (internal error).")
		changes_left -= 1
		var ids: Array[String] = _sorted_ids(work)
		var degree: Dictionary = _degrees(work)
		var changed: bool = false

		# Prune.
		for id: String in ids:
			var edge: _WorkEdge = work[id]
			if (edge.node_a == edge.node_b
					or _is_dead_end(edge.node_a, degree, term_a, term_b)
					or _is_dead_end(edge.node_b, degree, term_a, term_b)):
				result.steps.append(_prune_step(edge))
				work.erase(id)
				changed = true
				break
		if changed:
			continue

		# Parallel merge.
		for i: int in ids.size():
			var first: _WorkEdge = work[ids[i]]
			for j: int in range(i + 1, ids.size()):
				var second: _WorkEdge = work[ids[j]]
				if second.joins(first.node_a, first.node_b):
					var combined: Rational = _parallel_value(first.value, second.value)
					if combined == null:
						return _fail(result, "CircuitSolver.solve: parallel merge of '%s' and '%s' overflowed 64 bits." % [first.id, second.id])
					_merge(work, result, ReductionStep.Kind.PARALLEL, first, second,
							first.node_a, first.node_b, combined, used_ids, next_number)
					changed = true
					break
			if changed:
				break
		if changed:
			continue

		# Series merge.
		for id: String in ids:
			var first: _WorkEdge = work[id]
			for node: String in [first.node_a, first.node_b]:
				if node == term_a or node == term_b or int(degree.get(node, 0)) != 2:
					continue
				var second: _WorkEdge = null
				for other_id: String in ids:
					var candidate: _WorkEdge = work[other_id]
					if other_id != id and (candidate.node_a == node or candidate.node_b == node):
						second = candidate
						break
				var combined: Rational = first.value.add(second.value)
				if combined == null:
					return _fail(result, "CircuitSolver.solve: series merge of '%s' and '%s' overflowed 64 bits." % [first.id, second.id])
				_merge(work, result, ReductionStep.Kind.SERIES, first, second,
						first.other_end(node), second.other_end(node), combined, used_ids, next_number)
				changed = true
				break
			if changed:
				break
		if not changed:
			break

	if work.is_empty():
		result.status = CircuitResult.Status.OPEN
	elif work.size() == 1:
		var last: _WorkEdge = work.values()[0]
		if last.joins(term_a, term_b):
			result.status = CircuitResult.Status.OK
			result.value = last.value
		else:
			result.status = CircuitResult.Status.UNSUPPORTED
	else:
		result.status = CircuitResult.Status.UNSUPPORTED
	return result


## (r1 * r2) / (r1 + r2), or null if any step overflows (each Rational
## operation pushes its own error; this stops at the first failure).
static func _parallel_value(r1: Rational, r2: Rational) -> Rational:
	var product: Rational = r1.mul(r2)
	if product == null:
		return null
	var total: Rational = r1.add(r2)
	if total == null:
		return null
	return product.div(total)


static func _fail(result: CircuitResult, message: String) -> CircuitResult:
	push_error(message)
	result.status = CircuitResult.Status.ERROR
	result.value = null
	result.error_message = message
	return result


static func _find(parent: Dictionary, node: String) -> String:
	var root: String = node
	while parent.has(root) and String(parent[root]) != root:
		root = parent[root]
	# Path compression.
	var current: String = node
	while parent.has(current) and String(parent[current]) != root:
		var next: String = parent[current]
		parent[current] = root
		current = next
	return root


## Joins two groups. The alphabetically smaller root becomes the group's name.
static func _union(parent: Dictionary, a: String, b: String) -> void:
	var root_a: String = _find(parent, a)
	var root_b: String = _find(parent, b)
	if root_a == root_b:
		return
	if root_a < root_b:
		parent[root_b] = root_a
		parent[root_a] = root_a
	else:
		parent[root_a] = root_b
		parent[root_b] = root_b


static func _sorted_ids(work: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for key: String in work.keys():
		ids.append(key)
	ids.sort()
	return ids


static func _degrees(work: Dictionary) -> Dictionary:
	var degree: Dictionary = {}
	for edge: _WorkEdge in work.values():
		degree[edge.node_a] = int(degree.get(edge.node_a, 0)) + 1
		degree[edge.node_b] = int(degree.get(edge.node_b, 0)) + 1
	return degree


static func _is_dead_end(node: String, degree: Dictionary, term_a: String, term_b: String) -> bool:
	return node != term_a and node != term_b and int(degree.get(node, 0)) == 1


static func _reachable_nodes(work: Dictionary, start: String) -> Dictionary:
	var adjacency: Dictionary = {}  # node -> Array of neighbour nodes
	for edge: _WorkEdge in work.values():
		if not adjacency.has(edge.node_a):
			adjacency[edge.node_a] = []
		if not adjacency.has(edge.node_b):
			adjacency[edge.node_b] = []
		(adjacency[edge.node_a] as Array).append(edge.node_b)
		(adjacency[edge.node_b] as Array).append(edge.node_a)
	var seen: Dictionary = {start: true}
	var queue: Array[String] = [start]
	while not queue.is_empty():
		var node: String = queue.pop_back()
		for neighbour: String in adjacency.get(node, []):
			if not seen.has(neighbour):
				seen[neighbour] = true
				queue.append(neighbour)
	return seen


static func _prune_step(edge: _WorkEdge) -> ReductionStep:
	var step: ReductionStep = ReductionStep.new()
	step.kind = ReductionStep.Kind.PRUNE
	step.input_ids = [edge.id]
	step.input_values = [edge.value]
	step.node_a = edge.node_a
	step.node_b = edge.node_b
	return step


static func _merge(work: Dictionary, result: CircuitResult, kind: ReductionStep.Kind,
		first: _WorkEdge, second: _WorkEdge, node_a: String, node_b: String,
		value: Rational, used_ids: Dictionary, next_number: Array[int]) -> void:
	var new_id: String = "m%d" % next_number[0]
	while used_ids.has(new_id):
		next_number[0] += 1
		new_id = "m%d" % next_number[0]
	next_number[0] += 1
	used_ids[new_id] = true

	var step: ReductionStep = ReductionStep.new()
	step.kind = kind
	step.input_ids = [first.id, second.id]
	step.input_values = [first.value, second.value]
	step.output_id = new_id
	step.output_value = value
	step.node_a = node_a
	step.node_b = node_b
	result.steps.append(step)

	work.erase(first.id)
	work.erase(second.id)
	work[new_id] = _WorkEdge.new(new_id, node_a, node_b, value)
