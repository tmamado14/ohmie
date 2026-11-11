class_name CircuitGraph
extends RefCounted
## A plain description of a resistor network: named nodes joined by edges.
##
## An edge is either a wire (zero resistance) or a resistor (a fixed resistor
## or a filled socket). Empty sockets are simply not added. Two nodes are the
## terminals; the solver reports the equivalent resistance between them.
##
## Invalid input (empty names, duplicate edge ids, a missing or non-positive
## resistance) calls push_error, leaves the graph unchanged and returns false.


class _Edge:
	extends RefCounted
	var id: String
	var node_a: String
	var node_b: String
	var is_wire: bool
	var ohms: Rational  # null for wires

	func _init(edge_id: String, a: String, b: String, wire: bool, value: Rational) -> void:
		id = edge_id
		node_a = a
		node_b = b
		is_wire = wire
		ohms = value


var _edges: Dictionary = {}  # String id -> _Edge
var _terminal_a: String = ""
var _terminal_b: String = ""


## Adds a zero-resistance wire. Returns false (with push_error) on bad input.
func add_wire(id: String, node_a: String, node_b: String) -> bool:
	if not _check_new_edge(id, node_a, node_b, "add_wire"):
		return false
	_edges[id] = _Edge.new(id, node_a, node_b, true, null)
	return true


## Adds a resistor of `ohms` > 0. Returns false (with push_error) on bad input.
func add_resistor(id: String, node_a: String, node_b: String, ohms: Rational) -> bool:
	if not _check_new_edge(id, node_a, node_b, "add_resistor"):
		return false
	if ohms == null or not ohms.is_valid():
		push_error("CircuitGraph.add_resistor: resistor '%s' has no valid value." % id)
		return false
	if ohms.sign() <= 0:
		push_error("CircuitGraph.add_resistor: resistor '%s' must be > 0, got %s." % [
				id, ohms.to_text()])
		return false
	_edges[id] = _Edge.new(id, node_a, node_b, false, ohms)
	return true


## Sets the two terminal node names. Returns false (with push_error) if either is empty.
func set_terminals(a: String, b: String) -> bool:
	if a.is_empty() or b.is_empty():
		push_error("CircuitGraph.set_terminals: terminal names must not be empty.")
		return false
	_terminal_a = a
	_terminal_b = b
	return true


func has_terminals() -> bool:
	return not _terminal_a.is_empty() and not _terminal_b.is_empty()


## Empty string if unset.
func get_terminal_a() -> String:
	return _terminal_a


## Empty string if unset.
func get_terminal_b() -> String:
	return _terminal_b


func edge_count() -> int:
	return _edges.size()


func has_edge(id: String) -> bool:
	return _edges.has(id)


## All edge ids in sorted order.
func get_edge_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: String in _edges.keys():
		ids.append(key)
	ids.sort()
	return ids


## All node names that appear on any edge, in sorted order.
func get_nodes() -> Array[String]:
	var seen: Dictionary = {}
	for edge: _Edge in _edges.values():
		seen[edge.node_a] = true
		seen[edge.node_b] = true
	var nodes: Array[String] = []
	for key: String in seen.keys():
		nodes.append(key)
	nodes.sort()
	return nodes


## True if the edge is a wire. push_error and false for an unknown id.
func is_wire(id: String) -> bool:
	var edge: _Edge = _get_edge(id, "is_wire")
	return edge != null and edge.is_wire


## push_error and "" for an unknown id.
func get_edge_node_a(id: String) -> String:
	var edge: _Edge = _get_edge(id, "get_edge_node_a")
	return edge.node_a if edge != null else ""


## push_error and "" for an unknown id.
func get_edge_node_b(id: String) -> String:
	var edge: _Edge = _get_edge(id, "get_edge_node_b")
	return edge.node_b if edge != null else ""


## The resistance of a resistor edge; null for a wire. push_error and null for
## an unknown id.
func get_edge_ohms(id: String) -> Rational:
	var edge: _Edge = _get_edge(id, "get_edge_ohms")
	return edge.ohms if edge != null else null


## An independent copy. Rational values are immutable, so they are shared.
func duplicate_graph() -> CircuitGraph:
	var copy: CircuitGraph = CircuitGraph.new()
	for edge: _Edge in _edges.values():
		copy._edges[edge.id] = _Edge.new(edge.id, edge.node_a, edge.node_b, edge.is_wire, edge.ohms)
	copy._terminal_a = _terminal_a
	copy._terminal_b = _terminal_b
	return copy


## A deterministic multi-line description, for debugging and tests.
func to_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("terminals %s %s" % [_terminal_a, _terminal_b])
	for id: String in get_edge_ids():
		var edge: _Edge = _edges[id]
		if edge.is_wire:
			lines.append("wire %s %s %s" % [id, edge.node_a, edge.node_b])
		else:
			lines.append("resistor %s %s %s %s" % [id, edge.node_a, edge.node_b, edge.ohms.to_text()])
	return "\n".join(lines)


func _check_new_edge(id: String, node_a: String, node_b: String, op: String) -> bool:
	if id.is_empty():
		push_error("CircuitGraph.%s: edge id must not be empty." % op)
		return false
	if node_a.is_empty() or node_b.is_empty():
		push_error("CircuitGraph.%s: edge '%s' has an empty node name." % [op, id])
		return false
	if _edges.has(id):
		push_error("CircuitGraph.%s: duplicate edge id '%s'." % [op, id])
		return false
	return true


func _get_edge(id: String, op: String) -> _Edge:
	if not _edges.has(id):
		push_error("CircuitGraph.%s: unknown edge id '%s'." % [op, id])
		return null
	return _edges[id]
