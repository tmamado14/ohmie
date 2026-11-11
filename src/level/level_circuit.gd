class_name LevelCircuit
extends RefCounted
## The circuit section of a level file (GDD section 6), validated, plus the
## only conversion from level data to a CircuitGraph.
##
## Pure data: no nodes, no drawing. Positions are kept for whoever draws the
## board. Resistances are Rationals parsed once here.

const TYPE_WIRE: String = "wire"
const TYPE_SOCKET: String = "socket"
const TYPE_FIXED: String = "fixed"
const EDGE_TYPES: PackedStringArray = [TYPE_WIRE, TYPE_SOCKET, TYPE_FIXED]


## One edge of the board as written in the level file.
class Edge:
	extends RefCounted
	var id: String
	## One of TYPE_WIRE, TYPE_SOCKET, TYPE_FIXED.
	var type: String
	var from_node: String
	var to_node: String
	## Set only for TYPE_FIXED.
	var ohms: Rational

	func _init(edge_id: String, edge_type: String, a: String, b: String, value: Rational) -> void:
		id = edge_id
		type = edge_type
		from_node = a
		to_node = b
		ohms = value


## Terminal node names (A first, B second).
var terminal_a: String = ""
var terminal_b: String = ""

var _positions: Dictionary = {}  # String node name -> Vector2 centre in pixels
var _node_names: Array[String] = []  # in file order
var _edges: Array[Edge] = []  # in file order


## Validates and parses a level's "circuit" object. Returns null and pushes an
## error naming the problem if anything is wrong. `source` names the origin.
static func from_dictionary(data: Variant, source: String = "circuit") -> LevelCircuit:
	if not data is Dictionary:
		push_error("LevelCircuit: %s: 'circuit' must be an object" % source)
		return null
	var dict: Dictionary = data
	for field: String in ["nodes", "terminals", "edges"]:
		if not dict.has(field):
			push_error("LevelCircuit: %s: circuit is missing '%s'" % [source, field])
			return null
	var circuit: LevelCircuit = LevelCircuit.new()
	if not circuit._parse_nodes(dict["nodes"], source):
		return null
	if not circuit._parse_terminals(dict["terminals"], source):
		return null
	if not circuit._parse_edges(dict["edges"], source):
		return null
	return circuit


## Node names in file order.
func get_node_names() -> Array[String]:
	return _node_names.duplicate()


func has_node_named(node_name: String) -> bool:
	return _positions.has(node_name)


## Centre of a node in pixels.
func get_node_position(node_name: String) -> Vector2:
	return _positions.get(node_name, Vector2.ZERO)


## Every edge in file order.
func get_edges() -> Array[Edge]:
	return _edges.duplicate()


## Number of edges (of any type) that touch `node_name`.
func get_node_degree(node_name: String) -> int:
	var degree: int = 0
	for edge: Edge in _edges:
		if edge.from_node == node_name:
			degree += 1
		if edge.to_node == node_name:
			degree += 1
	return degree


func is_terminal(node_name: String) -> bool:
	return node_name == terminal_a or node_name == terminal_b


## Sockets as PuzzleSolver expects them: each { "id", "from", "to" }, in file order.
func get_socket_descriptors() -> Array[Dictionary]:
	var sockets: Array[Dictionary] = []
	for edge: Edge in _edges:
		if edge.type == TYPE_SOCKET:
			sockets.append({"id": edge.id, "from": edge.from_node, "to": edge.to_node})
	return sockets


## Wires, fixed resistors and terminals. Every socket is left out (empty).
func build_base_graph() -> CircuitGraph:
	return build_graph({})


## The base graph plus a resistor for every socket listed in `filled`
## (socket id -> Rational). Sockets not in `filled` are empty and left out.
## Unknown socket ids or bad values push an error and are skipped.
func build_graph(filled: Dictionary) -> CircuitGraph:
	var graph: CircuitGraph = CircuitGraph.new()
	graph.set_terminals(terminal_a, terminal_b)
	var socket_ids: Dictionary = {}
	for edge: Edge in _edges:
		match edge.type:
			TYPE_WIRE:
				graph.add_wire(edge.id, edge.from_node, edge.to_node)
			TYPE_FIXED:
				graph.add_resistor(edge.id, edge.from_node, edge.to_node, edge.ohms)
			TYPE_SOCKET:
				socket_ids[edge.id] = true
				if filled.has(edge.id):
					var value: Variant = filled[edge.id]
					if not value is Rational:
						push_error("LevelCircuit.build_graph: value for socket '%s' is not a Rational" % edge.id)
						continue
					graph.add_resistor(edge.id, edge.from_node, edge.to_node, value as Rational)
	for key: Variant in filled.keys():
		if not socket_ids.has(key):
			push_error("LevelCircuit.build_graph: '%s' is not a socket of this circuit" % str(key))
	return graph


