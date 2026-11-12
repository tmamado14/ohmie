class_name LevelCircuit
extends RefCounted
## The "circuit" object of a level file (GDD 12.2, 12.4), validated, plus the
## only conversion from level data to a DcNetwork.
##
## Pure data: no nodes, no drawing, no solving. Positions are kept for whoever
## draws the board. Values are Rationals parsed once here.
##
##   {"nodes": {"n1": [x, y], ...},
##    "edges": [{"id", "type", "from", "to", ...}, ...]}
##
## Edge types and their extra fields:
##   wire                       zero resistance
##   slot                       holds one carried Part; empty is open
##   resistor  value            fixed resistor, ohms
##   battery   value            fixed battery, volts, plus at `from`
##   lamp      value, rated_min, rated_max
##                              a resistor of `value` ohms, lit while its
##                              current is within rated_min..rated_max amps
##   ammeter, voltmeter, ohmmeter   ideal meters (see DcNetwork)
## Every value is a string such as "3/2" and must be > 0.
## Any edge may carry an optional "label" (a short non-empty string such as
## "top"); the readout plaque shows it after the quantity symbol ("I top").

const TYPE_WIRE: String = "wire"
const TYPE_SLOT: String = "slot"
const TYPE_RESISTOR: String = "resistor"
const TYPE_BATTERY: String = "battery"
const TYPE_LAMP: String = "lamp"
const TYPE_AMMETER: String = "ammeter"
const TYPE_VOLTMETER: String = "voltmeter"
const TYPE_OHMMETER: String = "ohmmeter"
const EDGE_TYPES: PackedStringArray = [
	TYPE_WIRE, TYPE_SLOT, TYPE_RESISTOR, TYPE_BATTERY, TYPE_LAMP,
	TYPE_AMMETER, TYPE_VOLTMETER, TYPE_OHMMETER,
]
const METER_TYPES: PackedStringArray = [TYPE_AMMETER, TYPE_VOLTMETER, TYPE_OHMMETER]
## Types that need a "value".
const VALUE_TYPES: PackedStringArray = [TYPE_RESISTOR, TYPE_BATTERY, TYPE_LAMP]
## Types a "power" goal condition may name.
const POWER_TYPES: PackedStringArray = [TYPE_RESISTOR, TYPE_LAMP, TYPE_BATTERY, TYPE_SLOT]
const CIRCUIT_KEYS: PackedStringArray = ["nodes", "edges"]
const EDGE_KEYS: PackedStringArray = ["id", "type", "from", "to"]
const LAMP_RATING_KEYS: PackedStringArray = ["rated_min", "rated_max"]
## Optional on every edge.
const LABEL_KEY: String = "label"


## One edge of the board as written in the level file.
class Edge:
	extends RefCounted
	var id: String
	## One of the TYPE_* constants.
	var type: String
	var from_node: String
	var to_node: String
	## Ohms (resistor, lamp) or volts (battery); null for other types.
	var value: Rational = null
	## Lamps only: the current range in amperes in which the lamp is lit.
	var rated_min: Rational = null
	var rated_max: Rational = null
	## Optional short name for the readout plaque, e.g. "top" ("" if none).
	var label: String = ""

	func _init(edge_id: String, edge_type: String, a: String, b: String) -> void:
		id = edge_id
		type = edge_type
		from_node = a
		to_node = b

	func is_meter() -> bool:
		return METER_TYPES.has(type)


var _positions: Dictionary = {}  # String node name -> Vector2 centre in pixels
var _node_names: Array[String] = []  # in file order
var _edges: Array[Edge] = []  # in file order
var _edges_by_id: Dictionary = {}  # String id -> Edge


## Validates and parses a level's "circuit" object. Returns null and pushes an
## error naming the problem if anything is wrong. `source` names the origin.
static func from_dictionary(data: Variant, source: String = "circuit") -> LevelCircuit:
	if not data is Dictionary:
		push_error("LevelCircuit: %s: 'circuit' must be an object" % source)
		return null
	var dict: Dictionary = data
	for key: Variant in dict.keys():
		if not CIRCUIT_KEYS.has(str(key)):
			push_error("LevelCircuit: %s: circuit has unknown field '%s' (allowed: nodes, edges)" % [source, str(key)])
			return null
	for field: String in CIRCUIT_KEYS:
		if not dict.has(field):
			push_error("LevelCircuit: %s: circuit is missing '%s'" % [source, field])
			return null
	var circuit: LevelCircuit = LevelCircuit.new()
	if not circuit._parse_nodes(dict["nodes"], source):
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


