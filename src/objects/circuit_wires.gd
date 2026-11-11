class_name CircuitWires
extends Node2D
## Draws the board's wires with Line2D: a wide dark outline under a narrow
## copper line for every edge. Wire edges run node to node; socket and fixed
## edges get a lead from each node to the component's side.
##
## Colour shows the circuit state: copper when open, bright copper when closed
## (status OK), pulsing cyan when the value matches the target.

const OUTLINE_COLOR: Color = Color("182e3a")
const COPPER_COLOR: Color = Color("b66b39")
const CLOSED_COLOR: Color = Color("eb9a5c")
const MATCH_COLOR: Color = Color("47d1c0")
const OUTLINE_WIDTH: float = 8.0
const COPPER_WIDTH: float = 4.0
## Half the drawn size of a socket or fixed resistor (104x72 frame).
const COMPONENT_HALF_SIZE: Vector2 = Vector2(52, 36)
## Pulse on a match: brightness swings by this much, this many times a second.
const PULSE_AMOUNT: float = 0.3
const PULSE_FREQUENCY: float = 1.2

var _outline_layer: Node2D = null
var _copper_layer: Node2D = null
var _pulse_time: float = 0.0


func _ready() -> void:
	set_process(false)


## Replaces any existing lines with the wires of `circuit`.
func build(circuit: LevelCircuit) -> void:
	for child: Node in get_children():
		child.queue_free()
	_outline_layer = Node2D.new()
	_outline_layer.name = "Outline"
	add_child(_outline_layer)
	_copper_layer = Node2D.new()
	_copper_layer.name = "Copper"
	add_child(_copper_layer)
	for edge: LevelCircuit.Edge in circuit.get_edges():
		var a: Vector2 = circuit.get_node_position(edge.from_node)
		var b: Vector2 = circuit.get_node_position(edge.to_node)
		if edge.type == LevelCircuit.TYPE_WIRE:
			_add_segment(a, b)
		else:
			_add_leads(a, b)
	set_state(false, false)


## closed: the circuit conducts (status OK). matched: it equals the target.
func set_state(closed: bool, matched: bool) -> void:
	if _copper_layer == null:
		return
	var color: Color = COPPER_COLOR
	if matched:
		color = MATCH_COLOR
	elif closed:
		color = CLOSED_COLOR
	for child: Node in _copper_layer.get_children():
		(child as Line2D).default_color = color
	_pulse_time = 0.0
	_copper_layer.modulate = Color.WHITE
	set_process(matched)


func _process(delta: float) -> void:
	_pulse_time += delta
	var wave: float = 0.5 + 0.5 * cos(_pulse_time * TAU * PULSE_FREQUENCY)
	var brightness: float = 1.0 - PULSE_AMOUNT * (1.0 - wave)
	_copper_layer.modulate = Color(brightness, brightness, brightness)


## Leads from each end to the side of a component drawn at the midpoint.
func _add_leads(a: Vector2, b: Vector2) -> void:
	var length: float = a.distance_to(b)
	if length <= 0.0:
		return
	var direction: Vector2 = (b - a) / length
	var half: float = COMPONENT_HALF_SIZE.x if absf(direction.x) >= absf(direction.y) else COMPONENT_HALF_SIZE.y
	if half * 2.0 >= length:
		return
	var middle: Vector2 = (a + b) * 0.5
	_add_segment(a, middle - direction * half)
	_add_segment(middle + direction * half, b)


func _add_segment(a: Vector2, b: Vector2) -> void:
	_outline_layer.add_child(_make_line(a, b, OUTLINE_WIDTH, OUTLINE_COLOR))
	_copper_layer.add_child(_make_line(a, b, COPPER_WIDTH, COPPER_COLOR))


static func _make_line(a: Vector2, b: Vector2, width: float, color: Color) -> Line2D:
	var line: Line2D = Line2D.new()
	line.points = PackedVector2Array([a, b])
	line.width = width
	line.default_color = color
	line.begin_cap_mode = Line2D.LINE_CAP_BOX
	line.end_cap_mode = Line2D.LINE_CAP_BOX
	line.antialiased = false
	return line