func _parse_nodes(value: Variant, source: String) -> bool:
	if not value is Dictionary:
		push_error("LevelCircuit: %s: 'nodes' must be an object of name: [x, y]" % source)
		return false
	var nodes: Dictionary = value
	if nodes.is_empty():
		push_error("LevelCircuit: %s: 'nodes' is empty" % source)
		return false
	for key: Variant in nodes.keys():
		var node_name: String = str(key)
		if node_name.is_empty():
			push_error("LevelCircuit: %s: a node has an empty name" % source)
			return false
		var point: Variant = nodes[key]
		if not point is Array or (point as Array).size() != 2 \
				or not _is_number((point as Array)[0]) or not _is_number((point as Array)[1]):
			push_error("LevelCircuit: %s: node '%s' must be two numbers [x, y]" % [source, node_name])
			return false
		var pair: Array = point
		_positions[node_name] = Vector2(float(pair[0]), float(pair[1]))
		_node_names.append(node_name)
	return true


func _parse_terminals(value: Variant, source: String) -> bool:
	if not value is Array or (value as Array).size() != 2:
		push_error("LevelCircuit: %s: 'terminals' must be an array of two node names" % source)
		return false
	var pair: Array = value
	if not pair[0] is String or not pair[1] is String:
		push_error("LevelCircuit: %s: 'terminals' must be two node names" % source)
		return false
	var a: String = pair[0]
	var b: String = pair[1]
	if a == b:
		push_error("LevelCircuit: %s: the two terminals must be different nodes (both are '%s')" % [source, a])
		return false
	for node_name: String in [a, b]:
		if not _positions.has(node_name):
			push_error("LevelCircuit: %s: terminal '%s' is not a node" % [source, node_name])
			return false
	terminal_a = a
	terminal_b = b
	return true


func _parse_edges(value: Variant, source: String) -> bool:
	if not value is Array:
		push_error("LevelCircuit: %s: 'edges' must be an array" % source)
		return false
	var raw_edges: Array = value
	var seen: Dictionary = {}
	for i: int in raw_edges.size():
		if not raw_edges[i] is Dictionary:
			push_error("LevelCircuit: %s: edges[%d] must be an object" % [source, i])
			return false
		var edge: Edge = _parse_edge(raw_edges[i], i, source)
		if edge == null:
			return false
		if seen.has(edge.id):
			push_error("LevelCircuit: %s: edge id '%s' is used more than once" % [source, edge.id])
			return false
		seen[edge.id] = true
		_edges.append(edge)
	return true


func _parse_edge(raw: Dictionary, index: int, source: String) -> Edge:
	for field: String in ["id", "type", "from", "to"]:
		if not raw.has(field) or not raw[field] is String or String(raw[field]).is_empty():
			push_error("LevelCircuit: %s: edges[%d] needs a non-empty string '%s'" % [source, index, field])
			return null
	var id: String = raw["id"]
	var type: String = raw["type"]
	var from_node: String = raw["from"]
	var to_node: String = raw["to"]
	if not EDGE_TYPES.has(type):
		push_error("LevelCircuit: %s: edge '%s' has unknown type '%s' (expected wire, socket or fixed)" % [source, id, type])
		return null
	for node_name: String in [from_node, to_node]:
		if not _positions.has(node_name):
			push_error("LevelCircuit: %s: edge '%s' refers to unknown node '%s'" % [source, id, node_name])
			return null
	if from_node == to_node:
		push_error("LevelCircuit: %s: edge '%s' starts and ends at the same node '%s'" % [source, id, from_node])
		return null
	var ohms: Rational = null
	if type == TYPE_FIXED:
		if not raw.has("ohms") or not raw["ohms"] is String:
			push_error("LevelCircuit: %s: fixed edge '%s' needs 'ohms' as a string" % [source, id])
			return null
		ohms = Rational.parse(raw["ohms"])
		if ohms == null or not ohms.is_valid():
			push_error("LevelCircuit: %s: fixed edge '%s' has an invalid 'ohms' value '%s'" % [source, id, raw["ohms"]])
			return null
		if ohms.sign() <= 0:
			push_error("LevelCircuit: %s: fixed edge '%s' must have 'ohms' > 0, got '%s'" % [source, id, raw["ohms"]])
			return null
	return Edge.new(id, type, from_node, to_node, ohms)


static func _is_number(value: Variant) -> bool:
	return value is float or value is int
