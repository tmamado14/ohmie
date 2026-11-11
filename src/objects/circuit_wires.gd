class_name CircuitWires
extends Node2D
## Draws the board's wires with Line2D: a wide dark outline under a narrow
## core line for every edge. Wire edges run node to node; every other edge
## (slots, fixed parts, lamps, meters) gets a lead from each node to the side
## of the 104x72 component drawn at its midpoint.
##
## Colour shows the circuit state, using the room theme's wire colours:
##   PLAIN      no current flows (theme "normal")
##   ENERGIZED  current flows (theme "closed")
##   MATCH      the goal is met (theme "match", pulsing)
##   SHORT      a short: the core flashes between SHORT_COLOR and the plain colour

enum State { PLAIN, ENERGIZED, MATCH, SHORT }

const OUTLINE_WIDTH: float = 7.0
const COPPER_WIDTH: float = 4.0
## Half the drawn size of a component on an edge (104x72 frame).
const COMPONENT_HALF_SIZE: Vector2 = Vector2(52, 36)
## Pulse on a match: brightness swings by this much, this many times a second.
const PULSE_AMOUNT: float = 0.3
const PULSE_FREQUENCY: float = 1.2
## Short warning: the core alternates with this colour every SHORT_FLASH_PERIOD seconds.
const SHORT_COLOR: Color = Color("c8452f")
const SHORT_FLASH_PERIOD: float = 0.25

var _outline_layer: Node2D = null
var _copper_layer: Node2D = null
var _time: float = 0.0
var _state: State = State.PLAIN
## Colours come from this theme; a default RoomTheme when none is given.
var _theme: RoomTheme = null


func _ready() -> void:
	set_process(false)


## Replaces any existing lines with the wires of `circuit`, coloured by `theme`.
func build(circuit: LevelCircuit, theme: RoomTheme = null) -> void:
	_theme = theme if theme != null else RoomTheme.new()
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
	set_state(State.PLAIN)


func set_state(state: State) -> void:
	if _copper_layer == null:
		return
	_state = state
	var color: Color = _theme.wire_normal
	var outline: Color = _theme.wire_normal_outline
	match state:
		State.MATCH:
			color = _theme.wire_match
			outline = _theme.wire_match_outline
		State.ENERGIZED:
			color = _theme.wire_closed
			outline = _theme.wire_closed_outline
	_set_colors(color, outline)
	_time = 0.0
	_copper_layer.modulate = Color.WHITE
	set_process(state == State.MATCH or state == State.SHORT)
	if state == State.SHORT:
		_set_core_color(SHORT_COLOR)


func get_state() -> State:
	return _state


## The core colour of the wires as currently drawn.
func get_core_color() -> Color:
	if _copper_layer == null or _copper_layer.get_child_count() == 0:
		return Color.BLACK
	return (_copper_layer.get_child(0) as Line2D).default_color


func _process(delta: float) -> void:
	_time += delta
	if _state == State.SHORT:
		var red: bool = int(_time / SHORT_FLASH_PERIOD) % 2 == 0
		_set_core_color(SHORT_COLOR if red else _theme.wire_normal)
		return
	var wave: float = 0.5 + 0.5 * cos(_time * TAU * PULSE_FREQUENCY)
	var brightness: float = 1.0 - PULSE_AMOUNT * (1.0 - wave)
	_copper_layer.modulate = Color(brightness, brightness, brightness)


func _set_colors(core: Color, outline: Color) -> void:
	_set_core_color(core)
	for child: Node in _outline_layer.get_children():
		(child as Line2D).default_color = outline


func _set_core_color(core: Color) -> void:
	for child: Node in _copper_layer.get_children():
		(child as Line2D).default_color = core


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
	_outline_layer.add_child(_make_line(a, b, OUTLINE_WIDTH, _theme.wire_normal_outline))
	_copper_layer.add_child(_make_line(a, b, COPPER_WIDTH, _theme.wire_normal))


static func _make_line(a: Vector2, b: Vector2, width: float, color: Color) -> Line2D:
	var line: Line2D = Line2D.new()
	line.points = PackedVector2Array([a, b])
	line.width = width
	line.default_color = color
	line.begin_cap_mode = Line2D.LINE_CAP_BOX
	line.end_cap_mode = Line2D.LINE_CAP_BOX
	line.antialiased = true
	return line
