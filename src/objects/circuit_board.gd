class_name CircuitBoard
extends Node2D
## The level's circuit drawn on the wall: wires, junction dots, terminals A and
## B, sockets and fixed resistors, built from a LevelCircuit.
##
## Whenever a socket's contents change it builds the graph through
## LevelCircuit.build_graph, solves it with CircuitSolver and announces the
## result with `resistance_changed`; `is_match` is the level goal's verdict
## (LevelGoal.is_met). It also announces once right after build().
## For a goal with a battery (a current goal) it also draws the battery left of
## terminal A with its voltage under it.

signal resistance_changed(result: CircuitResult, is_match: bool)

const NODE_DOT_TEXTURE: Texture2D = preload("res://assets/processed/node_dot.png")
const TERMINAL_TEXTURE: Texture2D = preload("res://assets/processed/terminal.png")
## The processed art is drawn at 2x; this brings it to its on-screen size.
const ART_SCALE: Vector2 = Vector2(0.5, 0.5)
## Nodes with at least this many edges get a junction dot.
const JUNCTION_DEGREE: int = 3
const TERMINAL_NAMES: PackedStringArray = ["A", "B"]
const TERMINAL_LABEL_RECT: Rect2 = Rect2(-16, -42, 32, 22)
const TERMINAL_LABEL_COLOR: Color = Color("f6e7c8")
const TERMINAL_LABEL_OUTLINE: Color = Color("24180f")
const TERMINAL_LABEL_SIZE: int = 18
const TERMINAL_LABEL_OUTLINE_SIZE: int = 5
const BATTERY_TEXTURE: Texture2D = preload("res://assets/props/battery_pickup.png")
## The battery's centre relative to terminal A.
const BATTERY_OFFSET: Vector2 = Vector2(-48, 0)
## The voltage label's rectangle relative to the battery's centre.
const BATTERY_LABEL_RECT: Rect2 = Rect2(-40, 20, 80, 22)
const VOLT_SUFFIX: String = " V"

@export var socket_scene: PackedScene

var _circuit: LevelCircuit = null
var _goal: LevelGoal = null
var _sockets: Array[CircuitSocket] = []
var _wires: CircuitWires = null
var _last_result: CircuitResult = null


## Builds every visual from `circuit` and announces the first reading.
## `goal` decides what counts as a match. `theme` colours the wires.
func build(circuit: LevelCircuit, goal: LevelGoal, theme: RoomTheme = null) -> void:
	_circuit = circuit
	_goal = goal
	_wires = CircuitWires.new()
	_wires.name = "Wires"
	add_child(_wires)
	_wires.build(circuit, theme)
	_add_battery()
	_add_node_markers()
	_add_components()
	_refresh()


func get_sockets() -> Array[CircuitSocket]:
	return _sockets.duplicate()


## The most recent reading (null before build()).
func get_last_result() -> CircuitResult:
	return _last_result


func _add_node_markers() -> void:
	for node_name: String in _circuit.get_node_names():
		var at: Vector2 = _circuit.get_node_position(node_name)
		if _circuit.is_terminal(node_name):
			var index: int = 0 if node_name == _circuit.terminal_a else 1
			_add_terminal(at, TERMINAL_NAMES[index])
		elif _circuit.get_node_degree(node_name) >= JUNCTION_DEGREE:
			_add_sprite(NODE_DOT_TEXTURE, at, "Dot_" + node_name)


func _add_terminal(at: Vector2, label_text: String) -> void:
	_add_sprite(TERMINAL_TEXTURE, at, "Terminal" + label_text)
	_add_label("TerminalLabel" + label_text, label_text,
			Rect2(at + TERMINAL_LABEL_RECT.position, TERMINAL_LABEL_RECT.size))


## Draws the battery of a goal that has one (goal.voltage set) left of terminal A.
func _add_battery() -> void:
	if _goal == null or _goal.voltage == null:
		return
	var at: Vector2 = _circuit.get_node_position(_circuit.terminal_a) + BATTERY_OFFSET
	_add_sprite(BATTERY_TEXTURE, at, "Battery")
	_add_label("BatteryLabel", _goal.voltage.to_text() + VOLT_SUFFIX,
			Rect2(at + BATTERY_LABEL_RECT.position, BATTERY_LABEL_RECT.size))


## A cream label with a dark ink outline, as used for the terminal names.
func _add_label(label_name: String, text: String, rect: Rect2) -> void:
	var label: Label = Label.new()
	label.name = label_name
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", TERMINAL_LABEL_SIZE)
	label.add_theme_color_override(&"font_color", TERMINAL_LABEL_COLOR)
	label.add_theme_color_override(&"font_outline_color", TERMINAL_LABEL_OUTLINE)
	label.add_theme_constant_override(&"outline_size", TERMINAL_LABEL_OUTLINE_SIZE)
	add_child(label)


func _add_sprite(texture: Texture2D, at: Vector2, sprite_name: String) -> void:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = sprite_name
	sprite.texture = texture
	sprite.scale = ART_SCALE
	sprite.position = at
	add_child(sprite)


func _add_components() -> void:
	for edge: LevelCircuit.Edge in _circuit.get_edges():
		var middle: Vector2 = (_circuit.get_node_position(edge.from_node)
				+ _circuit.get_node_position(edge.to_node)) * 0.5
		if edge.type == LevelCircuit.TYPE_SOCKET:
			_add_socket(edge.id, middle)
		elif edge.type == LevelCircuit.TYPE_FIXED:
			var fixed: FixedResistor = FixedResistor.new()
			fixed.name = "Fixed_" + edge.id
			fixed.position = middle
			fixed.set_value(edge.ohms)
			add_child(fixed)


func _add_socket(id: String, at: Vector2) -> void:
	if socket_scene == null:
		push_error("CircuitBoard: socket_scene is not set")
		return
	var socket: CircuitSocket = socket_scene.instantiate() as CircuitSocket
	if socket == null:
		push_error("CircuitBoard: socket_scene does not have a CircuitSocket root")
		return
	socket.name = "Socket_" + id
	socket.socket_id = id
	socket.position = at
	add_child(socket)
	socket.contents_changed.connect(_refresh)
	_sockets.append(socket)


func _refresh() -> void:
	var filled: Dictionary = {}
	for socket: CircuitSocket in _sockets:
		if socket.is_filled():
			filled[socket.socket_id] = socket.get_value()
	var result: CircuitResult = CircuitSolver.solve(_circuit.build_graph(filled))
	var is_match: bool = _goal != null and _goal.is_met(result)
	_last_result = result
	_wires.set_state(result.status == CircuitResult.Status.OK, is_match)
	resistance_changed.emit(result, is_match)
