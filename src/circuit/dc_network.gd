class_name DcNetwork
extends RefCounted
## A description of a closed DC circuit: named nodes joined by elements.
##
## Every element has a unique string id and two node names, called its first
## node and its second node (a and b; for a voltage source, plus and minus).
##
## Element kinds:
##   WIRE            zero resistance; its two nodes are one electrical point.
##   RESISTOR        a resistance > 0.
##   VOLTAGE_SOURCE  ideal; holds V(plus) - V(minus) = volts. Any rational,
##                   including 0 and negative values.
##   AMMETER         ideal (zero resistance); measures the current flowing
##                   through it from its first node to its second node.
##   VOLTMETER       ideal (draws no current); measures V(a) - V(b).
##   OHMMETER        ideal; measures the resistance between a and b with every
##                   source switched off (see DcSolution.meter_reading).
##
## Every add_* function returns true on success. On bad input (empty id or node
## name, duplicate id, a null or invalid value, a resistance that is not > 0)
## it calls push_error, leaves the network unchanged and returns false.
##
## Read accessors never call push_error: for an unknown id they return "",
## null or -1 as documented on each function.

enum Kind { WIRE, RESISTOR, VOLTAGE_SOURCE, AMMETER, VOLTMETER, OHMMETER }

const _KIND_NAMES: Array[String] = [
		"wire", "resistor", "voltage_source", "ammeter", "voltmeter", "ohmmeter"]


class _Element:
	extends RefCounted
	var id: String
	var kind: Kind
	var node_a: String
	var node_b: String
	var value: Rational  # ohms for a resistor, volts for a source, else null

	func _init(element_id: String, element_kind: Kind, a: String, b: String,
			element_value: Rational) -> void:
		id = element_id
		kind = element_kind
		node_a = a
		node_b = b
		value = element_value


var _elements: Dictionary = {}  # String id -> _Element


## Adds a zero-resistance wire between a and b.
func add_wire(id: String, a: String, b: String) -> bool:
	if not _check_new(id, a, b, "add_wire"):
		return false
	_elements[id] = _Element.new(id, Kind.WIRE, a, b, null)
	return true


## Adds a resistor of `ohms` (> 0) between a and b.
func add_resistor(id: String, a: String, b: String, ohms: Rational) -> bool:
	if not _check_new(id, a, b, "add_resistor"):
		return false
	if ohms == null or not ohms.is_valid():
		push_error("DcNetwork.add_resistor: resistor '%s' has no valid value." % id)
		return false
	if ohms.sign() <= 0:
		push_error("DcNetwork.add_resistor: resistor '%s' must be > 0 ohms, got %s." % [
				id, ohms.to_text()])
		return false
	_elements[id] = _Element.new(id, Kind.RESISTOR, a, b, ohms)
	return true


## Adds an ideal voltage source with V(plus) - V(minus) = volts.
func add_voltage_source(id: String, plus: String, minus: String, volts: Rational) -> bool:
	if not _check_new(id, plus, minus, "add_voltage_source"):
		return false
	if volts == null or not volts.is_valid():
		push_error("DcNetwork.add_voltage_source: source '%s' has no valid value." % id)
		return false
	_elements[id] = _Element.new(id, Kind.VOLTAGE_SOURCE, plus, minus, volts)
	return true


## Adds an ideal ammeter that measures the current from a to b through it.
func add_ammeter(id: String, a: String, b: String) -> bool:
	if not _check_new(id, a, b, "add_ammeter"):
		return false
	_elements[id] = _Element.new(id, Kind.AMMETER, a, b, null)
	return true


## Adds an ideal voltmeter that measures V(a) - V(b).
func add_voltmeter(id: String, a: String, b: String) -> bool:
	if not _check_new(id, a, b, "add_voltmeter"):
		return false
	_elements[id] = _Element.new(id, Kind.VOLTMETER, a, b, null)
	return true


## Adds an ideal ohmmeter that measures the resistance between a and b.
func add_ohmmeter(id: String, a: String, b: String) -> bool:
	if not _check_new(id, a, b, "add_ohmmeter"):
		return false
	_elements[id] = _Element.new(id, Kind.OHMMETER, a, b, null)
	return true


func element_count() -> int:
	return _elements.size()


func has_element(id: String) -> bool:
	return _elements.has(id)


## All element ids in sorted order.
func get_element_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: String in _elements.keys():
		ids.append(key)
	ids.sort()
	return ids


## All node names used by any element, in sorted order.
func get_nodes() -> Array[String]:
	var seen: Dictionary = {}
	for element: _Element in _elements.values():
		seen[element.node_a] = true
		seen[element.node_b] = true
	var nodes: Array[String] = []
	for key: String in seen.keys():
		nodes.append(key)
	nodes.sort()
	return nodes


## The element's Kind, or -1 for an unknown id.
func get_kind(id: String) -> int:
	var element: _Element = _elements.get(id, null)
	if element == null:
		return -1
	return element.kind


## The first node (plus for a voltage source), or "" for an unknown id.
func get_node_a(id: String) -> String:
	var element: _Element = _elements.get(id, null)
	return element.node_a if element != null else ""


## The second node (minus for a voltage source), or "" for an unknown id.
func get_node_b(id: String) -> String:
	var element: _Element = _elements.get(id, null)
	return element.node_b if element != null else ""


## Ohms for a resistor, volts for a voltage source; null for every other kind
## and for an unknown id.
func get_value(id: String) -> Rational:
	var element: _Element = _elements.get(id, null)
	return element.value if element != null else null


## "wire", "resistor", "voltage_source", "ammeter", "voltmeter", "ohmmeter".
## "" for anything else.
static func kind_name(kind: int) -> String:
	if kind < 0 or kind >= _KIND_NAMES.size():
		return ""
	return _KIND_NAMES[kind]


## An independent copy. Rational values are immutable, so they are shared.
func duplicate_network() -> DcNetwork:
	var copy: DcNetwork = DcNetwork.new()
	for element: _Element in _elements.values():
		copy._elements[element.id] = _Element.new(element.id, element.kind,
				element.node_a, element.node_b, element.value)
	return copy


## A deterministic multi-line description, one element per line in id order:
## "<kind> <id> <a> <b>" plus " <value>" for resistors and sources.
func to_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for id: String in get_element_ids():
		var element: _Element = _elements[id]
		var line: String = "%s %s %s %s" % [kind_name(element.kind), id, element.node_a, element.node_b]
		if element.value != null:
			line += " " + element.value.to_text()
		lines.append(line)
	return "\n".join(lines)


func _check_new(id: String, a: String, b: String, op: String) -> bool:
	if id.is_empty():
		push_error("DcNetwork.%s: element id must not be empty." % op)
		return false
	if a.is_empty() or b.is_empty():
		push_error("DcNetwork.%s: element '%s' has an empty node name." % [op, id])
		return false
	if _elements.has(id):
		push_error("DcNetwork.%s: duplicate element id '%s'." % [op, id])
		return false
	return true