## The edge with this id, or null.
func get_edge(id: String) -> Edge:
	return _edges_by_id.get(id, null)


## Number of edges (of any type) that touch `node_name`.
func get_node_degree(node_name: String) -> int:
	var degree: int = 0
	for edge: Edge in _edges:
		if edge.from_node == node_name:
			degree += 1
		if edge.to_node == node_name:
			degree += 1
	return degree


## Slots as DcPuzzleSearch expects them: each { "id", "from", "to" }, in file order.
func get_slot_descriptors() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for edge: Edge in _edges:
		if edge.type == TYPE_SLOT:
			slots.append({"id": edge.id, "from": edge.from_node, "to": edge.to_node})
	return slots


## The fixed board: wires, fixed resistors, batteries, lamps and meters. Every
## slot is left out (empty).
func build_base_network() -> DcNetwork:
	return build_network({})


## The base network plus the part in every slot listed in `filled` (slot id ->
## Part): a resistor becomes add_resistor(slot, from, to, ohms), a battery
## add_voltage_source(slot, from, to, volts) with plus at `from`. Slots not in
## `filled` are empty and left out. Unknown slot ids or values that are not a
## Part push an error and are skipped.
func build_network(filled: Dictionary) -> DcNetwork:
	var network: DcNetwork = DcNetwork.new()
	var slot_ids: Dictionary = {}
	for edge: Edge in _edges:
		var a: String = edge.from_node
		var b: String = edge.to_node
		match edge.type:
			TYPE_WIRE:
				network.add_wire(edge.id, a, b)
			TYPE_RESISTOR, TYPE_LAMP:
				network.add_resistor(edge.id, a, b, edge.value)
			TYPE_BATTERY:
				network.add_voltage_source(edge.id, a, b, edge.value)
			TYPE_AMMETER:
				network.add_ammeter(edge.id, a, b)
			TYPE_VOLTMETER:
				network.add_voltmeter(edge.id, a, b)
			TYPE_OHMMETER:
				network.add_ohmmeter(edge.id, a, b)
			TYPE_SLOT:
				slot_ids[edge.id] = true
				if not filled.has(edge.id):
					continue
				var content: Variant = filled[edge.id]
				if not content is Part or (content as Part).value == null:
					push_error("LevelCircuit.build_network: the content of slot '%s' is not a Part" % edge.id)
					continue
				var part: Part = content
				if part.is_battery():
					network.add_voltage_source(edge.id, a, b, part.value)
				else:
					network.add_resistor(edge.id, a, b, part.value)
	for key: Variant in filled.keys():
		if not slot_ids.has(key):
			push_error("LevelCircuit.build_network: '%s' is not a slot of this circuit" % str(key))
	return network


## True when every condition names an edge of this circuit and asks for a
## quantity that edge has: resistance only on an ohmmeter; power only on a
## resistor, lamp, battery or slot; current and voltage on anything but a
## wire. Otherwise pushes an error naming the problem and returns false.
func validate_goal(conditions: Array[GoalCondition], source: String = "goal") -> bool:
	for condition: GoalCondition in conditions:
		if condition == null:
			push_error("LevelCircuit: %s: a goal condition is null" % source)
			return false
		var edge: Edge = get_edge(condition.element_id)
		if edge == null:
			push_error("LevelCircuit: %s: goal condition names '%s', which is not an edge of the circuit" % [
					source, condition.element_id])
			return false
		var allowed: bool = true
		match condition.quantity:
			GoalCondition.Quantity.RESISTANCE:
				allowed = edge.type == TYPE_OHMMETER
			GoalCondition.Quantity.POWER:
				allowed = POWER_TYPES.has(edge.type)
			_:
				allowed = edge.type != TYPE_WIRE
		if not allowed:
			push_error("LevelCircuit: %s: a %s goal cannot be measured on %s '%s'" % [
					source, condition.quantity_name(), edge.type, edge.id])
			return false
	return true


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


