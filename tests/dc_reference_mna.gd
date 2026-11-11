extends RefCounted
## Test-only reference solver: textbook modified nodal analysis of a DcNetwork,
## written as plainly as possible (every voltage source and ammeter current is
## an unknown, one big Gauss-Jordan elimination). DcSolver uses a faster,
## equivalent formulation; tests compare the two on many networks.
##
## solve() returns:
##   {"status": "OK" | "SHORT" | "INDETERMINATE" | "OVERFLOW",
##    "voltages": {node: Rational},   # only when OK; ground per component =
##                                    # alphabetically smallest node
##    "currents": {id: Rational}}     # only when OK; same sign conventions as
##                                    # DcSolution.current_through


static func solve(network: DcNetwork) -> Dictionary:
	var ids: Array[String] = network.get_element_ids()
	var parent: Dictionary = {}
	for id: String in ids:
		if network.get_kind(id) == DcNetwork.Kind.WIRE:
			_union(parent, network.get_node_a(id), network.get_node_b(id))
	var nodes: Array[String] = network.get_nodes()
	var merged: Dictionary = {}
	for node: String in nodes:
		merged[node] = _find(parent, node)
	var component_parent: Dictionary = {}
	for id: String in ids:
		if _conducts(network.get_kind(id)):
			_union(component_parent, merged[network.get_node_a(id)], merged[network.get_node_b(id)])
	var ground_of: Dictionary = {}
	for node: String in nodes:
		ground_of[node] = _find(component_parent, merged[node])

	var unknown_nodes: Array[String] = []
	for node: String in nodes:
		var m: String = merged[node]
		if m != ground_of[node] and not unknown_nodes.has(m):
			unknown_nodes.append(m)
	unknown_nodes.sort()
	var index: Dictionary = {}
	for i: int in unknown_nodes.size():
		index[unknown_nodes[i]] = i
	var size: int = unknown_nodes.size()
	var branch: Dictionary = {}
	for id: String in ids:
		var kind: int = network.get_kind(id)
		if kind == DcNetwork.Kind.VOLTAGE_SOURCE or kind == DcNetwork.Kind.AMMETER:
			branch[id] = size
			size += 1

	var matrix: Array[Array] = []
	for r: int in size:
		var row: Array[Rational] = []
		for c: int in size + 1:
			row.append(Rational.new(0))
		matrix.append(row)
	for id: String in ids:
		var kind: int = network.get_kind(id)
		var ia: int = int(index.get(merged[network.get_node_a(id)], -1))
		var ib: int = int(index.get(merged[network.get_node_b(id)], -1))
		if kind == DcNetwork.Kind.RESISTOR:
			var g: Rational = network.get_value(id).reciprocal()
			if not (_add(matrix, ia, ia, g) and _add(matrix, ib, ib, g)
					and _add(matrix, ia, ib, g.negate()) and _add(matrix, ib, ia, g.negate())):
				return {"status": "OVERFLOW"}
		elif kind == DcNetwork.Kind.VOLTAGE_SOURCE or kind == DcNetwork.Kind.AMMETER:
			var k: int = branch[id]
			_add(matrix, ia, k, Rational.new(1))
			_add(matrix, ib, k, Rational.new(-1))
			_add(matrix, k, ia, Rational.new(1))
			_add(matrix, k, ib, Rational.new(-1))
			if kind == DcNetwork.Kind.VOLTAGE_SOURCE:
				_add(matrix, k, size, network.get_value(id))

	# Plain Gauss-Jordan.
	var pivot_row: int = 0
	for col: int in size:
		var found: int = -1
		for r: int in range(pivot_row, size):
			if not (matrix[r][col] as Rational).is_zero():
				found = r
				break
		if found < 0:
			continue
		var swap: Array = matrix[found]
		matrix[found] = matrix[pivot_row]
		matrix[pivot_row] = swap
		var inverse: Rational = (matrix[pivot_row][col] as Rational).reciprocal()
		for j: int in size + 1:
			var scaled: Rational = (matrix[pivot_row][j] as Rational).mul(inverse)
			if scaled == null:
				return {"status": "OVERFLOW"}
			matrix[pivot_row][j] = scaled
		for r: int in size:
			if r == pivot_row:
				continue
			var factor: Rational = matrix[r][col]
			if factor.is_zero():
				continue
			for j: int in size + 1:
				var product: Rational = factor.mul(matrix[pivot_row][j])
				if product == null:
					return {"status": "OVERFLOW"}
				var updated: Rational = (matrix[r][j] as Rational).sub(product)
				if updated == null:
					return {"status": "OVERFLOW"}
				matrix[r][j] = updated
		pivot_row += 1
	for r: int in range(pivot_row, size):
		if not (matrix[r][size] as Rational).is_zero():
			return {"status": "SHORT"}
	if pivot_row < size:
		return {"status": "INDETERMINATE"}

	var voltages: Dictionary = {}
	for node: String in nodes:
		var i: int = int(index.get(merged[node], -1))
		voltages[node] = matrix[i][size] if i >= 0 else Rational.new(0)
	var currents: Dictionary = {}
	for id: String in ids:
		var kind: int = network.get_kind(id)
		if kind == DcNetwork.Kind.RESISTOR:
			var v: Rational = (voltages[network.get_node_a(id)] as Rational).sub(voltages[network.get_node_b(id)])
			currents[id] = v.div(network.get_value(id))
		elif kind == DcNetwork.Kind.VOLTAGE_SOURCE:
			currents[id] = (matrix[branch[id]][size] as Rational).negate()
		elif kind == DcNetwork.Kind.AMMETER:
			currents[id] = matrix[branch[id]][size]
	return {"status": "OK", "voltages": voltages, "currents": currents}


static func _conducts(kind: int) -> bool:
	return (kind == DcNetwork.Kind.RESISTOR or kind == DcNetwork.Kind.VOLTAGE_SOURCE
			or kind == DcNetwork.Kind.AMMETER)


static func _add(matrix: Array[Array], r: int, c: int, value: Rational) -> bool:
	if r < 0 or c < 0:
		return true
	var total: Rational = (matrix[r][c] as Rational).add(value)
	if total == null:
		return false
	matrix[r][c] = total
	return true


static func _find(parent: Dictionary, node: String) -> String:
	var root: String = node
	while parent.has(root) and String(parent[root]) != root:
		root = parent[root]
	return root


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
