class_name PuzzleSolver
extends RefCounted
## Finds every way of filling a level's sockets that hits the target.
##
## Each resistor (by index) is used at most once and any socket may stay empty.
## Two assignments that differ only in which of several equal-valued resistors
## went into a socket count as one solution: resistors are told apart by value,
## not by index. Placing the same values in different sockets is a different
## solution.
##
## Search cost grows quickly (roughly (resistors + 1) ^ sockets assignments are
## tried), which is fine for hand-made levels with a handful of sockets.


## base: wires, fixed resistors and terminals (not modified).
## sockets: each { "id": String, "from": String, "to": String }.
## resistors: the values available to place, each > 0.
## target: the resistance that solves the level.
## Returns each solution as { socket id: resistor value text }; empty sockets
## are omitted. Solutions come in a fixed order (sockets in the given order,
## "empty" first, then resistor values in order of first appearance).
## Invalid input calls push_error and returns an empty array.
static func find_solutions(base: CircuitGraph, sockets: Array[Dictionary],
		resistors: Array[Rational], target: Rational) -> Array[Dictionary]:
	var solutions: Array[Dictionary] = []
	if not _validate(base, sockets, resistors, target):
		return solutions
	var texts: Array[String] = []
	for value: Rational in resistors:
		texts.append(value.to_text())
	var used: Array[bool] = []
	used.resize(resistors.size())
	used.fill(false)
	var assignment: Array[int] = []
	assignment.resize(sockets.size())
	assignment.fill(-1)
	_search(0, base, sockets, resistors, texts, target, used, assignment, solutions)
	return solutions


static func _search(socket_index: int, base: CircuitGraph, sockets: Array[Dictionary],
		resistors: Array[Rational], texts: Array[String], target: Rational,
		used: Array[bool], assignment: Array[int], solutions: Array[Dictionary]) -> void:
	if socket_index == sockets.size():
		_evaluate(base, sockets, resistors, texts, target, assignment, solutions)
		return
	# Option 1: leave this socket empty.
	assignment[socket_index] = -1
	_search(socket_index + 1, base, sockets, resistors, texts, target, used, assignment, solutions)
	# Option 2: one resistor of each distinct still-available value.
	var tried: Dictionary = {}
	for i: int in resistors.size():
		if used[i] or tried.has(texts[i]):
			continue
		tried[texts[i]] = true
		used[i] = true
		assignment[socket_index] = i
		_search(socket_index + 1, base, sockets, resistors, texts, target, used, assignment, solutions)
		used[i] = false
	assignment[socket_index] = -1


static func _evaluate(base: CircuitGraph, sockets: Array[Dictionary],
		resistors: Array[Rational], texts: Array[String], target: Rational,
		assignment: Array[int], solutions: Array[Dictionary]) -> void:
	var graph: CircuitGraph = base.duplicate_graph()
	var solution: Dictionary = {}
	for s: int in sockets.size():
		var index: int = assignment[s]
		if index < 0:
			continue
		var socket: Dictionary = sockets[s]
		graph.add_resistor(socket["id"], socket["from"], socket["to"], resistors[index])
		solution[socket["id"]] = texts[index]
	var result: CircuitResult = CircuitSolver.solve(graph)
	if result.matches(target):
		solutions.append(solution)


static func _validate(base: CircuitGraph, sockets: Array[Dictionary],
		resistors: Array[Rational], target: Rational) -> bool:
	if base == null:
		push_error("PuzzleSolver.find_solutions: base graph is null.")
		return false
	if target == null or not target.is_valid():
		push_error("PuzzleSolver.find_solutions: target is null or invalid.")
		return false
	var socket_ids: Dictionary = {}
	for socket: Dictionary in sockets:
		for key: String in ["id", "from", "to"]:
			if not socket.has(key) or typeof(socket[key]) != TYPE_STRING or String(socket[key]).is_empty():
				push_error("PuzzleSolver.find_solutions: socket %s needs a non-empty String '%s'." % [
						str(socket), key])
				return false
		var id: String = socket["id"]
		if socket_ids.has(id) or base.has_edge(id):
			push_error("PuzzleSolver.find_solutions: socket id '%s' is not unique." % id)
			return false
		socket_ids[id] = true
	for i: int in resistors.size():
		var value: Rational = resistors[i]
		if value == null or not value.is_valid() or value.sign() <= 0:
			push_error("PuzzleSolver.find_solutions: resistor %d must be a valid value > 0." % i)
			return false
	return true