func _parse_edges(value: Variant, source: String) -> bool:
	if not value is Array:
		push_error("LevelCircuit: %s: 'edges' must be an array" % source)
		return false
	var raw_edges: Array = value
	if raw_edges.is_empty():
		push_error("LevelCircuit: %s: 'edges' is empty" % source)
		return false
	for i: int in raw_edges.size():
		if not raw_edges[i] is Dictionary:
			push_error("LevelCircuit: %s: edges[%d] must be an object" % [source, i])
			return false
		var edge: Edge = _parse_edge(raw_edges[i], i, source)
		if edge == null:
			return false
		if _edges_by_id.has(edge.id):
			push_error("LevelCircuit: %s: edge id '%s' is used more than once" % [source, edge.id])
			return false
		_edges_by_id[edge.id] = edge
		_edges.append(edge)
	return true


func _parse_edge(raw: Dictionary, index: int, source: String) -> Edge:
	for field: String in EDGE_KEYS:
		if not raw.has(field) or not raw[field] is String or String(raw[field]).is_empty():
			push_error("LevelCircuit: %s: edges[%d] needs a non-empty string '%s'" % [source, index, field])
			return null
	var id: String = raw["id"]
	var type: String = raw["type"]
	if not EDGE_TYPES.has(type):
		push_error("LevelCircuit: %s: edge '%s' has unknown type '%s' (expected %s)" % [
				source, id, type, ", ".join(EDGE_TYPES)])
		return null
	var allowed: PackedStringArray = EDGE_KEYS.duplicate()
	allowed.append(LABEL_KEY)
	if VALUE_TYPES.has(type):
		allowed.append("value")
	if type == TYPE_LAMP:
		allowed.append_array(LAMP_RATING_KEYS)
	for key: Variant in raw.keys():
		if not allowed.has(str(key)):
			push_error("LevelCircuit: %s: %s edge '%s' has unknown field '%s' (allowed: %s)" % [
					source, type, id, str(key), ", ".join(allowed)])
			return null
	var from_node: String = raw["from"]
	var to_node: String = raw["to"]
	for node_name: String in [from_node, to_node]:
		if not _positions.has(node_name):
			push_error("LevelCircuit: %s: edge '%s' refers to unknown node '%s'" % [source, id, node_name])
			return null
	if from_node == to_node:
		push_error("LevelCircuit: %s: edge '%s' starts and ends at the same node '%s'" % [source, id, from_node])
		return null
	var edge: Edge = Edge.new(id, type, from_node, to_node)
	if raw.has(LABEL_KEY):
		if not raw[LABEL_KEY] is String or String(raw[LABEL_KEY]).strip_edges().is_empty():
			push_error("LevelCircuit: %s: edge '%s' needs '%s' as a non-empty string" % [source, id, LABEL_KEY])
			return null
		edge.label = String(raw[LABEL_KEY]).strip_edges()
	if VALUE_TYPES.has(type):
		edge.value = _parse_positive(raw, "value", type, id, source)
		if edge.value == null:
			return null
	if type == TYPE_LAMP:
		edge.rated_min = _parse_positive(raw, "rated_min", type, id, source)
		if edge.rated_min == null:
			return null
		edge.rated_max = _parse_positive(raw, "rated_max", type, id, source)
		if edge.rated_max == null:
			return null
		if edge.rated_min.compare(edge.rated_max) > 0:
			push_error("LevelCircuit: %s: lamp '%s' has rated_min %s greater than rated_max %s" % [
					source, id, edge.rated_min.to_text(), edge.rated_max.to_text()])
			return null
	return edge


## The exact value of `raw[key]` (> 0), or null after pushing an error.
static func _parse_positive(raw: Dictionary, key: String, type: String, id: String,
		source: String) -> Rational:
	if not raw.has(key) or not raw[key] is String:
		push_error("LevelCircuit: %s: %s edge '%s' needs '%s' as a string like \"3/2\"" % [source, type, id, key])
		return null
	var value: Rational = Rational.parse(raw[key])
	if value == null or not value.is_valid():
		push_error("LevelCircuit: %s: %s edge '%s' has an invalid '%s' value '%s'" % [source, type, id, key, raw[key]])
		return null
	if value.sign() <= 0:
		push_error("LevelCircuit: %s: %s edge '%s' must have '%s' > 0, got '%s'" % [source, type, id, key, raw[key]])
		return null
	return value


static func _is_number(value: Variant) -> bool:
	return value is float or value is int
